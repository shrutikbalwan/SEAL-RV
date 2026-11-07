// One-cycle terminating error slave for unmapped or otherwise rejected cycles.
module wb_error_slave (
    input  logic clk,
    input  logic rst_n,
    input  logic cyc,
    input  logic stb,
    output logic ack,
    output logic err,
    output logic [31:0] dat_r
);
    logic pending;
    always_comb begin
        ack = 1'b0;
        err = pending && cyc && stb;
        dat_r = 32'b0;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pending <= 1'b0;
        else
            pending <= cyc && stb;
    end
endmodule
