// 8-N-1 UART at 0x4000_0000. DIVIDER is system clocks per serial bit;
// reset divisor is rounded from CLK_HZ/115200 (minimum four clocks).
module wb_uart #(
    parameter integer CLK_HZ=50_000_000,
    parameter logic [31:0] BASE_ADDR=32'h4000_0000,
    parameter integer DEFAULT_DIV=(CLK_HZ/115200 < 4 ? 4 : (CLK_HZ+57600)/115200)
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    output logic uart_tx,
    input logic uart_rx,
    output logic irq_uart
);
    localparam logic [1:0] RX_IDLE=0,RX_START=1,RX_DATA=2,RX_STOP=3;
    logic [31:0] divider, response, saved_adr, saved_data;
    logic [3:0] saved_sel;
    logic saved_we,pending,response_err,accept;
    logic [7:0] tx_shift,rx_shift,rx_data;
    logic tx_busy,rx_valid,rx_overrun,tx_enable,rx_enable,tx_irq_enable,rx_irq_enable;
    logic [3:0] tx_bit;
    logic [1:0] rx_state;
    logic [3:0] rx_bit;
    logic [31:0] tx_count,rx_count;
    logic rx_meta,rx_sync;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b; begin merge_bytes=old_v; for(b=0;b<4;b=b+1) if(lanes[b]) merge_bytes[b*8 +: 8]=new_v[b*8 +: 8]; end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response; assign ack=pending&&!response_err&&cyc&&stb; assign err=pending&&response_err&&cyc&&stb;
    assign irq_uart=(rx_irq_enable&&rx_valid)||(tx_irq_enable&&!tx_busy);
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_meta<=1;rx_sync<=1; end
        else begin rx_meta<=uart_rx;rx_sync<=rx_meta; end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            divider<=DEFAULT_DIV;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;pending<=0;response_err<=0;
            uart_tx<=1;tx_shift<=0;tx_busy<=0;tx_bit<=0;tx_count<=0;
            rx_state<=RX_IDLE;rx_bit<=0;rx_count<=0;rx_shift<=0;rx_data<=0;rx_valid<=0;rx_overrun<=0;
            tx_enable<=1;rx_enable<=1;tx_irq_enable<=0;rx_irq_enable<=0;
        end else begin
            if(!accept&&pending) pending<=0;
            else if(accept) begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err <= (sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||
                                !((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0) case(adr[11:0])
                    12'h000: begin response<={24'b0,rx_data}; if(we) begin
                        if(tx_enable&&!tx_busy) begin tx_shift<=dat_w[7:0];tx_busy<=1;tx_bit<=0;tx_count<=0;uart_tx<=0; end
                        else response_err<=1;
                    end else if(sel[0]) begin rx_valid<=0;rx_overrun<=0;end end
                    12'h004: begin response<={24'b0,rx_data}; if(!we&&sel[0]) begin rx_valid<=0;rx_overrun<=0;end else if(we) response_err<=1; end
                    12'h008: begin response<={29'b0,rx_overrun,rx_valid,tx_busy}; if(we) response_err<=1; end
                    12'h00c: begin response<={28'b0,rx_irq_enable,tx_irq_enable,rx_enable,tx_enable}; if(we) begin
                        if(sel[0]) begin tx_enable<=dat_w[0];rx_enable<=dat_w[1];tx_irq_enable<=dat_w[2];rx_irq_enable<=dat_w[3];end
                    end end
                    12'h010: begin response<=divider; if(we) divider<=merge_bytes(divider,dat_w,sel); end
                    default: begin end
                endcase
            end
            if(tx_busy) begin
                if(tx_count+1>=divider) begin
                    tx_count<=0;
                    if(tx_bit==0) begin uart_tx<=tx_shift[0];tx_bit<=1; end
                    else if(tx_bit<8) begin uart_tx<=tx_shift[tx_bit];tx_bit<=tx_bit+1'b1; end
                    else if(tx_bit==8) begin uart_tx<=1;tx_bit<=9; end
                    else begin tx_busy<=0;tx_bit<=0; end
                end else tx_count<=tx_count+1'b1;
            end
            case(rx_state)
                RX_IDLE: if(rx_enable&&!rx_sync) begin rx_state<=RX_START;rx_count<=divider>>1;rx_bit<=0; end
                default: if(rx_count!=0) rx_count<=rx_count-1'b1;
                         else case(rx_state)
                            RX_START: if(!rx_sync) begin rx_state<=RX_DATA;rx_count<=divider-1'b1;rx_bit<=0; end else rx_state<=RX_IDLE;
                            RX_DATA: begin
                                rx_shift<={rx_sync,rx_shift[7:1]};rx_count<=divider-1'b1;
                                if(rx_bit==7) begin rx_state<=RX_STOP;rx_bit<=0;end else rx_bit<=rx_bit+1'b1;
                            end
                            RX_STOP: begin
                                if(rx_sync) begin if(rx_valid) rx_overrun<=1;rx_data<=rx_shift;rx_valid<=1;end
                                rx_state<=RX_IDLE;
                            end
                            default: rx_state<=RX_IDLE;
                         endcase
            endcase
        end
    end
endmodule
