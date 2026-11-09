// Independent Wishbone firewall for every bus master. Master IDs: 0 CPU,
// 1 DMA, 2+ other engines. Address policy is intentionally default-deny.
// Region rules derive from docs/MEMORY_MAP.md; key-vault access is CPU-M only.
module wb_firewall #(
    parameter logic [31:0] VIOLATION_RESET = 32'b0
) (
    input logic clk, rst_n,
    input logic [2:0] master_id,
    input logic [1:0] privilege,
    input logic cpu_execute,
    input logic m_cyc, m_stb, m_we,
    input logic [31:0] m_adr, m_dat_w,
    input logic [3:0] m_sel,
    output logic [31:0] m_dat_r,
    output logic m_ack, m_err,
    output logic s_cyc, s_stb, s_we,
    output logic [31:0] s_adr, s_dat_w,
    output logic [3:0] s_sel,
    input logic [31:0] s_dat_r,
    input logic s_ack, s_err,
    output logic violation_valid,
    output logic [31:0] violation_addr,
    output logic [2:0] violation_master,
    output logic [31:0] violation_count
);
    logic allowed, req, mem_region, periph_region, is_key, is_secure_sram, byte_ok;
    integer b;
    always_comb begin
        req=m_cyc && m_stb;
        mem_region=0; periph_region=0; is_key=0; is_secure_sram=0; byte_ok=1;
        // Evaluate every selected byte so a beat cannot straddle policy regions.
        for (b=0;b<4;b=b+1) if (m_sel[b]) begin
            if (({m_adr[31:2],2'b00}+b) <= 32'h0000_0fff) begin
                if ((master_id==0 && !m_we)) mem_region=1;
                else byte_ok=0;
            end else if (({m_adr[31:2],2'b00}+b) >= 32'h1000_0000 && ({m_adr[31:2],2'b00}+b) <= 32'h1000_7fff) begin
                mem_region=1;
                if (({m_adr[31:2],2'b00}+b) >= 32'h1000_7000) is_secure_sram=1;
            end else if (({m_adr[31:2],2'b00}+b) >= 32'h4000_0000 && ({m_adr[31:2],2'b00}+b) <= 32'h4000_ffff) begin
                periph_region=1;
                if (({m_adr[31:2],2'b00}+b) >= 32'h4000_8000 && ({m_adr[31:2],2'b00}+b) <= 32'h4000_8fff) is_key=1;
            end else byte_ok=0;
        end
        allowed=byte_ok && (m_sel!=0) && !(cpu_execute && (m_we || periph_region));
        if (mem_region && !periph_region) begin
            if (m_adr>=32'h0000_0000 && m_adr<=32'h0000_0fff) allowed=allowed && master_id==0 && !m_we;
            else if (m_adr>=32'h1000_0000 && m_adr<=32'h1000_7fff)
                allowed=allowed && (master_id==0 || master_id==1) && (!cpu_execute || master_id==0);
            if (is_secure_sram)
                allowed=allowed && master_id==0 && (privilege === 2'b11);
        end
        if (periph_region) begin
            // DMA and accelerator masters cannot access peripheral windows.
            allowed=allowed && master_id==0 && !cpu_execute;
            if (is_key) allowed=allowed && (privilege === 2'b11) && m_we;
        end
        s_cyc=m_cyc && allowed; s_stb=m_stb && allowed; s_we=m_we;
        s_adr=m_adr; s_dat_w=m_dat_w; s_sel=m_sel;
        m_dat_r=allowed ? s_dat_r : 32'b0;
        m_ack=req && allowed && s_ack && !s_err;
        m_err=req && ((!allowed) || s_err);
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            violation_valid<=0; violation_addr<=0; violation_master<=0;
            violation_count<=VIOLATION_RESET;
        end else begin
            violation_valid<=req && !allowed;
            if (req && !allowed) begin
                violation_addr<=m_adr; violation_master<=master_id;
                if (!(&violation_count)) violation_count<=violation_count+1'b1;
            end
        end
    end
`ifdef FORMAL
    default clocking cb @(posedge clk); endclocking
    assert property (req && !allowed |-> !s_cyc && !s_stb && m_err);
    assert property (m_ack |-> s_ack && !s_err);
    assert property (m_err && !allowed |-> !s_cyc);
    assert property (s_cyc |-> allowed);
`endif
endmodule
