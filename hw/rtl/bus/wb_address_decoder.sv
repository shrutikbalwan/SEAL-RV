// Full-address, one-hot decode for the fixed ROM/SRAM/peripheral target ports.
module wb_address_decoder #(
    parameter logic [31:0] ROM_BASE  = 32'h0000_0000,
    parameter logic [31:0] ROM_MASK  = 32'hFFFF_F000,
    parameter logic [31:0] SRAM_BASE = 32'h1000_0000,
    parameter logic [31:0] SRAM_MASK = 32'hFFFF_8000,
    parameter logic [31:0] PERIPH_BASE = 32'h4000_0000,
    parameter logic [31:0] PERIPH_MASK = 32'hFFFF_0000
) (
    input  logic [31:0] adr,
    output logic [2:0]  select,
    output logic        unmapped
);
    logic [2:0] raw_select;
    always_comb begin
        raw_select[0] = ((adr & ROM_MASK) == (ROM_BASE & ROM_MASK));
        raw_select[1] = ((adr & SRAM_MASK) == (SRAM_BASE & SRAM_MASK));
        raw_select[2] = ((adr & PERIPH_MASK) == (PERIPH_BASE & PERIPH_MASK));
    end
    assign unmapped = !(|raw_select) || ((raw_select & (raw_select - 3'b001)) != 3'b000);
    assign select = unmapped ? 3'b000 : raw_select;
endmodule
