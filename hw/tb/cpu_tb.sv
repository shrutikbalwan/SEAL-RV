`timescale 1ns/1ps
module cpu_tb;
    logic clk, rst_n;
    logic [31:0] pc, instr;
    logic dmem_valid, dmem_write, dmem_ready, dmem_error;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0] dmem_wstrb;
    logic trap_valid;
    logic [31:0] trap_pc, trap_cause, trap_value;
    logic [31:0] imem [0:255];

    cpu_core uut (
        .clk(clk), .rst_n(rst_n), .pc(pc), .instr(instr), .irq_external(1'b0), .irq_timer(1'b0),
        .dmem_valid(dmem_valid), .dmem_write(dmem_write),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .dmem_ready(dmem_ready), .dmem_rdata(dmem_rdata), .dmem_error(dmem_error),
        .trap_valid(trap_valid), .trap_pc(trap_pc),
        .trap_cause(trap_cause), .trap_value(trap_value)
    );

    initial begin
        dmem_ready = 1'b1;
        dmem_rdata = 32'b0;
        dmem_error = 1'b0;
    end

    initial $readmemh("hw/tb/test_prog.hex", imem);
    // The smoke program has three words; fetch benign NOPs afterward.
    assign instr = (pc[31:2] < 3) ? imem[pc[31:2]] : 32'h00000013;

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $dumpfile("cpu.vcd"); $dumpvars(0, cpu_tb);
        rst_n = 0; #20; rst_n = 1;
        #100;
        if (uut.rf.regs[3] !== 32'd15) $fatal(1, "Test failed: expected x3=15, got %0d", uut.rf.regs[3]);
        if (trap_valid) $fatal(1, "Test failed: unexpected trap cause=%0d", trap_cause);
        else $display("Test passed! x3 = %0d", uut.rf.regs[3]);
        $finish;
    end
endmodule
