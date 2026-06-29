const std = @import("std");
const capability = @import("capability.zig");
const scheduler = @import("scheduler.zig");
const ipc_transport = @import("ipc_transport.zig");
const paging = @import("paging.zig");
extern fn kernel_alloc(len: u64, align_bytes: u64) ?[*]u8;

pub const AdapterEntryFn = *const fn () callconv(.c) noreturn;

pub const AdapterDescriptor = struct {
    name: []const u8,
    entry: AdapterEntryFn,
    priority: u8,
    stack_pages: usize = 4,
};

pub const LoadedAdapter = struct {
    thread: *scheduler.Thread,
    clist: *capability.CList,
    port_id: u32,
    stack_base: usize,
};

pub const Loader = struct {
    loaded: [8]LoadedAdapter = undefined,
    loaded_count: usize = 0,
    next_thread_id: u32 = 1,

    pub fn loadAll(
        self: *Loader,
        sched: *scheduler.Scheduler,
        router: *ipc_transport.Router,
        kernel_aspace: *paging.AddressSpace,
        descriptors: []const AdapterDescriptor,
    ) void {
        const print = @import("main.zig").printString;

        for (descriptors) |desc| {
            print("[Loader] Spawning adapter: ");
            print(desc.name);
            print("\n");

            const thread_id = self.next_thread_id;
            self.next_thread_id += 1;

            const stack_bytes = desc.stack_pages * paging.AddressSpace.PageSize;
            const stack_raw = kernel_alloc(stack_bytes, paging.AddressSpace.PageSize) orelse {
                print("[Loader] Out of memory for adapter stack\n");
                continue;
            };
            const stack_base = @intFromPtr(stack_raw);
            const stack_top = stack_base + stack_bytes;

            var page: u64 = stack_base;
            while (page < stack_top) : (page += paging.AddressSpace.PageSize) {
                kernel_aspace.map(page, page, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write | paging.PTE.Flags.user) catch {
                    print("[Loader] Failed to map adapter stack\n");
                    break;
                };
            }

            const clist_raw = kernel_alloc(@sizeOf(capability.CList), @alignOf(capability.CList)) orelse {
                print("[Loader] Out of memory for adapter CList\n");
                continue;
            };
            const clist = @as(*capability.CList, @ptrCast(@alignCast(clist_raw)));
            capability.CList.init(clist, 16, thread_id);

            const thread_raw = kernel_alloc(@sizeOf(scheduler.Thread), @alignOf(scheduler.Thread)) orelse {
                print("[Loader] Out of memory for adapter thread\n");
                continue;
            };
            const thread = @as(*scheduler.Thread, @ptrCast(@alignCast(thread_raw)));
            thread.* = scheduler.Thread.init(thread_id, clist, null, stack_top, @intFromPtr(desc.entry));
            thread.priority = desc.priority;
            thread.uses_vectors = std.mem.eql(u8, desc.name, "neural-engine");

            const port_id = router.createPort(thread_id, clist) catch {
                print("[Loader] Failed to create IPC port for adapter\n");
                continue;
            };

            clist.caps[0] = .{
                .cap_type = .ipc_endpoint,
                .rights = capability.Capability.Rights.read | capability.Capability.Rights.write,
                .object_id = @intCast(port_id),
                .base = 0,
                .limit = 0,
            };

            sched.addThread(thread) catch {
                print("[Loader] Scheduler full, cannot add adapter thread\n");
                continue;
            };

            if (self.loaded_count < self.loaded.len) {
                self.loaded[self.loaded_count] = .{
                    .thread = thread,
                    .clist = clist,
                    .port_id = port_id,
                    .stack_base = stack_base,
                };
                self.loaded_count += 1;
            }
        }

        print("[Loader] ");
        printUsize(self.loaded_count, print);
        print(" adapter(s) ready\n");
    }
};

fn printUsize(val: usize, print: fn ([]const u8) void) void {
    var buf: [16]u8 = undefined;
    var n = val;
    var i: usize = 0;
    if (n == 0) {
        print("0");
        return;
    }
    while (n > 0) : (i += 1) {
        buf[i] = @intCast('0' + (n % 10));
        n /= 10;
    }
    while (i > 0) {
        i -= 1;
        print(buf[i .. i + 1]);
    }
}
