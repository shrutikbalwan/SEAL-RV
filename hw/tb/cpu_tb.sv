`timescale 1ns/1ps
module cpu_tb;
    logic clk, rst_n;
    logic [31:0] pc, instr;
    logic [31:0] imem [0:255];

    cpu_core uut (.clk(clk), .rst_n(rst_n), .pc(pc), .instr(instr));

    initial $readmemh("hw/tb/test_prog.hex", imem);
    assign instr = imem[pc[31:2]];

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $dumpfile("cpu.vcd"); $dumpvars(0, cpu_tb);
        rst_n = 0; #20; rst_n = 1;
        #100;
        if (uut.rf.regs[3] !== 32'd15) $error("Test failed: expected x3=15");
        else $display("Test passed! x3 = %0d", uut.rf.regs[3]);
        $finish;
    end
endmodule
