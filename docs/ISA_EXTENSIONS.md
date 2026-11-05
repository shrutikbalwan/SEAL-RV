# ISA and CPU Architectural Contract

This document records the SoC target and current implementation boundary. Phase 02 implements RV32I and Phase 03 adds the RV32M/RV32C integer profile and machine-mode subset described in [RV32IMC_IMPLEMENTATION.md](RV32IMC_IMPLEMENTATION.md). Official architectural compliance has not been established.

## Proposed profile

- `RV32I`: integer base, 32 integer registers, `x0` reads as zero and ignores writes.
- `M`: integer multiply/divide instructions (`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`) with RISC-V-defined divide-by-zero and signed-overflow results.
- `C`: 16-bit compressed encodings; instruction fetch and PC advance by 2 or 4 bytes as appropriate. A 32-bit instruction may begin at a halfword boundary.
- `Zicsr`: implemented machine CSR subset for trap, interrupt, and counters.
- **Deferred:** `Zifencei`/`FENCE.I`; the current single-hart core accepts only base FENCE as a no-op.
- Machine privilege only in the first SoC. No A, F, D, B, V, S, U, or debug-spec extension is included in the initial profile.

The exact ratified ISA and privileged-architecture versions, CSR list, `misa` value, counter access policy, and toolchain string remain open SoC decisions. Do not infer extension support from the target specification.

## Required instruction families

RV32I includes LUI/AUIPC, JAL/JALR, conditional branches, byte/halfword/word loads and stores, immediate and register ALU operations, shifts, comparisons, fences, and system/trap instructions under the selected profile. M and C families above are required for the target. Every unimplemented or reserved encoding must raise an illegal-instruction exception; it must not silently write a register or behave like a NOP.

## Architectural rules to settle and verify

- `x0` is always zero. Register-file reset of x1–x31 is not architecturally required; software initializes them. Verification must not assume a value before write.
- Reset PC is `0x0000_0000`, mapping to Boot ROM.
- Branch/jump targets and link values follow the selected ISA version. C support means `IALIGN=16`; misaligned access behavior follows the selected execution environment and must be explicit.
- Loads/stores must define byte lanes, sign/zero extension, misalignment traps, access faults, and bus-error mapping.
- Machine trap CSRs and interrupt enable/delegation state must match the selected privileged architecture. `mcycle`/`minstret` presence and write access must be explicit.
- M-extension divide-by-zero and signed overflow must match the ISA, not trap unless the selected platform explicitly specifies an additional platform event.

## AI custom instruction decision

No custom CFU instruction is in the first implementation contract. The accelerator is memory-mapped. If a custom opcode is later proposed, reserve a non-conflicting encoding, define operands/results, privilege, precise exceptions, latency/handshake, interrupt behavior, and compiler/assembler support, then review it before implementation.
