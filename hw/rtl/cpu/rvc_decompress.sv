// RV32C integer instruction decompressor. Emits canonical RV32I/RV32M words.
module rvc_decompress (
    input  logic [15:0] cinsn,
    output logic [31:0] insn,
    output logic        illegal
);
    logic [4:0] rd, rs2, rs1p, rs2p;
    logic [11:0] imm12;
    logic [20:0] jimm;
    logic [12:0] bimm;
    logic [31:0] imm32;

    always_comb begin
        insn = 32'h0000_0013; // HINTs are represented as NOP.
        illegal = 1'b0;
        rd = cinsn[11:7];
        rs2 = cinsn[6:2];
        rs1p = {2'b01, cinsn[9:7]};
        rs2p = {2'b01, cinsn[4:2]};
        imm12 = {{7{cinsn[12]}}, cinsn[6:2]};
        jimm = '0;
        bimm = '0;
        imm32 = '0;

        case (cinsn[1:0])
            2'b00: begin
                case (cinsn[15:13])
                    3'b000: begin // C.ADDI4SPN
                        imm32 = {22'b0, cinsn[10:7], cinsn[12:11], cinsn[5], cinsn[6], 2'b00};
                        if (imm32 == 0) illegal = 1'b1;
                        else insn = {imm32[11:0], 5'd2, 3'b000, rs2p, 7'h13};
                    end
                    3'b010: begin // C.LW
                        imm32 = {25'b0, cinsn[5], cinsn[12:10], cinsn[6], 2'b00};
                        insn = {imm32[11:0], rs1p, 3'b010, rs2p, 7'h03};
                    end
                    3'b110: begin // C.SW
                        imm32 = {25'b0, cinsn[5], cinsn[12:10], cinsn[6], 2'b00};
                        insn = {imm32[11:5], rs2p, rs1p, 3'b010, imm32[4:0], 7'h23};
                    end
                    default: illegal = 1'b1;
                endcase
            end
            2'b01: begin
                case (cinsn[15:13])
                    3'b000: begin // C.ADDI / C.NOP
                        if (rd != 0) insn = {imm12, rd, 3'b000, rd, 7'h13};
                    end
                    3'b001, 3'b101: begin // C.JAL / C.J
                        jimm = {{9{cinsn[12]}}, cinsn[12], cinsn[8], cinsn[10:9], cinsn[6], cinsn[7], cinsn[2], cinsn[11], cinsn[5:3], 1'b0};
                        insn = {jimm[20], jimm[10:1], jimm[11], jimm[19:12], (cinsn[15:13] == 3'b001 ? 5'd1 : 5'd0), 7'h6f};
                    end
                    3'b010: begin // C.LI
                        if (rd != 0) insn = {imm12, 5'd0, 3'b000, rd, 7'h13};
                    end
                    3'b011: begin
                        if (rd == 5'd2) begin // C.ADDI16SP
                            imm32 = {{22{cinsn[12]}}, cinsn[12], cinsn[4:3], cinsn[5], cinsn[2], cinsn[6], 4'b0000};
                            if (imm32 == 0) illegal = 1'b1;
                            else insn = {imm32[11:0], 5'd2, 3'b000, 5'd2, 7'h13};
                        end else if (rd != 0) begin // C.LUI
                            if ({cinsn[12], cinsn[6:2]} == 0) illegal = 1'b1;
                            else insn = {{14{cinsn[12]}}, cinsn[12], cinsn[6:2], rd, 7'h37};
                        end else illegal = 1'b1;
                    end
                    3'b100: begin
                        case (cinsn[11:10])
                            2'b00: begin // C.SRLI
                                if (cinsn[12]) illegal = 1'b1;
                                else insn = {7'b0000000, cinsn[6:2], rs1p, 3'b101, rs1p, 7'h13};
                            end
                            2'b01: begin // C.SRAI
                                if (cinsn[12]) illegal = 1'b1;
                                else insn = {7'b0100000, cinsn[6:2], rs1p, 3'b101, rs1p, 7'h13};
                            end
                            2'b10: begin // C.ANDI
                                insn = {imm12, rs1p, 3'b111, rs1p, 7'h13};
                            end
                            2'b11: begin
                                if (cinsn[12]) illegal = 1'b1; // RV64 SUBW/ADDW encodings
                                else begin
                                    case (cinsn[6:5])
                                        2'b00: insn = {7'b0100000, rs2p, rs1p, 3'b000, rs1p, 7'h33};
                                        2'b01: insn = {7'b0000000, rs2p, rs1p, 3'b100, rs1p, 7'h33};
                                        2'b10: insn = {7'b0000000, rs2p, rs1p, 3'b110, rs1p, 7'h33};
                                        2'b11: insn = {7'b0000000, rs2p, rs1p, 3'b111, rs1p, 7'h33};
                                    endcase
                                end
                            end
                        endcase
                    end
                    3'b110, 3'b111: begin // C.BEQZ / C.BNEZ
                        bimm = {{4{cinsn[12]}}, cinsn[12], cinsn[6:5], cinsn[2], cinsn[11:10], cinsn[4:3], 1'b0};
                        insn = {bimm[12], bimm[10:5], 5'd0, rs1p,
                                (cinsn[15:13] == 3'b110 ? 3'b000 : 3'b001),
                                bimm[4:1], bimm[11], 7'h63};
                    end
                    default: illegal = 1'b1;
                endcase
            end
            2'b10: begin
                case (cinsn[15:13])
                    3'b000: begin // C.SLLI
                        if (cinsn[12]) illegal = 1'b1;
                        else if (rd != 0) insn = {7'b0000000, cinsn[6:2], rd, 3'b001, rd, 7'h13};
                    end
                    3'b010: begin // C.LWSP
                        imm32 = {24'b0, cinsn[3:2], cinsn[12], cinsn[6:4], 2'b00};
                        if (rd == 0) illegal = 1'b1;
                        else insn = {imm32[11:0], 5'd2, 3'b010, rd, 7'h03};
                    end
                    3'b100: begin
                        if (!cinsn[12] && rs2 == 0) begin // C.JR
                            if (rd == 0) illegal = 1'b1;
                            else insn = {12'b0, rd, 3'b000, 5'd0, 7'h67};
                        end else if (!cinsn[12] && rs2 != 0) begin // C.MV
                            if (rd != 0) insn = {7'b0, rs2, 5'd0, 3'b000, rd, 7'h33};
                        end else if (cinsn[12] && rs2 == 0 && rd == 0) begin // C.EBREAK
                            insn = 32'h0010_0073;
                        end else if (cinsn[12] && rs2 == 0) begin // C.JALR
                            insn = {12'b0, rd, 3'b000, 5'd1, 7'h67};
                        end else begin // C.ADD
                            if (rd != 0) insn = {7'b0, rs2, rd, 3'b000, rd, 7'h33};
                        end
                    end
                    3'b110: begin // C.SWSP
                        imm32 = {24'b0, cinsn[8:7], cinsn[12:9], 2'b00};
                        insn = {imm32[11:5], rs2, 5'd2, 3'b010, imm32[4:0], 7'h23};
                    end
                    default: illegal = 1'b1;
                endcase
            end
            default: illegal = 1'b1;
        endcase
    end
endmodule
