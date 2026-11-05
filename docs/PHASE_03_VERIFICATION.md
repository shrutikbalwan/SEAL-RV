# Phase 03 — CPU Verification Status

This document previously contained a report of 11 executed tests, but the checked-in sources did not contain those 11 tests or a reproducible command/result record. Those counts are withdrawn and must not be treated as verified results. The Phase 01 source audit is in `REPOSITORY_AUDIT.md`.

## Current verification assets

- `hw/tb/counter_tb.sv`: counter enable/reset/count directed test.
- `hw/tb/cpu_tb.sv`: hex-program CPU smoke test.
- `verification/tb/cpu_tb.sv`: inline-program CPU directed check for x0 and arithmetic.
- `verification/cocotb/test_rv32i.py`: directed RV32I and Phase 03 RV32M/RV32C/machine-mode tests.

The two CPU SystemVerilog benches are smoke tests. The Cocotb suite exercises the claimed behaviors but does not establish full RV32IMC compliance. The official RISC-V architectural tests and formal verification are not run.

## Required future coverage

Next verification work should add the official riscv-arch-test suite, a RISC-V toolchain-based mixed-width binary test, randomized reference-model comparisons, privilege-spec corner cases, and protocol/formal properties before declaring architectural compliance.
