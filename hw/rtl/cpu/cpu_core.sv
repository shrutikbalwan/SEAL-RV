// Multicycle, single-issue RV32IMC machine-mode core.
// instr is a 32-bit fetch window whose low halfword is at pc; the next
// halfword is instr[31:16], including when a 32-bit instruction crosses a
// word boundary. Fetch has no wait/error handshake.
module cpu_core (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] pc,
    input  logic [31:0] instr,
    input  logic        irq_external,
    input  logic        irq_timer,

    output logic        dmem_valid,
    output logic        dmem_write,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    input  logic        dmem_ready,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_error,

    output logic        trap_valid,
    output logic [31:0] trap_pc,
    output logic [31:0] trap_cause,
    output logic [31:0] trap_value,
    output logic        retire
);
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_MISC   = 7'b0001111;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;
    localparam logic [31:0] MISA_RV32IMC = 32'h4000_1104;

    typedef enum logic [1:0] {ST_EXEC, ST_MEM, ST_SLEEP} state_t;
    state_t state;

    logic [15:0] compressed_word;
    logic [31:0] decoded_instr;
    logic compressed, compressed_illegal;
    logic [4:0] rs1, rs2, rd;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic [31:0] rs1_data, rs2_data;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    logic dec_legal, dec_write_rd, dec_is_load, dec_is_store;
    logic dec_exception, dec_is_mret, dec_is_wfi, dec_is_csr;
    logic [31:0] dec_write_data, dec_next_pc, dec_exception_cause, dec_exception_value;
    logic [31:0] dec_mem_address, dec_mem_wdata;
    logic [3:0] dec_mem_wstrb;
    logic [31:0] alu_a, alu_b, alu_result;
    logic [3:0] alu_ctrl;

    logic rf_we;
    logic [4:0] rf_rd;
    logic [31:0] rf_wdata;

    logic mem_is_store;
    logic [2:0] mem_funct3;
    logic [1:0] mem_lane, mem_pc_step;
    logic [4:0] mem_rd;
    logic [31:0] mem_pc, mem_aligned_addr, mem_write_data;
    logic [3:0] mem_write_strobe;
    logic [15:0] shifted_load_data;
    logic [31:0] load_result;

    logic [31:0] mstatus, mie, mtvec, mepc, mcause, mtval;
    logic [63:0] mcycle, minstret;
    logic [31:0] mip_value, csr_rdata, csr_wdata;
    logic [11:0] csr_addr;
    logic csr_known, csr_readonly, csr_write, csr_write_illegal;
    logic [31:0] csr_source;
    logic pending_timer, pending_external, interrupt_pending;
    logic [31:0] interrupt_cause;
    logic trap_take, trap_is_interrupt;
    logic [31:0] trap_entry_cause, trap_entry_value, trap_entry_epc, trap_entry_pc;

    logic [63:0] mul_product;
    logic signed [63:0] mul_a_signed, mul_b_signed;
    logic [63:0] mul_a_unsigned, mul_b_unsigned;
    logic [31:0] muldiv_result;
    logic [63:0] pmpcfg_flat;
    logic [255:0] pmpaddr_flat;
    logic [7:0] pmp_cfg_we;
    logic pmp_addr_we, pmp_data_deny, pmp_fetch_deny, pmp_data_allow, pmp_fetch_allow;
    logic [2:0] pmp_addr_index;
    logic [31:0] pmp_addr_write_data;
    logic [4:0] pmp_data_size, pmp_fetch_size;
    logic pmp_mem_ready, pmp_mem_error;
    logic [7:0] pmp_cfg_unused;
    logic [31:0] pmp_addr_unused;

    assign pmp_cfg_we = (state==ST_EXEC && !pmp_fetch_deny && dec_is_csr && csr_write && !dec_exception &&
                         (csr_addr==12'h3a0 || csr_addr==12'h3a2)) ?
                        ((csr_addr==12'h3a0) ? 8'h0f : 8'hf0) : 8'h00;
    assign pmp_addr_we = (state==ST_EXEC && !pmp_fetch_deny && dec_is_csr && csr_write && !dec_exception &&
                         csr_addr>=12'h3b0 && csr_addr<=12'h3b7);
    assign pmp_addr_index = csr_addr[2:0];
    assign pmp_addr_write_data = csr_wdata;
    seal_pmp pmp_regs (
        .clk, .rst_n, .cfg_we(pmp_cfg_we), .cfg_wdata({csr_wdata,csr_wdata}),
        .addr_we(pmp_addr_we), .addr_index(pmp_addr_index), .addr_wdata(pmp_addr_write_data),
        .read_index(csr_addr[2:0]), .cfg_rdata(pmp_cfg_unused), .addr_rdata(pmp_addr_unused),
        .cfg_flat(pmpcfg_flat), .addr_flat(pmpaddr_flat)
    );
    always_comb begin
        case (mem_funct3)
            3'b000,3'b100: pmp_data_size=1;
            3'b001,3'b101: pmp_data_size=2;
            default: pmp_data_size=4;
        endcase
        pmp_fetch_size=compressed ? 2 : 4;
    end
    pmp_checker pmp_data_check (
        .addr(mem_aligned_addr + {30'b0,mem_lane}), .size_bytes(pmp_data_size),
        .access_read(!mem_is_store), .access_write(mem_is_store), .access_execute(1'b0),
        .privilege(2'b11), .cfg_flat(pmpcfg_flat), .addr_flat(pmpaddr_flat),
        .allow(pmp_data_allow), .matched(), .matched_index()
    );
    pmp_checker pmp_fetch_check (
        .addr(pc), .size_bytes(pmp_fetch_size), .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
        .privilege(2'b11), .cfg_flat(pmpcfg_flat), .addr_flat(pmpaddr_flat),
        .allow(pmp_fetch_allow), .matched(), .matched_index()
    );
    assign pmp_data_deny = !pmp_data_allow;
    assign pmp_fetch_deny = !pmp_fetch_allow;

    assign compressed_word = instr[15:0];
    assign compressed = (compressed_word[1:0] != 2'b11);
    rvc_decompress decompress (
        .cinsn(compressed_word), .insn(decoded_instr), .illegal(compressed_illegal)
    );

    logic [31:0] active_instr;
    always_comb active_instr = compressed ? decoded_instr : instr;

    assign opcode = active_instr[6:0];
    assign rd = active_instr[11:7];
    assign funct3 = active_instr[14:12];
    assign rs1 = active_instr[19:15];
    assign rs2 = active_instr[24:20];
    assign funct7 = active_instr[31:25];
    assign imm_i = {{20{active_instr[31]}}, active_instr[31:20]};
    assign imm_s = {{20{active_instr[31]}}, active_instr[31:25], active_instr[11:7]};
    assign imm_b = {{19{active_instr[31]}}, active_instr[31], active_instr[7], active_instr[30:25], active_instr[11:8], 1'b0};
    assign imm_u = {active_instr[31:12], 12'b0};
    assign imm_j = {{11{active_instr[31]}}, active_instr[31], active_instr[19:12], active_instr[20], active_instr[30:21], 1'b0};

    regfile rf (
        .clk(clk), .rst_n(rst_n), .we(rf_we), .rs1(rs1), .rs2(rs2),
        .rd(rf_rd), .wd(rf_wdata), .rd1(rs1_data), .rd2(rs2_data)
    );
    alu alu_inst (.a(alu_a), .b(alu_b), .alu_ctrl(alu_ctrl), .result(alu_result), .zero());

    assign mip_value = {20'b0, irq_external, 3'b0, irq_timer, 7'b0};
    assign pending_timer = irq_timer && mie[7];
    assign pending_external = irq_external && mie[11];
    assign interrupt_pending = pending_external || pending_timer;
    assign interrupt_cause = pending_external ? 32'd11 : 32'd7;

    always_comb begin
        csr_addr = active_instr[31:20];
        csr_known = 1'b1;
        csr_readonly = 1'b0;
        csr_rdata = 32'b0;
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h301: begin csr_rdata = MISA_RV32IMC; csr_readonly = 1'b1; end
            12'h304: csr_rdata = mie;
            12'h344: begin csr_rdata = mip_value; csr_readonly = 1'b1; end
            12'h305: csr_rdata = mtvec;
            12'h3a0: csr_rdata = pmpcfg_flat[31:0];
            12'h3a2: csr_rdata = pmpcfg_flat[63:32];
            12'h3b0,12'h3b1,12'h3b2,12'h3b3,12'h3b4,12'h3b5,12'h3b6,12'h3b7:
                csr_rdata = pmpaddr_flat[csr_addr[2:0]*32 +: 32];
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'hB00: csr_rdata = mcycle[31:0];
            12'hB80: csr_rdata = mcycle[63:32];
            12'hB02: csr_rdata = minstret[31:0];
            12'hB82: csr_rdata = minstret[63:32];
            12'hC00: begin csr_rdata = mcycle[31:0]; csr_readonly = 1'b1; end
            12'hC80: begin csr_rdata = mcycle[63:32]; csr_readonly = 1'b1; end
            12'hC02: begin csr_rdata = minstret[31:0]; csr_readonly = 1'b1; end
            12'hC82: begin csr_rdata = minstret[63:32]; csr_readonly = 1'b1; end
            default: begin csr_known = 1'b0; csr_rdata = 32'b0; end
        endcase
    end

    always_comb begin
        dec_legal = 1'b0;
        dec_write_rd = 1'b0;
        dec_write_data = alu_result;
        dec_next_pc = pc + (compressed ? 32'd2 : 32'd4);
        dec_is_load = 1'b0;
        dec_is_store = 1'b0;
        dec_exception = 1'b0;
        dec_exception_cause = 32'd2;
        dec_exception_value = compressed ? {16'b0, compressed_word} : active_instr;
        dec_mem_address = 32'b0;
        dec_mem_wstrb = 4'b0;
        dec_mem_wdata = 32'b0;
        dec_is_mret = 1'b0;
        dec_is_wfi = 1'b0;
        dec_is_csr = 1'b0;
        alu_ctrl = 4'h0;
        alu_a = rs1_data;
        alu_b = rs2_data;
        csr_source = funct3[2] ? {27'b0, active_instr[19:15]} : rs1_data;
        csr_wdata = csr_source;
        csr_write = 1'b0;
        csr_write_illegal = 1'b0;

        case (opcode)
            OPCODE_LUI: begin dec_legal = 1; dec_write_rd = 1; dec_write_data = imm_u; end
            OPCODE_AUIPC: begin dec_legal = 1; dec_write_rd = 1; alu_a = pc; alu_b = imm_u; end
            OPCODE_OP_IMM: begin
                alu_b = imm_i;
                case (funct3)
                    3'b000: begin alu_ctrl = 4'h0; dec_legal = 1; end
                    3'b010: begin alu_ctrl = 4'h2; dec_legal = 1; end
                    3'b011: begin alu_ctrl = 4'h3; dec_legal = 1; end
                    3'b100: begin alu_ctrl = 4'h4; dec_legal = 1; end
                    3'b110: begin alu_ctrl = 4'h6; dec_legal = 1; end
                    3'b111: begin alu_ctrl = 4'h7; dec_legal = 1; end
                    3'b001: if (funct7 == 0) begin alu_ctrl = 4'h1; dec_legal = 1; end
                    3'b101: if (funct7 == 0 || funct7 == 7'h20) begin alu_ctrl = funct7[5] ? 4'hD : 4'h5; dec_legal = 1; end
                    default: dec_legal = 0;
                endcase
                dec_write_rd = dec_legal;
            end
            OPCODE_OP: begin
                case ({funct7, funct3})
                    {7'h00,3'b000}: begin alu_ctrl=4'h0; dec_legal=1; end
                    {7'h20,3'b000}: begin alu_ctrl=4'h8; dec_legal=1; end
                    {7'h00,3'b001}: begin alu_ctrl=4'h1; dec_legal=1; end
                    {7'h00,3'b010}: begin alu_ctrl=4'h2; dec_legal=1; end
                    {7'h00,3'b011}: begin alu_ctrl=4'h3; dec_legal=1; end
                    {7'h00,3'b100}: begin alu_ctrl=4'h4; dec_legal=1; end
                    {7'h00,3'b101}: begin alu_ctrl=4'h5; dec_legal=1; end
                    {7'h20,3'b101}: begin alu_ctrl=4'hD; dec_legal=1; end
                    {7'h00,3'b110}: begin alu_ctrl=4'h6; dec_legal=1; end
                    {7'h00,3'b111}: begin alu_ctrl=4'h7; dec_legal=1; end
                    {7'h01,3'b000},{7'h01,3'b001},{7'h01,3'b010},{7'h01,3'b011},
                    {7'h01,3'b100},{7'h01,3'b101},{7'h01,3'b110},{7'h01,3'b111}: dec_legal=1;
                    default: dec_legal=0;
                endcase
                dec_write_rd = dec_legal;
                if (funct7 == 7'h01) dec_write_data = muldiv_result;
            end
            OPCODE_BRANCH: begin
                case (funct3)
                    3'b000: begin dec_legal=1; if (rs1_data == rs2_data) dec_next_pc=pc+imm_b; end
                    3'b001: begin dec_legal=1; if (rs1_data != rs2_data) dec_next_pc=pc+imm_b; end
                    3'b100: begin dec_legal=1; if ($signed(rs1_data) < $signed(rs2_data)) dec_next_pc=pc+imm_b; end
                    3'b101: begin dec_legal=1; if ($signed(rs1_data) >= $signed(rs2_data)) dec_next_pc=pc+imm_b; end
                    3'b110: begin dec_legal=1; if (rs1_data < rs2_data) dec_next_pc=pc+imm_b; end
                    3'b111: begin dec_legal=1; if (rs1_data >= rs2_data) dec_next_pc=pc+imm_b; end
                    default: dec_legal=0;
                endcase
            end
            OPCODE_JAL: begin dec_legal=1; dec_write_rd=1; dec_write_data=pc+(compressed ? 32'd2 : 32'd4); dec_next_pc=pc+imm_j; end
            OPCODE_JALR: if (funct3==0) begin dec_legal=1; dec_write_rd=1; dec_write_data=pc+(compressed ? 32'd2 : 32'd4); dec_next_pc=(rs1_data+imm_i)&32'hFFFF_FFFE; end
            OPCODE_LOAD: begin
                case (funct3)
                    3'b000,3'b001,3'b010,3'b100,3'b101: begin
                        dec_legal=1; dec_is_load=1; dec_mem_address=rs1_data+imm_i;
                        if ((funct3==3'b001 || funct3==3'b101) && dec_mem_address[0]) begin dec_exception=1; dec_exception_cause=4; dec_exception_value=dec_mem_address; end
                        if (funct3==3'b010 && dec_mem_address[1:0]!=0) begin dec_exception=1; dec_exception_cause=4; dec_exception_value=dec_mem_address; end
                    end
                    default: dec_legal=0;
                endcase
            end
            OPCODE_STORE: begin
                dec_mem_address=rs1_data+imm_s;
                case (funct3)
                    3'b000: begin dec_legal=1; dec_is_store=1; dec_mem_wstrb=4'b0001<<dec_mem_address[1:0]; dec_mem_wdata=rs2_data<<(dec_mem_address[1:0]*8); end
                    3'b001: begin dec_legal=1; dec_is_store=1; if (!dec_mem_address[0]) begin dec_mem_wstrb=4'b0011<<dec_mem_address[1:0]; dec_mem_wdata=rs2_data<<(dec_mem_address[1:0]*8); end else begin dec_exception=1; dec_exception_cause=6; dec_exception_value=dec_mem_address; end end
                    3'b010: begin dec_legal=1; dec_is_store=1; if (dec_mem_address[1:0]==0) begin dec_mem_wstrb=4'hf; dec_mem_wdata=rs2_data; end else begin dec_exception=1; dec_exception_cause=6; dec_exception_value=dec_mem_address; end end
                    default: dec_legal=0;
                endcase
            end
            OPCODE_MISC: if (funct3==0 && rd==0 && rs1==0 && rs2==0 && active_instr[31:28]==0) dec_legal=1;
            OPCODE_SYSTEM: begin
                if (funct3==0) begin
                    case (active_instr)
                        32'h0000_0073: begin dec_legal=1; dec_exception=1; dec_exception_cause=11; dec_exception_value=0; end // ECALL
                        32'h0010_0073: begin dec_legal=1; dec_exception=1; dec_exception_cause=3; dec_exception_value=pc; end // EBREAK
                        32'h3020_0073: begin dec_legal=1; dec_is_mret=1; end
                        32'h1050_0073: begin dec_legal=1; dec_is_wfi=1; end
                        default: dec_legal=0;
                    endcase
                end else if (funct3 != 3'b100) begin
                    dec_is_csr=1;
                    dec_legal=csr_known;
                    dec_write_rd=csr_known;
                    dec_write_data=csr_rdata;
                    if (funct3==3'b001 || funct3==3'b101) begin csr_write=1; csr_wdata=csr_source; end
                    else if (funct3==3'b010 || funct3==3'b110) begin csr_write=(csr_source!=0); csr_wdata=csr_rdata|csr_source; end
                    else if (funct3==3'b011 || funct3==3'b111) begin csr_write=(csr_source!=0); csr_wdata=csr_rdata&~csr_source; end
                    csr_write_illegal=csr_write && csr_readonly;
                    if (csr_write_illegal) dec_legal=0;
                end
            end
            default: dec_legal=0;
        endcase
        if (compressed && compressed_illegal) dec_legal=0;
    end

    always_comb begin
        mul_a_signed = {{32{rs1_data[31]}}, rs1_data};
        mul_b_signed = {{32{rs2_data[31]}}, rs2_data};
        mul_a_unsigned = {32'b0, rs1_data};
        mul_b_unsigned = {32'b0, rs2_data};
        case (funct3)
            3'b000: begin mul_product = rs1_data * rs2_data; muldiv_result = mul_product[31:0]; end
            3'b001: begin mul_product = mul_a_signed * mul_b_signed; muldiv_result = mul_product[63:32]; end
            3'b010: begin mul_product = mul_a_signed * mul_b_unsigned; muldiv_result = mul_product[63:32]; end
            3'b011: begin mul_product = mul_a_unsigned * mul_b_unsigned; muldiv_result = mul_product[63:32]; end
            3'b100: begin
                mul_product=0;
                if (rs2_data==0) muldiv_result=32'hffff_ffff;
                else if (rs1_data==32'h8000_0000 && rs2_data==32'hffff_ffff) muldiv_result=32'h8000_0000;
                else muldiv_result=$signed(rs1_data)/$signed(rs2_data);
            end
            3'b101: begin mul_product=0; muldiv_result=(rs2_data==0) ? 32'hffff_ffff : rs1_data/rs2_data; end
            3'b110: begin
                mul_product=0;
                if (rs2_data==0) muldiv_result=rs1_data;
                else if (rs1_data==32'h8000_0000 && rs2_data==32'hffff_ffff) muldiv_result=0;
                else muldiv_result=$signed(rs1_data)%$signed(rs2_data);
            end
            3'b111: begin mul_product=0; muldiv_result=(rs2_data==0) ? rs1_data : rs1_data%rs2_data; end
            default: begin mul_product=0; muldiv_result=0; end
        endcase
    end

    always_comb begin
        case (mem_lane)
            2'd0: shifted_load_data=dmem_rdata[15:0];
            2'd1: shifted_load_data=dmem_rdata[23:8];
            2'd2: shifted_load_data=dmem_rdata[31:16];
            default: shifted_load_data={8'b0,dmem_rdata[31:24]};
        endcase
        case (mem_funct3)
            3'b000: load_result={{24{shifted_load_data[7]}},shifted_load_data[7:0]};
            3'b001: load_result={{16{shifted_load_data[15]}},shifted_load_data[15:0]};
            3'b010: load_result=dmem_rdata;
            3'b100: load_result={24'b0,shifted_load_data[7:0]};
            3'b101: load_result={16'b0,shifted_load_data[15:0]};
            default: load_result=0;
        endcase
    end

    always_comb begin
        rf_we=0; rf_rd=rd; rf_wdata=dec_write_data;
        if (state==ST_EXEC && !pmp_fetch_deny && dec_legal && dec_write_rd && !dec_exception && !dec_is_load && !dec_is_store && !dec_is_mret && !dec_is_wfi) rf_we=1;
        else if (state==ST_MEM && dmem_ready && !dmem_error && !pmp_data_deny && !mem_is_store) begin rf_we=1; rf_rd=mem_rd; rf_wdata=load_result; end
    end
    always_comb begin
        dmem_valid=(state==ST_MEM) && !pmp_data_deny; dmem_write=mem_is_store; dmem_addr=mem_aligned_addr;
        dmem_wdata=mem_write_data; dmem_wstrb=mem_write_strobe;
    end
    // One-cycle architectural retirement pulse for observability/performance
    // counters. Memory instructions retire only when their bus operation ends.
    assign retire = rst_n && !trap_take &&
                    ((state==ST_EXEC && dec_legal && !dec_exception && !dec_is_load && !dec_is_store) ||
                     (state==ST_MEM && dmem_ready && !dmem_error && !pmp_data_deny));

    assign pmp_mem_ready = dmem_ready || (state==ST_MEM && pmp_data_deny);
    assign pmp_mem_error = dmem_error || pmp_data_deny;

    always_comb begin
        trap_take = 1'b0;
        trap_is_interrupt = 1'b0;
        trap_entry_cause = 32'd0;
        trap_entry_value = 32'd0;
        trap_entry_epc = pc;
        if (state==ST_EXEC && pmp_fetch_deny) begin
            trap_take=1'b1; trap_entry_cause=32'd1; trap_entry_value=pc;
        end else if (state==ST_EXEC && interrupt_pending && mstatus[3]) begin
            trap_take=1'b1; trap_is_interrupt=1'b1; trap_entry_cause=interrupt_cause;
        end else if (state==ST_EXEC && (!dec_legal || dec_exception)) begin
            trap_take=1'b1; trap_entry_cause=dec_legal ? dec_exception_cause : 32'd2;
            trap_entry_value=dec_legal ? dec_exception_value : (compressed ? {16'b0,compressed_word} : active_instr);
        end else if (state==ST_MEM && pmp_mem_ready && pmp_mem_error) begin
            trap_take=1'b1; trap_entry_cause=mem_is_store ? 32'd7 : 32'd5;
            trap_entry_value=mem_aligned_addr+{30'b0,mem_lane}; trap_entry_epc=mem_pc;
        end else if (state==ST_SLEEP && interrupt_pending && mstatus[3]) begin
            trap_take=1'b1; trap_is_interrupt=1'b1; trap_entry_cause=interrupt_cause;
        end
        trap_entry_pc=mtvec[31:2]<<2;
        if (trap_is_interrupt && mtvec[1:0]==2'b01)
            trap_entry_pc=(mtvec[31:2]<<2)+(trap_entry_cause<<2);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_EXEC; pc<=0; trap_valid<=0; trap_pc<=0; trap_cause<=0; trap_value<=0;
            mem_is_store<=0; mem_funct3<=0; mem_lane<=0; mem_pc_step<=0; mem_rd<=0; mem_pc<=0;
            mem_aligned_addr<=0; mem_write_data<=0; mem_write_strobe<=0;
            mstatus<=32'h0000_1800; mie<=0; mtvec<=0; mepc<=0; mcause<=0; mtval<=0;
            mcycle<=0; minstret<=0;
        end else begin
            mcycle <= mcycle + 1'b1;
            trap_valid <= 1'b0;
            if (trap_take) begin
                trap_valid<=1'b1; trap_pc<=trap_entry_epc;
                trap_cause<={trap_is_interrupt,trap_entry_cause[30:0]}; trap_value<=trap_entry_value;
                mepc<={trap_entry_epc[31:1],1'b0};
                mcause<={trap_is_interrupt,trap_entry_cause[30:0]}; mtval<=trap_entry_value;
                mstatus[7]<=mstatus[3]; mstatus[3]<=1'b0; mstatus[12:11]<=2'b11;
                pc<=trap_entry_pc; state<=ST_EXEC;
            end else case (state)
                ST_EXEC: begin
                    if (dec_is_load || dec_is_store) begin
                        mem_is_store<=dec_is_store; mem_funct3<=funct3; mem_lane<=dec_mem_address[1:0];
                        mem_rd<=rd; mem_pc<=pc; mem_pc_step<=compressed ? 2'd2 : 2'd0;
                        mem_aligned_addr<={dec_mem_address[31:2],2'b00}; mem_write_data<=dec_mem_wdata;
                        mem_write_strobe<=dec_mem_wstrb; state<=ST_MEM;
                    end else if (dec_is_mret) begin
                        mstatus[3]<=mstatus[7]; mstatus[7]<=1'b1; mstatus[12:11]<=2'b11;
                        pc<=mepc; minstret<=minstret+1'b1;
                    end else if (dec_is_wfi) begin
                        pc<=dec_next_pc; minstret<=minstret+1'b1;
                        if (interrupt_pending) state<=ST_EXEC; else state<=ST_SLEEP;
                    end else begin
                        pc<=dec_next_pc; minstret<=minstret+1'b1;
                        if (dec_is_csr && csr_write) begin
                            case (csr_addr)
                                12'h300: mstatus <= (csr_wdata & 32'h0000_1888) | 32'h0000_1800;
                                12'h304: mie <= csr_wdata & 32'h0000_0880;
                                12'h305: mtvec <= {csr_wdata[31:2], (csr_wdata[1:0] <= 1 ? csr_wdata[1:0] : 2'b00)};
                                12'h341: mepc <= {csr_wdata[31:1],1'b0};
                                12'h342: mcause <= csr_wdata;
                                12'h343: mtval <= csr_wdata;
                                12'hB00: mcycle[31:0] <= csr_wdata;
                                12'hB80: mcycle[63:32] <= csr_wdata;
                                12'hB02: minstret <= {minstret[63:32],csr_wdata};
                                12'hB82: minstret <= {csr_wdata,minstret[31:0]};
                                default: begin end
                            endcase
                        end
                    end
                end
                ST_MEM: if (pmp_mem_ready) begin
                    pc<=mem_pc + (mem_pc_step==2 ? 32'd2 : 32'd4);
                    state<=ST_EXEC; minstret<=minstret+1'b1;
                end
                ST_SLEEP: begin
                    if (interrupt_pending) begin
                        state<=ST_EXEC;
                    end
                end
                default: begin state<=ST_EXEC; end
            endcase
        end
    end

`ifdef FORMAL
    default clocking pmp_cb @(posedge clk); endclocking
    assert property (state==ST_MEM && pmp_data_deny |-> !dmem_valid);
    assert property (state==ST_EXEC && pmp_fetch_deny |-> trap_take && trap_entry_cause==32'd1 && !rf_we);
    assert property (state==ST_EXEC && pmp_fetch_deny |-> !(|pmp_cfg_we) && !pmp_addr_we);
`endif
endmodule
