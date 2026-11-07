# Wishbone-B4 Bus Specification

This specification defines the implemented Phase 04 subsystem. The RTL implements the classic, single-outstanding subset described below. It does not implement pipelined B4 (`CTI`/`BTE`) or `RTY`.

## Selected profile

**Implemented:** Wishbone B4 Classic, synchronous, 32-bit byte address and data, little-endian lanes, one global outstanding transfer. Signals are `CYC`, `STB`, `WE`, `ADR`, `DAT_W`, and `SEL` from master; slave returns `DAT_R`, `ACK`, or `ERR`. `CTI`, `BTE`, and `RTY` are absent.

## Transfer rules

- A master presents stable address, direction, select, and write data while a request is active. `CYC` and `STB` remain asserted until termination.
- Exactly one of `ACK` or `ERR` terminates a transfer. They must never be asserted together. A slave must not produce a response without a selected request.
- `SEL[n]` selects byte lane `n`; `SEL=0000` is invalid and returns `ERR`. Byte lane 0 corresponds to the least-significant byte at the lowest address.
- On a successful write, only selected byte lanes change. A read returns the 32-bit aligned word; CPU load extraction/sign extension is performed by the CPU or its data path.
- All accesses are 32-bit words; `ADR[1:0]` are preserved for target decode but CPU adapter aligns data addresses to word boundaries. CPU byte lanes are carried in `SEL`; lane 0 is the least-significant byte. `SEL=0` returns `ERR`.
- The CPU adapter holds its request fields until termination, sends `SEL=1111` for reads, preserves write byte strobes, and maps Wishbone `ERR` to the CPU ready/error response.
- Address decode selects exactly one of ROM (`0x0000_0000`–`0x0000_0FFF`), SRAM (`0x1000_0000`–`0x1000_7FFF`) or peripheral window (`0x4000_0000`–`0x4000_FFFF`). Other addresses return `ERR`. The Phase 06 `peripheral_subsystem` refines its window to implemented UART, GPIO, timer, interrupt-controller, and watchdog pages; unimplemented pages return `ERR`.
- The arbiter is round-robin between CPU master 0 and DMA master 1. Only one master is forwarded at once. Grant persists until termination, master withdrawal, reset, or timeout. A response is delivered only to the owner. After completion, priority rotates to the other master.
- Default timeout is 16 clocks from grant. If no `ACK`/`ERR` arrives, the owner receives a one-cycle `ERR`; the target request is withdrawn. Reset asynchronously clears arbitration state and error response state, aborting the transaction without a late acknowledgement.
- The unmapped/invalid-select error target returns `ERR` on the cycle after request recognition. `ACK` and `ERR` are mutually exclusive. No response is valid without a request owned by the arbiter.
- Reset aborts in-flight requests and clears response outputs. Masters restart only after reset release. No stale `ACK` may terminate a post-reset request.

## Arbitration and protection

CPU and DMA requests are arbitrated round-robin. Locking/atomic bus cycles are out of scope while the A extension is excluded. PMP and the DMA firewall are not yet connected to this interconnect.

## CDC and timing

All initial bus participants share a synchronous clock. A future asynchronous peripheral domain must cross through a reviewed CDC bridge; direct unsynchronized Wishbone signals are prohibited. Response latency and timeout thresholds must be parameters with a documented default before integration.

## Verification and formal properties

The bus testbench checks single-master transfers, simultaneous requests, contention, delayed/backpressured targets, byte enables, decode boundaries, unmapped and empty-select errors, reset abort, ordering, and timeout. `FORMAL` assertions in arbiter/adapter/interconnect check owner routing, stable stalled fields, one-hot target selection, and termination exclusivity. These assertions have not yet been run in a formal engine. The current testbench uses independent target state machines and independent master drivers; additional randomized seeds and formal proof remain future verification work.
