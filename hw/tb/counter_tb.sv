`timescale 1ns/1ps
module counter_tb;
    parameter int WIDTH = 8;
    logic clk, rst_n, en;
    logic [WIDTH-1:0] count;
    counter #(WIDTH) uut (.clk(clk), .rst_n(rst_n), .en(en), .count(count));
    initial clk = 0;
    always #5 clk = ~clk;
    initial begin
        $dumpfile("counter.vcd"); $dumpvars(0, counter_tb);
        rst_n = 0; en = 0; #20;
        rst_n = 1; #10; en = 1; #100; en = 0; #20;
        if (count !== 8'd10) $error("Test failed");
        else $display("Test passed! Count = %0d", count);
        $finish;
    end
endmodule
