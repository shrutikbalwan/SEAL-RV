# SEAL-RV

SEAL-RV is a secure, energy-efficient RISC-V edge-AI SoC project. The current RTL includes an RV32IMC/machine-mode CPU implementation and an independent counter, with directed rather than official architectural compliance testing. The interconnect, protection, memories, peripherals, cryptography, AI, DMA, ECC, and physical implementation remain future work.

Phase 01 architecture proposals and the source-based audit are in [`docs/`](docs/SOC_SPEC.md). Proposed capabilities are targets and must not be read as implemented features.

## Local build

With Icarus Verilog, Verilator, Yosys, GNU Make, Python 3, and Cocotb installed:

```sh
make sim          # counter and directed CPU SystemVerilog tests
make test-cocotb  # CPU Cocotb tests for implemented behavior
make lint         # Verilator lint smoke checks
make synth        # Yosys counter and CPU synthesis smoke checks
make all          # sim, Cocotb, lint, synth
```

The same checks run in GitHub Actions. See [`docs/REPOSITORY_AUDIT.md`](docs/REPOSITORY_AUDIT.md) for the observed baseline, tool limitations, and current phase gate.
