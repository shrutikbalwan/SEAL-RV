// Wishbone target for Phase 06 peripherals. Connect irq_timer/irq_external
// directly to the matching cpu_core inputs. Watchdog reset_request is active
// high and should be combined with the SoC reset controller.
module peripheral_subsystem #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer GPIO_WIDTH=32
) (
    input logic clk, rst_n,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    output logic uart_tx,
    input logic uart_rx,
    input logic [GPIO_WIDTH-1:0] gpio_in,
    output logic [GPIO_WIDTH-1:0] gpio_out, gpio_oe,
    output logic spi_sck,spi_cs_n,spi_mosi,
    input logic spi_miso,
    input logic i2c_scl_i,i2c_sda_i,
    output logic i2c_scl_o,i2c_scl_oe,i2c_sda_o,i2c_sda_oe,
    input logic [31:0] cpu_pc,
    input logic cpu_retire,
    output logic irq_timer, irq_external, reset_request,
    output logic sleep_request,
    output logic [4:0] clock_enable_req,
    output logic [5:0] wake_status
);
    logic uart_sel,gpio_sel,spi_sel,i2c_sel,timer_sel,irqc_sel,wd_sel,debug_sel,power_sel,known_sel;
    logic [31:0] uart_r,gpio_r,spi_r,i2c_r,timer_r,irqc_r,wd_r,debug_r,power_r;
    logic uart_ack,uart_err,gpio_ack,gpio_err,spi_ack,spi_err,i2c_ack,i2c_err,timer_ack,timer_err,irqc_ack,irqc_err,wd_ack,wd_err,debug_ack,debug_err,power_ack,power_err;
    logic irq_uart,irq_gpio,irq_watchdog,irq_timer_raw,irq_spi,irq_i2c,soft_reset_request,wd_reset_request,bus_event;
    logic bus_seen,bus_saved_we;
    logic [31:0] bus_saved_adr,bus_saved_data;
    logic [3:0] bus_saved_sel;
    logic unmapped_pending;
    assign uart_sel=(adr[31:12]==20'h40000);
    assign gpio_sel=(adr[31:12]==20'h40001);
    assign spi_sel=(adr[31:12]==20'h40002);
    assign i2c_sel=(adr[31:12]==20'h40003);
    assign timer_sel=(adr[31:12]==20'h40004);
    assign irqc_sel=(adr[31:12]==20'h40005);
    assign wd_sel=(adr[31:12]==20'h4000d);
    assign debug_sel=(adr[31:12]==20'h4000a);
    assign power_sel=(adr[31:12]==20'h4000b);
    assign known_sel=uart_sel|gpio_sel|spi_sel|i2c_sel|timer_sel|irqc_sel|wd_sel|debug_sel|power_sel;
    wb_uart #(.CLK_HZ(CLK_HZ)) uart(.clk,.rst_n,.cyc(cyc&&uart_sel),.stb(stb&&uart_sel),.we,.adr,.dat_w,.sel,
      .dat_r(uart_r),.ack(uart_ack),.err(uart_err),.uart_tx,.uart_rx,.irq_uart);
    wb_gpio #(.WIDTH(GPIO_WIDTH)) gpio(.clk,.rst_n,.cyc(cyc&&gpio_sel),.stb(stb&&gpio_sel),.we,.adr,.dat_w,.sel,
      .dat_r(gpio_r),.ack(gpio_ack),.err(gpio_err),.gpio_in,.gpio_out,.gpio_oe,.irq_gpio);
    wb_spi spi(.clk,.rst_n,.cyc(cyc&&spi_sel),.stb(stb&&spi_sel),.we,.adr,.dat_w,.sel,.dat_r(spi_r),.ack(spi_ack),.err(spi_err),
      .spi_sck,.spi_cs_n,.spi_mosi,.spi_miso,.irq_spi);
    wb_i2c i2c(.clk,.rst_n,.cyc(cyc&&i2c_sel),.stb(stb&&i2c_sel),.we,.adr,.dat_w,.sel,.dat_r(i2c_r),.ack(i2c_ack),.err(i2c_err),
      .scl_i(i2c_scl_i),.sda_i(i2c_sda_i),.scl_o(i2c_scl_o),.scl_oe(i2c_scl_oe),.sda_o(i2c_sda_o),.sda_oe(i2c_sda_oe),.irq_i2c);
    wb_timer timer(.clk,.rst_n,.cyc(cyc&&timer_sel),.stb(stb&&timer_sel),.we,.adr,.dat_w,.sel,
      .dat_r(timer_r),.ack(timer_ack),.err(timer_err),.irq_timer(irq_timer_raw));
    wb_watchdog watchdog(.clk,.rst_n,.cyc(cyc&&wd_sel),.stb(stb&&wd_sel),.we,.adr,.dat_w,.sel,
      .dat_r(wd_r),.ack(wd_ack),.err(wd_err),.irq_watchdog,.reset_request(wd_reset_request));
    interrupt_controller intc(.clk,.rst_n,.cyc(cyc&&irqc_sel),.stb(stb&&irqc_sel),.we,.adr,.dat_w,.sel,
      .dat_r(irqc_r),.ack(irqc_ack),.err(irqc_err),.irq_timer_in(irq_timer_raw),.irq_uart_in(irq_uart),
      .irq_gpio_in(irq_gpio),.irq_watchdog_in(irq_watchdog),.irq_timer,.irq_external);
    wb_debug_perf debug_regs(.clk,.rst_n,.cyc(cyc&&debug_sel),.stb(stb&&debug_sel),.we,.adr,.dat_w,.sel,
      .dat_r(debug_r),.ack(debug_ack),.err(debug_err),.cpu_retire,.cpu_pc,.bus_event,.irq_event(irq_timer|irq_external));
    wb_power_ctrl power(.clk,.rst_n,.cyc(cyc&&power_sel),.stb(stb&&power_sel),.we,.adr,.dat_w,.sel,
      .dat_r(power_r),.ack(power_ack),.err(power_err),.wake_sources({wd_reset_request,irq_gpio,irq_uart,irq_external,irq_timer_raw}),
      .sleep_request,.clock_enable_req,.wake_status,.reset_request(soft_reset_request));
    assign reset_request=wd_reset_request|soft_reset_request;
    assign bus_event=cyc&&stb&&(!bus_seen||({we,adr,dat_w,sel}!={bus_saved_we,bus_saved_adr,bus_saved_data,bus_saved_sel}));
    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n)begin bus_seen<=0;bus_saved_we<=0;bus_saved_adr<=0;bus_saved_data<=0;bus_saved_sel<=0;end
        else if(!cyc||!stb)bus_seen<=0;
        else if(bus_event)begin bus_seen<=1;bus_saved_we<=we;bus_saved_adr<=adr;bus_saved_data<=dat_w;bus_saved_sel<=sel;end
    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) unmapped_pending<=0;
        else unmapped_pending<=cyc&&stb&&!known_sel;
    always_comb begin
        dat_r=0;ack=0;err=0;
        if(uart_sel) begin dat_r=uart_r;ack=uart_ack;err=uart_err;end
        else if(gpio_sel) begin dat_r=gpio_r;ack=gpio_ack;err=gpio_err;end
        else if(spi_sel) begin dat_r=spi_r;ack=spi_ack;err=spi_err;end
        else if(i2c_sel) begin dat_r=i2c_r;ack=i2c_ack;err=i2c_err;end
        else if(timer_sel) begin dat_r=timer_r;ack=timer_ack;err=timer_err;end
        else if(irqc_sel) begin dat_r=irqc_r;ack=irqc_ack;err=irqc_err;end
        else if(wd_sel) begin dat_r=wd_r;ack=wd_ack;err=wd_err;end
        else if(debug_sel) begin dat_r=debug_r;ack=debug_ack;err=debug_err;end
        else if(power_sel) begin dat_r=power_r;ack=power_ack;err=power_err;end
        else err=unmapped_pending&&cyc&&stb;
    end
endmodule
