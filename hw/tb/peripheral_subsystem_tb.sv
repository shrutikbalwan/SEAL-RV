`timescale 1ns/1ps
module peripheral_subsystem_tb;
    logic clk=0,rst_n=0;
    always #5 clk=~clk;
    logic cyc,stb,we;
    logic [31:0] adr,dat_w,dat_r;
    logic [3:0] sel;
    logic ack,err,uart_tx;
    logic [31:0] gpio_in;
    wire [31:0] gpio_out,gpio_oe;
    wire irq_timer,irq_external,reset_request;
    wire uart_rx=uart_tx;
    logic spi_miso=1;
    wire spi_sck,spi_cs_n,spi_mosi;
    wire i2c_scl_oe,i2c_sda_oe,i2c_scl_o,i2c_sda_o;
    wire i2c_scl_i=!i2c_scl_oe;
    wire i2c_sda_i=!i2c_sda_oe;
    logic [31:0] cpu_pc=0;
    logic cpu_retire=0;
    logic i2c_ack_seen=0,i2c_nack_seen=0;
    wire sleep_request;
    wire [4:0] clock_enable_req;
    wire [5:0] wake_status;
    always @(posedge clk) if(dut.i2c.state==4'd7&&dut.i2c.i2c_read) begin
        if(dut.i2c.read_nack) begin if(i2c_sda_oe!==0)$fatal(1,"I2C NACK must release SDA");i2c_nack_seen<=1;end
        else begin if(i2c_sda_oe!==1)$fatal(1,"I2C ACK must pull SDA low");i2c_ack_seen<=1;end
    end
    peripheral_subsystem #(.CLK_HZ(921600)) dut(.clk,.rst_n,.cyc,.stb,.we,.adr,.dat_w,.sel,.dat_r,.ack,.err,
      .uart_tx,.uart_rx,.gpio_in,.gpio_out,.gpio_oe,.spi_sck,.spi_cs_n,.spi_mosi,.spi_miso,.i2c_scl_i,.i2c_sda_i,
      .i2c_scl_o,.i2c_scl_oe,.i2c_sda_o,.i2c_sda_oe,.cpu_pc,.cpu_retire,.irq_timer,.irq_external,.reset_request,
      .sleep_request,.clock_enable_req,.wake_status);

    task automatic access(input logic write_en,input logic [31:0] address,input logic [31:0] value,
                          input logic [3:0] lanes,input logic expect_error,input logic [31:0] expected);
        integer n;
        begin
            @(negedge clk);cyc=1;stb=1;we=write_en;adr=address;dat_w=value;sel=lanes;n=0;
            while(!ack&&!err&&n<5) begin @(posedge clk);#1;n=n+1;end
            if(n==5)$fatal(1,"timeout at %h",address);
            if(err!==expect_error)$fatal(1,"error mismatch at %h err=%b expected=%b",address,err,expect_error);
            if(!write_en&&!expect_error&&expected!=32'hdead_beef&&dat_r!==expected)
                $fatal(1,"read %h=%h expected %h",address,dat_r,expected);
            @(negedge clk);cyc=0;stb=0;we=0;
        end
    endtask
    task automatic wait_clocks(input integer n);
        integer i; begin for(i=0;i<n;i=i+1) @(posedge clk); #1; end
    endtask

    integer b;
    logic [31:0] saved_mtime;
    initial begin
        cyc=0;stb=0;we=0;adr=0;dat_w=0;sel=0;gpio_in=0;
        repeat(3) @(negedge clk);rst_n=1;

        // UART registers, reset baud default, 8-N-1 TX waveform and loopback RX.
        access(0,32'h4000_0010,0,4'hf,0,8);
        access(0,32'h4000_0008,0,4'hf,0,0);
        access(0,32'h4000_000c,0,4'hf,0,3);
        access(1,32'h4000_000c,32'hb,4'h1,0,0); // TX, RX and RX interrupt enable
        access(1,32'h4000_0000,32'ha5,4'h1,0,0);
        if(uart_tx!==0)$fatal(1,"UART start bit not asserted");
        repeat(4) @(posedge clk); #1;
        if(uart_tx!==0)$fatal(1,"UART start bit width/level incorrect");
        for(b=0;b<8;b=b+1) begin
            repeat(8) @(posedge clk); #1;
            if(uart_tx!==((8'ha5>>b)&1'b1))$fatal(1,"UART TX data bit %0d incorrect",b);
        end
        repeat(8) @(posedge clk); #1;
        if(uart_tx!==1)$fatal(1,"UART stop bit missing");
        wait_clocks(20);
        access(0,32'h4000_0008,0,4'hf,0,32'h2); // RX valid
        access(0,32'h4000_0004,0,4'hf,0,32'ha5); // receive data clears valid
        access(1,32'h4000_0008,0,4'hf,1,0); // STATUS is read-only

        // GPIO direction/output, synchronized input, rising-edge interrupt.
        access(1,32'h4000_1004,32'h1,4'hf,0,0);
        access(1,32'h4000_1000,32'h1,4'hf,0,0);
        if(gpio_out!==1||gpio_oe!==1)$fatal(1,"GPIO output/direction failed");
        access(1,32'h4000_100c,32'h2,4'hf,0,0); // edge mode on pin 1
        access(1,32'h4000_1010,32'hffff_ffff,4'hf,0,0); // high level / rising edge polarity
        access(1,32'h4000_1008,32'h2,4'hf,0,0); // enable IRQ pin 1
        access(0,32'h4000_1004,0,4'hf,0,1);
        access(0,32'h4000_1008,0,4'hf,0,2);
        access(0,32'h4000_100c,0,4'hf,0,2);
        access(0,32'h4000_1010,0,4'hf,0,32'hffff_ffff);
        gpio_in[1]=1;
        wait_clocks(6);
        access(0,32'h4000_1000,0,4'hf,0,32'h2);
        access(0,32'h4000_1014,0,4'hf,0,32'h2);

        // SPI master modes 0-3, byte transfer, chip select and RX path.
        access(1,32'h4000_2008,2,4'hf,0,0);
        access(0,32'h4000_2008,0,4'hf,0,2);
        for(b=0;b<4;b=b+1)begin
            access(1,32'h4000_2004,32'h1|(((b>>1)&1)<<1)|((b&1)<<2),4'hf,0,0);
            access(1,32'h4000_2000,32'ha5,4'h1,0,0);
            wait_clocks(40);
            if(spi_cs_n!==1||spi_sck!==((b>>1)&1'b1))$fatal(1,"SPI mode %0d did not return to idle",b);
            access(0,32'h4000_200c,0,4'hf,0,32'h2);
            access(0,32'h4000_2000,0,4'hf,0,32'hff);
        end

        // I2C open-drain START, byte write/NACK, byte read/NACK, and STOP.
        access(1,32'h4000_3008,1,4'h1,0,0);
        access(1,32'h4000_300c,2,4'hf,0,0);
        access(0,32'h4000_3008,0,4'hf,0,1);
        access(0,32'h4000_300c,0,4'hf,0,2);
        access(1,32'h4000_3004,1,4'h1,0,0);
        wait_clocks(5);
        if(i2c_sda_oe!==1||i2c_scl_oe!==1)$fatal(1,"I2C START waveform invalid");
        access(1,32'h4000_3000,8'ha0,4'h1,0,0);
        access(1,32'h4000_3004,4,4'h1,0,0);
        wait_clocks(45);
        access(0,32'h4000_3010,0,4'hf,0,32'h6); // done + NACK (no target on bus)
        access(1,32'h4000_3004,8'h08,4'h1,0,0); // read byte and ACK
        wait_clocks(45);
        access(0,32'h4000_3000,0,4'h1,0,32'hff);
        if(!i2c_ack_seen)$fatal(1,"I2C read ACK waveform not observed");
        access(1,32'h4000_3004,8'h18,4'h1,0,0); // read byte and NACK
        wait_clocks(45);
        access(0,32'h4000_3000,0,4'h1,0,32'hff);
        if(!i2c_nack_seen)$fatal(1,"I2C read NACK waveform not observed");
        access(1,32'h4000_3004,2,4'h1,0,0);
        wait_clocks(5);
        if(i2c_scl_oe!==0||i2c_sda_oe!==0)$fatal(1,"I2C STOP did not release open-drain lines");

        // Debug/performance counters and sampled retirement PC.
        cpu_pc=32'h1234_5678;cpu_retire=1;wait_clocks(1);cpu_retire=0;
        access(0,32'h4000_a000,0,4'hf,0,1);
        access(0,32'h4000_a00c,0,4'hf,0,32'h1);
        access(0,32'h4000_a010,0,4'hf,0,0);
        access(0,32'h4000_a01c,0,4'hf,0,32'h1234_5678);
        access(0,32'h4000_a014,0,4'hf,0,32'hdead_beef);
        if(dat_r==0)$fatal(1,"debug bus counter did not increment: read=%0d internal=%0d event=%b",dat_r,dut.debug_regs.bus_count,dut.bus_event);
        access(0,32'h4000_a018,0,4'hf,0,32'hdead_beef);
        access(0,32'h4000_a004,0,4'hf,0,32'hdead_beef);
        if(dat_r==0)$fatal(1,"debug cycle counter did not increment");
        access(0,32'h4000_a008,0,4'hf,0,0);
        access(1,32'h4000_a01c,0,4'hf,1,0); // sampled PC is read-only

        // Clock requests and interrupt-driven sleep/wake behavior.
        access(0,32'h4000_b004,0,4'hf,0,32'h1f);
        access(1,32'h4000_b004,32'h15,4'hf,0,0);
        access(0,32'h4000_b004,0,4'hf,0,32'h15);
        access(1,32'h4000_b008,32'h21,4'hf,0,0); // timer and software wake
        access(0,32'h4000_b008,0,4'hf,0,32'h21);
        access(1,32'h4000_b000,1,4'h1,0,0);
        if(!sleep_request)$fatal(1,"sleep request was not set");

        // Interrupt map, threshold masking, default priorities, claim/complete.
        access(1,32'h4000_5004,32'hf,4'hf,0,0);
        access(1,32'h4000_5000,1,4'hf,1,0); // PENDING is read-only
        access(0,32'h4000_5000,0,4'hf,0,32'h6); // UART/GPIO pending sources
        access(1,32'h4000_5008,3,4'hf,0,0);
        #1;if(irq_external)$fatal(1,"threshold must mask priority 3");
        access(1,32'h4000_5008,2,4'hf,0,0);
        #1;if(!irq_external)$fatal(1,"enabled pending external IRQ not asserted");
        access(0,32'h4000_5010,0,4'hf,0,3);
        access(0,32'h4000_5014,0,4'hf,0,2);
        access(0,32'h4000_5018,0,4'hf,0,1);
        access(0,32'h4000_500c,0,4'hf,0,1); // UART has highest priority
        access(1,32'h4000_500c,1,4'h1,0,0);
        access(1,32'h4000_1014,2,4'hf,0,0);
        access(0,32'h4000_5000,0,4'hf,0,32'h4); // GPIO stays latched until completion
        access(1,32'h4000_500c,2,4'h1,0,0);
        access(0,32'h4000_5000,0,4'hf,0,0);

        // Timer mtime/mtimecmp and machine timer interrupt routing.
        access(0,32'h4000_4000,0,4'hf,0,32'hdead_beef);
        access(0,32'h4000_4000,0,4'hf,0,32'hdead_beef);
        saved_mtime=dat_r;
        access(1,32'h4000_400c,0,4'hf,0,0);
        access(1,32'h4000_4008,saved_mtime+30,4'hf,0,0);
        access(1,32'h4000_4010,1,4'h1,0,0);
        access(1,32'h4000_5004,32'hf,4'hf,0,0);
        access(1,32'h4000_5008,0,4'hf,0,0);
        wait_clocks(40);
        if(!irq_timer)$fatal(1,"mtimecmp did not assert machine timer IRQ");
        if(sleep_request||!wake_status[0])$fatal(1,"timer did not wake sleep request");
        access(1,32'h4000_4010,0,4'h1,0,0); // remove level source before clearing latched wake
        access(1,32'h4000_b00c,1,4'h1,0,0);
        access(0,32'h4000_b00c,0,4'hf,0,0);
        access(1,32'h4000_b000,1,4'h1,0,0);
        access(1,32'h4000_b014,1,4'h1,0,0);
        if(sleep_request||!wake_status[5])$fatal(1,"software wake event not latched");
        access(1,32'h4000_b00c,32'h20,4'h1,0,0);
        access(0,32'h4000_4000,0,4'hf,0,32'hdead_beef);
        if(dat_r==0)$fatal(1,"mtime did not increment");
        access(0,32'h4000_4004,0,4'hf,0,32'hdead_beef);

        // Software reset request, consumed by the system reset controller.
        access(1,32'h4000_b010,32'h52535401,4'hf,0,0);
        if(!reset_request)$fatal(1,"software reset request not asserted");
        @(negedge clk);rst_n=0;repeat(3)@(negedge clk);
        if(reset_request||clock_enable_req!==5'h1f)$fatal(1,"power/reset state failed reset");
        rst_n=1;

        // Watchdog programming, authenticated service and expiry/reset request.
        access(1,32'h4000_5004,8,4'hf,0,0); // enable watchdog's external interrupt source
        access(1,32'h4000_d004,50,4'hf,0,0);
        access(0,32'h4000_d004,0,4'hf,0,50);
        access(1,32'h4000_d008,1,4'hf,1,0); // COUNT is read-only
        access(0,32'h4000_d00c,0,4'hf,1,0); // SERVICE is write-only
        access(1,32'h4000_d000,1,4'h1,0,0);
        wait_clocks(20);
        access(1,32'h4000_d00c,32'h51f15eed,4'hf,0,0);
        wait_clocks(30);
        if(reset_request)$fatal(1,"valid watchdog service did not reload timeout");
        wait_clocks(30);
        if(!reset_request||!irq_external)$fatal(1,"watchdog expiry did not request reset/interrupt");
        access(0,32'h4000_d008,0,4'hf,0,0);

        // Bad/unmapped accesses and invalid selects terminate with ERR.
        access(0,32'h4000_0020,0,4'hf,1,0);
        access(0,32'h4000_0000,0,0,1,0);
        access(0,32'h4000_2020,0,4'hf,1,0);
        access(0,32'h4000_3020,0,4'hf,1,0);
        access(0,32'h4000_a020,0,4'hf,1,0);
        access(0,32'h4000_b018,0,4'hf,1,0);
        access(0,32'h5000_0000,0,4'hf,1,0);
        $display("peripheral_subsystem_tb PASS");$finish;
    end
endmodule
