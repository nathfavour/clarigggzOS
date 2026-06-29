//! Keystone SBI extension ABI — mirrored from keystone-zig for native integration.
//!
//! Do not duplicate logic here long-term; import the `keystone` Zig module once
//! clarigggzOS depends on keystone-zig as a path package. This file keeps the
//! host↔SM contract stable while keystone-zig is still WIP.
//!
//! Reference: `keystore/keystone-zig/lib/sbi.zig`

pub const extension_id: u32 = 0x08424b45;

pub const Fid = enum(u32) {
    create_enclave = 2001,
    destroy_enclave = 2002,
    run_enclave = 2003,
    resume_enclave = 2005,
    random = 3001,
    attest_enclave = 3002,
    get_sealing_key = 3003,
    stop_enclave = 3004,
    exit_enclave = 3006,
    call_plugin = 4000,
};

pub const fid_range_host: u32 = 2999;
pub const fid_range_enclave: u32 = 3999;

pub const Error = enum(i32) {
    success = 0,
    unknown = 100_000,
    invalid_id = 100_001,
    interrupted = 100_002,
    pmp_failure = 100_003,
    not_runnable = 100_004,
    not_destroyable = 100_005,
    region_overlaps = 100_006,
    not_accessible = 100_007,
    illegal_argument = 100_008,
    not_running = 100_009,
    not_resumable = 100_010,
    edge_call_host = 100_011,
    not_initialized = 100_012,
    no_free_resource = 100_013,
    sbi_prohibited = 100_014,
    illegal_pte = 100_015,
    not_fresh = 100_016,
    not_implemented = 100_100,
};

pub const SbiRet = struct {
    error_code: i32,
    value: usize,

    pub fn ok(self: SbiRet) bool {
        return self.error_code == @intFromEnum(Error.success);
    }

    pub fn errEnum(self: SbiRet) Error {
        return @enumFromInt(self.error_code);
    }
};

pub const PRegion = extern struct {
    paddr: usize,
    size: usize,
};

/// Host-provided enclave creation parameters (`keystone_sbi_create_t`).
pub const CreateArgs = extern struct {
    epm_region: PRegion,
    utm_region: PRegion,
    runtime_paddr: usize,
    user_paddr: usize,
    free_paddr: usize,
    free_requested: usize,
};

pub const MDSIZE: usize = 64;
pub const SEALING_KEY_SIZE: usize = 128;

pub const SealingKey = extern struct {
    key: [SEALING_KEY_SIZE]u8,
    signature: [64]u8,
};
