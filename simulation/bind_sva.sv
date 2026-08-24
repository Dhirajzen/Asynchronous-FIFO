// ---------------------------------------------------------------------------
// bind_sva.sv - Attaches the assertion checkers to the RTL.
//
// `bind` keeps every assertion out of the design files: the RTL stays exactly
// as synthesised, and the checkers can still reach internal signals (the Gray
// pointers, and the first stage of each synchronizer) that are not exposed on
// any module port.
// ---------------------------------------------------------------------------

// Top-level FIFO behaviour: Gray-code integrity, overflow/underflow, flag
// correctness. WIDTH/DEPTH resolve against the parameters of the `top`
// instance being bound into.
bind top fifo_sva #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH)
) u_fifo_sva (
    .w_clk      (w_clk),
    .r_clk      (r_clk),
    .rst_n      (rst_n),
    .wr_rq      (wr_rq),
    .rd_rq      (rd_rq),
    .full       (full),
    .empty      (empty),
    .wdata      (wdata),
    .rdata      (rdata),
    .waddr      (waddr),
    .raddr      (raddr),
    .wptr       (wptr),
    .rptr       (rptr),
    .wsync_ptr2 (wsync_ptr2),
    .rsync_ptr2 (rsync_ptr2)
);

// Read pointer crossing into the write clock domain.
// wsync_ptr1 is internal to sync_r2w - reachable here precisely because this
// is a bind into that module's scope.
bind sync_r2w sync_sva #(
    .W ($clog2(DEPTH) + 1)
) u_sync_r2w_sva (
    .clk   (w_clk),
    .rst_n (rst_n),
    .din   (rptr),
    .sync1 (wsync_ptr1),
    .sync2 (wsync_ptr2)
);

// Write pointer crossing into the read clock domain.
bind sync_w2r sync_sva #(
    .W ($clog2(DEPTH) + 1)
) u_sync_w2r_sva (
    .clk   (r_clk),
    .rst_n (rst_n),
    .din   (wptr),
    .sync1 (rsync_ptr1),
    .sync2 (rsync_ptr2)
);
