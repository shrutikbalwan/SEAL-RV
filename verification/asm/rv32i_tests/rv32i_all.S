    .section .text
    .option norvc
    .globl _start
_start:
    lui   x1, 0x80000
    auipc x2, 0x00001
    addi  x3, x0, -1
    addi  x4, x0, 1

    add   x5, x3, x4
    sub   x6, x3, x4
    sll   x7, x4, x4
    slt   x8, x3, x4
    sltu  x9, x3, x4
    xor   x10, x3, x4
    srl   x11, x3, x4
    sra   x12, x3, x4
    or    x13, x3, x4
    and   x14, x3, x4

    slti  x15, x3, 1
    sltiu x16, x3, 1
    xori  x17, x3, -1
    ori   x18, x0, 0x7ff
    andi  x19, x3, 0x7ff
    slli  x20, x4, 31
    srli  x21, x3, 1
    srai  x22, x3, 1

    addi  x23, x0, 256
    sb    x4, 0(x23)
    sh    x4, 2(x23)
    sw    x1, 4(x23)
    lb    x24, 0(x23)
    lh    x25, 2(x23)
    lw    x26, 4(x23)
    lbu   x27, 0(x23)
    lhu   x28, 2(x23)

    beq   x4, x4, 1f
    addi  x29, x0, 1
1:  bne   x4, x0, 2f
    addi  x29, x0, 2
2:  blt   x3, x4, 3f
    addi  x29, x0, 3
3:  bge   x4, x3, 4f
    addi  x29, x0, 4
4:  bltu  x4, x3, 5f
    addi  x29, x0, 5
5:  bgeu  x3, x4, 6f
    addi  x29, x0, 6
6:  jal   x30, 7f
    addi  x29, x0, 7
7:  auipc x30, 0
    addi  x30, x30, 12
    jalr  x31, 0(x30)
    addi  x29, x0, 8
    fence rw, rw
    jal   x0, _done
_done:
    ebreak
