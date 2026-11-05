# RV32I assembly smoke source

`rv32i_all.S` is a human-readable program containing every implemented RV32I instruction family. The executable directed tests live in `verification/cocotb/test_rv32i.py`, where instruction words are encoded directly and supplied from a PC-indexed instruction-memory model. This keeps tests runnable without a RISC-V cross toolchain.

The assembly file is not currently assembled or executed by CI. When a cross toolchain is available, a suitable command is:

```sh
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Wl,-Ttext=0 -o rv32i_all.elf rv32i_all.S
```

This program is a smoke source, not a RISC-V architectural compliance test.
