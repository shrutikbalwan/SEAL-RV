`timescale 1ns/1ps
module wb_cpu_adapter_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic cpu_valid, cpu_write;
    logic [31:0] cpu_addr, cpu_wdata;
    logic [3:0] cpu_wstrb;
    wire cpu_ready, cpu_error;
    wire [31:0] cpu_rdata;
    wire wb_cyc, wb_stb, wb_we;
    wire [31:0] wb_adr, wb_dat_w;
    wire [3:0] wb_sel;
    logic [31:0] wb_dat_r;
    logic wb_ack, wb_err;

    wb_cpu_adapter dut (.*);

    initial begin
        cpu_valid=0; cpu_write=0; cpu_addr=0; cpu_wdata=0; cpu_wstrb=0;
        wb_dat_r=0; wb_ack=0; wb_err=0;
        repeat(2) @(posedge clk); rst_n=1;

        @(negedge clk); cpu_valid=1; cpu_addr=32'h1000_0003; cpu_wdata=32'h1234_5678; cpu_wstrb=0;
        @(posedge clk); #1;
        if (!wb_cyc || !wb_stb || wb_we || wb_adr!=32'h1000_0000 || wb_sel!=4'hf)
            $fatal(1,"CPU read request was not correctly adapted");
        repeat(2) begin
            @(posedge clk); #1;
            if (cpu_ready || !wb_cyc || wb_adr!=32'h1000_0000) $fatal(1,"read was not held under backpressure");
        end
        wb_dat_r=32'hCAFE_BABE; wb_ack=1; #1;
        if (!cpu_ready || cpu_error || cpu_rdata!=32'hCAFE_BABE) $fatal(1,"ACK response mapping failed");
        @(posedge clk); #1; wb_ack=0; cpu_valid=0;
        if (wb_cyc) $fatal(1,"adapter did not retire ACKed transfer");

        @(negedge clk); cpu_valid=1; cpu_write=1; cpu_addr=32'h1000_0007;
        cpu_wdata=32'hAABB_CCDD; cpu_wstrb=4'b1000;
        @(posedge clk); #1;
        if (!wb_cyc || !wb_we || wb_adr!=32'h1000_0004 || wb_sel!=4'b1000 || wb_dat_w!=32'hAABB_CCDD)
            $fatal(1,"CPU write request was not correctly adapted");
        wb_err=1; #1;
        if (!cpu_ready || !cpu_error) $fatal(1,"ERR response mapping failed");
        @(posedge clk); #1; wb_err=0; cpu_valid=0;
        if (wb_cyc) $fatal(1,"adapter did not retire ERR response");

        @(negedge clk); cpu_valid=1; cpu_write=0; cpu_addr=32'h0000_0020;
        @(posedge clk); #1;
        if (!wb_cyc) $fatal(1,"third transfer did not start");
        @(negedge clk); rst_n=0; #1;
        if (wb_cyc || wb_stb) $fatal(1,"reset did not abort adapter transfer");
        $display("Wishbone CPU adapter tests passed");
        $finish;
    end
endmodule
