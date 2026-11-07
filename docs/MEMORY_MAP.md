# SEAL-RV 2.0 Memory Map

All addresses are byte addresses. Boot ROM and main SRAM are implemented by Phase 05. UART, GPIO, SPI, I2C, machine timer, external interrupt controller, watchdog, debug/performance counters, and power/clock requests are implemented by the Phase 06 peripheral subsystem. Other peripheral windows remain reserved and return an error. The interconnect must reject accesses outside a target's implemented range and must not mirror addresses unless a later revision explicitly defines aliases.

| Region | Base | Limit (inclusive) | Size | Access and purpose |
|---|---:|---:|---:|---|
| Boot ROM | `0x0000_0000` | `0x0000_0FFF` | 4 KiB | Read-only instruction/data; reset entry; one-cycle Wishbone read |
| Main SRAM | `0x1000_0000` | `0x1000_7FFF` | 32 KiB | Read/write behavioral SRAM; one-cycle Wishbone response; byte writes |
| UART | `0x4000_0000` | `0x4000_0FFF` | 4 KiB window | 8-N-1 serial; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| GPIO | `0x4000_1000` | `0x4000_1FFF` | 4 KiB window | Synchronized GPIO and IRQ; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| SPI | `0x4000_2000` | `0x4000_2FFF` | 4 KiB window | SPI master; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| I2C | `0x4000_3000` | `0x4000_3FFF` | 4 KiB window | Single-controller open-drain master; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| Machine timer | `0x4000_4000` | `0x4000_4FFF` | 4 KiB window | 64-bit `mtime`, `mtimecmp`, MTIP; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| External interrupt controller | `0x4000_5000` | `0x4000_5FFF` | 4 KiB window | UART/GPIO/watchdog pending, masks, priorities, claim/complete; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| DMA | `0x4000_6000` | `0x4000_6FFF` | 4 KiB window | Two channel control/status banks |
| AES/SHA engines | `0x4000_7000` | `0x4000_7FFF` | 4 KiB window | Crypto command/status/data |
| Key vault | `0x4000_8000` | `0x4000_8FFF` | 4 KiB window | Restricted key lifecycle/control |
| AI accelerator | `0x4000_9000` | `0x4000_9FFF` | 4 KiB window | INT8/INT4 command/status/data |
| Debug/performance | `0x4000_A000` | `0x4000_AFFF` | 4 KiB window | Cycle, retire, bus, IRQ counters and last PC; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| Power management | `0x4000_B000` | `0x4000_BFFF` | 4 KiB window | Clock requests, sleep/wake status, software reset; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| TRNG interface | `0x4000_C000` | `0x4000_CFFF` | 4 KiB window | Entropy data/status/health |
| Watchdog | `0x4000_D000` | `0x4000_DFFF` | 4 KiB window | Programmable reset watchdog; see [peripheral register map](PERIPHERAL_SUBSYSTEM.md) |
| PMP/firewall control | `0x4000_E000` | `0x4000_EFFF` | 4 KiB window | Locked policy configuration/status |

## Access rules

- Register windows use aligned 32-bit registers at offsets documented by each peripheral specification. The initial bus supports byte enables; partial-write behavior is defined in [PERIPHERAL_SUBSYSTEM.md](PERIPHERAL_SUBSYSTEM.md).
- Boot ROM writes return an error. SRAM accesses outside the 32 KiB range return an error. Unmapped addresses return an error and set an observable fault cause.
- Execute permission is denied for MMIO by default. ROM and SRAM execute permissions are governed by CPU privilege/PMP policy.
- DMA may access SRAM and explicitly permitted memory windows only. DMA access to ROM, key-vault state, debug controls, or protected peripheral registers is denied by default.
- Address decode uses the complete address so high-address aliases cannot reach a valid target.

DMA, crypto, AI accelerator, TRNG, and PMP/firewall register behavior remains to be implemented. Physical clock gating, debug halt/step, and external debug transport are not part of the initial Phase 06 RTL.
