// 4 KiB read-only image. Wishbone reads ACK in one clock; writes ERR.
// fetch_addr/fetch_data provide the CPU's existing combinational fetch window.
module boot_rom #(
    parameter INIT_FILE = "hw/tb/boot_image.hex"
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    input logic [31:0] fetch_addr,
    output logic [31:0] fetch_data
);
    logic [31:0] mem [0:1023];
    logic pending, pending_err;
    logic [31:0] response;
    logic [9:0] fetch_word_index;
    integer i;
    initial begin
        for (i=0; i<1024; i=i+1) mem[i] = 32'h0000_0013;
        $readmemh(INIT_FILE, mem);
    end
    // Present a 32-bit fetch window whose low halfword is at fetch_addr,
    // including RV32C instructions starting in the upper half of a word.
    // The fetch port has no fault handshake; out-of-ROM fetches return NOP.
    assign fetch_word_index = fetch_addr[11:2];
    always_comb begin
        fetch_data = 32'h0000_0013;
        if (fetch_addr[31:12] == 0) begin
            fetch_data = mem[fetch_word_index];
            if (fetch_addr[1]) begin
                if (fetch_word_index != 10'd1023)
                    fetch_data = {mem[fetch_word_index + 10'd1][15:0], mem[fetch_word_index][31:16]};
                else
                    fetch_data = {16'h0013, mem[fetch_word_index][31:16]};
            end
        end
    end
    assign dat_r = response;
    assign ack = pending && !pending_err && cyc && stb;
    assign err = pending && pending_err && cyc && stb;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin pending<=0; pending_err<=0; response<=0; end
        else begin
            pending <= cyc && stb;
            if (cyc && stb) begin
                pending_err <= we || sel==0 || adr[31:12]!=0;
                response <= (!we && sel!=0 && adr[31:12]==0) ? mem[adr[11:2]] : 0;
            end
        end
    end
endmodule
