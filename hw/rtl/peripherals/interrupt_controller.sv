// Compact PLIC-like controller at 0x4000_5000.
// Timer is routed to the CPU MTIP input; UART/GPIO/watchdog share MEIP.
// External source IDs: UART=1, GPIO=2, watchdog=3. Higher numeric priority
// wins; equal priorities choose the lowest ID. Threshold is exclusive.
module interrupt_controller #(
    parameter logic [31:0] BASE_ADDR=32'h4000_5000
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    input logic irq_timer_in, irq_uart_in, irq_gpio_in, irq_watchdog_in,
    output logic irq_timer, irq_external
);
    logic [2:0] pending_ext;
    logic [3:0] enable_ext;
    logic [2:0] priority_uart,priority_gpio,priority_watchdog,threshold;
    logic pending,pending_err,accept,saved_we;
    logic [31:0] response,saved_adr,saved_data;
    logic [3:0] saved_sel;
    logic [2:0] eligible;
    logic [1:0] claim_id;
    logic [2:0] clear_mask;
    logic [2:0] best_priority;
    logic [31:0] word_value;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b; begin merge_bytes=old_v; for(b=0;b<4;b=b+1) if(lanes[b]) merge_bytes[b*8 +: 8]=new_v[b*8 +: 8]; end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;assign ack=pending&&!pending_err&&cyc&&stb;assign err=pending&&pending_err&&cyc&&stb;
    assign irq_timer=irq_timer_in&&enable_ext[0];
    always_comb begin
        eligible[0]=pending_ext[0]&&enable_ext[1]&&(priority_uart>threshold);
        eligible[1]=pending_ext[1]&&enable_ext[2]&&(priority_gpio>threshold);
        eligible[2]=pending_ext[2]&&enable_ext[3]&&(priority_watchdog>threshold);
        claim_id=0; best_priority=0;
        if(eligible[0]) begin claim_id=1; best_priority=priority_uart; end
        if(eligible[1]&&(claim_id==0||priority_gpio>best_priority)) begin claim_id=2; best_priority=priority_gpio; end
        if(eligible[2]&&(claim_id==0||priority_watchdog>best_priority)) begin claim_id=3; best_priority=priority_watchdog; end
        clear_mask=0;
        if(accept&&adr[11:0]==12'h00c) begin
            if(!we&&claim_id!=0) clear_mask[claim_id-1'b1]=1'b1;
            else if(we&&sel[0]&&dat_w[7:0]>=1&&dat_w[7:0]<=3) clear_mask[dat_w[1:0]-1'b1]=1'b1;
        end
    end
    assign irq_external=|eligible;
    always_comb begin
        case(adr[11:0])
            12'h000: word_value={28'b0,pending_ext[2],pending_ext[1],pending_ext[0],irq_timer_in};
            12'h004: word_value={28'b0,enable_ext};
            12'h008: word_value={29'b0,threshold};
            12'h00c: word_value={30'b0,claim_id};
            12'h010: word_value={29'b0,priority_uart};
            12'h014: word_value={29'b0,priority_gpio};
            12'h018: word_value={29'b0,priority_watchdog};
            default: word_value=0;
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pending_ext<=0;enable_ext<=0;threshold<=0;priority_uart<=3;priority_gpio<=2;priority_watchdog<=1;
            pending<=0;pending_err<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;
        end else begin
            pending_ext <= (pending_ext & ~clear_mask) | {irq_watchdog_in,irq_gpio_in,irq_uart_in};
            if(!accept&&pending) pending<=0;
            else if(accept) begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=word_value;
                pending_err <= (sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||
                               !((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16)||(adr[11:0]==20)||(adr[11:0]==24));
                if(we&&adr[11:0]==12'h000) pending_err<=1;
                if(we&&sel!=0&&adr[31:12]==BASE_ADDR[31:12]) case(adr[11:0])
                    12'h004: enable_ext<=merge_bytes({28'b0,enable_ext},dat_w,sel);
                    12'h008: threshold<=merge_bytes({29'b0,threshold},dat_w,sel);
                    12'h00c: begin end
                    12'h010: priority_uart<=merge_bytes({29'b0,priority_uart},dat_w,sel);
                    12'h014: priority_gpio<=merge_bytes({29'b0,priority_gpio},dat_w,sel);
                    12'h018: priority_watchdog<=merge_bytes({29'b0,priority_watchdog},dat_w,sel);
                    default: begin end
                endcase
            end
        end
    end
endmodule
