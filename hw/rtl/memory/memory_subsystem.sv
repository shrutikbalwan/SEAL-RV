// Combined CPU instruction fetch and Wishbone memory slave.
module memory_subsystem #(
    parameter ROM_INIT_FILE = "hw/tb/boot_image.hex",
    parameter SRAM_INIT_FILE = ""
) (
    input logic clk, rst_n,
    input logic [31:0] fetch_addr,
    output logic [31:0] fetch_data,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err
);
    logic [31:0] rdata_rom, rdata_sram;
    logic ack_rom, err_rom, ack_sram, err_sram;
    logic rom_sel, sram_sel;
    assign rom_sel = adr[31:12] == 20'h00000;
    assign sram_sel = adr[31:15] == 17'h02000; // 0x1000_0000 / 0x8000

    boot_rom #(.INIT_FILE(ROM_INIT_FILE)) rom (
        .clk, .rst_n, .cyc(cyc && rom_sel), .stb(stb && rom_sel), .we, .adr, .dat_w, .sel,
        .dat_r(rdata_rom), .ack(ack_rom), .err(err_rom), .fetch_addr, .fetch_data
    );
    wb_sram #(.INIT_FILE(SRAM_INIT_FILE)) sram (
        .clk, .rst_n, .cyc(cyc && sram_sel), .stb(stb && sram_sel), .we, .adr, .dat_w, .sel,
        .dat_r(rdata_sram), .ack(ack_sram), .err(err_sram)
    );
    logic pending_unmapped;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) pending_unmapped <= 0;
        else pending_unmapped <= cyc && stb && !rom_sel && !sram_sel;
    assign dat_r = rom_sel ? rdata_rom : sram_sel ? rdata_sram : 32'b0;
    assign ack = rom_sel ? ack_rom : sram_sel ? ack_sram : 1'b0;
    assign err = rom_sel ? err_rom : sram_sel ? err_sram : pending_unmapped && cyc && stb;
endmodule
