`timescale 1ns/1ps
module memory_subsystem_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic [31:0] pc, instr;
    logic dv,dw,dr,de,cyc,stb,we,ack,err;
    logic [31:0] da,dwd,drd,ba,bwd,brd;
    logic [3:0] ds,sel;
    logic acyc,astb,awe;
    logic [31:0] aba,abwd;
    logic [3:0] asel;
    logic manual_bus;
    wire mcyc = manual_bus ? cyc : acyc;
    wire mstb = manual_bus ? stb : astb;
    wire mwe = manual_bus ? we : awe;
    wire [31:0] mba = manual_bus ? ba : aba;
    wire [31:0] mbwd = manual_bus ? bwd : abwd;
    wire [3:0] msel = manual_bus ? sel : asel;
    logic trap_valid;
    logic [31:0] trap_pc,trap_cause,trap_value;
    cpu_core cpu(.clk,.rst_n,.pc,.instr,.irq_external(1'b0),.irq_timer(1'b0),
      .dmem_valid(dv),.dmem_write(dw),.dmem_addr(da),.dmem_wdata(dwd),.dmem_wstrb(ds),
      .dmem_ready(dr),.dmem_rdata(drd),.dmem_error(de),.trap_valid,.trap_pc,.trap_cause,.trap_value,.retire());
    wb_cpu_adapter adapter(.clk,.rst_n,.cpu_valid(dv),.cpu_write(dw),.cpu_addr(da),.cpu_wdata(dwd),.cpu_wstrb(ds),
      .cpu_ready(dr),.cpu_rdata(drd),.cpu_error(de),.wb_cyc(acyc),.wb_stb(astb),.wb_we(awe),.wb_adr(aba),.wb_dat_w(abwd),.wb_sel(asel),.wb_dat_r(brd),.wb_ack(ack),.wb_err(err));
    memory_subsystem #(.ROM_INIT_FILE("hw/tb/boot_image.hex")) mem(.clk,.rst_n,.fetch_addr(pc),.fetch_data(instr),
      .cyc(mcyc),.stb(mstb),.we(mwe),.adr(mba),.dat_w(mbwd),.sel(msel),.dat_r(brd),.ack,.err);
    task automatic wb_access(input logic wr,input logic [31:0] a,input logic [31:0] d,input logic [3:0] s,
                             input logic expect_err,input logic [31:0] expected);
      integer timeout;
      begin
        @(negedge clk); cyc=1; stb=1; we=wr; ba=a; bwd=d; sel=s; timeout=0;
        while (!ack && !err && timeout<5) begin @(posedge clk); #1; timeout=timeout+1; end
        if (timeout==5) $fatal(1,"memory response timeout at %h",a);
        if (err !== expect_err) $fatal(1,"wrong error at %h",a);
        if (!wr && !expect_err && brd !== expected) $fatal(1,"read %h got %h expected %h",a,brd,expected);
        @(negedge clk); cyc=0; stb=0; we=0;
      end
    endtask
    task automatic wb_back_to_back_writes;
      begin
        @(negedge clk); cyc=1; stb=1; we=1; ba=32'h1000_0010; bwd=32'h1234_5678; sel=4'hf;
        @(posedge clk); #1; if (!ack || err) $fatal(1,"first back-to-back write failed");
        @(negedge clk); ba=32'h1000_0014; bwd=32'h89ab_cdef;
        @(posedge clk); #1; if (!ack || err) $fatal(1,"second back-to-back write failed");
        @(negedge clk); cyc=0; stb=0; we=0;
        wb_access(0,32'h1000_0010,0,4'hf,0,32'h1234_5678);
        wb_access(0,32'h1000_0014,0,4'hf,0,32'h89ab_cdef);
      end
    endtask
    initial begin
      cyc=0; stb=0; we=0; ba=0; bwd=0; sel=0;
      manual_bus=0;
      repeat(3) @(negedge clk); rst_n=1;
      repeat(40) @(posedge clk);
      if (cpu.rf.regs[4] !== 42 || cpu.rf.regs[5] !== 42 || cpu.rf.regs[6] !== 42 ||
          cpu.rf.regs[8] !== 32'hffff_fffe)
        $fatal(1,"ROM program did not verify SRAM stack/data/subword access: x4=%h x5=%h x6=%h x8=%h",
               cpu.rf.regs[4],cpu.rf.regs[5],cpu.rf.regs[6],cpu.rf.regs[8]);
      if (trap_valid) $fatal(1,"unexpected CPU trap %h",trap_cause);
      manual_bus=1;
      wb_access(0,32'h1000_0000,0,4'hf,0,32'hfffe_2a2a);
      wb_access(1,32'h1000_7ffc,32'b0,4'hf,0,0);
      wb_access(1,32'h1000_7fff,32'hAA00_0000,4'h8,0,0);
      wb_access(0,32'h1000_7ffc,0,4'hf,0,32'hAA00_0000);
      wb_access(1,32'h1000_7ffc,32'h0000_55cc,4'h3,0,0);
      wb_access(0,32'h1000_7ffc,0,4'hf,0,32'hAA00_55cc);
      wb_access(0,32'h0000_0ffc,0,4'hf,0,32'h0000_0013);
      wb_access(1,32'h0000_0000,0,4'hf,1,0);
      wb_access(0,32'h1000_8000,0,4'hf,1,0);
      wb_access(0,32'h2000_0000,0,4'hf,1,0);
      wb_access(0,32'h1000_0000,0,0,1,0);
      wb_back_to_back_writes();
      // Reset while a response is pending: cancel the response, retain SRAM.
      @(negedge clk); cyc=1; stb=1; we=0; ba=32'h1000_0010; sel=4'hf;
      @(posedge clk); #1; if (!ack) $fatal(1,"reset-abort setup failed");
      @(negedge clk); rst_n=0; #1;
      if (ack || err) $fatal(1,"reset failed to clear pending response");
      cyc=0; stb=0;
      repeat(2) @(negedge clk);
      rst_n=1;
      repeat(2) @(negedge clk);
      if (ack || err) $fatal(1,"stale response after reset");
      wb_access(0,32'h1000_0010,0,4'hf,0,32'h1234_5678);
      $display("memory_subsystem_tb PASS"); $finish;
    end
endmodule
