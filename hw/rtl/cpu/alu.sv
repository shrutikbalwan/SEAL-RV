module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_ctrl,
    output logic [31:0] result,
    output logic        zero
);
    localparam logic [3:0] ALU_ADD  = 4'h0;
    localparam logic [3:0] ALU_SLL  = 4'h1;
    localparam logic [3:0] ALU_SLT  = 4'h2;
    localparam logic [3:0] ALU_SLTU = 4'h3;
    localparam logic [3:0] ALU_XOR  = 4'h4;
    localparam logic [3:0] ALU_SRL  = 4'h5;
    localparam logic [3:0] ALU_OR   = 4'h6;
    localparam logic [3:0] ALU_AND  = 4'h7;
    localparam logic [3:0] ALU_SUB  = 4'h8;
    localparam logic [3:0] ALU_SRA  = 4'hD;

    always_comb begin
        case (alu_ctrl)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SLT:  result = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU: result = {31'b0, (a < b)};
            ALU_XOR:  result = a ^ b;
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $signed(a) >>> b[4:0];
            ALU_OR:   result = a | b;
            ALU_AND:  result = a & b;
            default:  result = 32'b0;
        endcase
        zero = (result == 32'b0);
    end
endmodule
