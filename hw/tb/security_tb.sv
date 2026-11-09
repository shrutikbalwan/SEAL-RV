`timescale 1ns/1ps
module security_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;

    logic [7:0] cfg_we=0;
    logic [63:0] cfg_wdata=0;
    logic addr_we=0;
    logic [2:0] addr_index=0, read_index=0;
    logic [31:0] addr_wdata=0;
    wire [7:0] cfg_rdata;
    wire [31:0] addr_rdata;
    wire [63:0] cfg_flat;
    wire [255:0] addr_flat;
    logic [31:0] paddr;
    logic [4:0] psize;
    logic pread, pwrite, pexec;
    logic [1:0] ppriv;
    wire pallow, pmatch;
    wire [2:0] pindex;
    seal_pmp pmp_regs(.clk,.rst_n,.cfg_we,.cfg_wdata,.addr_we,.addr_index,.addr_wdata,
        .read_index,.cfg_rdata,.addr_rdata,.cfg_flat,.addr_flat);
    pmp_checker check(.addr(paddr),.size_bytes(psize),.access_read(pread),.access_write(pwrite),
        .access_execute(pexec),.privilege(ppriv),.cfg_flat,.addr_flat,.allow(pallow),
        .matched(pmatch),.matched_index(pindex));

    logic [2:0] master_id=0;
    logic [1:0] privilege=3;
    logic cpu_execute=0, m_cyc=0, m_stb=0, m_we=0;
    logic [31:0] m_adr=0, m_dat_w=0;
    logic [3:0] m_sel=4'hf;
    wire [31:0] m_dat_r, s_adr, s_dat_w;
    wire m_ack,m_err,s_cyc,s_stb,s_we;
    wire [3:0] s_sel;
    wire violation_valid;
    wire [31:0] violation_addr, violation_count;
    wire [2:0] violation_master;
    wb_firewall firewall(.clk,.rst_n,.master_id,.privilege,.cpu_execute,.m_cyc,.m_stb,.m_we,
        .m_adr,.m_dat_w,.m_sel,.m_dat_r,.m_ack,.m_err,.s_cyc,.s_stb,.s_we,.s_adr,.s_dat_w,.s_sel,
        .s_dat_r(32'h12345678),.s_ack(s_cyc),.s_err(1'b0),.violation_valid,.violation_addr,
        .violation_master,.violation_count);

    task automatic write_cfg(input logic [2:0] ix,input logic [7:0] value);
        @(negedge clk); cfg_we=8'b1<<ix; cfg_wdata={8{value}};
        @(negedge clk); cfg_we=0;
    endtask
    task automatic write_addr(input logic [2:0] ix,input logic [31:0] value);
        @(negedge clk); addr_we=1; addr_index=ix; addr_wdata=value;
        @(negedge clk); addr_we=0;
    endtask
    task automatic expect_pmp(input logic expected,input string label_text);
        #1; if (pallow !== expected) $fatal(1,"PMP %s expected %b got %b",label_text,expected,pallow);
    endtask
    task automatic firewall_request(input logic [2:0] id,input logic wr,input logic [31:0] address,
                                    input logic [1:0] priv,input logic expected,input string label_text);
        begin
            master_id=id; m_we=wr; m_adr=address; privilege=priv; m_cyc=1; m_stb=1; #1;
            if (s_cyc !== expected || m_err !== !expected)
                $fatal(1,"firewall %s expected allow=%b got target=%b err=%b",label_text,expected,s_cyc,m_err);
            if (!expected && s_stb) $fatal(1,"denied request reached target: %s",label_text);
            @(negedge clk); m_cyc=0; m_stb=0;
            if (!expected && (!violation_valid || violation_addr!=address || violation_master!=id))
                $fatal(1,"firewall failed to log denial: %s",label_text);
        end
    endtask

    initial begin
        paddr=0; psize=4; pread=1; pwrite=0; pexec=0; ppriv=0;
        repeat(2) @(negedge clk); rst_n=1;
        // Two overlapping 16-byte NAPOT entries: entry zero wins.
        write_addr(0,32'h0400_0001);
        write_addr(1,32'h0400_0001);
        write_cfg(0,8'h1d); // R=1, X=1, NAPOT
        write_cfg(1,8'h18); // no permissions, NAPOT
        paddr=32'h1000_0000; psize=4; pread=1; pwrite=0; pexec=0; ppriv=0;
        expect_pmp(1,"overlap priority/read permission");
        pwrite=1; pread=0; expect_pmp(0,"write permission");
        pwrite=0; pexec=1; expect_pmp(1,"execute permission");
        pexec=0; paddr=32'h1000_000c; psize=8; pread=1;
        expect_pmp(0,"partial boundary crossing");
        ppriv=3; expect_pmp(0,"M-mode partial boundary crossing");
        write_addr(1,32'h0800_0001);
        ppriv=0; paddr=32'h2000_0000; psize=4; pexec=1;
        expect_pmp(0,"execute permission denial");
        pexec=0; pread=1; expect_pmp(0,"read permission denial");
        paddr=32'h3000_0000; expect_pmp(0,"unmatched U-mode deny");
        // Lock entry zero, then prove both config and address writes are ignored;
        // machine mode is also constrained by the locked entry.
        write_cfg(0,8'h9d);
        write_cfg(0,8'h1f);
        write_addr(0,32'h0800_0001);
        read_index=0; #1;
        if (!cfg_rdata[7] || addr_rdata!=32'h0400_0001) $fatal(1,"PMP locked register changed");
        ppriv=3; paddr=32'h1000_0000; psize=4; pwrite=1; pread=0;
        expect_pmp(0,"locked M-mode write denial");

        firewall_request(0,0,32'h0000_0ffc,3,1,"boot ROM read boundary");
        firewall_request(0,1,32'h0000_0000,3,0,"boot ROM write denial");
        firewall_request(1,0,32'h0000_0000,3,0,"DMA ROM denial");
        firewall_request(1,1,32'h1000_0000,3,1,"DMA ordinary SRAM");
        firewall_request(1,1,32'h1000_7ffc,3,0,"DMA secure SRAM denial");
        firewall_request(0,1,32'h1000_7ffc,3,1,"CPU machine secure SRAM access");
        firewall_request(0,1,32'h1000_7ffc,0,0,"U-mode secure SRAM denial");
        firewall_request(1,0,32'h1000_8000,3,0,"DMA SRAM upper boundary");
        firewall_request(1,0,32'h4000_0000,3,0,"DMA peripheral denial");
        firewall_request(1,0,32'h4000_8000,3,0,"DMA key-vault denial");
        firewall_request(0,0,32'h4000_8000,3,0,"CPU key read denial");
        firewall_request(0,1,32'h4000_8000,3,1,"machine key write allowed");
        firewall_request(0,0,32'h4000_7ffc,3,1,"CPU peripheral read");
        @(negedge clk); master_id=0; privilege=3; cpu_execute=1; m_we=0;
        m_adr=32'h4000_0000; m_sel=4'hf; m_cyc=1; m_stb=1; #1;
        if (s_cyc || !m_err) $fatal(1,"firewall allowed MMIO instruction fetch");
        @(negedge clk); m_cyc=0; m_stb=0; cpu_execute=0;
        if (!violation_valid || violation_count<1 || violation_master!=0 || violation_addr!=32'h4000_0000)
            $fatal(1,"violation log did not retain the latest denied request");
        $display("security_tb PASS"); $finish;
    end
endmodule
