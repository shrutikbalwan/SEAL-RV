// Eight-entry RV32 PMP register bank. pmpcfg is supplied one byte at a time;
// pmpaddr follows the architectural 4 KiB-granularity encoding.
module seal_pmp (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  cfg_we,
    input  logic [63:0] cfg_wdata,
    input  logic        addr_we,
    input  logic [2:0]  addr_index,
    input  logic [31:0] addr_wdata,
    input  logic [2:0]  read_index,
    output logic [7:0]  cfg_rdata,
    output logic [31:0] addr_rdata,
    output logic [63:0] cfg_flat,
    output logic [255:0] addr_flat
);
    logic [7:0] cfg [0:7];
    logic [31:0] paddr [0:7];
    integer i;
    always_comb begin
        cfg_rdata = cfg[read_index];
        addr_rdata = paddr[read_index];
        for (integer j=0; j<8; j=j+1) begin
            cfg_flat[j*8 +: 8] = cfg[j];
            addr_flat[j*32 +: 32] = paddr[j];
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<8; i=i+1) begin cfg[i] <= 0; paddr[i] <= 0; end
        end else begin
            for (integer j=0; j<8; j=j+1) if (cfg_we[j] && !cfg[j][7]) begin
                cfg[j] <= {cfg_wdata[j*8+7], 2'b00, cfg_wdata[j*8+3 +: 2],
                           cfg_wdata[j*8+2], (cfg_wdata[j*8+1] && cfg_wdata[j*8]), cfg_wdata[j*8]};
                // Reserved address mode 2 is WARL and reads back as OFF.
                if (cfg_wdata[j*8 + 3 +: 2] == 2'b10) cfg[j][4:3] <= 2'b00;
            end
            if (addr_we && !cfg[addr_index][7] &&
                !(addr_index < 7 && cfg[addr_index+1'b1][7] && cfg[addr_index+1'b1][4:3] == 2'b01))
                paddr[addr_index] <= {2'b00,addr_wdata[29:0]};
        end
    end
endmodule
