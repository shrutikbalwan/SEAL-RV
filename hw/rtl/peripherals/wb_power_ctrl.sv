// Power/clock request and wake-status registers at 0x4000_B000.
// Clock enables are requests for glitch-free ICG integration; this block never
// gates a clock directly. Reset requests are sticky until system reset.
module wb_power_ctrl #(
    parameter logic [31:0] BASE_ADDR=32'h4000_b000,
    parameter logic [31:0] RESET_KEY=32'h52535401
) (
    input logic clk,rst_n,
    input logic cyc,stb,we,
    input logic [31:0] adr,dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack,err,
    input logic [4:0] wake_sources,
    output logic sleep_request,
    output logic [4:0] clock_enable_req,
    output logic [5:0] wake_status,
    output logic reset_request
);
    localparam logic [4:0] VALID_CLOCKS=5'b1_1111;
    logic [5:0] wake_enable;
    logic pending,response_err,accept,saved_we;
    logic [31:0] response,saved_adr,saved_data;
    logic [3:0] saved_sel;
    logic [5:0] selected_wake,clear_wake;
    logic [31:0] lane_mask;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b;begin merge_bytes=old_v;for(b=0;b<4;b=b+1)if(lanes[b])merge_bytes[b*8 +: 8]=new_v[b*8 +: 8];end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;assign ack=pending&&!response_err&&cyc&&stb;assign err=pending&&response_err&&cyc&&stb;
    assign lane_mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
    always_comb begin
        selected_wake={1'b0,wake_sources}&wake_enable;
        clear_wake=0;
        if(accept&&we&&adr[11:0]==12'h00c)clear_wake=dat_w[5:0]&lane_mask[5:0];
    end
    always_ff @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin sleep_request<=0;clock_enable_req<=VALID_CLOCKS;wake_enable<=0;wake_status<=0;reset_request<=0;pending<=0;response_err<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;end
        else begin
            wake_status<=(wake_status&~clear_wake)|selected_wake;
            if(|selected_wake)sleep_request<=0;
            if(!accept&&pending)pending<=0;
            else if(accept)begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err<=(sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||!((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16)||(adr[11:0]==20));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0)case(adr[11:0])
                    12'h000:begin response<={31'b0,sleep_request};if(we&&sel[0])sleep_request<=dat_w[0];end
                    12'h004:begin response<={27'b0,clock_enable_req};if(we)clock_enable_req<=merge_bytes({27'b0,clock_enable_req},dat_w,sel)&VALID_CLOCKS;end
                    12'h008:begin response<={26'b0,wake_enable};if(we)wake_enable<=merge_bytes({26'b0,wake_enable},dat_w,sel);end
                    12'h00c:begin response<={26'b0,wake_status};end
                    12'h010:begin response<=0;if(!we||sel!=4'hf||dat_w!=RESET_KEY)response_err<=1;else reset_request<=1;end
                    12'h014:begin response<=0;if(we&&sel[0]&&dat_w[0])begin wake_status[5]<=1;sleep_request<=0;end else response_err<=1;end
                    default:begin end
                endcase
            end
        end
    end
endmodule
