`timescale 1ns/1ps
module cpu_pmp_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic [31:0] pc, instr;
    logic dmem_valid, dmem_write;
    logic [31:0] dmem_addr, dmem_wdata;
    logic [3:0] dmem_wstrb;
    logic trap_valid;
    logic [31:0] trap_pc, trap_cause, trap_value;
    logic retire;
    logic saw_deny=0;
    cpu_core dut(.clk,.rst_n,.pc,.instr,.irq_external(1'b0),.irq_timer(1'b0),
        .dmem_valid,.dmem_write,.dmem_addr,.dmem_wdata,.dmem_wstrb,
        .dmem_ready(1'b0),.dmem_rdata(32'b0),.dmem_error(1'b0),
        .trap_valid,.trap_pc,.trap_cause,.trap_value,.retire);
    always_comb begin
        case (pc)
            32'h00: instr=32'h1000_00b7; // lui   x1,0x10000
            32'h04: instr=32'h0020_d093; // srli  x1,x1,2 -> pmpaddr encoding
            32'h08: instr=32'h3b00_9073; // csrw  pmpaddr0,x1
            32'h0c: instr=32'h0980_0113; // addi  x2,x0,0x98 (locked, NAPOT, no access)
            32'h10: instr=32'h3a01_1073; // csrw  pmpcfg0,x2
            32'h14: instr=32'h1000_0237; // lui   x4,0x10000
            32'h18: instr=32'h0010_0193; // addi  x3,x0,1
            32'h1c: instr=32'h0032_2023; // sw    x3,0(x4), must PMP fault
            default: instr=32'h0000_0013;
        endcase
    end
    always @(posedge clk) begin
        if (rst_n && dmem_valid && dmem_write && dmem_addr==32'h1000_0000)
            $fatal(1,"PMP-denied store escaped to the bus");
        if (rst_n && trap_valid && trap_cause==32'd7) begin
            if (trap_value!=32'h1000_0000) $fatal(1,"wrong PMP store-fault value %h",trap_value);
            saw_deny<=1;
        end
    end
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        repeat(40) @(negedge clk);
        if (!saw_deny) $fatal(1,"CPU did not trap on PMP-denied store");
        $display("cpu_pmp_tb PASS"); $finish;
    end
endmodule
