# Phase 01 — RTL Development Environment

## Supported CI environment

GitHub Actions uses Ubuntu and installs Icarus Verilog, Yosys, Verilator, and GNU Make. Python 3 and Cocotb are installed for CPU co-simulation. The workflow runs counter and CPU SystemVerilog tests, Cocotb CPU tests, lint, and synthesis smoke checks.

## Local commands

```sh
make sim
make test-cocotb
make lint
make synth
```

## Known environment limits

During the Phase 01 audit on Windows, Icarus was usable and GNU Make was unavailable on `PATH`. Yosys and Verilator are bundled with OSS CAD Suite; they require its runtime library path, and Verilator also requires `VERILATOR_ROOT` to point to `share/verilator`. With those variables set, the revised synthesis and lint commands completed. The baseline runs and exact commands/results are in `REPOSITORY_AUDIT.md`.

The synthesis target covers the current counter and CPU RTL only. It is a smoke check, not a SoC PPA result. SKY130 physical implementation needs a separately versioned PDK and OpenLane/OpenROAD flow plus actual physical verification.

## Reproducibility

CI runs the same make targets on pushes and pull requests and propagates failing commands. Cocotb is pinned to 2.1.0; operating-system RTL tool packages still follow the Ubuntu runner package versions.
