//! Trusted Execution Environment integration for Clarigggz OS.
//!
//! Backends:
//!   - `stub`     — in-memory / MMIO vault for simulator and pre-Keystone bring-up
//!   - `keystone` — PMP-isolated enclaves via keystone-zig Security Monitor (WIP)
//!
//! Upstream TEE: `~/code/nathfavour/keystore/keystone-zig`

const config = @import("config");
const std = @import("std");

pub const layout = @import("layout.zig");
pub const sbi_contract = @import("sbi_contract.zig");
pub const backend = @import("backend.zig");
pub const keychain = @import("keychain.zig");
pub const stub_backend = @import("stub_backend.zig");
pub const keystone_backend = @import("keystone_backend.zig");

pub const Keychain = keychain.Keychain;
pub const ItemKind = keychain.ItemKind;
pub const ItemId = keychain.ItemId;
pub const BackendKind = backend.BackendKind;
pub const EnclaveId = backend.EnclaveId;

/// Select TEE backend from build option `tee_backend`.
pub fn initBackend() backend.TeeBackend {
    if (keystone_backend.isRequested()) {
        return keystone_backend.init(stub_backend.defaultBase());
    }
    return stub_backend.init(stub_backend.defaultBase());
}

pub fn initKeychain() Keychain {
    return Keychain.init(initBackend());
}

test "default backend is stub unless keystone requested" {
    const tee = initBackend();
    if (keystone_backend.isRequested()) {
        try std.testing.expectEqual(backend.BackendKind.keystone, tee.vtable.kind);
    } else {
        try std.testing.expectEqual(backend.BackendKind.stub, tee.vtable.kind);
    }
}
