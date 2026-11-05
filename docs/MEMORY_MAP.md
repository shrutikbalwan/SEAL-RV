# SEAL-RV 2.0 Memory Map

All addresses are byte addresses. Windows below are proposed and reserved for the architecture; they are not implemented in the current repository. The interconnect must reject accesses outside a target's implemented registers and must not mirror addresses unless a later revision explicitly defines aliases.

| Region | Base | Limit (inclusive) | Size | Access and purpose |
|---|---:|---:|---:|---|
| Boot ROM | `0x0000_0000` | `0x0000_0FFF` | 4 KiB | Read-only instruction/data; reset entry |
| Main SRAM | `0x1000_0000` | `0x1000_7FFF` | 32 KiB | Read/write, SECDED-protected logical data |
| UART | `0x4000_0000` | `0x4000_0FFF` | 4 KiB window | Serial port registers |
| GPIO | `0x4000_1000` | `0x4000_1FFF` | 4 KiB window | GPIO control/data |
| SPI | `0x4000_2000` | `0x4000_2FFF` | 4 KiB window | SPI controller |
| I2C | `0x4000_3000` | `0x4000_3FFF` | 4 KiB window | I2C controller |
| Machine timer | `0x4000_4000` | `0x4000_4FFF` | 4 KiB window | `mtime`, `mtimecmp`, software interrupt |
| External interrupt controller | `0x4000_5000` | `0x4000_5FFF` | 4 KiB window | Pending, enable, priority, claim/complete |
| DMA | `0x4000_6000` | `0x4000_6FFF` | 4 KiB window | Two channel control/status banks |
| AES/SHA engines | `0x4000_7000` | `0x4000_7FFF` | 4 KiB window | Crypto command/status/data |
| Key vault | `0x4000_8000` | `0x4000_8FFF` | 4 KiB window | Restricted key lifecycle/control |
| AI accelerator | `0x4000_9000` | `0x4000_9FFF` | 4 KiB window | INT8/INT4 command/status/data |
| Debug/performance | `0x4000_A000` | `0x4000_AFFF` | 4 KiB window | Debug and counters |
| Power management | `0x4000_B000` | `0x4000_BFFF` | 4 KiB window | Clock enables, sleep, wake status |
| TRNG interface | `0x4000_C000` | `0x4000_CFFF` | 4 KiB window | Entropy data/status/health |
| Watchdog | `0x4000_D000` | `0x4000_DFFF` | 4 KiB window | Watchdog control/status |
| PMP/firewall control | `0x4000_E000` | `0x4000_EFFF` | 4 KiB window | Locked policy configuration/status |

## Access rules

- Register windows use aligned 32-bit registers at offsets documented by each peripheral specification. The initial bus supports byte enables; each register must define whether partial writes are accepted, merged, or rejected.
- Boot ROM writes return an error. SRAM accesses outside the 32 KiB range return an error. Unmapped addresses return an error and set an observable fault cause.
- Execute permission is denied for MMIO by default. ROM and SRAM execute permissions are governed by CPU privilege/PMP policy.
- DMA may access SRAM and explicitly permitted memory windows only. DMA access to ROM, key-vault state, debug controls, or protected peripheral registers is denied by default.
- The memory map is fixed for Phase 02 unless review approves a revision. Address decode must use the complete address so high-address aliases cannot reach a valid target.

Per-register offsets, reset values, privilege, and side effects remain open until each peripheral is designed.
