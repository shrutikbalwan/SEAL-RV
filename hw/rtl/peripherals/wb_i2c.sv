// Single-controller, byte-oriented I2C master at 0x4000_3000.
// SDA/SCL are open-drain: *_oe=1 actively pulls the line low; *_oe=0 releases it.
module wb_i2c #(
    parameter logic [31:0] BASE_ADDR=32'h4000_3000
) (
    input logic clk,rst_n,
    input logic cyc,stb,we,
    input logic [31:0] adr,dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack,err,
    input logic scl_i,sda_i,
    output logic scl_o,scl_oe,sda_o,sda_oe,
    output logic irq_i2c
);
    localparam logic [3:0] IDLE=0,START=1,STOP_LOW=2,STOP_HIGH=3,BIT_SETUP=4,BIT_HIGH=5,ACK_SETUP=6,ACK_HIGH=7;
    logic enabled,busy,done,nack,rx_valid,read_nack,i2c_read;
    logic [31:0] divider,count,response,saved_adr,saved_data;
    logic [3:0] saved_sel;
    logic saved_we,pending,response_err,accept;
    logic [3:0] state;
    logic [7:0] tx_data,rx_shift,rx_data;
    logic [2:0] bit_index;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b;begin merge_bytes=old_v;for(b=0;b<4;b=b+1)if(lanes[b])merge_bytes[b*8 +: 8]=new_v[b*8 +: 8];end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;assign ack=pending&&!response_err&&cyc&&stb;assign err=pending&&response_err&&cyc&&stb;
    assign scl_o=1'b0;assign sda_o=1'b0;assign irq_i2c=done|nack|rx_valid;
    always_ff @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin enabled<=0;busy<=0;done<=0;nack<=0;rx_valid<=0;read_nack<=0;i2c_read<=0;divider<=4;count<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;pending<=0;response_err<=0;state<=IDLE;tx_data<=0;rx_shift<=0;rx_data<=0;bit_index<=0;scl_oe<=0;sda_oe<=0;end
        else begin
            if(!accept&&pending)pending<=0;
            else if(accept)begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err<=(sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||!((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12)||(adr[11:0]==16));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0)case(adr[11:0])
                    12'h000:begin response<={24'b0,rx_data};if(we&&sel[0])tx_data<=dat_w[7:0];else if(!we&&sel[0])rx_valid<=0;end
                    12'h004:begin response<=0;if(!we)response_err<=1;else if(busy||!enabled)response_err<=1;else begin
                        done<=0;nack<=0;count<=0;busy<=1;
                        case(dat_w[3:0])
                            4'b0001:begin state<=START;scl_oe<=0;sda_oe<=1;end // START
                            4'b0010:begin state<=STOP_LOW;scl_oe<=1;sda_oe<=1;end // STOP
                            4'b0100:begin state<=BIT_SETUP;i2c_read<=0;bit_index<=7;rx_shift<=0;sda_oe<=~tx_data[7];scl_oe<=1;end // WRITE byte
                            4'b1000:begin state<=BIT_SETUP;i2c_read<=1;bit_index<=7;rx_shift<=0;read_nack<=dat_w[4];sda_oe<=0;scl_oe<=1;end // READ; bit 4: NACK response
                            default:begin busy<=0;state<=IDLE;response_err<=1;end
                        endcase
                    end end
                    12'h008:begin response<={31'b0,enabled};if(we&&!busy&&sel[0])enabled<=dat_w[0];else if(we&&busy)response_err<=1;end
                    12'h00c:begin response<=divider;if(we&&!busy)begin if(merge_bytes(divider,dat_w,sel)<2)divider<=2;else divider<=merge_bytes(divider,dat_w,sel);end else if(we&&busy)response_err<=1;end
                    12'h010:begin response<={28'b0,rx_valid,nack,done,busy};if(we)response_err<=1;else begin done<=0;nack<=0;end end
                    default:begin end
                endcase
            end
            if(busy)begin
                if(state==START)begin
                    if(count+1>=divider)begin count<=0;scl_oe<=1;state<=IDLE;busy<=0;done<=1;end else count<=count+1'b1;
                end else if(state==STOP_LOW)begin
                    if(count+1>=divider)begin count<=0;scl_oe<=0;state<=STOP_HIGH;end else count<=count+1'b1;
                end else if(state==STOP_HIGH)begin
                    if(scl_i)begin if(count+1>=divider)begin count<=0;sda_oe<=0;state<=IDLE;busy<=0;done<=1;end else count<=count+1'b1;end
                end else if(state==BIT_SETUP)begin
                    if(count+1>=divider)begin count<=0;scl_oe<=0;state<=BIT_HIGH;end else count<=count+1'b1;
                end else if(state==BIT_HIGH)begin
                    if(scl_i)begin
                        if(count+1>=divider)begin
                            count<=0;scl_oe<=1;
                            if(!i2c_read)begin
                                if(bit_index==0)begin sda_oe<=0;state<=ACK_SETUP;end
                                else begin bit_index<=bit_index-1'b1;sda_oe<=~(tx_data[bit_index-1'b1]);state<=BIT_SETUP;end
                            end else begin
                                rx_shift[bit_index]<=sda_i;
                                if(bit_index==0)begin sda_oe<=~read_nack;state<=ACK_SETUP;end
                                else begin bit_index<=bit_index-1'b1;state<=BIT_SETUP;end
                            end
                        end else count<=count+1'b1;
                    end
                end else if(state==ACK_SETUP)begin
                    if(count+1>=divider)begin count<=0;scl_oe<=0;state<=ACK_HIGH;end else count<=count+1'b1;
                end else if(state==ACK_HIGH)begin
                    if(scl_i)begin if(count+1>=divider)begin
                        count<=0;scl_oe<=1;sda_oe<=0;
                        if(!i2c_read)nack<=sda_i;
                        else begin rx_data<=rx_shift;rx_valid<=1;end
                        state<=IDLE;busy<=0;done<=1;
                    end else count<=count+1'b1;end
                end
            end
        end
    end
endmodule
