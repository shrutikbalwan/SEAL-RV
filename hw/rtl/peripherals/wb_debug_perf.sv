// Machine-mode performance/debug observation counters at 0x4000_A000.
// This block provides counters/last-PC only; no halt or single-step transport.
module wb_debug_perf #(
    parameter logic [31:0] BASE_ADDR=32'h4000_a000
) (
    input logic clk,rst_n,
    input logic cyc,stb,we,
    input logic [31:0] adr,dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack,err,
    input logic cpu_retire,
    input logic [31:0] cpu_pc,
    input logic bus_event,irq_event
);
    logic enabled,pending,response_err,accept,saved_we,irq_prev;
    logic [31:0] response,saved_adr,saved_data,last_pc;
    logic [3:0] saved_sel;
    logic [63:0] cycle_count,retired_count;
    logic [31:0] bus_count,irq_count;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b;begin merge_bytes=old_v;for(b=0;b<4;b=b+1)if(lanes[b])merge_bytes[b*8 +: 8]=new_v[b*8 +: 8];end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;assign ack=pending&&!response_err&&cyc&&stb;assign err=pending&&response_err&&cyc&&stb;
    always_ff @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin enabled<=1;pending<=0;response_err<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;cycle_count<=0;retired_count<=0;bus_count<=0;irq_count<=0;last_pc<=0;irq_prev<=0;end
        else begin
            irq_prev<=irq_event;
            if(enabled)begin
                cycle_count<=cycle_count+1'b1;
                if(cpu_retire)begin retired_count<=retired_count+1'b1;last_pc<=cpu_pc;end
                if(bus_event)bus_count<=bus_count+1'b1;
                if(irq_event&&!irq_prev)irq_count<=irq_count+1'b1;
            end
            if(!accept&&pending)pending<=0;
            else if(accept)begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err<=(sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||
                    !((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16)||(adr[11:0]==20)||(adr[11:0]==24)||(adr[11:0]==28));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0)case(adr[11:0])
                    12'h000:begin response<={31'b0,enabled};if(we&&sel[0])enabled<=dat_w[0];end
                    12'h004:begin response<=cycle_count[31:0];if(we)cycle_count[31:0]<=merge_bytes(cycle_count[31:0],dat_w,sel);end
                    12'h008:begin response<=cycle_count[63:32];if(we)cycle_count[63:32]<=merge_bytes(cycle_count[63:32],dat_w,sel);end
                    12'h00c:begin response<=retired_count[31:0];if(we)retired_count[31:0]<=merge_bytes(retired_count[31:0],dat_w,sel);end
                    12'h010:begin response<=retired_count[63:32];if(we)retired_count[63:32]<=merge_bytes(retired_count[63:32],dat_w,sel);end
                    12'h014:begin response<=bus_count;if(we)bus_count<=merge_bytes(bus_count,dat_w,sel);end
                    12'h018:begin response<=irq_count;if(we)irq_count<=merge_bytes(irq_count,dat_w,sel);end
                    12'h01c:begin response<=last_pc;if(we)response_err<=1;end
                    default:begin end
                endcase
            end
        end
    end
endmodule
