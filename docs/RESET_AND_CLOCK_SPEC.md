# Reset and Clock Specification

This is the proposed system policy. Current RTL has an asynchronous active-low reset on the PC only; the register file has no reset and there is no system clock controller.

## Reset

- External reset is active-low. Assertion may be asynchronous; deassertion must be synchronized separately into every clock domain.
- Reset entry PC is `0x0000_0000` (Boot ROM). Bus masters are idle, bus response signals are inactive, interrupt outputs are masked, DMA is disabled, and peripheral enables are off after reset.
- Control/status registers take their documented reset values. Large SRAM/ROM arrays are not reset. SRAM contents are unspecified after power-up/reset and software must initialize memory before reading it.
- `x0` reads zero by construction. General registers x1–x31 are unspecified after reset unless the CPU implementation deliberately initializes them; software must not depend on a reset value.
- Key-vault secret state is zeroized on power-on reset and defined security-reset/tamper events. Warm reset behavior and retained-key policy require a security review; default recommendation is zeroize on every system reset.
- Reset aborts all in-flight bus operations. A slave must not return a stale completion after release.
- Watchdog reset cause and prior fault status may be retained only in a separately specified always-on domain; otherwise they clear. Retention is an unresolved power/reset decision.

## Clocking and low power

- Initial implementation uses one primary clock for CPU, interconnect, SRAM controller, and peripherals.
- Clock frequency and source are integration parameters; no frequency or power figure is asserted here.
- Sleep uses clock enables or characterized integrated clock-gating cells with glitch-free enable capture. Combinationally ANDing arbitrary logic into a clock is prohibited.
- Wake sources include enabled interrupts, watchdog, and explicitly configured peripheral events. Wake must restore clocks before exposing the event to the CPU.
- Any future separate clock domain requires synchronizers for single-bit controls, asynchronous FIFOs or equivalent for multi-bit data, reset-domain review, and CDC analysis.

## Existing implementation difference

The current `cpu_core` uses `always_ff @(posedge clk or negedge rst_n)` for PC reset, so its PC reset is asynchronous assertion, active-low. The register file state is unreset. This is the observed RTL baseline, not full-system behavior.
