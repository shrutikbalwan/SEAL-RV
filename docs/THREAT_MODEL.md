# SEAL-RV Threat Model

## Scope and status

This is an initial threat model for architectural planning. It does not establish that mitigations exist or that the SoC is secure. Physical attacks and implementation leakage require later testing and specialist review.

## Assets

- Boot code, firmware authenticity, and execution integrity.
- Secret encryption/authentication keys and derived key material.
- Model weights, input data, and intermediate accelerator state where confidentiality is required.
- CPU privilege state, PMP settings, firewall policy, and debug locks.
- SRAM/ROM contents, DMA descriptors, interrupt state, entropy source health, and availability.

## Trust boundaries and assumed adversary

Boot ROM and immutable trust-anchor storage form the intended root boundary. CPU software, DMA descriptors, external serial inputs, accelerator input buffers, and bus masters are potentially untrusted. The adversary may supply malformed firmware/data, issue unauthorized bus requests through compromised software or DMA programming, exploit reset/power sequencing, and observe externally visible timing or I/O. The initial model does not assume resistance to invasive fault injection, decapsulation, or all power/EM side channels.

## Threats and required controls

| Threat | Required architectural control | Evidence required later |
|---|---|---|
| Unauthorized boot image | ROM authenticates image against immutable trust anchor before handoff; anti-rollback policy | Negative signature/hash tests, key provisioning review, boot fault injection plan |
| CPU access outside policy | Eight-entry PMP, precise access faults, locked policy as required | Boundary and privilege tests, formal access properties |
| DMA exfiltration or overwrite | Default-deny bus firewall, range/permission checks on every beat | Boundary, overflow, concurrent reprogramming, formal non-bypass properties |
| Key readback or stale key | Non-readable key vault, explicit zeroization, restricted debug path | Bus negative tests, reset/tamper zeroization tests |
| Weak or failed entropy | Health-tested TRNG interface, fail-closed key-generation behavior | Entropy-source characterization, health-test and stuck-source tests |
| Malformed bus behavior | Bounded error response, no alias, reset abort semantics | Assertions and randomized protocol tests |
| ECC corruption | SECDED correction/detection, error reporting, defined uncorrectable response | Exhaustive single-bit and representative multi-bit injection tests |
| Debug abuse | Locked/disabled production debug policy, authenticated lifecycle if supported | Lifecycle and access-control tests; physical review |
| Timing/power leakage | Constant-time design where appropriate, masking/hardening as justified | Side-channel measurements; no claim of universal resistance |
| Availability exhaustion | Bounded arbitration, DMA limits, watchdog recovery | Saturation/fairness and timeout tests |

## Cryptographic boundary

AES-128 confidentiality does not authenticate a firmware image. SHA-256 is a digest, not a signature. Secure boot needs an authenticated manifest and a verified signature or MAC under an explicitly selected trust policy. Key storage, key derivation, nonce/counter handling, rollback state, and failure behavior need separate specifications. This project must not claim constant-time cryptography resists all side-channel attacks.

## Open security decisions

Select the signature scheme and trust-anchor storage; define key lifecycle and reset retention; choose TRNG source and conditioning; define secure debug lifecycle; specify rollback protection; define ECC response and fault logging; and determine which assets require confidentiality. These choices gate any statement that secure boot or the SoC security architecture is complete.
