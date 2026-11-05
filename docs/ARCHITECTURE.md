# SEAL-RV 2.0 Architecture

## Status and design decisions

This document describes the target SoC architecture. The Phase 02 RV32I core and counter are implemented; the remaining diagram blocks are architectural targets and must not be inferred as implemented. Decisions marked **provisional** need review before their implementation phases.

## Block diagram

```text
 RV32IMC CPU -- PMP ----+
                       |
 DMA channel 0 --------+--> Wishbone-B4 Classic arbiter/decoder
 DMA channel 1 --------+       |       |       |       |
                       |      ROM    ECC SRAM  Crypto   AI
 Firewall ------------+                       |       |
                                      UART GPIO SPI I2C timers
                                      IRQ controller / watchdog
                                      debug, counters, power control
```

The diagram indicates intended connectivity only. The final master topology and whether DMA has two independent masters or one shared master are review decisions.

## CPU

- Architectural target: RV32IMC, machine mode, with machine CSR and timer/external interrupt support. The exact CSR extension/toolchain string is specified in [ISA_EXTENSIONS.md](ISA_EXTENSIONS.md).
- **Implemented for Phase 02:** multicycle control FSM with a single architectural instruction in flight; no compressed fetch. The core exposes `pc`/`instr` fetch and a simple request/ready/error data interface, not Wishbone.
- A 3-stage pipeline remains an alternative for a later measured optimization; it is not implemented.
- PMP has eight entries. TOR and NA4/NAPOT support, lock behavior, priority, reset configuration, and CSR semantics must be specified against the chosen privileged architecture version before implementation.

## Interconnect and agents

**Provisional recommendation:** Wishbone B4 Classic, 32-bit address/data, byte selects, one outstanding transfer per granted master. A central decoder maps one selected target per transfer. CPU and DMA access are arbitrated; fairness and maximum wait are specified in the bus contract. The firewall checks DMA address, direction, and transfer size before target selection. PMP checks CPU accesses; bus firewall rules do not replace PMP.

Targets are boot ROM, SRAM, security control/crypto, AI accelerator, and peripheral register banks. ROM and SRAM may be integrated into a shared target or separate targets, but each must preserve the memory map and fault behavior.

## Memory and protection

Boot ROM is 4 KiB at address zero. Main SRAM is 32 KiB at `0x1000_0000`, SECDED protected per 32-bit data word. The architectural SRAM capacity excludes parity storage. Correctable errors are corrected on reads and counted; uncorrectable errors return an error and raise a machine-check style event. Exact scrub policy and error-register details remain to be specified.

## Security and acceleration

AES-128 and SHA-256 are memory-mapped engines initially. The AI accelerator supports signed INT8 and packed signed INT4 MAC operations with explicit accumulator width, saturation/overflow behavior, alignment, and completion/error signaling. No custom CPU instruction is part of the initial contract; any CFU instruction encoding is a separate review decision.

Secure boot authenticates the image before execution. AES encryption is not a substitute for authentication. Trust-anchor storage, signature scheme, rollback policy, and key provisioning must be selected before the secure-boot milestone.

## Interrupts, debug, and performance

The proposed interrupt scheme is machine-mode timer/software/external interrupt support plus a 32-source, priority-based external controller. This is PLIC-like behavior, not a claim of full PLIC compatibility. Debug transport and halt semantics are deferred; performance counters should begin with cycle, retired-instruction, and event counters, with access governed by privilege policy.

## Clock and reset

One primary clock is assumed initially. Peripheral/accelerator clock domains may be gated using safe clock enables or characterized integrated clock-gating cells. Reset assertion is asynchronous and release is synchronized per domain. SRAM contents are not reset; security-sensitive key state is zeroized according to the reset/security policy.

## Physical implementation

**Provisional target:** SkyWater SKY130 HD standard cells. OpenLane/OpenROAD flow version, SRAM implementation, timing target, pad ring, and signoff flow are undecided. No tapeout-readiness claim is made.

## Decisions requiring review

| Topic | Proposed default | Status |
|---|---|---|
| CPU organization | Multicycle FSM | Provisional; compare with 3-stage pipeline |
| Wishbone mode | B4 Classic, one outstanding transfer | Provisional; pipelined mode deferred |
| SRAM implementation | Behavioral inferred memory first; macro later | Provisional; macro and ECC mapping need PDK review |
| External interrupts | 32-source priority controller, PLIC-like | Provisional; exact compatibility/version open |
| AI access | Memory-mapped command/data registers | Initial recommendation; CFU semantics open |
| Secure-boot trust anchor | OTP/eFuse digest or public key | Open; simulation provisioning must not be mistaken for hardware root of trust |
| Physical target | SKY130 HD | Provisional; flow and signoff constraints open |
