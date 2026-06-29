# Keystone TEE Integration

Clarigggz OS will use the in-house **keystone-zig** Security Monitor as its native Trusted Execution Environment (TEE). This document describes the integration contract and the foundations already present in the Clarigggz tree.

**Upstream (WIP, do not fork logic here):** `~/code/nathfavour/keystore/keystone-zig`

---

## Why Keystone

| Layer | Role |
|---|---|
| **M-mode SM** (`keystone-sm`) | PMP arbiter, enclave metadata, SBI handler — root of trust |
| **S-mode Clarigggz** | Core Broker, capabilities, IPC, scheduler |
| **Secure enclaves** | Isolated Zig workloads (`wallet-core`, `biometric`, `camera-vault`) |
| **Capabilities** | Gate *who may invoke* enclave/keychain operations |
| **PMP** | Gate *what memory is reachable* — hardware enforcement |

Capabilities and PMP are complementary: Clarigggz grants `CAP_ENCLAVE` / `CAP_KEYCHAIN_SLOT`; Keystone enforces physical isolation.

---

## Boot Chain (target)

```
Reset → keystone-sm @ 0x8000_0000
          → PMP init, SM keys (phase 3)
          → mret → Clarigggz kmain @ 0x8020_0000
```

Clarigggz already links at `0x8020_0000` (`arch/riscv64/k1/kernel.ld`), matching keystone-zig `layout.qemu_virt.kernel_base`.

Enclave private memory is carved from `0x9000_0000` (256 MiB pool).

---

## Clarigggz Keychain

The **Clarigggz Keychain** (`core/tee/keychain.zig`) is the kernel broker for all sensitive material:

| Item kind | Use |
|---|---|
| `passkey` | WebAuthn / FIDO credentials |
| `biometric_template` | Tactile ID sensor templates |
| `seed_material` | Wallet / signing roots |
| `liability_record` | Intent-to-unlock audit trail |
| `attestation_bundle` | Keystone SM reports (future) |

### TEE backends

| Build flag | Backend | Module |
|---|---|---|
| `-Dtee_backend=stub` (default) | In-memory / MMIO vault | `core/tee/stub_backend.zig` |
| `-Dtee_backend=keystone` | SBI `0x08424b45` bridge | `core/tee/keystone_backend.zig` |

```bash
zig build kernel -Dtee_backend=stub      # simulator / pre-SM bring-up
zig build kernel -Dtee_backend=keystone  # requires SM as reset vector
```

### Capability model

New capability types in `core/capability.zig`:

- `enclave` — `object_id` = Keystone EID; rights gate `run` / `destroy`
- `keychain_slot` — `object_id` = sealed item ID; rights gate `read` / `write`

Only the Core Broker invokes SBI host FIDs (≤ 2999). User-space adapters use IPC (`KeychainPort`, protocol `0xCAF5`) or derived capabilities.

---

## SBI Contract

Mirrored in `core/tee/sbi_contract.zig` (will become a `keystone` module import):

| FID | Operation |
|---|---|
| 2001 | `create_enclave` |
| 2002 | `destroy_enclave` |
| 2003 | `run_enclave` |
| 2005 | `resume_enclave` |
| 3002 | `attest_enclave` (enclave-only) |
| 3003 | `get_sealing_key` (enclave-only) |

Host creates enclaves with `CreateArgs`: EPM region, UTM shared buffer, runtime/user/free layout.

---

## Planned Secure Enclaves

| Enclave | Protects | Clarigggz consumer |
|---|---|---|
| `biometric` | Tactile ID templates | `components/tactile_id` |
| `wallet-core` | Seeds, passkeys, signing | Future wallet adapter |
| `camera-vault` | Raw ISP buffers | Future vision pipeline |

Pattern: freestanding Zig enclave, UTM for host IPC, `exit_enclave` / `stop_enclave` for edge calls.

---

## Integration Sequence

1. **keystone-zig P0** — Fix QEMU S-mode `mret` handoff (SM → Clarigggz)
2. **Package import** — Add keystone-zig as path dependency in `build.zig`; replace `sbi_contract.zig` duplicate
3. **Boot swap** — QEMU loads `keystone-sm` as `-kernel`; Clarigggz as S-mode payload
4. **Keychain enclave** — Move seal/open crypto into first secure enclave; stub backend remains for CI
5. **Phase 3 crypto** — Real attestation + sealing before production passkeys
6. **K1 profile** — Extend `core/tee/layout.zig` when keystone-zig adds SpacemiT silicon map

---

## Files (Clarigggz)

```
core/tee/
  root.zig              # initBackend(), initKeychain()
  layout.zig            # Memory map contract (aligned with keystone-zig)
  sbi_contract.zig      # SBI ABI mirror (temporary)
  backend.zig           # TeeBackend vtable
  stub_backend.zig      # Development vault
  keystone_backend.zig  # SBI bridge (WIP)
  keychain.zig          # Clarigggz Keychain API
protocols/keychain.zig  # KeychainPort IPC (0xCAF5)
```

Security manager (`core/security.zig`) routes biometric digest and liability logging through `clarigggz_keychain`.

---

## References

- keystone-zig: `docs/architecture.md`, `lib/sbi.zig`, `lib/layout.zig`
- Clarigggz: `docs/docs/CONSTITUTION.md` (Article IV — Liability Shift)
- Keystone spec: SBI extension `0x08424b45`, FID ranges 2000–2999 (host), 3000–3999 (enclave)
