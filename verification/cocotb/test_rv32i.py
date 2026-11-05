"""Directed RV32I tests for the multicycle SEAL-RV core."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


NOP = 0x00000013
MASK32 = 0xFFFFFFFF


def enc_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm, rs1, funct3, rd, opcode=0x13):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3):
    value = imm & 0xFFF
    return (((value >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((value & 0x1F) << 7) | 0x23


def enc_b(imm, rs2, rs1, funct3):
    value = imm & 0x1FFF
    return (((value >> 12) & 1) << 31) | (((value >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (((value >> 1) & 0xF) << 8) | (((value >> 11) & 1) << 7) | 0x63


def enc_u(imm20, rd, opcode=0x37):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm, rd):
    value = imm & 0x1FFFFF
    return (((value >> 20) & 1) << 31) | (((value >> 1) & 0x3FF) << 21) | (((value >> 11) & 1) << 20) | (((value >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def program(words, start=0):
    return {start + 4 * index: word & MASK32 for index, word in enumerate(words)}


def reg(dut, index):
    return int(dut.rf.regs[index].value)


async def start_and_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0
    dut.instr.value = NOP
    dut.irq_external.value = 0
    dut.irq_timer.value = 0
    dut.dmem_ready.value = 0
    dut.dmem_rdata.value = 0
    dut.dmem_error.value = 0
    await Timer(2, unit="ns")
    assert int(dut.pc.value) == 0
    assert int(dut.trap_valid.value) == 0
    for index in range(32):
        assert reg(dut, index) == 0
    dut.rst_n.value = 1
    await Timer(1, unit="ns")


async def run_program(dut, words_by_pc, end_pc, memory=None, max_steps=300, stall_cycles=0, error_addresses=None, break_on_trap=True):
    memory = {} if memory is None else dict(memory)
    error_addresses = set() if error_addresses is None else set(error_addresses)
    transactions = []

    for _ in range(max_steps):
        current_pc = int(dut.pc.value)
        if current_pc == end_pc or (break_on_trap and int(dut.trap_valid.value)):
            break

        dut.instr.value = words_by_pc.get(current_pc, NOP)
        dut.dmem_ready.value = 0
        dut.dmem_error.value = 0
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        if int(dut.dmem_valid.value):
            request = (
                int(dut.dmem_write.value),
                int(dut.dmem_addr.value),
                int(dut.dmem_wstrb.value),
                int(dut.dmem_wdata.value),
            )
            for _stall in range(stall_cycles):
                await RisingEdge(dut.clk)
                await Timer(1, unit="ns")
                assert int(dut.dmem_valid.value) == 1
                assert (
                    int(dut.dmem_write.value),
                    int(dut.dmem_addr.value),
                    int(dut.dmem_wstrb.value),
                    int(dut.dmem_wdata.value),
                ) == request

            is_write, address, strobe, write_data = request
            error = address in error_addresses
            transactions.append((is_write, address, strobe, write_data, error))
            dut.dmem_rdata.value = memory.get(address, 0)
            dut.dmem_error.value = int(error)
            dut.dmem_ready.value = 1
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")
            if is_write and not error:
                old_word = memory.get(address, 0)
                new_word = old_word
                for lane in range(4):
                    if strobe & (1 << lane):
                        lane_mask = 0xFF << (lane * 8)
                        new_word = (new_word & ~lane_mask) | (write_data & lane_mask)
                memory[address] = new_word & MASK32
            dut.dmem_ready.value = 0
            dut.dmem_error.value = 0

        if break_on_trap and int(dut.trap_valid.value):
            break
    else:
        raise AssertionError(f"program did not finish within {max_steps} instructions; pc=0x{int(dut.pc.value):08x}")

    return memory, transactions


def assert_trap(dut, cause, pc=0, value=0):
    assert int(dut.trap_valid.value) == 1
    assert int(dut.trap_pc.value) == pc
    assert int(dut.trap_cause.value) == cause
    assert int(dut.trap_value.value) == value & MASK32
    assert int(dut.mepc.value) == pc


def enc_csr(csr, rs1, funct3, rd):
    return (csr << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x73


def c_addi(rd, imm):
    value = imm & 0x3F
    return (value >> 5 << 12) | (rd << 7) | ((value & 0x1F) << 2) | 1


def c_li(rd, imm):
    value = imm & 0x3F
    return 0x4000 | (value >> 5 << 12) | (rd << 7) | ((value & 0x1F) << 2) | 1


def c_mv(rd, rs2, add=False):
    return 0x8000 | (int(add) << 12) | (rd << 7) | (rs2 << 2) | 2


def c_sw(rs1, rs2, offset):
    value = offset & 0x7F
    rs1p, rs2p = rs1 - 8, rs2 - 8
    return (6 << 13) | ((value >> 6 & 1) << 5) | (rs2p << 2) | (rs1p << 7) | ((value >> 3 & 7) << 10) | ((value >> 2 & 1) << 6)


def c_lw(rd, rs1, offset):
    value = offset & 0x7F
    return (2 << 13) | (((rd - 8) & 7) << 2) | (((rs1 - 8) & 7) << 7) | (((value >> 3) & 7) << 10) | (((value >> 2) & 1) << 6) | (((value >> 6) & 1) << 5)


def c_jump(imm, link=False):
    value = imm & 0xFFF
    return ((1 if link else 5) << 13) | (((value >> 11) & 1) << 12) | (((value >> 4) & 1) << 11) | (((value >> 8) & 3) << 9) | (((value >> 10) & 1) << 8) | (((value >> 6) & 1) << 7) | (((value >> 7) & 1) << 6) | (((value >> 1) & 7) << 3) | (((value >> 5) & 1) << 2) | 1


def c_branch(rs1, imm, not_equal=False):
    value = imm & 0x1FF
    return ((7 if not_equal else 6) << 13) | (((value >> 8) & 1) << 12) | (((value >> 3) & 3) << 10) | (((rs1 - 8) & 7) << 7) | (((value >> 6) & 3) << 5) | (((value >> 1) & 3) << 3) | (((value >> 5) & 1) << 2) | 1


def c_alu(rs1, rs2, operation):
    return (4 << 13) | (3 << 10) | (((rs1 - 8) & 7) << 7) | ((operation & 3) << 5) | (((rs2 - 8) & 7) << 2) | 1


def c_slli(rd, shamt):
    return ((rd & 31) << 7) | ((shamt & 31) << 2) | 2


@cocotb.test()
async def test_rv32i_alu_and_immediate_matrix(dut):
    await start_and_reset(dut)
    words = [
        enc_i(0x7FF, 0, 0, 1),                         # x1 = 2047
        enc_i(-1, 0, 0, 2),                            # x2 = -1
        enc_i(1, 0, 0, 3),                             # x3 = 1
        enc_u(0x80000, 4),                             # x4 = 0x80000000
        enc_i(-1, 4, 0, 4),                            # x4 = 0x7fffffff
        enc_r(0, 3, 4, 0, 5),                          # ADD  -> 0x80000000
        enc_r(0x20, 3, 0, 0, 6),                       # SUB  -> -1
        enc_r(0, 2, 3, 1, 7),                          # SLL  -> 0x80000000
        enc_r(0, 3, 2, 2, 8),                          # SLT  -> 1
        enc_r(0, 3, 2, 3, 9),                          # SLTU -> 0
        enc_r(0, 3, 2, 4, 10),                         # XOR  -> 0xfffffffe
        enc_r(0, 3, 2, 5, 11),                         # SRL  -> 0x7fffffff
        enc_r(0x20, 3, 2, 5, 12),                      # SRA  -> -1
        enc_r(0, 3, 2, 6, 13),                         # OR   -> -1
        enc_r(0, 3, 2, 7, 14),                         # AND  -> 1
        enc_i(-2048, 0, 0, 15),                        # ADDI negative immediate
        enc_i(1, 2, 2, 16),                            # SLTI -> 1
        enc_i(1, 2, 3, 17),                            # SLTIU -> 0
        enc_i(0x7FF, 0, 6, 18),                        # ORI positive immediate
        enc_i(0x7FF, 2, 7, 19),                        # ANDI
        enc_i(-1, 2, 4, 20),                           # XORI -> 0
        enc_i(31, 3, 1, 21),                           # SLLI
        enc_i(1, 2, 5, 22),                            # SRLI
        enc_i((0x20 << 5) | 1, 2, 5, 23),              # SRAI
    ]
    await run_program(dut, program(words), len(words) * 4)
    expected = {
        1: 2047, 2: MASK32, 3: 1, 4: 0x7FFFFFFF,
        5: 0x80000000, 6: MASK32, 7: 0x80000000, 8: 1,
        9: 0, 10: 0xFFFFFFFE, 11: 0x7FFFFFFF, 12: MASK32,
        13: MASK32, 14: 1, 15: 0xFFFFF800, 16: 1, 17: 0,
        18: 0x7FF, 19: 0x7FF, 20: 0, 21: 0x80000000,
        22: 0x7FFFFFFF, 23: MASK32,
    }
    for index, value in expected.items():
        assert reg(dut, index) == value, f"x{index}: expected 0x{value:08x}, got 0x{reg(dut, index):08x}"
    assert int(dut.trap_valid.value) == 0


@cocotb.test()
async def test_lui_auipc_and_register_dependencies(dut):
    await start_and_reset(dut)
    words = [
        enc_u(0xABCDE, 1),
        enc_u(0x12345, 2, opcode=0x17),
        enc_i(0x123, 1, 0, 3),
        enc_r(0, 3, 1, 0, 4),
    ]
    await run_program(dut, program(words), len(words) * 4)
    assert reg(dut, 1) == 0xABCDE000
    assert reg(dut, 2) == 0x12345004
    assert reg(dut, 3) == 0xABCDE123
    assert reg(dut, 4) == (0xABCDE000 + 0xABCDE123) & MASK32


@cocotb.test()
async def test_all_branches_taken_and_not_taken(dut):
    await start_and_reset(dut)
    cases = [
        (0, 1, 1, True), (0, 1, 2, False),
        (1, 1, 2, True), (1, 1, 1, False),
        (4, 1, 2, True), (4, 2, 1, False),
        (5, 2, 1, True), (5, 1, 2, False),
        (6, 2, 1, True), (6, 1, 2, False),
        (7, 1, 2, True), (7, 2, 1, False),
    ]
    for funct3, rs1, rs2, taken in cases:
        await start_and_reset(dut)
        words = {
            0: enc_i(-1, 0, 0, 1),
            4: enc_i(1, 0, 0, 2),
            8: enc_b(12, rs2, rs1, funct3),
            12: enc_i(1, 0, 0, 3),
            16: enc_j(16, 0),
            20: enc_i(2, 0, 0, 3),
            24: enc_j(12, 0),
            32: NOP,
        }
        await run_program(dut, words, 36)
        assert reg(dut, 3) == (2 if taken else 1), f"branch funct3={funct3}, taken={taken}"
        assert int(dut.trap_valid.value) == 0

    await start_and_reset(dut)
    loop = [
        enc_i(2, 0, 0, 1),
        enc_i(0, 0, 0, 2),
        enc_i(1, 2, 0, 2),
        enc_i(-1, 1, 0, 1),
        enc_b(-8, 0, 1, 1),  # BNE x1,x0, back to PC 8
        enc_i(0, 2, 0, 3),
    ]
    await run_program(dut, program(loop), len(loop) * 4)
    assert reg(dut, 1) == 0
    assert reg(dut, 2) == 2
    assert reg(dut, 3) == 2


@cocotb.test()
async def test_jal_jalr_and_alignment(dut):
    await start_and_reset(dut)
    words = {0: enc_j(8, 5), 4: enc_i(99, 0, 0, 7), 8: enc_i(17, 0, 0, 1), 12: enc_i(-1, 1, 0, 6, opcode=0x67), 16: enc_i(7, 0, 0, 7)}
    await run_program(dut, words, 20)
    assert reg(dut, 5) == 4
    assert reg(dut, 6) == 16
    assert reg(dut, 7) == 7
    assert int(dut.trap_valid.value) == 0

    await start_and_reset(dut)
    negative_jal = {
        0: enc_i(0, 0, 0, 1),
        4: enc_i(1, 1, 0, 1),
        8: enc_i(2, 0, 0, 2),
        12: enc_b(8, 2, 1, 5),
        16: enc_j(-12, 5),
        20: enc_i(0, 1, 0, 3),
    }
    await run_program(dut, negative_jal, 24)
    assert reg(dut, 1) == 2
    assert reg(dut, 3) == 2
    assert reg(dut, 5) == 20

    await start_and_reset(dut)
    await run_program(dut, {0: enc_j(2, 5)}, 2)
    assert int(dut.trap_valid.value) == 0
    assert int(dut.pc.value) == 2
    assert reg(dut, 5) == 4

    await start_and_reset(dut)
    words = {0: enc_i(2, 0, 0, 1), 4: enc_i(0, 1, 0, 5, opcode=0x67)}
    await run_program(dut, words, 2)
    assert int(dut.trap_valid.value) == 0
    assert int(dut.pc.value) == 2
    assert reg(dut, 5) == 8


@cocotb.test()
async def test_load_store_lanes_sign_extension_and_stalls(dut):
    await start_and_reset(dut)
    words = [
        enc_i(0x200, 0, 0, 1),
        enc_u(0x11223, 2),
        enc_i(0x344, 2, 0, 2),
        enc_s(-1, 2, 1, 0),
        enc_s(0, 2, 1, 0),
        enc_s(1, 2, 1, 0),
        enc_s(2, 2, 1, 0),
        enc_s(2, 2, 1, 1),
        enc_s(4, 2, 1, 2),
        enc_i(0, 1, 0, 3, opcode=0x03),
        enc_i(1, 1, 4, 4, opcode=0x03),
        enc_i(2, 1, 1, 5, opcode=0x03),
        enc_i(0, 1, 5, 6, opcode=0x03),
        enc_i(4, 1, 2, 7, opcode=0x03),
        enc_i(0x208, 0, 0, 8),
        enc_i(0, 8, 0, 9, opcode=0x03),
        enc_i(1, 8, 4, 10, opcode=0x03),
        enc_i(0, 8, 1, 11, opcode=0x03),
        enc_i(2, 8, 5, 12, opcode=0x03),
        enc_i(2, 8, 1, 13, opcode=0x03),
        enc_i(0, 8, 5, 14, opcode=0x03),
        enc_i(0, 8, 2, 15, opcode=0x03),
    ]
    seeded = {0x1FC: 0, 0x200: 0, 0x204: 0, 0x208: 0x8001FF80}
    mem, transactions = await run_program(dut, program(words), len(words) * 4, seeded, stall_cycles=2)

    assert mem[0x200] == 0x33444444
    assert mem[0x204] == 0x11223344
    assert mem[0x1FC] == 0x44000000
    assert reg(dut, 3) == 0x44
    assert reg(dut, 4) == 0x44
    assert reg(dut, 5) == 0x3344
    assert reg(dut, 6) == 0x4444
    assert reg(dut, 7) == 0x11223344
    assert reg(dut, 9) == 0xFFFFFF80
    assert reg(dut, 10) == 0xFF
    assert reg(dut, 11) == 0xFFFFFF80
    assert reg(dut, 12) == 0x8001
    assert reg(dut, 13) == 0xFFFF8001
    assert reg(dut, 14) == 0xFF80
    assert reg(dut, 15) == 0x8001FF80
    assert [(t[0], t[1], t[2], t[3]) for t in transactions[:6]] == [
        (1, 0x1FC, 0x8, 0x44000000),
        (1, 0x200, 0x1, 0x11223344),
        (1, 0x200, 0x2, 0x22334400),
        (1, 0x200, 0x4, 0x33440000),
        (1, 0x200, 0xC, 0x33440000),
        (1, 0x204, 0xF, 0x11223344),
    ]


@cocotb.test()
async def test_misaligned_accesses_and_bus_faults(dut):
    for instruction, cause, value in [
        (enc_i(1, 0, 1, 5, opcode=0x03), 4, 1),
        (enc_i(2, 0, 2, 5, opcode=0x03), 4, 2),
        (enc_s(1, 2, 0, 1), 6, 1),
        (enc_s(2, 2, 0, 2), 6, 2),
    ]:
        await start_and_reset(dut)
        await run_program(dut, {0: instruction}, 4)
        assert_trap(dut, cause=cause, value=value)
        assert reg(dut, 5) == 0

    await start_and_reset(dut)
    words = [enc_i(0x100, 0, 0, 1), enc_i(0, 1, 2, 5, opcode=0x03)]
    await run_program(dut, program(words), 12, error_addresses={0x100})
    assert_trap(dut, cause=5, pc=4, value=0x100)
    assert reg(dut, 5) == 0


@cocotb.test()
async def test_illegal_encodings_do_not_write_registers(dut):
    invalid = [
        enc_r(2, 2, 1, 0, 5),             # unsupported funct7 for ADD/MUL
        enc_i((1 << 5) | 1, 1, 1, 5),     # reserved SLLI upper immediate bits
        enc_i((0x10 << 5) | 1, 1, 5, 5), # reserved SRLI upper immediate bits
        enc_i(0, 1, 3, 5, opcode=0x03),   # reserved load funct3
        enc_s(0, 2, 1, 3),                # reserved store funct3
        enc_b(4, 2, 1, 2),                # reserved branch funct3
        enc_i(0, 1, 1, 5, opcode=0x67),   # JALR funct3 must be zero
        0x1000000F,                       # unsupported FENCE fm
        0x0010000F,                       # FENCE rs2 must be zero
        enc_i(0, 0, 1, 5, opcode=0x73),   # CSR instruction (Zicsr deferred)
        0xFFFFFFFF,                       # unsupported opcode
    ]
    for instruction in invalid:
        await start_and_reset(dut)
        await run_program(dut, {0: instruction}, 4)
        assert int(dut.trap_valid.value) == 1, f"expected illegal trap for 0x{instruction:08x}"
        assert_trap(dut, cause=2, value=instruction)
        assert reg(dut, 5) == 0, f"illegal instruction wrote x5: 0x{instruction:08x}"

    await start_and_reset(dut)
    await run_program(dut, {0: 0x0000000F}, 4)  # legal FENCE is a no-op
    assert int(dut.trap_valid.value) == 0

    await start_and_reset(dut)
    await run_program(dut, {0: 0x00000073}, 4)
    assert_trap(dut, cause=11, value=0)

    await start_and_reset(dut)
    await run_program(dut, {0: 0x00100073}, 4)
    assert_trap(dut, cause=3, value=0)


@cocotb.test()
async def test_reset_during_idle_and_memory_execution(dut):
    await start_and_reset(dut)
    await run_program(dut, {0: enc_i(7, 0, 0, 1)}, 4)
    assert reg(dut, 1) == 7
    dut.rst_n.value = 0
    await Timer(2, unit="ns")
    assert int(dut.pc.value) == 0
    assert reg(dut, 1) == 0
    assert int(dut.dmem_valid.value) == 0
    dut.rst_n.value = 1
    await Timer(1, unit="ns")


@cocotb.test()
async def test_rv32m_arithmetic_edges(dut):
    await start_and_reset(dut)
    words = [
        enc_u(0x80000, 1), enc_i(-1, 0, 0, 2),
        enc_r(1, 2, 1, 0, 10), enc_r(1, 2, 1, 1, 11),
        enc_r(1, 2, 1, 2, 12), enc_r(1, 2, 1, 3, 13),
        enc_r(1, 2, 1, 4, 14), enc_r(1, 2, 1, 6, 15),
        enc_r(1, 0, 1, 4, 16), enc_r(1, 0, 1, 6, 17),
        enc_i(7, 0, 0, 3), enc_i(-3, 0, 0, 4),
        enc_r(1, 4, 3, 4, 18), enc_r(1, 4, 3, 6, 19),
        enc_i(1, 0, 0, 20), enc_i(0, 0, 0, 21),
        enc_r(1, 21, 20, 5, 22), enc_r(1, 21, 20, 7, 23),
    ]
    await run_program(dut, program(words), len(words) * 4)
    expected = {
        10: 0x80000000, 11: 0, 12: 0x80000000, 13: 0x7FFFFFFF,
        14: 0x80000000, 15: 0, 16: MASK32, 17: 0x80000000,
        18: MASK32 - 1, 19: 1, 22: 0xFFFFFFFF, 23: 1,
    }
    for index, value in expected.items():
        assert reg(dut, index) == value, f"RV32M x{index}: got 0x{reg(dut,index):08x}"
    assert int(dut.trap_valid.value) == 0


@cocotb.test()
async def test_rv32c_mixed_width_stream_and_memory(dut):
    await start_and_reset(dut)
    crossing = {0: c_li(1, 5), 2: enc_i(10, 1, 0, 2), 6: c_addi(1, -1)}
    await run_program(dut, crossing, 8)
    assert reg(dut, 1) == 4
    assert reg(dut, 2) == 15

    await start_and_reset(dut)
    # 16-bit instructions at 0/2, a 32-bit instruction at byte address 4,
    # then compressed instructions again; the preceding stream covers a 32-bit
    # instruction beginning at byte address 2.
    words = {
        0: c_li(1, 5),
        2: c_addi(1, -1),
        4: enc_i(10, 1, 0, 2),
        8: c_li(8, 0x1C),
        10: c_addi(8, 4),
        12: c_addi(9, 3),
        14: c_mv(10, 9),
        16: c_mv(10, 8, add=True),
        18: 0x00000001,  # C.NOP
    }
    await run_program(dut, words, 20)
    assert reg(dut, 1) == 4
    assert reg(dut, 2) == 14
    assert reg(dut, 8) == 0x20
    assert reg(dut, 9) == 3
    assert reg(dut, 10) == 0x23

    await start_and_reset(dut)
    # C.SW/C.LW use the compact x8-x15 register bank and the aligned word bus.
    words = {
        0: enc_i(0x200, 0, 0, 8),
        4: enc_i(0x55, 0, 0, 9),
        8: c_sw(8, 9, 4),
        10: c_lw(10, 8, 4),
    }
    mem, tx = await run_program(dut, words, 12, {0x204: 0})
    assert mem[0x204] == 0x55
    assert reg(dut, 10) == 0x55
    assert tx[0][2] == 0xF

    await start_and_reset(dut)
    words = {
        0: 0x6141,                    # C.ADDI16SP sp,16
        2: 0x0800,                    # C.ADDI4SPN x8,sp,16
        4: 0x6485,                    # C.LUI x9,1
        6: c_li(10, -1),
        8: 0x8105,                    # C.SRLI x10,1
        10: 0x8505,                   # C.SRAI x10,1
        12: 0x897D,                   # C.ANDI x10,31
        14: c_alu(8, 10, 0),          # C.SUB x8,x10 -> 1
        16: 0xC222,                   # C.SWSP x8,4(sp)
        18: 0x4592,                   # C.LWSP x11,4(sp)
    }
    memory, _ = await run_program(dut, words, 20, {20: 0})
    assert reg(dut, 2) == 16
    assert reg(dut, 8) == 1
    assert reg(dut, 9) == 0x1000
    assert reg(dut, 10) == 31
    assert reg(dut, 11) == 1
    assert memory[20] == 1

    await start_and_reset(dut)
    # Compressed branches and jumps use halfword offsets and two-byte links.
    words = {
        0: c_li(8, 1),
        2: c_branch(8, 4),           # BEQZ not taken
        4: c_branch(8, 4, True),     # BNEZ to PC 8
        6: c_addi(9, 7),             # skipped
        8: c_jump(4, link=True),     # x1=10, target PC 12
        10: c_addi(9, 1),            # skipped
        12: c_addi(9, 2),
        14: 0x9002,                  # C.JR x8, to address 0x20 not aligned? replaced below at runtime
    }
    words.pop(14)
    words[14] = enc_i(24, 0, 0, 5)   # prepare JR target x5=24
    words[18] = 0x8282               # C.JR x5
    words[20] = c_addi(9, 9)         # skipped by JR
    words[24] = c_addi(9, 3)
    await run_program(dut, words, 26)
    assert reg(dut, 1) == 10
    assert reg(dut, 9) == 5


@cocotb.test()
async def test_machine_csrs_trap_entry_and_mret(dut):
    await start_and_reset(dut)
    words = {
        0: enc_i(0x40, 0, 0, 1),
        4: enc_csr(0x305, 1, 1, 0),       # mtvec = 0x40
        8: 0x00000073,                    # ECALL, should trap with EPC=8
        12: enc_i(7, 0, 0, 2),
        16: enc_csr(0x301, 0, 2, 3),      # read-only misa
        20: enc_csr(0x341, 0, 2, 4),      # returned mepc
        24: enc_csr(0x342, 0, 2, 5),      # mcause
        28: enc_j(0, 0),
        64: enc_csr(0x341, 0, 2, 6),
        68: enc_csr(0x342, 0, 2, 7),
        72: enc_i(12, 0, 0, 8),
        76: enc_csr(0x341, 8, 1, 0),      # skip the ECALL on return
        80: 0x30200073,                   # MRET
    }
    await run_program(dut, words, 28, break_on_trap=False)
    assert reg(dut, 2) == 7
    assert reg(dut, 3) == 0x40001104
    assert reg(dut, 4) == 12
    assert reg(dut, 5) == 11
    assert reg(dut, 6) == 8
    assert reg(dut, 7) == 11
    assert int(dut.mstatus.value) & 0x88 == 0x80  # MIE cleared, MPIE set on trap

    await start_and_reset(dut)
    await run_program(dut, {0: enc_csr(0x301, 1, 1, 2)}, 4)
    assert_trap(dut, cause=2, value=enc_csr(0x301, 1, 1, 2))


@cocotb.test()
async def test_machine_interrupt_priority_masking_and_wfi(dut):
    await start_and_reset(dut)
    # Configure direct vector, enable timer+external sources and global MIE.
    setup = {
        0: enc_i(0x100, 0, 0, 1),
        4: enc_csr(0x305, 1, 1, 0),
        8: enc_i(0x880, 0, 0, 2),
        12: enc_csr(0x304, 2, 1, 0),
        16: enc_i(8, 0, 0, 3),
        20: enc_csr(0x300, 3, 2, 0),
        24: enc_i(1, 0, 0, 4),
    }
    await run_program(dut, setup, 24)
    dut.irq_timer.value = 1
    dut.irq_external.value = 1
    await run_program(dut, {**setup, 24: enc_i(1, 0, 0, 4)}, 28)
    assert int(dut.trap_valid.value) == 1
    assert int(dut.mcause.value) == 0x8000000B  # MEI outranks MTI
    assert int(dut.mepc.value) == 24
    assert int(dut.pc.value) == 0x100

    await start_and_reset(dut)
    masked = {0: enc_i(0x80, 0, 0, 1), 4: enc_csr(0x304, 1, 1, 0), 8: enc_i(7, 0, 0, 2)}
    await run_program(dut, masked, 8)  # MTIE enabled, global MIE remains clear
    dut.irq_timer.value = 1
    await run_program(dut, masked, 12)
    assert int(dut.trap_valid.value) == 0
    assert reg(dut, 2) == 7

    # WFI with global MIE clear sleeps on an enabled source and resumes at PC+4.
    await start_and_reset(dut)
    await run_program(dut, {0: enc_i(0x80, 0, 0, 1), 4: enc_csr(0x304, 1, 1, 0)}, 8)
    dut.instr.value = 0x10500073
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert int(dut.pc.value) == 12
    dut.instr.value = enc_i(9, 0, 0, 2)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert reg(dut, 2) == 0
    dut.irq_timer.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert reg(dut, 2) == 9

    dut.instr.value = enc_i(0x100, 0, 0, 1)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.instr.value = enc_i(0, 1, 2, 2, opcode=0x03)
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert int(dut.dmem_valid.value) == 1
    dut.rst_n.value = 0
    await Timer(2, unit="ns")
    assert int(dut.pc.value) == 0
    assert int(dut.dmem_valid.value) == 0
    assert int(dut.trap_valid.value) == 0
    assert reg(dut, 1) == 0
    dut.rst_n.value = 1
    await Timer(1, unit="ns")
