const std = @import("std");

/// A minimalist fixed-size heap for the Core Broker.
/// Following "Zero-Cost Abstraction", this does not use a standard allocator.
pub const KernelHeap = struct {
    heap_start: usize,
    heap_end: usize,
    next: usize,

    pub fn init(start: usize, size_kb: usize) KernelHeap {
        return .{
            .heap_start = start,
            .heap_end = start + (size_kb * 1024),
            .next = start,
        };
    }

    /// Allocate memory from the kernel heap.
    /// This is a simple bump allocator for early boot; will be upgraded to a buddy allocator.
    pub fn alloc(self: *KernelHeap, size: usize, alignment: usize) ?[]u8 {
        const aligned_next = (self.next + alignment - 1) & ~(alignment - 1);
        const end = aligned_next + size;
        
        if (end > self.heap_end) return null;
        
        const ptr = @as([*]u8, @ptrFromInt(aligned_next))[0..size];
        self.next = end;
        return ptr;
    }

    /// Standard Zig allocator interface for KernelHeap.
    pub fn allocator(self: *KernelHeap) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc_adapter,
                .resize = resize_adapter,
                .free = free_adapter,
            },
        };
    }

    fn alloc_adapter(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *KernelHeap = @ptrCast(@alignCast(ctx));
        const alignment = @as(usize, 1) << @as(u6, @truncate(ptr_align));
        const result = self.alloc(len, alignment);
        return if (result) |r| r.ptr else null;
    }

    fn resize_adapter(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx; _ = buf; _ = buf_align; _ = new_len; _ = ret_addr;
        return false; // Resize not supported in bump allocator
    }

    fn free_adapter(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ctx; _ = buf; _ = buf_align; _ = ret_addr;
        // Free not supported in bump allocator
    }
};
