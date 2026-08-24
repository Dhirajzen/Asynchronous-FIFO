module top #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    input w_clk,
    input r_clk,
    input rst_n,
    input wr_rq,
    input rd_rq,
    input logic [WIDTH-1:0] wdata,
    output logic full,
    output logic empty,
    output logic [WIDTH-1:0] rdata
);

    initial begin
        if ((DEPTH <= 0) || ((DEPTH & (DEPTH - 1)) != 0))
            $fatal(1, "top: DEPTH=%0d must be a power of two - required by the MSB-invert FULL/EMPTY comparison", DEPTH);
    end

    wire [$clog2(DEPTH)-1:0] waddr, raddr;
    wire [$clog2(DEPTH):0] wptr, rptr, wsync_ptr2, rsync_ptr2;

    sync_r2w #(DEPTH) sync_r2w (.*);
    sync_w2r #(DEPTH) sync_w2r (.*);
    fifo_mem #(WIDTH, DEPTH) fifomem (.*);
    wfull  #(WIDTH, DEPTH) u_wfull  (.*);
    rempty #(WIDTH, DEPTH) u_rempty (.*);

endmodule
