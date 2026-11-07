// Two-master, three-target Wishbone B4 Classic interconnect.
// Masters: m0 is CPU, m1 is DMA. Targets: s0 ROM, s1 SRAM, s2 peripherals.
// A single global transaction may be active; all target clocks are synchronous.
module wb_interconnect #(
    parameter integer TIMEOUT_CYCLES = 16
) (
    input logic clk,
    input logic rst_n,
    input logic m0_cyc, m0_stb, m0_we,
    input logic [31:0] m0_adr, m0_dat_w,
    input logic [3:0] m0_sel,
    output logic [31:0] m0_dat_r,
    output logic m0_ack, m0_err,
    input logic m1_cyc, m1_stb, m1_we,
    input logic [31:0] m1_adr, m1_dat_w,
    input logic [3:0] m1_sel,
    output logic [31:0] m1_dat_r,
    output logic m1_ack, m1_err,
    output logic [2:0] s_cyc, s_stb, s_we,
    output logic [95:0] s_adr,
    output logic [95:0] s_dat_w,
    output logic [11:0] s_sel,
    input logic [95:0] s_dat_r,
    input logic [2:0] s_ack, s_err
);
    logic d_cyc, d_stb, d_we;
    logic [31:0] d_adr, d_dat_w, d_dat_r;
    logic [3:0] d_sel;
    logic d_ack, d_err;
    logic [2:0] target;
    logic unmapped;
    logic error_ack, error_err;
    logic [31:0] error_rdata;
    logic target_ack, target_err;

    wb_arbiter #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) arbiter (
        .clk, .rst_n,
        .m0_cyc, .m0_stb, .m0_we, .m0_adr, .m0_dat_w, .m0_sel,
        .m0_dat_r, .m0_ack, .m0_err,
        .m1_cyc, .m1_stb, .m1_we, .m1_adr, .m1_dat_w, .m1_sel,
        .m1_dat_r, .m1_ack, .m1_err,
        .s_cyc(d_cyc), .s_stb(d_stb), .s_we(d_we), .s_adr(d_adr), .s_dat_w(d_dat_w), .s_sel(d_sel),
        .s_dat_r(d_dat_r), .s_ack(d_ack), .s_err(d_err)
    );

    wb_address_decoder decoder (.adr(d_adr), .select(target), .unmapped);
    wb_error_slave error_target (
        .clk, .rst_n,
        .cyc(d_cyc && (unmapped || d_sel == 4'b0)),
        .stb(d_stb && (unmapped || d_sel == 4'b0)),
        .ack(error_ack), .err(error_err), .dat_r(error_rdata)
    );

    assign s_cyc[0] = d_cyc && target[0] && !unmapped && (d_sel != 0);
    assign s_cyc[1] = d_cyc && target[1] && !unmapped && (d_sel != 0);
    assign s_cyc[2] = d_cyc && target[2] && !unmapped && (d_sel != 0);
    assign s_stb[0] = d_stb && target[0] && !unmapped && (d_sel != 0);
    assign s_stb[1] = d_stb && target[1] && !unmapped && (d_sel != 0);
    assign s_stb[2] = d_stb && target[2] && !unmapped && (d_sel != 0);
    assign s_we = {3{d_we}} & s_stb;
    assign s_adr = {3{d_adr}};
    assign s_dat_w = {3{d_dat_w}};
    assign s_sel = {3{d_sel}};
    assign d_dat_r = (unmapped || d_sel == 0) ? error_rdata :
                     target[0] ? s_dat_r[31:0] :
                     target[1] ? s_dat_r[63:32] :
                     target[2] ? s_dat_r[95:64] : 32'b0;
    assign target_ack = (unmapped || d_sel == 0) ? error_ack :
                        target[0] ? s_ack[0] : target[1] ? s_ack[1] : target[2] ? s_ack[2] : 1'b0;
    assign target_err = (unmapped || d_sel == 0) ? error_err :
                        target[0] ? s_err[0] : target[1] ? s_err[1] : target[2] ? s_err[2] : 1'b0;
    // If a misbehaving target raises both, terminate as an error only.
    assign d_ack = d_cyc && d_stb && target_ack && !target_err;
    assign d_err = d_cyc && d_stb && target_err;

`ifdef FORMAL
    default clocking cb @(posedge clk); endclocking
    assert property ($onehot0(s_cyc));
    assert property ($onehot0(s_stb));
    assert property ((|s_ack) |-> $onehot(s_ack));
    assert property ((|s_err) |-> $onehot(s_err));
    assert property ((|s_ack) |-> !(|s_err));
`endif
endmodule
