// Two-master Wishbone B4 Classic arbiter. One transfer may be outstanding.
// The selected owner's request is held until ACK, ERR, reset, or timeout.
module wb_arbiter #(
    parameter integer TIMEOUT_CYCLES = 16
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        m0_cyc, m0_stb, m0_we,
    input  logic [31:0] m0_adr, m0_dat_w,
    input  logic [3:0]  m0_sel,
    output logic [31:0] m0_dat_r,
    output logic        m0_ack, m0_err,
    input  logic        m1_cyc, m1_stb, m1_we,
    input  logic [31:0] m1_adr, m1_dat_w,
    input  logic [3:0]  m1_sel,
    output logic [31:0] m1_dat_r,
    output logic        m1_ack, m1_err,
    output logic        s_cyc, s_stb, s_we,
    output logic [31:0] s_adr, s_dat_w,
    output logic [3:0]  s_sel,
    input  logic [31:0] s_dat_r,
    input  logic        s_ack, s_err
);
    localparam integer TIMEOUT_LIMIT = (TIMEOUT_CYCLES < 1) ? 1 : TIMEOUT_CYCLES;
    localparam integer COUNT_W = (TIMEOUT_LIMIT < 2) ? 1 : $clog2(TIMEOUT_LIMIT + 1);
    logic busy, owner, next_owner;
    logic [COUNT_W-1:0] wait_count;
    logic timeout;
    assign s_cyc = busy && (owner ? m1_cyc : m0_cyc);
    assign s_stb = busy && (owner ? m1_stb : m0_stb);
    assign s_we = busy && (owner ? m1_we : m0_we);
    assign s_adr = busy ? (owner ? m1_adr : m0_adr) : 32'b0;
    assign s_dat_w = busy ? (owner ? m1_dat_w : m0_dat_w) : 32'b0;
    assign s_sel = busy ? (owner ? m1_sel : m0_sel) : 4'b0;
    assign m0_dat_r = busy && !owner ? s_dat_r : 32'b0;
    assign m1_dat_r = busy && owner ? s_dat_r : 32'b0;
    assign m0_ack = busy && !owner && s_ack;
    assign m1_ack = busy && owner && s_ack;
    assign m0_err = busy && !owner && (s_err | timeout);
    assign m1_err = busy && owner && (s_err | timeout);

    assign timeout = busy && (owner ? (m1_cyc && m1_stb) : (m0_cyc && m0_stb)) &&
                     (wait_count >= TIMEOUT_LIMIT-1) && !s_ack && !s_err;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            owner <= 1'b0;
            next_owner <= 1'b0;
            wait_count <= '0;
        end else if (!busy) begin
            wait_count <= '0;
            if (m0_cyc && m0_stb && m1_cyc && m1_stb) begin
                owner <= next_owner;
                busy <= 1'b1;
            end else if (m0_cyc && m0_stb) begin
                owner <= 1'b0;
                busy <= 1'b1;
            end else if (m1_cyc && m1_stb) begin
                owner <= 1'b1;
                busy <= 1'b1;
            end
        end else if (!(owner ? (m1_cyc && m1_stb) : (m0_cyc && m0_stb)) || s_ack || s_err || timeout) begin
            busy <= 1'b0;
            wait_count <= '0;
            next_owner <= ~owner;
        end else if (wait_count < TIMEOUT_LIMIT) begin
            wait_count <= wait_count + 1'b1;
        end
    end

`ifdef FORMAL
    default clocking cb @(posedge clk); endclocking
    assert property (m0_ack |-> !m0_err);
    assert property (m1_ack |-> !m1_err);
    assert property ((m0_ack || m0_err) |-> busy && !owner);
    assert property ((m1_ack || m1_err) |-> busy && owner);
    assert property (busy && !(s_ack || s_err || timeout) |=> $stable(owner));
    assert property (m0_cyc && m0_stb && !m0_ack && !m0_err |=> $stable({m0_cyc,m0_stb,m0_we,m0_adr,m0_dat_w,m0_sel}));
    assert property (m1_cyc && m1_stb && !m1_ack && !m1_err |=> $stable({m1_cyc,m1_stb,m1_we,m1_adr,m1_dat_w,m1_sel}));
    assert property ((s_ack || s_err) |-> busy && s_cyc && s_stb);
`endif
endmodule
