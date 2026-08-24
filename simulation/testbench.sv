`timescale 1ns/1ps
// ---------------------------------------------------------------------------
// testbench.sv - Self-checking testbench for the asynchronous FIFO.
//
// Structure:
//   * Programmable clock generators, so one run sweeps several write/read
//     frequency ratios (including a deliberately non-harmonic pair whose phase
//     relationship drifts continuously - that drift sweeps the full range of
//     edge alignments between the two domains rather than testing one fixed
//     skew).
//   * Passive monitors sampling in the preponed region via clocking blocks, so
//     the checker can never race the DUT's non-blocking updates.
//   * A reference queue acting as a scoreboard: every accepted write is pushed,
//     every performed read is popped and compared.
//   * A pass condition that requires evidence. The run FAILS on any data
//     mismatch, on underflow, on residual data after drain, on timeout, or if
//     no traffic was observed at all.
// ---------------------------------------------------------------------------
module testbench;

  localparam int WIDTH = 8;
  localparam int DEPTH = 16;

  logic             w_clk = 1'b0;
  logic             r_clk = 1'b0;
  logic             rst_n;
  logic             wr_rq;
  logic             rd_rq;
  logic [WIDTH-1:0] wdata;
  logic             full;
  logic             empty;
  logic [WIDTH-1:0] rdata;

  top #(WIDTH, DEPTH) dut (.*);

  // -------------------------------------------------------------------------
  // Programmable clocks. Half-periods are variables so a scenario can retune
  // the write/read ratio between phases of the same simulation.
  // -------------------------------------------------------------------------
  real w_half = 5.0;
  real r_half = 5.0;

  initial forever #(w_half) w_clk = ~w_clk;
  initial forever #(r_half) r_clk = ~r_clk;

  // -------------------------------------------------------------------------
  // Scoreboard state
  // -------------------------------------------------------------------------
  logic [WIDTH-1:0] model [$];        // reference FIFO
  logic [WIDTH-1:0] exp_data;

  int n_wr;                            // writes accepted by the DUT
  int n_rd;                            // reads performed and checked
  int n_err;                           // scoreboard + testbench errors
  int n_full_seen;                     // cycles observed with FULL asserted
  int n_empty_seen;                    // cycles observed with EMPTY asserted

  bit mon_en;                          // monitors active
  bit wr_en;                           // write stimulus active
  bit rd_en;                           // read stimulus active
  int wr_pct;                          // write-request probability, percent
  int rd_pct;                          // read-request probability, percent

  // -------------------------------------------------------------------------
  // Preponed sampling. `input #1step` samples the value that existed just
  // before the clock edge - exactly the value the DUT's own flops acted on.
  // This is what makes the monitors immune to NBA ordering.
  // -------------------------------------------------------------------------
  clocking wmon @(posedge w_clk);
    default input #1step;
    input rst_n, wr_rq, wdata, full;
  endclocking

  clocking rmon @(posedge r_clk);
    default input #1step;
    input rst_n, rd_rq, rdata, empty;
  endclocking

  // -------------------------------------------------------------------------
  // Write monitor: the DUT commits a write exactly when wr_rq && !full.
  // -------------------------------------------------------------------------
  always @(wmon) begin
    if (mon_en && wmon.rst_n) begin
      if (wmon.full) n_full_seen++;
      if (wmon.wr_rq && !wmon.full) begin
        model.push_back(wmon.wdata);
        n_wr++;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Read monitor + checker: the DUT presents the head combinationally and
  // advances the pointer at the edge, so the data consumed on this edge is the
  // preponed value of rdata.
  // -------------------------------------------------------------------------
  always @(rmon) begin
    if (mon_en && rmon.rst_n) begin
      if (rmon.empty) n_empty_seen++;
      if (rmon.rd_rq && !rmon.empty) begin
        if (model.size() == 0) begin
          n_err++;
          $error("[SCB] Underflow: DUT returned 0x%02h but the reference FIFO is empty",
                 rmon.rdata);
        end
        else begin
          exp_data = model.pop_front();
          if (rmon.rdata !== exp_data) begin
            n_err++;
            $error("[SCB] Data mismatch on read #%0d: exp=0x%02h got=0x%02h",
                   n_rd, exp_data, rmon.rdata);
          end
        end
        n_rd++;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Stimulus. Requests are randomised per cycle; the DUT's own full/empty
  // flags decide what is actually accepted, and the monitors record the truth.
  // -------------------------------------------------------------------------
  always @(posedge w_clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_rq <= 1'b0;
      wdata <= '0;
    end
    else if (wr_en) begin
      wr_rq <= ($urandom_range(99) < wr_pct);
      wdata <= $urandom_range((1 << WIDTH) - 1);
    end
    else begin
      wr_rq <= 1'b0;
    end
  end

  always @(posedge r_clk or negedge rst_n) begin
    if (!rst_n)          rd_rq <= 1'b0;
    else if (rd_en)      rd_rq <= ($urandom_range(99) < rd_pct);
    else                 rd_rq <= 1'b0;
  end

  // -------------------------------------------------------------------------
  // One scenario: reset, run randomised traffic at the given clock ratio and
  // request rates, then drain the FIFO and prove nothing was lost.
  // -------------------------------------------------------------------------
  task automatic run_scenario(input string name,
                              input real   wh,
                              input real   rh,
                              input int    wpct,
                              input int    rpct,
                              input int    n_cycles);
    int drain_limit;

    $display("\n--- Scenario: %s  (w_half=%0.1fns  r_half=%0.1fns  wr=%0d%%  rd=%0d%%) ---",
             name, wh, rh, wpct, rpct);

    // Quiesce and reset before retuning the clocks.
    wr_en  = 1'b0;
    rd_en  = 1'b0;
    mon_en = 1'b0;
    rst_n  = 1'b0;
    wr_pct = 0;
    rd_pct = 0;
    model.delete();

    w_half = wh;
    r_half = rh;

    repeat (5) @(posedge w_clk);
    @(negedge w_clk);
    rst_n = 1'b1;
    repeat (2) @(posedge w_clk);

    // Traffic phase
    wr_pct = wpct;
    rd_pct = rpct;
    mon_en = 1'b1;
    wr_en  = 1'b1;
    rd_en  = 1'b1;
    repeat (n_cycles) @(posedge w_clk);

    // Drain phase: stop writing FIRST and let the shutdown settle on the
    // write-clock domain before trusting model.size() for drain completion.
    // wr_en is a boolean gate (not a probability), so once the generator has
    // sampled it low, no further writes can be accepted - but the edge that
    // flips it races against the generator's own read of the *old* wr_pct on
    // this same w_clk edge (two processes woken by the same edge have no
    // guaranteed relative order in SystemVerilog). Waiting two more w_clk
    // cycles guarantees that race has resolved and any write still in flight
    // has completed, so nothing new can land in `model` after this point.
    wr_en  = 1'b0;
    wr_pct = 0;
    repeat (2) @(posedge w_clk);

    // Read flat out and require the FIFO to actually empty. Reads (rd_en)
    // stay live for the entire wait, unlike the old shared-enable version
    // that could cut reads off before every write was drained.
    rd_pct = 100;
    drain_limit = (n_cycles * 4) + 500;

    fork
      begin : drain_done
        while (!(empty && (model.size() == 0))) @(posedge r_clk);
      end
      begin : drain_timeout
        repeat (drain_limit) @(posedge r_clk);
        n_err++;
        $error("[TB] Scenario '%s': drain did not complete (%0d entries still expected, empty=%0b)",
               name, model.size(), empty);
      end
    join_any
    disable fork;

    rd_en = 1'b0;
    repeat (4) @(posedge r_clk);
    mon_en = 1'b0;

    if (model.size() != 0) begin
      n_err++;
      $error("[TB] Scenario '%s': %0d written item(s) never came back out",
             name, model.size());
    end

    $display("    writes=%0d  reads=%0d  cumulative errors=%0d", n_wr, n_rd, n_err);
  endtask

  // -------------------------------------------------------------------------
  // Final report. A pass has to be earned: traffic must have happened, the
  // FULL and EMPTY corners must have been reached, and nothing may have failed.
  // -------------------------------------------------------------------------
  task automatic report_and_finish();
    $display("\n==================== SUMMARY ====================");
    $display("  writes accepted   : %0d", n_wr);
    $display("  reads  checked    : %0d", n_rd);
    $display("  FULL  observed    : %0d cycles", n_full_seen);
    $display("  EMPTY observed    : %0d cycles", n_empty_seen);
    $display("  errors            : %0d", n_err);
    $display("================================================");

    if (n_wr == 0 || n_rd == 0) begin
      $display("  RESULT: FAIL - no traffic observed; a silent pass is not a pass");
      $fatal(1, "no traffic observed");
    end
    if (n_full_seen == 0) begin
      $display("  RESULT: FAIL - FULL was never reached, the overflow corner went untested");
      $fatal(1, "FULL never asserted");
    end
    if (n_empty_seen == 0) begin
      $display("  RESULT: FAIL - EMPTY was never reached, the underflow corner went untested");
      $fatal(1, "EMPTY never asserted");
    end
    if (n_err != 0) begin
      $display("  RESULT: FAIL - %0d error(s)", n_err);
      $fatal(1, "scoreboard errors");
    end

    $display("  RESULT: PASS");
    $finish;
  endtask

  // -------------------------------------------------------------------------
  // Main sequence
  // -------------------------------------------------------------------------
  initial begin
    // wr_rq / rd_rq / wdata are driven exclusively by the stimulus always
    // blocks below - their asynchronous reset branch clears them at time 0, so
    // initialising them here too would put two processes on the same variable.
    rst_n  = 1'b0;
    wr_en  = 1'b0;
    rd_en  = 1'b0;
    mon_en = 1'b0;

    //             name                    w_half r_half  wr%  rd%  cycles
    run_scenario("balanced 1:1",             5.0,   5.0,   50,  50,  400);
    run_scenario("fast write / slow read",   5.0,  15.0,   90,  20,  400);
    run_scenario("slow write / fast read",  15.0,   5.0,   20,  90,  400);
    run_scenario("non-harmonic phase drift", 5.0,   3.5,   60,  60,  600);
    run_scenario("FULL boundary hammer",     5.0,  25.0,  100,   5,  300);

    report_and_finish();
  end

  // -------------------------------------------------------------------------
  // Global watchdog. Note the polarity: a timeout is a FAILURE. The previous
  // version of this testbench printed SUCCESS on a timer, which meant it
  // reported a pass whether or not anything had been verified.
  // -------------------------------------------------------------------------
  initial begin
    #2_000_000;
    $display("\n  RESULT: FAIL - global timeout, simulation never completed");
    $fatal(1, "global timeout");
  end

  // -------------------------------------------------------------------------
  // Optional waveform dump: run with +DUMP
  // -------------------------------------------------------------------------
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("fifo.vcd");
      $dumpvars(0, testbench);
    end
  end

endmodule
