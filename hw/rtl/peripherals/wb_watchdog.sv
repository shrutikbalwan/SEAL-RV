// Watchdog at 0x4000_D000. Servicing requires 0x51F15EED at SERVICE.
module wb_watchdog #(
    parameter logic [31:0] BASE_ADDR = 32'h4000_d000,
    parameter logic [31:0] SERVICE_KEY = 32'h51f1_5eed
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    output logic irq_watchdog,
    output logic reset_request
);
    logic enabled, pending, response_err;
    logic [31:0] timeout_cycles, count, response;
    logic [31:0] saved_adr, saved_data;
    logic [3:0] saved_sel;
    logic saved_we, accept;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b; begin merge_bytes=old_v; for (b=0;b<4;b=b+1) if(lanes[b]) merge_bytes[b*8 +: 8]=new_v[b*8 +: 8]; end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response; assign ack=pending&&!response_err&&cyc&&stb; assign err=pending&&response_err&&cyc&&stb;
    assign irq_watchdog=reset_request;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin enabled<=0;timeout_cycles<=0;count<=0;reset_request<=0;pending<=0;response_err<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;end
        else begin
            if(!accept&&pending) pending<=0;
            else if(accept) begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err <= (sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||
                                !((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0) case(adr[11:0])
                    12'h000: begin response<={31'b0,enabled}; if(we&&sel[0]) begin enabled<=dat_w[0];count<=timeout_cycles;reset_request<=0;end end
                    12'h004: begin response<=timeout_cycles; if(we) timeout_cycles<=merge_bytes(timeout_cycles,dat_w,sel); end
                    12'h008: begin response<=count; if(we) response_err<=1; end
                    12'h00c: begin response<=0; if(!we) response_err<=1; else begin
                        if(sel==4'hf&&dat_w==SERVICE_KEY) begin count<=timeout_cycles;reset_request<=0;end
                        else reset_request<=1;
                    end end
                    default: begin end
                endcase
            end
            if(enabled&&!reset_request&&!(accept&&we&&(adr[11:0]==0||adr[11:0]==12'h00c))) begin
                if(count<=1) begin count<=0;reset_request<=1;end
                else count<=count-1'b1;
            end
        end
    end
endmodule
