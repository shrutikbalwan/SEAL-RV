// Byte-oriented SPI master, mode 0-3, MSB first, at 0x4000_2000.
// DIVIDER specifies system clocks per SCK half-period (minimum 2).
module wb_spi #(
    parameter logic [31:0] BASE_ADDR=32'h4000_2000
) (
    input logic clk,rst_n,
    input logic cyc,stb,we,
    input logic [31:0] adr,dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack,err,
    output logic spi_sck,spi_cs_n,spi_mosi,
    input logic spi_miso,
    output logic irq_spi
);
    logic enabled,cpol_cfg,cpha_cfg,cpol,cpha,busy,rx_valid;
    logic [31:0] divider,count,response,saved_adr,saved_data;
    logic [3:0] saved_sel;
    logic saved_we,pending,response_err,accept;
    logic [7:0] tx_shift,rx_shift,rx_data;
    logic [3:0] bit_index;
    function automatic [31:0] merge_bytes(input [31:0] old_v,input [31:0] new_v,input [3:0] lanes);
        integer b; begin merge_bytes=old_v;for(b=0;b<4;b=b+1)if(lanes[b])merge_bytes[b*8 +: 8]=new_v[b*8 +: 8];end
    endfunction
    assign accept=cyc&&stb&&(!pending||({we,adr,dat_w,sel}!={saved_we,saved_adr,saved_data,saved_sel}));
    assign dat_r=response;assign ack=pending&&!response_err&&cyc&&stb;assign err=pending&&response_err&&cyc&&stb;
    assign irq_spi=rx_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            enabled<=0;cpol_cfg<=0;cpha_cfg<=0;divider<=2;count<=0;response<=0;saved_adr<=0;saved_data<=0;saved_sel<=0;saved_we<=0;pending<=0;response_err<=0;
            tx_shift<=0;rx_shift<=0;rx_data<=0;bit_index<=0;busy<=0;rx_valid<=0;spi_sck<=0;spi_cs_n<=1;spi_mosi<=0;cpol<=0;cpha<=0;
        end else begin
            if(!accept&&pending)pending<=0;
            else if(accept)begin
                pending<=1;saved_adr<=adr;saved_data<=dat_w;saved_sel<=sel;saved_we<=we;response<=0;
                response_err<=(sel==0)||(adr[1:0]!=0)||(adr[31:12]!=BASE_ADDR[31:12])||!((adr[11:0]==0)||(adr[11:0]==4)||(adr[11:0]==8)||(adr[11:0]==12));
                if(adr[31:12]==BASE_ADDR[31:12]&&adr[1:0]==0&&sel!=0)case(adr[11:0])
                    12'h000:begin response<={24'b0,rx_data};if(we)begin
                        if(!enabled||busy)response_err<=1;
                        else begin tx_shift<=dat_w[7:0];rx_shift<=0;bit_index<=0;busy<=1;rx_valid<=0;count<=0;cpol<=cpol_cfg;cpha<=cpha_cfg;spi_sck<=cpol_cfg;spi_cs_n<=0;spi_mosi<=cpha_cfg?1'b0:dat_w[7];end
                    end else if(sel[0])rx_valid<=0;end
                    12'h004:begin response<={29'b0,cpha_cfg,cpol_cfg,enabled};if(we&&sel[0]&&!busy)begin enabled<=dat_w[0];cpol_cfg<=dat_w[1];cpha_cfg<=dat_w[2];end else if(we&&busy)response_err<=1;end
                    12'h008:begin response<=divider;if(we&&!busy)begin if(merge_bytes(divider,dat_w,sel)<2)divider<=2;else divider<=merge_bytes(divider,dat_w,sel);end else if(we&&busy)response_err<=1;end
                    12'h00c:begin response<={30'b0,rx_valid,busy};if(we)response_err<=1;end
                    default:begin end
                endcase
            end
            if(busy)begin
                if(count+1>=divider)begin
                    count<=0;
                    if(spi_sck==cpol)begin
                        spi_sck<=~cpol;
                        if(cpha)spi_mosi<=tx_shift[7];
                        else rx_shift<={rx_shift[6:0],spi_miso};
                    end else begin
                        spi_sck<=cpol;
                        if(cpha)rx_shift<={rx_shift[6:0],spi_miso};
                        if(bit_index==7)begin
                            busy<=0;spi_cs_n<=1;spi_mosi<=0;
                            rx_data<=cpha?{rx_shift[6:0],spi_miso}:rx_shift;rx_valid<=1;
                        end else begin
                            bit_index<=bit_index+1'b1;tx_shift<={tx_shift[6:0],1'b0};
                            if(!cpha)spi_mosi<=tx_shift[6];
                        end
                    end
                end else count<=count+1'b1;
            end
        end
    end
endmodule
