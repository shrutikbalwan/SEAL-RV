// Machine timer at 0x4000_4000. mtime advances once per clk; all bus
// accesses have a registered one-cycle response.
module wb_timer #(
    parameter logic [31:0] BASE_ADDR = 32'h4000_4000
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    output logic irq_timer
);
    logic [63:0] mtime, mtimecmp;
    logic irq_enable;
    logic pending, response_err;
    logic [31:0] response, saved_adr, saved_data;
    logic [3:0] saved_sel;
    logic saved_we;
    logic accept;
    logic [31:0] merged;

    function automatic [31:0] merge_bytes(input [31:0] old_v, input [31:0] new_v, input [3:0] lanes);
        integer b;
        begin merge_bytes=old_v; for (b=0;b<4;b=b+1) if (lanes[b]) merge_bytes[b*8 +: 8]=new_v[b*8 +: 8]; end
    endfunction
    assign accept = cyc && stb && (!pending || ({we,adr,dat_w,sel} != {saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;
    assign ack=pending && !response_err && cyc && stb;
    assign err=pending && response_err && cyc && stb;
    assign irq_timer=irq_enable && (mtime >= mtimecmp);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime<=0; mtimecmp<=64'hffff_ffff_ffff_ffff; irq_enable<=1'b1;
            pending<=0; response_err<=0; response<=0; saved_adr<=0; saved_data<=0; saved_sel<=0; saved_we<=0;
        end else begin
            if (!accept && pending) pending<=0;
            else if (accept) begin
                pending<=1; saved_adr<=adr; saved_data<=dat_w; saved_sel<=sel; saved_we<=we;
                response_err <= (sel==0) || (adr[1:0]!=0) || (adr[31:12] != BASE_ADDR[31:12]) ||
                                !((adr[11:0]==12'h000)||(adr[11:0]==12'h004)||(adr[11:0]==12'h008)||
                                  (adr[11:0]==12'h00c)||(adr[11:0]==12'h010));
                response<=0;
                if (adr[31:12]==BASE_ADDR[31:12] && adr[1:0]==0 && sel!=0) begin
                    case (adr[11:0])
                        12'h000: begin response<=mtime[31:0]; if (we) mtime[31:0]<=merge_bytes(mtime[31:0],dat_w,sel); end
                        12'h004: begin response<=mtime[63:32]; if (we) mtime[63:32]<=merge_bytes(mtime[63:32],dat_w,sel); end
                        12'h008: begin response<=mtimecmp[31:0]; if (we) mtimecmp[31:0]<=merge_bytes(mtimecmp[31:0],dat_w,sel); end
                        12'h00c: begin response<=mtimecmp[63:32]; if (we) mtimecmp[63:32]<=merge_bytes(mtimecmp[63:32],dat_w,sel); end
                        12'h010: begin response<={31'b0,irq_enable}; if (we && sel[0]) irq_enable<=dat_w[0]; end
                        default: begin end
                    endcase
                end
            end
            if (!(accept && we && (adr[11:0]==12'h000 || adr[11:0]==12'h004))) mtime<=mtime+64'd1;
        end
    end
endmodule
