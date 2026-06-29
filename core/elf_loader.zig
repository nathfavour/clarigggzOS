const std = @import("std");
const capability = @import("capability.zig");
const scheduler = @import("scheduler.zig");
const ipc_transport = @import("ipc_transport.zig");
const paging = @import("paging.zig");
extern fn kernel_alloc(len: u64, align_bytes: u64) ?[*]u8;

pub const Elf64Ehdr = extern struct {
    ident: [16]u8,
    file_type: u16,
    machine: u16,
    version: u32,
    entry: u64,
    phoff: u64,
    shoff: u64,
    flags: u32,
    ehsize: u16,
    phentsize: u16,
    phnum: u16,
    shentsize: u16,
    shnum: u16,
    shstrndx: u16,
};

pub const Elf64Phdr = extern struct {
    p_type: u32,
    p_flags: u32,
    p_offset: u64,
    p_vaddr: u64,
    p_paddr: u64,
    p_filesz: u64,
    p_memsz: u64,
    p_align: u64,
};

pub const PT_LOAD: u32 = 1;
pub const EM_RISCV: u16 = 243;
pub const ET_EXEC: u16 = 2;

pub const LoadedElf = struct {
    entry: u64,
    load_base: u64,
    thread: *scheduler.Thread,
    clist: *capability.CList,
    port_id: u32,
};

pub const ElfLoader = struct {
  pub fn validateHeader(elf: []const u8) !*const Elf64Ehdr {
        if (elf.len < @sizeOf(Elf64Ehdr)) return error.TruncatedElf;
        const hdr = @as(*const Elf64Ehdr, @ptrCast(@alignCast(elf.ptr)));
        if (hdr.ident[0] != 0x7f or hdr.ident[1] != 'E' or hdr.ident[2] != 'L' or hdr.ident[3] != 'F') {
            return error.BadMagic;
        }
        if (hdr.machine != EM_RISCV) return error.WrongArchitecture;
        if (hdr.file_type != ET_EXEC) return error.NotExecutable;
        return hdr;
    }

    pub fn load(
        elf_data: []const u8,
        name: []const u8,
        priority: u8,
        thread_id: u32,
        sched: *scheduler.Scheduler,
        router: *ipc_transport.Router,
        kernel_aspace: *paging.AddressSpace,
        uses_vectors: bool,
    ) !LoadedElf {
        const print = @import("main.zig").printString;
        const hdr = try validateHeader(elf_data);

        if (hdr.phoff + hdr.phnum * hdr.phentsize > elf_data.len) return error.TruncatedElf;

        var min_vaddr: u64 = std.math.maxInt(u64);
        var max_vaddr: u64 = 0;

        var i: u16 = 0;
        while (i < hdr.phnum) : (i += 1) {
            const off = hdr.phoff + @as(u64, i) * hdr.phentsize;
            const ph = @as(*const Elf64Phdr, @ptrCast(@alignCast(elf_data.ptr + off)));
            if (ph.p_type != PT_LOAD) continue;
            min_vaddr = @min(min_vaddr, ph.p_vaddr);
            const end = ph.p_vaddr + ph.p_memsz;
            max_vaddr = @max(max_vaddr, end);
        }

        if (min_vaddr == std.math.maxInt(u64)) return error.NoLoadableSegments;

        const span = max_vaddr - min_vaddr;
        const alloc_size = alignUp(span, paging.AddressSpace.PageSize);
        const image_raw = kernel_alloc(alloc_size, paging.AddressSpace.PageSize) orelse return error.OutOfMemory;
        const image_base = @intFromPtr(image_raw);
        @memset(image_raw[0..alloc_size], 0);

        i = 0;
        while (i < hdr.phnum) : (i += 1) {
            const off = hdr.phoff + @as(u64, i) * hdr.phentsize;
            const ph = @as(*const Elf64Phdr, @ptrCast(@alignCast(elf_data.ptr + off)));
            if (ph.p_type != PT_LOAD) continue;
            if (ph.p_offset + ph.p_filesz > elf_data.len) return error.TruncatedElf;

            const dest_off = ph.p_vaddr - min_vaddr;
            @memcpy(image_raw[dest_off .. dest_off + ph.p_filesz], elf_data[@intCast(ph.p_offset) ..][0..@intCast(ph.p_filesz)]);
        }

        var page: u64 = image_base;
        const image_end = image_base + alloc_size;
        while (page < image_end) : (page += paging.AddressSpace.PageSize) {
            const flags = paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write | paging.PTE.Flags.user | paging.PTE.Flags.exec;
            kernel_aspace.map(page, page, flags) catch {
                print("[ELF] Failed to map segment page\n");
                return error.MapFailed;
            };
        }

        const stack_bytes = 4 * paging.AddressSpace.PageSize;
        const stack_raw = kernel_alloc(stack_bytes, paging.AddressSpace.PageSize) orelse return error.OutOfMemory;
        const stack_base = @intFromPtr(stack_raw);
        const stack_top = stack_base + stack_bytes;
        page = stack_base;
        while (page < stack_top) : (page += paging.AddressSpace.PageSize) {
            kernel_aspace.map(page, page, paging.PTE.Flags.valid | paging.PTE.Flags.read | paging.PTE.Flags.write | paging.PTE.Flags.user) catch {
                return error.MapFailed;
            };
        }

        const clist_raw = kernel_alloc(@sizeOf(capability.CList), @alignOf(capability.CList)) orelse return error.OutOfMemory;
        const clist = @as(*capability.CList, @ptrCast(@alignCast(clist_raw)));
        capability.CList.init(clist, 16, thread_id);

        const thread_raw = kernel_alloc(@sizeOf(scheduler.Thread), @alignOf(scheduler.Thread)) orelse return error.OutOfMemory;
        const thread = @as(*scheduler.Thread, @ptrCast(@alignCast(thread_raw)));

        const entry = image_base + (hdr.entry - min_vaddr);
        thread.* = scheduler.Thread.init(thread_id, clist, null, stack_top, entry);
        thread.priority = priority;
        thread.uses_vectors = uses_vectors;

        const port_id = try router.createPort(thread_id, clist);
        clist.caps[0] = .{
            .cap_type = .ipc_endpoint,
            .rights = capability.Capability.Rights.read | capability.Capability.Rights.write,
            .object_id = @intCast(port_id),
            .base = 0,
            .limit = 0,
        };

        try sched.addThread(thread);

        print("[ELF] Loaded ");
        print(name);
        print(" entry=0x");
        printHex(entry, print);
        print("\n");

        return .{
            .entry = entry,
            .load_base = image_base,
            .thread = thread,
            .clist = clist,
            .port_id = port_id,
        };
    }
};

fn alignUp(val: u64, alignment: u64) u64 {
    return (val + alignment - 1) & ~(alignment - 1);
}

fn printHex(val: u64, print: fn ([]const u8) void) void {
    var buf: [20]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "{x}", .{val}) catch return;
    print(buf[0..]);
}

test "ELF loader validates magic" {
    const bad = [_]u8{0} ** 64;
    try std.testing.expectError(error.BadMagic, ElfLoader.validateHeader(&bad));
}
