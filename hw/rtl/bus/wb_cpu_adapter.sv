// Adapts the CPU's ready/error data port to a Wishbone Classic master.
// The CPU interface has no retry: ERR returns ready=1 and error=1 for one cycle.
module wb_cpu_adapter (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_valid,
    input  logic        cpu_write,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic [3:0]  cpu_wstrb,
    output logic        cpu_ready,
    output logic [31:0] cpu_rdata,
    output logic        cpu_error,
    output logic        wb_cyc,
    output logic        wb_stb,
    output logic        wb_we,
    output logic [31:0] wb_adr,
    output logic [31:0] wb_dat_w,
    output logic [3:0]  wb_sel,
    input  logic [31:0] wb_dat_r,
    input  logic        wb_ack,
    input  logic        wb_err
);
    logic active;
    logic [31:0] saved_addr, saved_data;
    logic [3:0] saved_sel;
    logic saved_write;

    always_comb begin
        wb_cyc = active;
        wb_stb = active;
        wb_we = saved_write;
        wb_adr = saved_addr;
        wb_dat_w = saved_data;
        wb_sel = saved_sel;
        cpu_ready = active && (wb_ack || wb_err);
        cpu_rdata = wb_dat_r;
        cpu_error = active && wb_err;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            saved_addr <= 32'b0;
            saved_data <= 32'b0;
            saved_sel <= 4'b0;
            saved_write <= 1'b0;
        end else if (!active) begin
            if (cpu_valid) begin
                active <= 1'b1;
                saved_addr <= {cpu_addr[31:2], 2'b00};
                saved_data <= cpu_wdata;
                saved_sel <= cpu_write ? cpu_wstrb : 4'hf;
                saved_write <= cpu_write;
            end
        end else if (wb_ack || wb_err) begin
            active <= 1'b0;
        end
    end

`ifdef FORMAL
    default clocking cb @(posedge clk); endclocking
    assert property (active && !wb_ack && !wb_err |=> $stable({wb_we,wb_adr,wb_dat_w,wb_sel}));
    assert property (wb_ack |-> !wb_err);
`endif
endmodule
