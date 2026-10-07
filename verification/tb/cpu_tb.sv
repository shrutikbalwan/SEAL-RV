`timescale 1ns/1ps

module cpu_tb;
    logic clk, rst_n;
    logic [31:0] pc, instr;
    
    cpu_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .pc(pc),
        .instr(instr)
    );

    // Instruction Memory Mock (Directed Tests)
    always_comb begin
        case(pc)
            32'h00000000: instr = 32'h00500093; // addi x1, x0, 5
            32'h00000004: instr = 32'h00a00113; // addi x2, x0, 10
            32'h00000008: instr = 32'h002081b3; // add  x3, x1, x2
            32'h0000000C: instr = 32'h00000000; // illegal instruction
            default:      instr = 32'h00000013; // NOP
        endcase
    end

    initial begin clk = 0; forever #5 clk = ~clk; end

    initial begin
        $dumpfile("verification/waves/cpu.vcd"); 
        $dumpvars(0, cpu_tb);
        
        rst_n = 0; #15; rst_n = 1;
        
        #100;
        // Reference Checks & Assertions
        assert (dut.rf.regs[0] == 32'b0) else $error("FAIL: Zero register modified!");
        assert (dut.rf.regs[3] == 32'd15) else $error("FAIL: Arithmetic ADD incorrect!");
        
        $display("SystemVerilog Directed Tests Completed. Check assertions.");
        $finish;
    end
endmodule
