module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [4:0]  rs1, rs2, rd,
    input  logic [31:0] wd,
    output logic [31:0] rd1, rd2
);
    logic [31:0] regs [0:31];
    always_comb begin
        rd1 = (rs1 == 0) ? 32'b0 : regs[rs1];
        rd2 = (rs2 == 0) ? 32'b0 : regs[rs2];
    end
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && rd != 0) begin
            regs[rd] <= wd;
        end
    end
endmodule
