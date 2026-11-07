// 32-pin GPIO at 0x4000_1000. Inputs pass through two synchronizer flops.
// IRQ_TYPE=1 selects edge mode (rising if IRQ_POL=1, falling otherwise);
// IRQ_TYPE=0 selects level mode (high if IRQ_POL=1, low otherwise).
module wb_gpio #(
    parameter integer WIDTH=32,
    parameter logic [31:0] BASE_ADDR=32'h4000_1000
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    input logic [WIDTH-1:0] gpio_in,
    output logic [WIDTH-1:0] gpio_out,
    output logic [WIDTH-1:0] gpio_oe,
    output logic irq_gpio
);
    logic [WIDTH-1:0] sync1,sync2,previous,output_reg,direction,irq_enable,irq_type,irq_polarity,irq_pending;
    logic pending,response_err,accept,saved_we;
    logic [31:0] response,saved_adr,saved_data;
    logic [3:0] saved_sel;
    logic [WIDTH-1:0] edge_event,level_event;
    logic [31:0] lane_mask;
    logic [WIDTH-1:0] clear_pending_mask;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b; begin merge_bytes=old_v; for(b=0;b<4;b=b+1) if(lanes[b]) merge_bytes[b*8 +: 8]=new_v[b*8 +: 8]; end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response; assign ack=pending&&!response_err&&cyc&&stb; assign err=pending&&response_err&&cyc&&stb;
    assign gpio_out=output_reg; assign gpio_oe=direction;
    assign lane_mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
    assign clear_pending_mask=(accept&&we&&(adr[11:0]==12'h014)) ? (dat_w[WIDTH-1:0]&lane_mask[WIDTH-1:0]) : {WIDTH{1'b0}};
    assign edge_event=irq_type & (((sync2 & ~previous & irq_polarity)) | ((~sync2 & previous & ~irq_polarity)));
    assign level_event=(~irq_type) & ((sync2 & irq_polarity) | (~sync2 & ~irq_polarity));
    assign irq_gpio=|(irq_enable & (irq_pending | level_event));
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin sync1<='0;sync2<='0;previous<='0;output_reg<='0;direction<='0;irq_enable<='0;irq_type<='0;irq_polarity<='0;irq_pending<='0;pending<=0;response_err<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;end
        else begin
            sync1<=gpio_in;sync2<=sync1;previous<=sync2;
            irq_pending <= (irq_pending & ~clear_pending_mask) | edge_event;
            if(!accept&&pending) pending<=0;
            else if(accept) begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err <= (sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||
                                !((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16)||(adr[11:0]==20));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0) begin
                    case(adr[11:0])
                        12'h000: begin response<={{(32-WIDTH){1'b0}},sync2}; if(we) output_reg<=merge_bytes({{(32-WIDTH){1'b0}},output_reg},dat_w,sel); end
                        12'h004: begin response<={{(32-WIDTH){1'b0}},direction}; if(we) direction<=merge_bytes({{(32-WIDTH){1'b0}},direction},dat_w,sel); end
                        12'h008: begin response<={{(32-WIDTH){1'b0}},irq_enable}; if(we) irq_enable<=merge_bytes({{(32-WIDTH){1'b0}},irq_enable},dat_w,sel); end
                        12'h00c: begin response<={{(32-WIDTH){1'b0}},irq_type}; if(we) irq_type<=merge_bytes({{(32-WIDTH){1'b0}},irq_type},dat_w,sel); end
                        12'h010: begin response<={{(32-WIDTH){1'b0}},irq_polarity}; if(we) irq_polarity<=merge_bytes({{(32-WIDTH){1'b0}},irq_polarity},dat_w,sel); end
                        12'h014: response<={{(32-WIDTH){1'b0}},irq_pending | level_event};
                        default: begin end
                    endcase
                end
            end
        end
    end
endmodule
