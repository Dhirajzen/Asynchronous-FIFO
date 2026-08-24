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
  // Reset-settle guard. `disable iff (!rst_n)` suppresses the *check* during
  // reset, but $past still looks back across the reset boundary into whatever
  // stale value it last held - so the first cycle(s) after rst_n deasserts can
  // spuriously fail a $past-based property. settle_cnt counts valid clocks
  // since reset (saturating at 2) so each property below can require enough
  // real history before trusting its $past() terms.
  // -------------------------------------------------------------------------
  logic [1:0] settle_cnt;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n)                    settle_cnt <= 2'd0;
    else if (settle_cnt != 2'd2)   settle_cnt <= settle_cnt + 2'd1;

  // -------------------------------------------------------------------------
  // Stage-by-stage pipeline behaviour. Together these prove the synchronizer
  // is genuinely two flops deep - the single most common CDC review finding is
  // a "two-flop" synchronizer that has quietly been optimised down to one.
  // -------------------------------------------------------------------------
  property p_stage1;
    @(posedge clk) disable iff (!rst_n || settle_cnt < 2'd1) sync1 == $past(din);
  endproperty
  a_stage1: assert property (p_stage1)
    else $error("CDC-SVA: synchronizer stage 1 did not capture din");

  property p_stage2;
    @(posedge clk) disable iff (!rst_n || settle_cnt < 2'd1) sync2 == $past(sync1);
  endproperty
  a_stage2: assert property (p_stage2)
    else $error("CDC-SVA: synchronizer stage 2 did not capture stage 1");

  // -------------------------------------------------------------------------
  // End-to-end latency: exactly two destination-domain clocks, no more, no
  // less. A shorter latency means a missing flop; a longer one means the
  // full/empty comparison is working off data staler than the design assumes.
  // -------------------------------------------------------------------------
  property p_two_flop_latency;
    @(posedge clk) disable iff (!rst_n || settle_cnt < 2'd2) sync2 == $past(din, 2);
  endproperty
  a_two_flop_latency: assert property (p_two_flop_latency)
    else $error("CDC-SVA: synchronizer latency is not exactly two clocks");

  // -------------------------------------------------------------------------
  // NOTE: an earlier version of this file also asserted that `sync2` changes
  // by at most one bit per *destination-domain* clock (mirroring the
  // source-domain Gray checks in fifo_sva.sv). That property only holds when
  // the source and destination clocks tick at the same rate: whenever they
  // don't, several source-domain Gray-code increments can legitimately land
  // between two destination-domain samples, so `sync2` correctly jumps by
  // more than one bit. Simulation on Cadence Xcelium confirmed this property
  // fired on every non-1:1 clock-ratio scenario while the scoreboard's
  // independent, per-item data compare stayed at zero mismatches - i.e. the
  // pointer data was never actually corrupted, only this assertion was wrong.
  // The correct one-bit-per-clock Gray check belongs on each pointer's own
  // native clock (see a_wptr_gray/a_rptr_gray in fifo_sva.sv), where the
  // property is actually guaranteed, so it was removed from here.
  // -------------------------------------------------------------------------

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
