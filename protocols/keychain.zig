/// KeychainPort — secure secret broker protocol for passkeys, biometrics, and seeds.
pub const KeychainPort = struct {
    pub const ProtocolID: u32 = 0xCAF5;

    pub const Op = enum(u8) {
        seal,
        open,
        store_passkey,
        store_biometric,
        append_liability,
        derive_sealing_key,
    };

    pub const SealRequest = struct {
        kind: ItemKind,
        label_len: u8,
        payload_len: u16,
    };

    pub const OpenRequest = struct {
        item_id: u32,
        cap_index: u8,
    };

    pub const ItemKind = enum(u8) {
        passkey = 1,
        biometric_template = 2,
        seed_material = 3,
        liability_record = 4,
        generic_secret = 5,
        attestation_bundle = 6,
    };

    pub const Response = struct {
        status: enum(u8) { ok, denied, not_found, backend_error },
        item_id: u32,
        bytes_read: u16,
    };
};
