# SEAL-RV 2.0 SoC Specification (Phase 01 Baseline)

## Status

This is the proposed architecture baseline for review. It specifies target behavior; it does not claim that the SoC or any listed peripheral exists in RTL. Phase 01 is documentation and infrastructure work. Hardware implementation begins only after this baseline is reviewed.

## Product target

SEAL-RV is a little-endian, 32-bit embedded SoC for secure edge inference. The intended system contains an RV32IMC-class CPU, a 32-bit Wishbone-B4 interconnect, 4 KiB boot ROM, 32 KiB SRAM, eight PMP entries, a bus firewall, interrupt control, two DMA channels, AES-128, SHA-256, an INT8/INT4 accelerator, ECC, UART, GPIO, SPI, I2C, timers, watchdog, debug/performance counters, and low-power controls.

All blocks are future targets. Their presence in this document is not evidence of implementation, verification, synthesis, or physical signoff.

## System-level contract

- CPU-visible addresses and data are 32 bits. Memory is byte-addressed and little-endian.
- The CPU executes in machine mode in the initial system. User mode and virtualization are out of scope unless added by a later reviewed revision.
- Instruction and data accesses share the SoC interconnect. Boot ROM is read-only; SRAM is read/write and has a 32 KiB logical capacity.
- CPU and DMA are bus masters. DMA is confined by the bus firewall and programmed ranges; access violations return an error and raise an interrupt.
- Each peripheral uses a documented 32-bit register window. Reserved and unmapped accesses return a bus error rather than silently aliasing another device.
- Reset and clock behavior follow [RESET_AND_CLOCK_SPEC.md](RESET_AND_CLOCK_SPEC.md). All clock gating is controlled by integrated clock-gating cells or clock enables; fabric logic must not create clocks with combinational gates.
- Interrupt IDs, address windows, privilege checks, byte enables, reset values, and error behavior are specified in the companion documents before RTL for each block is accepted.

## Proposed system composition

The CPU and two DMA channels request the interconnect. A central decoder and arbiter route transactions to ROM, ECC-protected SRAM, security/AI engines, and peripheral registers. PMP checks CPU-originated accesses. A separate firewall checks DMA and any other non-CPU master. Interrupt sources feed a machine-mode interrupt controller. A clock/reset controller sequences domains and wake events.

The bus is proposed as 32-bit Wishbone B4 Classic with one outstanding transaction per master. This is a review decision, not an existing interface. See [BUS_SPECIFICATION.md](BUS_SPECIFICATION.md) and [IMPLEMENTATION_ROADMAP.md](IMPLEMENTATION_ROADMAP.md).

## Security and boot

Boot ROM is the immutable first-stage code boundary. Secure boot must authenticate the next image before control is transferred. SHA-256 supplies a digest, but AES and SHA alone do not authenticate a signature. A signature algorithm and immutable trust-anchor implementation must be selected before secure boot is claimed complete. Key-vault keys are never readable through ordinary bus reads and must be zeroized on the specified reset/tamper events.

The TRNG block in the architecture is an interface to a characterized entropy source, not an entropy source by itself. Entropy quality, conditioning, health tests, and failure response require a separate implementation and evidence. Cryptographic implementations must be reviewed for timing and leakage; no claim of resistance to all side-channel attacks is permitted.

## Error and exception policy

An unmapped, prohibited, or unsupported bus access completes with an error response and must not be acknowledged as a successful transfer. CPU access faults, illegal instructions, misalignment behavior, interrupt priority, and trap CSRs are architecturally visible CPU behavior and must be specified and tested before the CPU phase closes. A timeout is required for a non-responsive slave so a master cannot hold the system indefinitely; timeout value and recovery policy remain to be selected.

## Acceptance boundary

This specification becomes an implementation contract only after review. Each block must have an interface/register specification, reset values, directed and negative tests, and lint/synthesis evidence before SoC integration. ASIC readiness additionally requires technology-specific timing, DRC, LVS, antenna, and signoff evidence.
