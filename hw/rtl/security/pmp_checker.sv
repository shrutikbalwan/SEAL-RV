// Byte-accurate RV32 PMP checker: OFF, TOR, NA4 and NAPOT; lowest-index
// overlap wins. A request crossing the winning region boundary is denied.
module pmp_checker (
    input logic [31:0] addr,
    input logic [4:0] size_bytes,
    input logic access_read, access_write, access_execute,
    input logic [1:0] privilege, // 3=M, 0=U; reserved values fail closed
    input logic [63:0] cfg_flat,
    input logic [255:0] addr_flat,
    output logic allow,
    output logic matched,
    output logic [2:0] matched_index
);
    logic found, full_match, perm_ok;
    logic [32:0] req_end, lo, hi;
    logic [31:0] a;
    logic [7:0] c;
    logic overlap, covers;
    integer i;
    always_comb begin
        req_end = {1'b0,addr} + (size_bytes == 0 ? 33'd1 : {28'b0,size_bytes});
        found=0; full_match=0; perm_ok=0;
        matched=0; matched_index=0; allow=0;
        lo=0; hi=0; a=0; c=0; overlap=0; covers=0;
        for (i=0;i<8;i=i+1) begin
            c=cfg_flat[i*8 +: 8]; a=addr_flat[i*32 +: 32];
            lo=0; hi=0;
            case (c[4:3])
                2'b01: begin // TOR, previous address is exclusive lower bound
                    lo=(i==0) ? 33'b0 : {1'b0,addr_flat[(i-1)*32 +: 32],2'b00};
                    hi={1'b0,a,2'b00};
                end
                2'b10: begin lo={1'b0,a,2'b00}; hi=lo+4; end // NA4
                2'b11: begin // NAPOT: trailing ones encode size, 8 bytes minimum
                    integer n;
                    logic [31:0] mask;
                    n=0; mask=0;
                    for (integer k=0;k<32;k=k+1) if ((k==n) && a[k]) n=n+1;
                    if (n>=29) begin lo=0; hi=33'h1_0000_0000; end
                    else begin
                        mask=(32'hffff_ffff << n) << 2;
                        lo={1'b0,(a & mask),2'b00};
                        hi=lo + (33'd1 << (n+3));
                    end
                end
                default: begin lo=0; hi=0; end
            endcase
            overlap=(c[4:3] != 0) && ({1'b0,addr} < hi) && (req_end > lo) && (hi>lo);
            covers=({1'b0,addr} >= lo) && (req_end <= hi) && (hi>lo);
            if (!found && overlap) begin
                found=1; matched=1; matched_index=i[2:0]; full_match=covers;
                perm_ok=(!access_read || c[0]) && (!access_write || c[1]) && (!access_execute || c[2]);
                // M bypasses unlocked entries, while locked entries apply to M.
                if (privilege==2'b11 && !c[7]) perm_ok=1;
            end
        end
        if (privilege==2'b11) allow= !found || (full_match &&
            (!cfg_flat[matched_index*8+7] || perm_ok));
        else if (privilege==2'b00) allow= found && full_match && perm_ok;
        else allow=0;
        // With no entry matching, only machine mode is permitted.
    end
`ifdef FORMAL
    always_comb begin
        assert (allow || !matched || !full_match || !perm_ok);
        if (privilege==2'b00 && !matched) assert (!allow);
    end
`endif
endmodule
