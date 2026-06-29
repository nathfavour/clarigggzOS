//! Embedded adapter ELF blobs (populated by `zig build embed-adapters`).
pub const Blob = struct {
    name: []const u8,
    priority: u8,
    uses_vectors: bool,
    data: []const u8,
};

pub const blobs = [_]Blob{};
