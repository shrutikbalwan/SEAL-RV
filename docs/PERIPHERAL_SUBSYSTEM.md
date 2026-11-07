# SEAL-RV Phase 06 Peripheral Subsystem

`hw/rtl/peripherals/peripheral_subsystem.sv` is a one-target Wishbone-B4 Classic peripheral block. Connect its `irq_timer` and `irq_external` outputs to `cpu_core.irq_timer` and `cpu_core.irq_external`, and connect the CPU's `pc` and new `retire` pulse to the debug inputs. `reset_request` is active high and sticky until system reset; feed it to a reset controller that latches/qualifies recovery rather than directly gating `rst_n`. The target ACKs valid accesses one clock after acceptance. A zero select, unaligned register address, invalid offset, read-only write, or access to an unimplemented page returns ERR. Registers are 32-bit little-endian; writes with byte enables merge selected bytes unless identified as W1C or command registers.

## Register maps

All offsets below are relative to the corresponding 4 KiB window in [MEMORY_MAP.md](MEMORY_MAP.md).

### UART — `0x4000_0000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | TXDATA / RXDATA | W / R | Write sends low byte when TX enabled and idle; read returns last received byte and clears RX valid/overrun |
| `0x04` | RXDATA | R | Receive data alias; clears RX valid/overrun |
| `0x08` | STATUS | R | bit 0 TX busy, bit 1 RX valid, bit 2 RX overrun |
| `0x0C` | CONTROL | RW | bit 0 TX enable, bit 1 RX enable, bit 2 TX-empty IRQ enable, bit 3 RX-valid IRQ enable |
| `0x10` | DIVIDER | RW | System clocks per serial bit; reset value is rounded `CLK_HZ/115200`, minimum 4; writes below 4 clamp to 4 |

Serial format is 8 data bits, no parity, one stop bit, LSB first. TX data writes while busy or disabled return ERR. RX samples the synchronized input near bit centers; a complete valid frame sets RX valid, a new unread frame sets overrun. UART IRQ is a level OR of the enabled TX-empty and RX-valid conditions. The default `CLK_HZ` parameter is 50 MHz (divider 434, approximately 115207 baud); software can set the divider for the actual system clock.

### GPIO — `0x4000_1000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | DATA | R/W | Read synchronized pin inputs; write output latch |
| `0x04` | DIRECTION | RW | 1 drives the corresponding output; 0 is input |
| `0x08` | IRQ_ENABLE | RW | Per-pin interrupt mask |
| `0x0C` | IRQ_TYPE | RW | 1 edge-sensitive, 0 level-sensitive |
| `0x10` | IRQ_POLARITY | RW | Edge: 1 rising / 0 falling; level: 1 high / 0 low |
| `0x14` | IRQ_PENDING | R/W1C | Sticky edge status OR active level conditions; selected written ones clear edge bits |

Each input crosses two synchronizer flip-flops. Reset direction and interrupt enables are zero; reset polarity is zero. Set polarity bits high when low inputs should not assert level interrupts. `irq_gpio` is the OR of enabled pending/active pins.

### Machine timer — `0x4000_4000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | MTIME_LO | R/W | `mtime[31:0]` |
| `0x04` | MTIME_HI | R/W | `mtime[63:32]` |
| `0x08` | MTIMECMP_LO | R/W | `mtimecmp[31:0]` |
| `0x0C` | MTIMECMP_HI | R/W | `mtimecmp[63:32]` |
| `0x10` | CONTROL | R/W | bit 0 enables MTIP |

`mtime` increments once per system clock and is not reset by ordinary register writes. `mtimecmp` resets to all ones; CONTROL resets enabled. MTIP is asserted while enabled and `mtime >= mtimecmp`. Software should write the high compare word before the low word when moving a compare from its reset value.

### SPI master — `0x4000_2000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | DATA | W/R | Write starts one byte when enabled and idle; read returns last byte received and clears valid |
| `0x04` | CONTROL | RW | bit 0 enable, bit 1 CPOL, bit 2 CPHA |
| `0x08` | DIVIDER | RW | System clocks per SCK half-period, minimum 2 |
| `0x0C` | STATUS | R | bit 0 busy, bit 1 RX valid |

Transfers are eight bits, MSB first, one chip select, and support SPI modes 0–3. DATA writes while disabled or busy return ERR. STATUS is read-only. `spi_cs_n` is high when idle and low for a transfer.

### I2C master — `0x4000_3000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | DATA | RW | TX byte; read returns last received byte and clears RX valid |
| `0x04` | COMMAND | W | `1` START, `2` STOP, `4` write byte, `8` read byte, bit 4 requests NACK after read |
| `0x08` | CONTROL | RW | bit 0 enable |
| `0x0C` | DIVIDER | RW | System clocks per SCL half-period, minimum 2 |
| `0x10` | STATUS | R | bit 0 busy, bit 1 done, bit 2 transmitted-byte NACK, bit 3 RX valid |

This is a single-controller byte engine. SDA/SCL pins are open drain: `*_oe=1` means actively pull low; `*_oe=0` means release for the external pull-up. It supports START, STOP, byte write with ACK sampling, and byte read followed by ACK or NACK. The controller waits for SCL high during clock-high phases to allow clock stretching. Repeated-start sequencing and multi-controller arbitration are not implemented.

### Interrupt controller — `0x4000_5000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | PENDING | R | bit 0 timer level; bit 1 UART; bit 2 GPIO; bit 3 watchdog pending |
| `0x04` | ENABLE | RW | bit 0 timer/MTIP mask; bits 1–3 external-source masks |
| `0x08` | THRESHOLD | RW | 3-bit exclusive threshold for external sources |
| `0x0C` | CLAIM/COMPLETE | R/W | Read claims and returns highest eligible external source; write source ID completes it |
| `0x10` | UART_PRIORITY | RW | 3-bit priority, reset 3 |
| `0x14` | GPIO_PRIORITY | RW | 3-bit priority, reset 2 |
| `0x18` | WATCHDOG_PRIORITY | RW | 3-bit priority, reset 1 |

External IDs are UART=1, GPIO=2, watchdog=3. Larger priority wins; ties favor lower ID. A source is eligible when enabled and its priority is strictly greater than threshold. Reset masks all sources and sets threshold 0. MTIP is passed separately to the CPU timer input, matching the present core interface; the CPU gives MEIP priority over MTIP when both are pending. External pending is sticky until claim/complete and reasserts while the source remains high.

### Watchdog — `0x4000_D000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | CONTROL | RW | bit 0 enable; enabling reloads count |
| `0x04` | TIMEOUT | RW | Timeout in system clocks |
| `0x08` | COUNT | R | Remaining clocks |
| `0x0C` | SERVICE | W | Write `0x51F15EED` to reload and clear expiration; wrong key requests reset |

Watchdog reset request and watchdog interrupt assert when the counter expires. Expiration and invalid service are sticky until system reset or a valid service write. Reset request must be routed through the SoC reset controller; this block does not reset itself or other modules directly.

### Debug/performance counters — `0x4000_A000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | CONTROL | RW | bit 0 enables counters; reset enabled |
| `0x04/0x08` | CYCLE_LO/HI | RW | 64-bit system clock count |
| `0x0C/0x10` | RETIRED_LO/HI | RW | 64-bit architectural retire count from `cpu_core.retire` |
| `0x14` | BUS_COUNT | RW | Wishbone request count |
| `0x18` | IRQ_COUNT | RW | Rising-edge count of timer or external IRQ |
| `0x1C` | LAST_PC | R | PC sampled on the last retire pulse |

Counters reset to zero and can be read or written by machine-mode software. This is an observation block; it does not provide debug halt, step, or an external debug transport. The CPU's standard cycle/retired CSRs remain available independently.

### Power/clock requests — `0x4000_B000`

| Offset | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | CONTROL | RW | bit 0 sleep request; enabled wake event clears it |
| `0x04` | CLOCK_ENABLE | RW | bits 0–4 request UART, GPIO, SPI/I2C, timer, and debug clocks; reset `0x1F` |
| `0x08` | WAKE_ENABLE | RW | bits 0 timer, 1 external IRQ, 2 UART, 3 GPIO, 4 watchdog, 5 software wake |
| `0x0C` | WAKE_STATUS | R/W1C | Latched wake events in the same bit positions |
| `0x10` | SOFTWARE_RESET | W | Full-word key `0x52535401` raises sticky reset request |
| `0x14` | SOFTWARE_WAKE | W | Write bit 0 to latch software wake and clear sleep request |

Clock enables are requests only. The initial SoC shares one clock; a later integration must use characterized integrated clock-gating cells with safe enable capture and must keep wake logic active. Sleep requests do not gate clocks inside this register block. Wake status is set-dominant when a new event coincides with a W1C clear. Reset requests from power control and watchdog are ORed at the subsystem output.

## Verification

`hw/tb/peripheral_subsystem_tb.sv` checks all register maps, byte enables, UART TX waveform and loopback RX, GPIO synchronization/direction/IRQ, SPI modes 0–3, I2C START/STOP/data/NACK waveforms, interrupt mask/threshold/priority/claim/complete, timer compare and MTIP, watchdog service/expiry, performance counters, power wake/clock/reset controls, and error cases. `hw/tb/peripheral_cpu_irq_tb.sv` runs a ROM program through the CPU, memory system, adapter, and peripheral target. The program transmits `Hi`, configures GPIO, enables MTIE/MIE, receives and handles a machine timer interrupt, then enables the watchdog and verifies reset recovery. Run both as part of `mingw32-make sim` (or `make sim` on systems with GNU Make).
