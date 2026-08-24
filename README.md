# Asynchronous FIFO (CDC) - Gray Pointers + 2FF Synchronizers

A parameterized **dual-clock asynchronous FIFO** in SystemVerilog with:
- Independent **write clock** and **read clock**
- **Gray-code read/write pointers** to reduce CDC risk
- **Two-flop synchronizers** for pointer crossing (R→W and W→R)
- **Full/Empty flag generation** using synchronized Gray pointers
- **SVA assertion suite** (`bind`-attached, so the RTL stays synthesis-clean) covering
  Gray-code integrity, two-flop synchronizer latency, and overflow/underflow protection
- **Self-checking testbench** sweeping five write/read clock ratios with a
  reference-queue scoreboard and an earned pass/fail verdict

---

## Design Overview

In an async FIFO, the **read and write pointers live in different clock domains**. This design:
1. Maintains **binary pointers** locally for address indexing
2. Converts pointers to **Gray code** for safe multi-bit CDC transfer
3. Synchronizes Gray pointers using **2FF synchronizers**
4. Computes:
   - **FULL** in the write domain using synchronized read pointer
   - **EMPTY** in the read domain using synchronized write pointer

---

## File Layout

- `top.sv` - Top-level FIFO integration (connects memory, sync, full/empty logic)
- `fifo_mem.sv` - FIFO memory array (write in W domain, read in R domain)
- `sync_r2w.sv` - 2FF synchronizer (read pointer Gray → write clock domain)
- `sync_w2r.sv` - 2FF synchronizer (write pointer Gray → read clock domain)
- `wfull.sv` - Write pointer + FULL detection logic
- `empty.sv` - Read pointer + EMPTY detection logic
- `fifo_sva.sv` - Assertion checker for the FIFO (Gray integrity, overflow/underflow, flag rules)
- `sync_sva.sv` - Assertion checker for a two-flop CDC synchronizer
- `bind_sva.sv` - `bind` statements attaching both checkers to the RTL
- `testbench.sv` - Dual-clock self-checking testbench + reference-queue scoreboard
- `filelist.f` / `Makefile` - Build and run infrastructure (VCS / Xcelium / Questa)

---

## Top-Level Interface (`top.sv`)

### Key Signals
- `w_clk`,`r_clk` - independent write/read clocks
- `rst_n` - active-low reset
- `wr_rq` - write request (write domain)
- `rd_rq` - read request (read domain)
- `wdata` - write data input
- `rdata` - read data output
- `full` - asserted when FIFO cannot accept more writes
- `empty` - asserted when FIFO has no data to read

---

## Module Breakdown

### 1) `fifo_mem.sv` - Memory Array
- Writes on `w_clk` when `wr_rq && !full`
- Reads from `r_clk` domain when `rd_rq && !empty`
- Stores `DEPTH` entries of width `WIDTH`

### 2) `sync_r2w.sv` - Read Pointer Sync into Write Domain
- Implements a **two flip-flop synchronizer** in the `w_clk` domain
- Synchronizes the **read Gray pointer** into the write domain

### 3) `sync_w2r.sv` - Write Pointer Sync into Read Domain
- Implements a **two flip-flop synchronizer** in the `r_clk` domain
- Synchronizes the **write Gray pointer** into the read domain

### 4) `wfull.sv` - Write Pointer + FULL Flag
- Maintains:
  - local **binary write pointer** (for addressing)
  - **Gray write pointer** (for CDC transfer)
- FULL detection compares the **next write Gray pointer** with the synchronized read Gray pointer using the standard MSB-invert technique

### 5) `empty.sv` - Read Pointer + EMPTY Flag
- Maintains:
  - local **binary read pointer**
  - **Gray read pointer**
- EMPTY detection checks whether the **next read Gray pointer** equals the synchronized write Gray pointer

---

## Assertions (`fifo_sva.sv`, `sync_sva.sv`)

Assertions are kept out of the RTL entirely and attached with `bind`
(`bind_sva.sv`), so every design file still compiles for synthesis unchanged
while the checkers reach internal signals — the Gray pointers, and the first
stage inside each synchronizer — that no module port exposes.

Each property is clocked in the domain that owns the signals it checks:
write-side properties on `w_clk`, read-side on `r_clk`.

**FIFO-level (`fifo_sva.sv`)**

| Assertion | What it proves |
|---|---|
| `a_wptr_gray` / `a_rptr_gray` | Pointers change by at most **one bit per clock**. The entire CDC scheme depends on this: if two bits ever moved together, a synchronizer sampling mid-transition could latch a value that was never actually held. |
| `a_no_overflow` | A write request while `full` never advances the write pointer (no silent overwrite of unread data). |
| `a_no_underflow` | A read request while `empty` never advances the read pointer (no stale/garbage reads). |
| `a_not_full_and_empty` | `full` and `empty` are never asserted together. |
| `a_reset_empty` / `a_reset_not_full` | Reset leaves the FIFO empty, not full. |
| `a_no_x_*` | No X propagates onto the flags, the pointers, or `rdata` during an active read. |

**Synchronizer-level (`sync_sva.sv`, bound onto *both* crossings)**

| Assertion | What it proves |
|---|---|
| `a_stage1` / `a_stage2` | The pipeline is genuinely **two flops deep**, stage by stage — the most common CDC review finding is a "two-flop" synchronizer quietly optimised down to one. |
| `a_two_flop_latency` | End-to-end latency is **exactly two** destination-domain clocks — not fewer (missing flop), not more (staler than the flag logic assumes). |
| `a_sync_gray` | The pointer still looks like Gray code *after* the crossing. |
| `a_no_x` | No X inside the synchronizer pipeline. |

Cover properties record that the interesting corners were actually reached —
`full` asserted, `empty` asserted, write-while-full, read-while-empty,
simultaneous read and write, and both flags releasing again.

---

## Testbench (`testbench.sv`)

A self-checking, multi-scenario testbench:

- **Programmable clocks.** Half-periods are variables, so one run sweeps five
  write/read ratios, including a deliberately **non-harmonic** pair (5.0 ns vs
  3.5 ns) whose phase relationship drifts continuously — that drift sweeps the
  whole range of edge alignments between the domains instead of testing one
  fixed skew.
- **Race-free monitors.** Both monitors sample through clocking blocks with
  `input #1step` (preponed region), so the checker sees exactly the values the
  DUT's own flops acted on and can never race a non-blocking update.
- **Reference-queue scoreboard.** Every accepted write is pushed, every
  performed read is popped and compared, catching data corruption *and*
  ordering violations.
- **Drain check.** Each scenario ends by halting writes, reading flat out, and
  requiring the FIFO to empty — any item written but never returned is a
  failure.

### Scenarios

| Scenario | Ratio (w:r half-period) | Purpose |
|---|---|---|
| balanced 1:1 | 5.0 : 5.0 | baseline random traffic |
| fast write / slow read | 5.0 : 15.0 | drives the **FULL** boundary |
| slow write / fast read | 15.0 : 5.0 | drives the **EMPTY** boundary |
| non-harmonic phase drift | 5.0 : 3.5 | continuously drifting edge alignment |
| FULL boundary hammer | 5.0 : 25.0 | sustained backpressure against `full` |

### Pass criteria

The run reports **PASS** only if it earns it. It fails on any data mismatch,
underflow, residual data after drain, assertion failure, or global timeout —
and also if no traffic was observed, or if `full`/`empty` were never reached
(an untested corner is not a passing corner).

---

## Running

```bash
make vcs        # Synopsys VCS
make xrun       # Cadence Xcelium
make questa     # Siemens Questa
make vcs DUMP=1 # ... and dump waveforms to fifo.vcd
make clean
```

Simulator flags in the `Makefile` may need adjusting for a given site install.

