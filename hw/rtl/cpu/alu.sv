module alu (
    input  logic [31:0] a, b,
    input  logic [3:0]  alu_ctrl,
    output logic [31:0] result,
    output logic        zero
);
    always_comb begin
        case(alu_ctrl)
            4'b0000: result = a + b;
            4'b1000: result = a - b;
            default: result = 32'b0;
        endcase
        zero = (result == 32'b0);
    end
endmodule
