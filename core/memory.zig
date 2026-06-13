const std = @import("std");

/// A deterministic Buddy Allocator for the Clarigggz Core Broker.
/// Manages memory in power-of-two blocks using free list nodes embedded in free memory.
pub const KernelHeap = struct {
    heap_start: usize,
    heap_end: usize,
    free_lists: [15]?*Node, // Orders 0 to 14 (64 bytes to 1MB)
    // Bitset tracking allocated blocks of order 0 (16384 blocks total for 1MB)
    // 16384 bits = 2048 bytes. Stored at the very beginning of the heap.
    allocated_map: []u8,

    pub const Node = struct {
        next: ?*Node,
    };

    pub const min_block_size = 64;
    pub const max_order = 14;

    pub fn init(start: usize, size_kb: usize) KernelHeap {
        const total_bytes = size_kb * 1024;
        const end = start + total_bytes;

        // Allocate the allocation bitset map from the start of the heap
        const total_blocks = total_bytes / min_block_size;
        const map_size = (total_blocks + 7) / 8;

        const allocated_map = @as([*]u8, @ptrFromInt(start))[0..map_size];
        @memset(allocated_map, 0);

        var heap = KernelHeap{
            .heap_start = start,
            .heap_end = end,
            .free_lists = [_]?*Node{null} ** 15,
            .allocated_map = allocated_map,
        };

        // Align the actual allocatable area after the allocated_map
        const alloc_start = (start + map_size + min_block_size - 1) & ~@as(usize, min_block_size - 1);
        
        // Mark metadata blocks as allocated in bitset
        const meta_blocks = (alloc_start - start) / min_block_size;
        for (0..meta_blocks) |i| {
            heap.setAllocated(i, true);
        }

        // Initialize free lists with remaining memory blocks
        var current = alloc_start;
        while (current + min_block_size <= end) {
            // Find the largest power-of-two block size that fits and is aligned
            var order: usize = max_order;
            while (order > 0) : (order -= 1) {
                const block_size = @as(usize, 1) << @intCast(order + 6);
                if (current % block_size == 0 and current + block_size <= end) {
                    break;
                }
            }
            const node = @as(*Node, @ptrFromInt(current));
            node.next = heap.free_lists[order];
            heap.free_lists[order] = node;
            
            const block_size = @as(usize, 1) << @intCast(order + 6);
            current += block_size;
        }

        return heap;
    }

    fn setAllocated(self: *KernelHeap, block_idx: usize, val: bool) void {
        const byte_idx = block_idx / 8;
        const bit_idx = @as(u3, @intCast(block_idx % 8));
        if (val) {
            self.allocated_map[byte_idx] |= (@as(u8, 1) << bit_idx);
        } else {
            self.allocated_map[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        }
    }

    fn isAllocated(self: *const KernelHeap, block_idx: usize) bool {
        const byte_idx = block_idx / 8;
        const bit_idx = @as(u3, @intCast(block_idx % 8));
        return (self.allocated_map[byte_idx] & (@as(u8, 1) << bit_idx)) != 0;
    }

    fn sizeToOrder(size: usize) usize {
        if (size <= min_block_size) return 0;
        var s = size - 1;
        var order: usize = 0;
        s >>= 6; // divide by 64
        while (s > 0) : (order += 1) {
            s >>= 1;
        }
        return order;
    }

    /// Allocate memory of given size and alignment.
    pub fn alloc(self: *KernelHeap, size: usize, alignment: usize) ?[]u8 {
        _ = alignment; // Alignment is naturally power-of-two matched by buddy block sizing
        const req_order = sizeToOrder(size);
        if (req_order > max_order) return null;

        var order = req_order;
        while (order <= max_order) : (order += 1) {
            if (self.free_lists[order]) |node| {
                // Remove from free list
                self.free_lists[order] = node.next;

                // Split down to required order
                while (order > req_order) {
                    order -= 1;
                    const block_size = @as(usize, 1) << @intCast(order + 6);
                    const buddy_ptr = @intFromPtr(node) + block_size;
                    const buddy = @as(*Node, @ptrFromInt(buddy_ptr));

                    buddy.next = self.free_lists[order];
                    self.free_lists[order] = buddy;
                }

                const ptr_addr = @intFromPtr(node);
                const block_idx = (ptr_addr - self.heap_start) / min_block_size;
                const num_blocks = @as(usize, 1) << @intCast(req_order);
                for (0..num_blocks) |i| {
                    self.setAllocated(block_idx + i, true);
                }

                return @as([*]u8, @ptrFromInt(ptr_addr))[0..size];
            }
        }
        return null;
    }

    /// Free allocated block.
    pub fn free(self: *KernelHeap, ptr: []u8) void {
        const ptr_addr = @intFromPtr(ptr.ptr);
        if (ptr_addr < self.heap_start or ptr_addr >= self.heap_end) return;

        const block_idx = (ptr_addr - self.heap_start) / min_block_size;
        const order = sizeToOrder(ptr.len);
        const num_blocks = @as(usize, 1) << @intCast(order);
        for (0..num_blocks) |i| {
            self.setAllocated(block_idx + i, false);
        }

        self.freeBlock(ptr_addr, order);
    }

    fn freeBlock(self: *KernelHeap, ptr_addr: usize, order: usize) void {
        var current_addr = ptr_addr;
        var current_order = order;

        while (current_order < max_order) {
            const block_idx = (current_addr - self.heap_start) / min_block_size;
            const buddy_idx = block_idx ^ (@as(usize, 1) << @intCast(current_order));
            const buddy_addr = self.heap_start + buddy_idx * min_block_size;

            if (buddy_addr >= self.heap_end or self.isAllocated(buddy_idx)) {
                break;
            }

            // Remove buddy from its free list
            if (self.removeFromFreeList(buddy_addr, current_order)) {
                // Merge buddy
                if (buddy_addr < current_addr) {
                    current_addr = buddy_addr;
                }
                current_order += 1;
            } else {
                break;
            }
        }

        const node = @as(*Node, @ptrFromInt(current_addr));
        node.next = self.free_lists[current_order];
        self.free_lists[current_order] = node;
    }

    fn removeFromFreeList(self: *KernelHeap, addr: usize, order: usize) bool {
        var prev: ?*Node = null;
        var curr = self.free_lists[order];
        while (curr) |node| {
            if (@intFromPtr(node) == addr) {
                if (prev) |p| {
                    p.next = node.next;
                } else {
                    self.free_lists[order] = node.next;
                }
                return true;
            }
            prev = node;
            curr = node.next;
        }
        return false;
    }

    pub fn allocator(self: *KernelHeap) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc_adapter,
                .resize = resize_adapter,
                .remap = remap_adapter,
                .free = free_adapter,
            },
        };
    }

    fn alloc_adapter(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *KernelHeap = @ptrCast(@alignCast(ctx));
        const result = self.alloc(len, ptr_align.toByteUnits());
        return if (result) |r| r.ptr else null;
    }

    fn resize_adapter(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx; _ = buf; _ = buf_align; _ = new_len; _ = ret_addr;
        return false; // Resizing not directly supported by buddy allocation without remap
    }

    fn free_adapter(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = buf_align; _ = ret_addr;
        const self: *KernelHeap = @ptrCast(@alignCast(ctx));
        self.free(buf);
    }

    fn remap_adapter(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx; _ = buf; _ = buf_align; _ = new_len; _ = ret_addr;
        return null;
    }
};

test "Buddy Allocator - Direct Alloc and Free" {
    const allocator = std.testing.allocator;
    // Simulate raw memory heap (64KB heap)
    const mem_raw = try allocator.alloc(u8, 65536);
    defer allocator.free(mem_raw);

    var heap = KernelHeap.init(@intFromPtr(mem_raw.ptr), 64);
    
    // Allocate 128 bytes
    const block1 = heap.alloc(120, 64).?;
    try std.testing.expect(block1.len == 120);

    // Allocate 512 bytes
    const block2 = heap.alloc(500, 64).?;
    try std.testing.expect(block2.len == 500);

    // Free both
    heap.free(block1);
    heap.free(block2);
}
