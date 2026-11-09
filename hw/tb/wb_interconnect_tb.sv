`timescale 1ns/1ps
module wb_tb_slave #(
    parameter integer LATENCY = 1
) (
    input logic clk, rst_n, stall,
    input logic cyc, stb, we,
    input logic [31:0] adr, dat_w,
    input logic [3:0] sel,
    output logic [31:0] dat_r,
    output logic ack, err,
    output integer write_count
);
    logic [31:0] mem [0:15];
    logic [1:0] state;
    integer delay_count;
    logic [31:0] saved_adr, saved_data;
    logic [3:0] saved_sel;
    logic saved_we;
    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0; delay_count <= 0; dat_r <= 0; ack <= 0; err <= 0; write_count <= 0;
            saved_adr <= 0; saved_data <= 0; saved_sel <= 0; saved_we <= 0;
            for (i=0;i<16;i=i+1) mem[i] <= 0;
        end else begin
            ack <= 0; err <= 0;
            case (state)
                0: if (cyc && stb) begin
                    saved_adr <= adr; saved_data <= dat_w; saved_sel <= sel; saved_we <= we;
                    delay_count <= LATENCY + adr[3:2];
                    state <= 1;
                end
                1: if (!cyc || !stb) state <= 0;
                   else if (!stall) begin
                       if (delay_count > 0) delay_count <= delay_count-1;
                       else begin
                           if (saved_we) begin
                               for (i=0;i<4;i=i+1)
                                   if (saved_sel[i]) mem[saved_adr[5:2]][i*8 +: 8] <= saved_data[i*8 +: 8];
                               write_count <= write_count+1;
                           end else dat_r <= mem[saved_adr[5:2]];
                           if (saved_adr[11:0] == 12'h040) err <= 1;
                           else ack <= 1;
                           state <= 2;
                       end
                   end
                2: if (!cyc || !stb) state <= 0;
                default: state <= 0;
            endcase
        end
    end
endmodule

module wb_interconnect_tb;
    logic clk=0, rst_n=0;
    always #5 clk=~clk;
    logic [1:0] cyc, stb, we;
    logic [63:0] adr, dat_w;
    logic [7:0] sel;
    wire [63:0] dat_r;
    wire [1:0] ack, err;
    wire [2:0] s_cyc, s_stb, s_we;
    wire [95:0] s_adr, s_dat_w;
    wire [11:0] s_sel;
    wire [95:0] s_dat_r;
    wire [2:0] s_ack, s_err;
    logic stall_all;
    integer writes_rom, writes_sram, writes_periph, writes_before;
    logic [31:0] got0, got1;

    wb_interconnect #(.TIMEOUT_CYCLES(12)) dut (
        .clk, .rst_n,
        .m0_cyc(cyc[0]), .m0_stb(stb[0]), .m0_we(we[0]), .m0_adr(adr[31:0]), .m0_dat_w(dat_w[31:0]), .m0_sel(sel[3:0]),
        .m0_dat_r(dat_r[31:0]), .m0_ack(ack[0]), .m0_err(err[0]),
        .m1_cyc(cyc[1]), .m1_stb(stb[1]), .m1_we(we[1]), .m1_adr(adr[63:32]), .m1_dat_w(dat_w[63:32]), .m1_sel(sel[7:4]),
        .m1_dat_r(dat_r[63:32]), .m1_ack(ack[1]), .m1_err(err[1]),
        .m0_privilege(2'b11), .m1_privilege(2'b11),
        .s_cyc, .s_stb, .s_we, .s_adr, .s_dat_w, .s_sel, .s_dat_r, .s_ack, .s_err
    );

    wb_tb_slave #(.LATENCY(1)) rom (
        .clk,.rst_n,.stall(stall_all),.cyc(s_cyc[0]),.stb(s_stb[0]),.we(s_we[0]),
        .adr(s_adr[31:0]),.dat_w(s_dat_w[31:0]),.sel(s_sel[3:0]),.dat_r(s_dat_r[31:0]),
        .ack(s_ack[0]),.err(s_err[0]),.write_count(writes_rom));
    wb_tb_slave #(.LATENCY(2)) sram (
        .clk,.rst_n,.stall(stall_all),.cyc(s_cyc[1]),.stb(s_stb[1]),.we(s_we[1]),
        .adr(s_adr[63:32]),.dat_w(s_dat_w[63:32]),.sel(s_sel[7:4]),.dat_r(s_dat_r[63:32]),
        .ack(s_ack[1]),.err(s_err[1]),.write_count(writes_sram));
    wb_tb_slave #(.LATENCY(3)) periph (
        .clk,.rst_n,.stall(stall_all),.cyc(s_cyc[2]),.stb(s_stb[2]),.we(s_we[2]),
        .adr(s_adr[95:64]),.dat_w(s_dat_w[95:64]),.sel(s_sel[11:8]),.dat_r(s_dat_r[95:64]),
        .ack(s_ack[2]),.err(s_err[2]),.write_count(writes_periph));

    task automatic start(input integer m, input logic wr, input logic [31:0] a,
                         input logic [31:0] wd, input logic [3:0] byte_sel);
        begin
            @(negedge clk);
            cyc[m]=1; stb[m]=1; we[m]=wr;
            adr[m*32 +: 32]=a; dat_w[m*32 +: 32]=wd; sel[m*4 +: 4]=byte_sel;
        end
    endtask

    task automatic finish(input integer m, input logic expect_error, output logic [31:0] result);
        integer cycles;
        begin
            cycles=0; result=0;
            while (!(ack[m] || err[m]) && cycles<40) begin @(posedge clk); cycles=cycles+1; end
            if (cycles>=40) $fatal(1,"master %0d transfer timed out",m);
            if ((err[m] === 1'b1) !== expect_error) $fatal(1,"master %0d unexpected ERR=%b",m,err[m]);
            if (ack[m] && err[m]) $fatal(1,"ACK and ERR simultaneously asserted");
            result=dat_r[m*32 +: 32];
            @(negedge clk); cyc[m]=0; stb[m]=0; sel[m*4 +: 4]=0;
        end
    endtask

    initial begin
        cyc=0; stb=0; we=0; adr=0; dat_w=0; sel=0; stall_all=0;
        repeat(3) @(posedge clk); rst_n=1;
        repeat(2) @(posedge clk);

        start(0,1,32'h0000_0008,32'h1122_3344,4'hf); finish(0,1,got0);
        if (writes_rom!=0) $fatal(1,"denied ROM write reached protected target");
        start(0,1,32'h1000_0008,32'hAABB_CCDD,4'hf); finish(0,0,got0);
        start(0,1,32'h4000_0008,32'h5566_7788,4'hf); finish(0,0,got0);
        start(0,1,32'h1000_0008,32'h0000_00EE,4'b0001); finish(0,0,got0);
        start(0,0,32'h1000_0008,0,4'hf); finish(0,0,got0);
        if (got0!==32'hAABB_CCEE) $fatal(1,"byte-select/readback mismatch: %h",got0);

        start(0,0,32'h0000_0FFC,0,4'hf); finish(0,0,got0);
        start(0,0,32'h0000_1000,0,4'hf); finish(0,1,got0);
        start(0,0,32'h1000_7FFC,0,4'hf); finish(0,0,got0);
        start(0,0,32'h1000_8000,0,4'hf); finish(0,1,got0);
        start(0,0,32'h4000_EFFC,0,4'hf); finish(0,0,got0);
        start(0,0,32'h4001_0000,0,4'hf); finish(0,1,got0);
        start(0,0,32'h1000_0000,0,4'b0); finish(0,1,got0);

        start(0,1,32'h1000_0010,32'h1111_1111,4'hf);
        start(1,1,32'h1000_0014,32'h2222_2222,4'hf);
        fork
            finish(0,0,got0);
            finish(1,0,got1);
        join
        if (writes_sram<4) $fatal(1,"lost or duplicated writes during contention");
        writes_before=writes_sram;
        start(1,1,32'h1000_7ffc,32'hDEAD_BEEF,4'hf); finish(1,1,got1);
        if (writes_sram!=writes_before) $fatal(1,"denied DMA secure-SRAM write reached target");
        start(0,0,32'h1000_0010,0,4'hf); finish(0,0,got0);
        if (got0!==32'h1111_1111) $fatal(1,"first contending transaction lost/reordered");
        start(0,0,32'h1000_0014,0,4'hf); finish(0,0,got0);
        if (got0!==32'h2222_2222) $fatal(1,"second contending transaction lost/reordered");
        start(0,0,32'h1000_0040,0,4'hf); finish(0,1,got0);

        stall_all=1;
        start(0,0,32'h0000_0000,0,4'hf);
        repeat(4) @(posedge clk);
        @(negedge clk); rst_n=0; cyc=0; stb=0; stall_all=0;
        repeat(2) @(posedge clk); rst_n=1;
        repeat(3) @(posedge clk);
        if (ack || err) $fatal(1,"stale termination after reset");
        start(0,0,32'h0000_0000,0,4'hf); finish(0,0,got0);

        stall_all=1;
        start(1,0,32'h4000_0000,0,4'hf);
        finish(1,1,got1);
        stall_all=0;
        $display("Wishbone interconnect tests passed");
        $finish;
    end
endmodule
