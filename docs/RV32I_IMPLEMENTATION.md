# Phase 02 — RV32I CPU implementation (baseline)

This document records the Phase 02 RV32I baseline and is superseded for current CPU behavior by [RV32IMC_IMPLEMENTATION.md](RV32IMC_IMPLEMENTATION.md). The multicycle fetch, trap, and ISA contract changed in Phase 03.

## Status

The checked-in `cpu_core` implements the RV32I integer arithmetic, control-flow, and load/store instructions listed below. This is a multicycle, single-issue core with one instruction in flight. Ordinary instructions complete in one execute cycle; loads and stores enter a request/wait state and hold their data request until acknowledged. There is no instruction-side handshake: `instr` must continuously present the instruction at `pc`.

The core is a functional RTL milestone, not a complete privileged RISC-V implementation or a tapeout-ready subsystem. It has a sticky trap output and halts on traps; it does not vector to a handler.

## Implemented behavior

- LUI, AUIPC; JAL, JALR; BEQ, BNE, BLT, BGE, BLTU, BGEU.
- LB, LH, LW, LBU, LHU; SB, SH, SW.
- ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND.
- ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI.
- Exact opcode/funct validation for these encodings. Unsupported or reserved encodings trap with cause 2, preserve the PC, and do not write a destination register.
- FENCE with `fm=0`, `rd=0`, `rs1=0`, and `rs2=0` is accepted as a no-op in the single-hart core. FENCE.I and FENCE.TSO are unsupported.
- ECALL and EBREAK report machine-environment-call and breakpoint causes respectively. No machine CSRs, privilege transitions, interrupt handling, or MRET are implemented.
- x0 reads zero and ignores writes. All register-file entries reset asynchronously to zero when active-low `rst_n` is asserted.
- PC resets asynchronously to zero. Instruction addresses advance by four. Branch/JAL targets must be four-byte aligned; JALR clears bit 0 and then reports an instruction-address-misaligned trap if bit 1 remains set.
- Byte and halfword transfers use little-endian lanes on an aligned 32-bit data bus. `dmem_wstrb` identifies active byte lanes and `dmem_wdata` is shifted into those lanes. Loads use the address offset to select and sign/zero extend the requested value.
- Halfword and word misalignment traps before issuing a bus request. Bus errors map to load-access-fault cause 5 and store-access-fault cause 7.

## Core interface and integration contract

`pc` and `instr` form a combinational instruction-fetch contract. The instruction source must return the word for the current PC with no wait state. Data requests use `dmem_valid`, `dmem_write`, aligned `dmem_addr`, `dmem_wdata`, and `dmem_wstrb`. A target accepts a request only on a rising edge where `dmem_valid && dmem_ready`; `dmem_error` qualifies that acceptance. While waiting, request fields remain stable. Read data is a 32-bit aligned word. A load response is consumed on the accepting edge.

`trap_valid`, `trap_pc`, `trap_cause`, and `trap_value` remain asserted/stable after a synchronous exception until reset. The core then remains halted. There is no resume or trap-return input.

## Verification

`verification/cocotb/test_rv32i.py` drives instruction words from a PC-indexed memory model and checks all implemented instruction families, signed/unsigned comparisons, immediate boundaries/signs, dependencies, branches, jumps, load/store lanes, stalls, bus faults, illegal encodings, and reset during idle and a pending memory request. `verification/asm/rv32i_tests/rv32i_all.S` is an additional readable smoke program, not currently assembled by CI. The Cocotb suite is not the official RISC-V architectural test suite.

Run with `make test-cocotb` (Cocotb and Icarus required). Run `make sim`, `make lint`, and `make synth` for the SystemVerilog benches and tool smoke checks.

## Deferred behavior and limitations

RV32M, RV32C, A, Zicsr, privilege-state CSRs, machine interrupt/trap entry, MRET, WFI, debug, atomics, cache coherence, instruction fetch faults, and PMP are not implemented. The instruction port has no ready/error response, so fetch access faults are not modeled. Data memory supports one outstanding transfer and does not implement Wishbone signals directly. Misaligned accesses trap rather than being split. FENCE is a no-op because this core has no cache or second hart. ECALL/EBREAK halt through the exposed trap record rather than executing architectural trap entry. No performance, area, constant-time, security, or physical-signoff claims are made.
