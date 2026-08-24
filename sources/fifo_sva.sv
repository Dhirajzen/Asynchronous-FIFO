// ---------------------------------------------------------------------------
// fifo_sva.sv - SystemVerilog Assertion checker for the asynchronous FIFO.
//
// Bound onto `top` (see simulation/bind_sva.sv) so it can observe both the
// module ports and the internal Gray-coded pointers without modifying the RTL.
//
// Every property is clocked in the domain that owns the signals it checks:
// write-side properties on w_clk, read-side properties on r_clk. Sampling a
// signal in the domain that produces it is what keeps these checks meaningful
// across the CDC boundary.
// ---------------------------------------------------------------------------
module fifo_sva #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
)(
    input logic                      w_clk,
    input logic                      r_clk,
    input logic                      rst_n,
    input logic                      wr_rq,
    input logic                      rd_rq,
    input logic                      full,
    input logic                      empty,
    input logic [WIDTH-1:0]          wdata,
    input logic [WIDTH-1:0]          rdata,
    input logic [$clog2(DEPTH)-1:0]  waddr,
    input logic [$clog2(DEPTH)-1:0]  raddr,
    input logic [$clog2(DEPTH):0]    wptr,
    input logic [$clog2(DEPTH):0]    rptr,
    input logic [$clog2(DEPTH):0]    wsync_ptr2,
    input logic [$clog2(DEPTH):0]    rsync_ptr2
);

  // -------------------------------------------------------------------------
  // 1) Gray-code integrity: the whole CDC scheme rests on the pointer changing
  //    by at most ONE bit per clock. If two bits ever change together, a
  //    synchronizer sampling mid-transition can latch a value that was never
  //    actually held, and the full/empty comparison silently corrupts.
  //    $onehot0 accepts both "no change" (idle) and "exactly one bit".
  // -------------------------------------------------------------------------
  property p_wptr_gray;
    @(posedge w_clk) disable iff (!rst_n)
      $onehot0(wptr ^ $past(wptr));
  endproperty
  a_wptr_gray: assert property (p_wptr_gray)
    else $error("CDC-SVA: wptr changed by more than one bit in a single w_clk (now %b)", wptr);

  property p_rptr_gray;
    @(posedge r_clk) disable iff (!rst_n)
      $onehot0(rptr ^ $past(rptr));
  endproperty
  a_rptr_gray: assert property (p_rptr_gray)
    else $error("CDC-SVA: rptr changed by more than one bit in a single r_clk (now %b)", rptr);

  // -------------------------------------------------------------------------
  // 2) Overflow protection: a write request while FULL must not advance the
  //    write pointer. If it did, the FIFO would silently overwrite unread data.
  // -------------------------------------------------------------------------
  property p_no_overflow;
    @(posedge w_clk) disable iff (!rst_n)
      (full && wr_rq) |=> ($stable(waddr) && $stable(wptr));
  endproperty
  a_no_overflow: assert property (p_no_overflow)
    else $error("CDC-SVA: write pointer advanced while FULL (overflow)");

  // -------------------------------------------------------------------------
  // 3) Underflow protection: a read request while EMPTY must not advance the
  //    read pointer, or the FIFO would hand back stale/garbage data.
  // -------------------------------------------------------------------------
  property p_no_underflow;
    @(posedge r_clk) disable iff (!rst_n)
      (empty && rd_rq) |=> ($stable(raddr) && $stable(rptr));
  endproperty
  a_no_underflow: assert property (p_no_underflow)
    else $error("CDC-SVA: read pointer advanced while EMPTY (underflow)");

  // -------------------------------------------------------------------------
  // 4) FULL and EMPTY are mutually exclusive for any non-zero depth. Both
  //    flags are computed from a *stale* (synchronized) copy of the opposite
  //    pointer, which makes each one pessimistic - never optimistic - so they
  //    must never overlap.
  // -------------------------------------------------------------------------
  property p_not_full_and_empty;
    @(posedge w_clk) disable iff (!rst_n)
      !(full && empty);
  endproperty
  a_not_full_and_empty: assert property (p_not_full_and_empty)
    else $error("CDC-SVA: FULL and EMPTY asserted simultaneously");

  // -------------------------------------------------------------------------
  // 5) Reset behaviour: an empty FIFO out of reset means EMPTY high, FULL low.
  // -------------------------------------------------------------------------
  property p_reset_empty;
    @(posedge r_clk) (!rst_n) |-> empty;
  endproperty
  a_reset_empty: assert property (p_reset_empty)
    else $error("CDC-SVA: EMPTY not asserted during reset");

  property p_reset_not_full;
    @(posedge w_clk) (!rst_n) |-> !full;
  endproperty
  a_reset_not_full: assert property (p_reset_not_full)
    else $error("CDC-SVA: FULL asserted during reset");

  // -------------------------------------------------------------------------
  // 6) No unknowns on control outputs or pointers once out of reset. An X on a
  //    Gray pointer defeats every other check in this file, so it is worth
  //    catching directly.
  // -------------------------------------------------------------------------
  property p_no_x_full;
    @(posedge w_clk) disable iff (!rst_n) !$isunknown({full, wptr});
  endproperty
  a_no_x_full: assert property (p_no_x_full)
    else $error("CDC-SVA: X on FULL or wptr");

  property p_no_x_empty;
    @(posedge r_clk) disable iff (!rst_n) !$isunknown({empty, rptr});
  endproperty
  a_no_x_empty: assert property (p_no_x_empty)
    else $error("CDC-SVA: X on EMPTY or rptr");

  // rdata only carries meaning on a cycle that actually performs a read
  property p_no_x_rdata;
    @(posedge r_clk) disable iff (!rst_n)
      (rd_rq && !empty) |-> !$isunknown(rdata);
  endproperty
  a_no_x_rdata: assert property (p_no_x_rdata)
    else $error("CDC-SVA: X on RDATA during an active read");

  // -------------------------------------------------------------------------
  // Cover properties - proof that the interesting corners were actually
  // reached, not just that nothing failed.
  // -------------------------------------------------------------------------
  c_full:          cover property (@(posedge w_clk) disable iff (!rst_n) full);
  c_empty:         cover property (@(posedge r_clk) disable iff (!rst_n) empty);
  c_full_release:  cover property (@(posedge w_clk) disable iff (!rst_n) full  ##1 !full);
  c_empty_release: cover property (@(posedge r_clk) disable iff (!rst_n) empty ##1 !empty);
  c_write_at_full: cover property (@(posedge w_clk) disable iff (!rst_n) (wr_rq && full));
  c_read_at_empty: cover property (@(posedge r_clk) disable iff (!rst_n) (rd_rq && empty));
  c_concurrent_rw: cover property (@(posedge w_clk) disable iff (!rst_n)
                                     (wr_rq && !full && rd_rq && !empty));

endmodule
