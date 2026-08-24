// ---------------------------------------------------------------------------
// sync_sva.sv - Assertions for a two-flop CDC synchronizer.
//
// Bound onto BOTH sync_r2w and sync_w2r (see simulation/bind_sva.sv). The bind
// statement reaches the internal first-stage flop of each synchronizer, so the
// two-flop pipeline can be proven stage by stage rather than assumed.
//
// W is the full pointer width ($clog2(DEPTH)+1), not the address width.
// ---------------------------------------------------------------------------
module sync_sva #(
    parameter int W = 5
)(
    input logic         clk,
    input logic         rst_n,
    input logic [W-1:0] din,    // pointer arriving from the other clock domain
    input logic [W-1:0] sync1,  // first  synchronizer stage (metastability catcher)
    input logic [W-1:0] sync2   // second synchronizer stage (safe to use)
);

  // -------------------------------------------------------------------------
  // Stage-by-stage pipeline behaviour. Together these prove the synchronizer
  // is genuinely two flops deep - the single most common CDC review finding is
  // a "two-flop" synchronizer that has quietly been optimised down to one.
  // -------------------------------------------------------------------------
  property p_stage1;
    @(posedge clk) disable iff (!rst_n) sync1 == $past(din);
  endproperty
  a_stage1: assert property (p_stage1)
    else $error("CDC-SVA: synchronizer stage 1 did not capture din");

  property p_stage2;
    @(posedge clk) disable iff (!rst_n) sync2 == $past(sync1);
  endproperty
  a_stage2: assert property (p_stage2)
    else $error("CDC-SVA: synchronizer stage 2 did not capture stage 1");

  // -------------------------------------------------------------------------
  // End-to-end latency: exactly two destination-domain clocks, no more, no
  // less. A shorter latency means a missing flop; a longer one means the
  // full/empty comparison is working off data staler than the design assumes.
  // -------------------------------------------------------------------------
  property p_two_flop_latency;
    @(posedge clk) disable iff (!rst_n) sync2 == $past(din, 2);
  endproperty
  a_two_flop_latency: assert property (p_two_flop_latency)
    else $error("CDC-SVA: synchronizer latency is not exactly two clocks");

  // -------------------------------------------------------------------------
  // The synchronized pointer must still look like Gray code on this side of
  // the crossing. If more than one bit ever moves at once downstream, the
  // crossing has corrupted the pointer.
  // -------------------------------------------------------------------------
  property p_sync_gray;
    @(posedge clk) disable iff (!rst_n) $onehot0(sync2 ^ $past(sync2));
  endproperty
  a_sync_gray: assert property (p_sync_gray)
    else $error("CDC-SVA: synchronized pointer changed by more than one bit (now %b)", sync2);

  // -------------------------------------------------------------------------
  // No unknowns propagating through the crossing after reset.
  // -------------------------------------------------------------------------
  property p_no_x;
    @(posedge clk) disable iff (!rst_n) !$isunknown({sync1, sync2});
  endproperty
  a_no_x: assert property (p_no_x)
    else $error("CDC-SVA: X inside the synchronizer pipeline");

  // Proof that the pointer actually moved during the run - a synchronizer that
  // never sees a transition has not been exercised at all.
  c_sync_toggles: cover property (@(posedge clk) disable iff (!rst_n)
                                    sync2 != $past(sync2));

endmodule
