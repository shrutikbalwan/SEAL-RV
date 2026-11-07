// Behavioral 32 KiB little-endian SRAM, Wishbone Classic, one-cycle response.
// ASIC flows must replace this module with a characterized SRAM wrapper.
module wb_sram #(
    parameter INIT_FILE = ""
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err
);
    logic [31:0] mem [0:8191];
    logic pending;
    logic [31:0] response;
    logic response_err;
    logic [12:0] word_index;
    integer lane;

    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    assign word_index = adr[14:2];
    assign dat_r = response;
    assign ack = pending && !response_err && cyc && stb;
    assign err = pending && response_err && cyc && stb;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pending <= 1'b0; response <= 0; response_err <= 0; end
        else begin
            pending <= cyc && stb;
            if (cyc && stb) begin
                response_err <= (sel == 0) || (adr[31:15] != 17'h02000);
                if (sel != 0 && adr[31:15] == 17'h02000) begin
                    if (we) begin
                        for (lane=0; lane<4; lane=lane+1)
                            if (sel[lane]) mem[word_index][lane*8 +: 8] <= dat_w[lane*8 +: 8];
                    end
                    response <= mem[word_index];
                end else response <= 0;
            end
        end
    end
endmodule
