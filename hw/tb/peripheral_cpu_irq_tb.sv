`timescale 1ns/1ps
module peripheral_cpu_irq_tb;
    logic clk=0,rst_n=0;
    always #5 clk=~clk;
    logic [31:0] pc,instr;
    logic dvalid,dwrite,dready,derror,trap_valid,retire;
    logic [31:0] daddr,dwdata,drdata,trap_pc,trap_cause,trap_value;
    logic [3:0] dwstrb;
    logic wb_cyc,wb_stb,wb_we,wb_ack,wb_err;
    logic [31:0] wb_adr,wb_wdata,wb_rdata;
    logic [3:0] wb_sel;
    logic p_ack,p_err,m_ack,m_err;
    logic [31:0] p_rdata,m_rdata;
    logic uart_tx;
    logic irq_timer,irq_external,wd_reset;
    logic [31:0] gpio_in=0,gpio_out,gpio_oe;
    wire psel=wb_adr[31:16]==16'h4000;
    logic timer_trap_seen=0;
    logic [7:0] received_text [0:1];
    integer received_count=0;
    cpu_core cpu(.clk,.rst_n,.pc,.instr,.irq_external,.irq_timer,.dmem_valid(dvalid),.dmem_write(dwrite),
      .dmem_addr(daddr),.dmem_wdata(dwdata),.dmem_wstrb(dwstrb),.dmem_ready(dready),.dmem_rdata(drdata),.dmem_error(derror),
      .trap_valid,.trap_pc,.trap_cause,.trap_value,.retire);
    wb_cpu_adapter adapter(.clk,.rst_n,.cpu_valid(dvalid),.cpu_write(dwrite),.cpu_addr(daddr),.cpu_wdata(dwdata),.cpu_wstrb(dwstrb),
      .cpu_ready(dready),.cpu_rdata(drdata),.cpu_error(derror),.wb_cyc,.wb_stb,.wb_we,.wb_adr,.wb_dat_w(wb_wdata),.wb_sel,
      .wb_dat_r(wb_rdata),.wb_ack,.wb_err);
    memory_subsystem #(.ROM_INIT_FILE("hw/tb/peripheral_irq_boot.hex")) mem(.clk,.rst_n,.fetch_addr(pc),.fetch_data(instr),
      .cyc(wb_cyc&&!psel),.stb(wb_stb&&!psel),.we(wb_we),.adr(wb_adr),.dat_w(wb_wdata),.sel(wb_sel),
      .dat_r(m_rdata),.ack(m_ack),.err(m_err));
    peripheral_subsystem #(.CLK_HZ(921600)) periph(.clk,.rst_n,.cyc(wb_cyc&&psel),.stb(wb_stb&&psel),.we(wb_we),
      .adr(wb_adr),.dat_w(wb_wdata),.sel(wb_sel),.dat_r(p_rdata),.ack(p_ack),.err(p_err),.uart_tx,.uart_rx(uart_tx),
      .gpio_in,.gpio_out,.gpio_oe,.spi_sck(),.spi_cs_n(),.spi_mosi(),.spi_miso(1'b1),.i2c_scl_i(1'b1),.i2c_sda_i(1'b1),
      .i2c_scl_o(),.i2c_scl_oe(),.i2c_sda_o(),.i2c_sda_oe(),.cpu_pc(pc),.cpu_retire(retire),
      .irq_timer,.irq_external,.reset_request(wd_reset),.sleep_request(),.clock_enable_req(),.wake_status());
    assign wb_ack=psel?p_ack:m_ack;
    assign wb_err=psel?p_err:m_err;
    assign wb_rdata=psel?p_rdata:m_rdata;
    always @(posedge clk) if(trap_valid&&trap_cause==32'h8000_0007) timer_trap_seen<=1;
    always @(posedge clk) if(rst_n&&periph.uart.rx_state==2'd3&&periph.uart.rx_count==0&&periph.uart.rx_sync) begin
        if(received_count<2) received_text[received_count]<=periph.uart.rx_shift;
        received_count<=received_count+1;
    end
    integer cycles;
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        cycles=0;
        while(cpu.rf.regs[8]!==32'd1 && cycles<1000) begin @(posedge clk);#1;cycles=cycles+1; end
        if(cpu.rf.regs[8]!==32'd1)$fatal(1,"CPU did not service timer interrupt; pc=%h mie=%h mstatus=%h",pc,cpu.mie,cpu.mstatus);
        if(!timer_trap_seen)$fatal(1,"machine timer trap notification was not observed");
        if(received_count<2||received_text[0]!==8'h48||received_text[1]!==8'h69)
            $fatal(1,"bare-metal UART text mismatch, received count=%0d bytes=%h %h",received_count,received_text[0],received_text[1]);
        if(gpio_oe!==32'h1||gpio_out!==32'h1)$fatal(1,"bare-metal GPIO configuration failed");
        while(!wd_reset && cycles<1200) begin @(posedge clk);#1;cycles=cycles+1; end
        if(!wd_reset)$fatal(1,"bare-metal watchdog did not request recovery");
        // Model the SoC reset controller consuming the sticky watchdog request.
        @(negedge clk);rst_n=0;
        repeat(3) @(negedge clk);
        if(wd_reset)$fatal(1,"watchdog request did not clear under system reset");
        if(gpio_oe!==0||gpio_out!==0)$fatal(1,"peripheral reset did not restore GPIO reset state");
        rst_n=1;#1;
        if(pc!==0)$fatal(1,"CPU did not restart from reset vector after watchdog recovery");
        $display("peripheral_cpu_irq_tb PASS (%0d cycles, timer trap, UART, GPIO, watchdog recovery)",cycles);$finish;
    end
endmodule
