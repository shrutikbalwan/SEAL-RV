# Wishbone-B4 Bus Specification

This is the proposed SoC interface contract. No Wishbone interface exists in the current RTL.

## Selected profile

**Provisional:** Wishbone B4 Classic, synchronous, single 32-bit address and 32-bit data path, byte addressing, little-endian lane order, and at most one outstanding transfer per master. `CYC`, `STB`, `WE`, `ADR`, `DAT`, and `SEL` are used; `ACK`, `ERR`, and optionally `RTY` are slave responses. `CTI`/`BTE` and pipelined multiple outstanding transfers are not used in the initial profile. Whether retry is supported remains a decision; the recommended initial contract is no `RTY` and bounded `ACK` or `ERR`.

## Transfer rules

- A master presents stable address, direction, select, and write data while a request is active. `CYC` and `STB` remain asserted until termination.
- Exactly one of `ACK` or `ERR` terminates a transfer. They must never be asserted together. A slave must not produce a response without a selected request.
- `SEL[n]` selects byte lane `n`; `SEL=0000` is invalid and returns `ERR`. Byte lane 0 corresponds to the least-significant byte at the lowest address.
- On a successful write, only selected byte lanes change. A read returns the 32-bit aligned word; CPU load extraction/sign extension is performed by the CPU or its data path.
- A transfer may not be silently split by a slave. Any supported unaligned access policy must be handled above the slave and documented. The initial recommendation is to return an access error for unsupported unaligned word transfers.
- Address decode selects no more than one slave. Unmapped and prohibited transactions return `ERR` within a bounded number of clocks.
- Reset aborts in-flight requests and clears response outputs. Masters restart only after reset release. No stale `ACK` may terminate a post-reset request.

## Arbitration and protection

CPU and DMA requests are arbitrated. The proposed arbiter is round-robin with bounded service when all requests target responsive slaves. Locking/atomic bus cycles are out of scope while the A extension is excluded. CPU accesses are checked by PMP. DMA accesses are checked by a firewall using programmed allowed ranges and read/write permissions; default policy is deny until configured.

## CDC and timing

All initial bus participants share a synchronous clock. A future asynchronous peripheral domain must cross through a reviewed CDC bridge; direct unsynchronized Wishbone signals are prohibited. Response latency and timeout thresholds must be parameters with a documented default before integration.

## Verification requirements

Check stable request fields under stall, one-hot decode, no response without request, mutually exclusive termination, reset abort, byte select behavior, unmapped error, protection denial, and bounded completion. Add assertions for these protocol properties and randomized backpressure tests before bus integration is accepted.
