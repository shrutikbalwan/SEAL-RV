module cpu_core (
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] pc,
    input  logic [31:0] instr
);
    logic [4:0]  rs1, rs2, rd;
    logic [6:0]  opcode;
    logic [31:0] rd1, rd2, imm, alu_res;
    logic        we;
    logic [3:0]  alu_ctrl;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];

    // Minimal decoder for ADD/SUB/ADDI
    assign we = (opcode == 7'b0110011 || opcode == 7'b0010011);
    assign imm = {{20{instr[31]}}, instr[31:20]};
    assign alu_ctrl = (opcode == 7'b0110011 && instr[30]) ? 4'b1000 : 4'b0000;

    regfile rf (.clk(clk), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd), .wd(alu_res), .rd1(rd1), .rd2(rd2));
    alu alu_inst (.a(rd1), .b((opcode == 7'b0010011) ? imm : rd2), .alu_ctrl(alu_ctrl), .result(alu_res), .zero());

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'b0;
        else        pc <= pc + 4;
    end
endmodule
