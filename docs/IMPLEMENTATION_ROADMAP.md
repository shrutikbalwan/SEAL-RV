# SEAL-RV 2.0 Implementation Roadmap

Phases are gated in order. A specification entry is not an implementation claim. Do not start a phase until its predecessor's review gate is accepted.

| Phase | Scope | Exit gate |
|---|---|---|
| 00 — Project definition | Product goals and repository setup | Goals and ownership recorded |
| 01 — Repository audit and architecture specification | Baseline audit, specifications, reproducible existing tests, CI/lint/synthesis smoke-flow repair | Audit matches checked-in sources; specs reviewed; CI fails on real failures; all infrastructure results recorded. Current phase. |
| 02 — CPU architecture and ISA | Select CPU organization and ISA versions; implement core incrementally | Per-module directed/negative/random tests, ISA checks, lint/synthesis, traps and bus interface specified |
| 03 — CPU verification closure | Reference-model and instruction-family verification, assertions and coverage | Required supported-profile tests pass; unsupported encodings trap; coverage gaps documented and accepted |
| 04 — Bus and memory | Wishbone fabric, arbitration, ROM, 32 KiB SRAM controller, timeout/error behavior | Protocol assertions, contention/backpressure, address boundary, ROM-write and unmapped-error tests pass |
| 05 — Protection and interrupts | PMP, DMA firewall, interrupt/timer controller, watchdog | Access-control properties and negative tests pass; reset/interrupt behavior reviewed |
| 06 — Peripherals and debug | UART, GPIO, SPI, I2C, debug/performance counters, clock/power control | Initial register blocks and CPU-level integration tests pass. Lint/synthesis and physical clock/reset review remain build-flow/integration gates; physical gating and halt/step transport are explicitly outside the initial register-block scope. |
| 07 — Security subsystem | AES-128, SHA-256, TRNG interface, key vault, secure boot policy | Known-answer and negative tests, lifecycle tests, threat review; no security claims beyond evidence |
| 08 — AI and DMA | INT8/INT4 accelerator and two DMA channels | Arithmetic corner cases, overflow/saturation, alignment, firewall and concurrency tests pass |
| 09 — SoC integration | Integrate verified modules, firmware, TinyML runtime, boot image | End-to-end simulation and software tests reproducible; all address/interrupt/reset contracts consistent |
| 10 — FPGA/ASIC implementation | SKY130 mapping, timing, SRAM integration, floorplan and physical checks | Reproducible PPA reports plus DRC/LVS/timing/antenna/signoff evidence; no tapeout claim before actual signoff |

## Required evidence at each hardware gate

Record exact tool versions and commands. Run lint, directed and negative module tests, boundary/randomized tests where meaningful, synthesis smoke, and formal properties for safety-critical protocols/access control. Resolve every regression introduced by the current phase. Keep generated logs/reports or stable CI artifacts. Do not suppress failing tests or label placeholders as complete.

## Phase 01 open choices

The multicycle versus pipeline decision, Wishbone Classic versus pipelined mode, inferred versus macro SRAM, interrupt-controller compatibility, AI CFU semantics, secure-boot trust anchor/signature, and SKY130 physical flow are documented in [ARCHITECTURE.md](ARCHITECTURE.md). Phase 02 must resolve CPU/bus prerequisites; security and physical-design choices must be resolved before their respective phases.
