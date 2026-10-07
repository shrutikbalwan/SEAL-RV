# PHASE_02_RISCV: CPU Foundation
## 1. Microarchitecture & Pipeline
- **Current Pipeline:** Single-cycle (Incremental Step 1). 
- **Future Pipeline:** 3-stage (Fetch, Decode, Execute/Writeback).
## 2. Reset Behavior & Branch Handling
- Active-low synchronous reset (`rst_n`). PC resets to `0x00000000`.
- Branch handling currently disabled in the minimal subset. PC simply increments by 4.
## 3. Interfaces
- 32-bit Instruction Fetch Interface (PC out, Instruction in).
## 4. Instruction Support (V1 Minimum Subset)
- **Implemented:** `ADD`, `SUB`, `ADDI`
- **Missing:** RV32IMC remainder (CSR, Branches, Loads/Stores, Logic ops, M-ext, C-ext).
## 5. Known Limitations
- Not pipelined yet. No data memory interface. Minimal decoder.
