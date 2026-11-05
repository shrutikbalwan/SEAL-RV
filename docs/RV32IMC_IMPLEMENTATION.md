# Phase 03 — RV32IMC and machine mode

## Status and compliance statement

The core now implements RV32I plus the eight RV32M multiply/divide operations, the RV32C integer instruction set, a machine-mode CSR subset, synchronous trap entry, MRET, machine external/timer interrupts, and WFI. It remains a single-issue multicycle core. These claims describe the implemented RTL and directed tests; **full RV32IMC architectural compliance is not claimed**. The official RISC-V architectural test suite has not been run.

## RV32M

Supported OP encodings are MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, and REMU. The current implementation computes results combinationally in the execute path. Divide by zero returns all ones for DIV/DIVU and the dividend for REM/REMU. Signed overflow (`0x80000000 / 0xffffffff`) returns `0x80000000`, with remainder zero. These operations do not raise arithmetic exceptions.

## RV32C and fetch contract

The decompressor implements the RV32C integer encodings: ADDI4SPN, LW, SW, ADDI/NOP, JAL, LI, ADDI16SP, LUI, SRLI, SRAI, ANDI, SUB/XOR/OR/AND, J, BEQZ, BNEZ, SLLI, LWSP, JR, MV, EBREAK, JALR, ADD, and SWSP. Reserved encodings raise illegal-instruction traps; defined HINT encodings execute as NOPs. Floating-point compressed encodings are not supported because F/D are not part of this profile.

`instr` is a rolling 32-bit fetch window: `instr[15:0]` is the halfword at `pc`, and `instr[31:16]` is the next halfword. The instruction source must assemble this window across aligned memory words when needed. A compressed instruction advances PC by two; a 32-bit instruction advances it by four, including when it begins at a halfword address. `IALIGN=16`; JALR clears bit 0. The instruction port still has no ready/error handshake or fetch-fault reporting.

## Machine-mode CSRs

Implemented CSRs are `mstatus` (MIE/MPIE with MPP hardwired to M), read-only `misa` (RV32IMC), `mie` (MEIE/MTIE), read-only `mip` (MEIP/MTIP from the interrupt inputs), `mtvec`, `mepc`, `mcause`, `mtval`, `mcycle` and `minstret` with high halves, plus read-only `cycle`/`instret` aliases. Unknown CSRs and writes to read-only CSRs cause illegal-instruction traps. CSR register and immediate forms of CSRRW/CSRRS/CSRRC are implemented with their standard zero-source write suppression rules.

Only machine privilege is implemented. `mstatus.MPP` reads as M and is forced to M on writes/returns. `mtvec` supports direct and vectored modes; vectored interrupts use `BASE + 4*cause`. `mepc[0]` is hardwired to zero. The machine counters are 64-bit; low/high halves are independently readable and writable through machine counter addresses. Counter write/retirement corner semantics have directed but not architectural-suite coverage.

## Traps, interrupts, and WFI

Exceptions and interrupts update `mepc`, `mcause`, `mtval`, and trap status, then redirect PC through `mtvec`. `trap_valid` is a one-cycle event pulse; trap detail outputs retain the last event. ECALL, EBREAK, illegal instructions, load/store access faults, and misalignment faults are recorded. MRET restores MIE from MPIE and returns to `mepc`.

The only external interrupt sources are synchronous `irq_external` and `irq_timer` inputs, reflected in MEIP/MTIP. `mie` implements MEIE and MTIE. When both are pending, external interrupt has priority over timer interrupt. Global MIE gates interrupt entry while executing. WFI retires and advances PC; it sleeps until a locally enabled timer/external interrupt is pending. A locally enabled pending interrupt wakes WFI even when global MIE is clear; in that case execution resumes without trap entry. Interrupt pins must be synchronized to `clk` by the integration layer.

## Verification and build

`verification/cocotb/test_rv32i.py` includes directed RV32I regressions plus RV32M edge cases, mixed-width compressed streams (including 32-bit instructions at halfword addresses), compressed memory/control-flow operations, CSR/trap/MRET tests, interrupt-priority/masking tests, and WFI wake-up checks. The tests do not replace the official RISC-V architectural tests. `verification/asm/rv32i_tests/rv32i_all.S` remains an RV32I source; no RISC-V cross-compiler was available to build it.

Run `make test-cocotb`, `make sim`, `make lint`, and `make synth` with the required tools installed. A passing local run is evidence for these tests only; it does not establish full ISA compliance, privileged-architecture compliance, formal correctness, security properties, or physical signoff.

## Remaining limitations

The core has no user/supervisor modes, delegation, software interrupts, `mtvec` reset ROM contents, debug mode, performance event counters, instruction-fetch wait/error protocol, or PMP. Interrupt synchronizers and timer compare logic belong to integration and are absent. M operations use combinational multiply/divide and have no constant-latency or area claim. The current test suite is directed and does not include the official riscv-arch-test or a formal proof of decoder/decompressor correctness.
