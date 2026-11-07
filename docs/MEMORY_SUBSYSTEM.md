# SEAL-RV Memory Subsystem

Phase 05 implements the initial 32-bit little-endian memory system. Addresses are byte addresses.

| Region | Base | Last byte | Size | Behavior |
|---|---:|---:|---:|---|
| Boot ROM | `0x0000_0000` | `0x0000_0FFF` | 4 KiB | Read-only; CPU reset fetch address |
| Main SRAM | `0x1000_0000` | `0x1000_7FFF` | 32 KiB | Read/write, byte-lane writes |

Other addresses return Wishbone `ERR`; ROM writes and empty `SEL` return `ERR`. Decode uses the full address and does not mirror. The existing CPU rejects misaligned halfword and word operations before issuing a bus request. The Wishbone port accepts aligned 32-bit words with any nonzero lane mask; stores update the indicated bytes. `DAT_R` is the aligned 32-bit word and CPU load logic selects/sign extends subwords.

## Timing and reset

The Wishbone slave samples a request at a rising edge and asserts exactly one of `ACK` or `ERR` during the following cycle, while `CYC` and `STB` remain asserted: one-cycle response latency. Master fields must remain stable until termination. Back-to-back transactions are supported when the master drops and reasserts the request between transfers. Asynchronous active-low reset clears pending responses and aborts in-flight accesses. Memory arrays are not reset. ROM initializes from `hw/tb/boot_image.hex`; its unused words are NOP-filled for simulation. SRAM may load a simulation image through `SRAM_INIT_FILE`, otherwise contents are unspecified until written. The default image path is relative to the simulation working directory.

The CPU fetch interface predates the Wishbone bus and has no wait signal. `fetch_data` is a combinational 32-bit window with its low halfword at `fetch_addr`, including addresses in the upper half of an aligned word; instruction fetch therefore has zero-cycle combinational latency. Out-of-ROM fetch addresses return a NOP and do not alias ROM. The core's current reset PC is zero. The separate Wishbone ROM port uses one-cycle response latency.

## Simulation image and smoke program

`hw/tb/boot_image.hex` begins with compressed NOPs at addresses 0 and 2 to exercise upper-halfword instruction fetch, then sets `sp` inside the SRAM window, pushes and pops 42, writes and reads a separate data word, and exercises byte and halfword stores and loads before looping. `hw/tb/memory_subsystem_tb.sv` runs that image on `cpu_core` through `wb_cpu_adapter`. It also checks first and last valid ROM/SRAM words, the first invalid address after each region, high-address unmapped decode, all byte lanes, byte and halfword read-after-write through the CPU, consecutive Wishbone write cycles, empty selects, ROM write protection, reset cancellation of a pending response, SRAM retention across reset, and absence of stale responses. Run with `make sim` where Icarus Verilog is installed.

## ASIC macro replacement (SKY130)

`wb_sram.sv` and `boot_rom.sv` are behavioral simulation models, not ASIC memory implementations. Replace the array storage with technology wrappers instantiated from the selected SKY130-compatible SRAM compiler/macro, keeping wrappers separate from these behavioral modules. The integration must document the chosen macro dimensions, byte-write support or read/modify/write adaptation, read-during-write behavior, port count, clock polarity, output latency, setup/hold and timing constraints, power pins, test/MBIST access, and any required initialization strategy. Adapt the wrapper to preserve the one-cycle Wishbone contract or update the bus/CPU wait-state contract and verification together. ROM contents need a mask-ROM or loaded nonvolatile implementation; the simulation `$readmemh` mechanism does not synthesize as a production ROM. SRAM reset must not imply clearing the physical macro. No ECC is implemented in this initial phase; the prior architectural proposal for SECDED remains future work.
