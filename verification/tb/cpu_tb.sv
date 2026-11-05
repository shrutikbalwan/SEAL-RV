`timescale 1ns/1ps

module cpu_tb;
    logic clk, rst_n;
    logic [31:0] pc, instr;
    logic dmem_valid, dmem_write, dmem_ready, dmem_error;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0] dmem_wstrb;
    logic trap_valid;
    logic [31:0] trap_pc, trap_cause, trap_value;
    
    cpu_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc(pc),
        .instr(instr),
        .irq_external(1'b0),
        .irq_timer(1'b0),
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

    // Instruction Memory Mock (Directed Tests)
    always_comb begin
        case(pc)
            32'h00000000: instr = 32'h00500093; // addi x1, x0, 5
            32'h00000004: instr = 32'h00a00113; // addi x2, x0, 10
            32'h00000008: instr = 32'h002081b3; // add  x3, x1, x2
            32'h0000000C: instr = 32'h06300013; // addi x0, x0, 99 (write must be ignored)
            32'h00000010: instr = 32'h00700213; // addi x4, x0, 7 (x0 read must be zero)
            default:      instr = 32'h00000013; // NOP
        endcase
    end

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $dumpfile("build/cpu.vcd");
        $dumpvars(0, cpu_tb);
        
        rst_n = 0; #15; rst_n = 1;
        
        #100;
        // Reference Checks & Assertions
        if (dut.rf.regs[3] !== 32'd15) $fatal(1, "FAIL: Arithmetic ADD incorrect (x3=%0d)", dut.rf.regs[3]);
        if (dut.rf.regs[4] !== 32'd7) $fatal(1, "FAIL: x0 did not read as zero after attempted write (x4=%0d)", dut.rf.regs[4]);
        if (trap_valid) $fatal(1, "FAIL: unexpected trap cause=%0d", trap_cause);
        
        $display("SystemVerilog Directed Tests Completed. Check assertions.");
        $finish;
    end
endmodule
