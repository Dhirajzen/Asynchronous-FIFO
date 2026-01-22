# Asynchronous FIFO (CDC-Safe) - Gray Pointers + 2FF Synchronizers

A parameterized **dual-clock asynchronous FIFO** in SystemVerilog with:
- Independent **write clock** and **read clock**
- **Gray-code read/write pointers** to reduce CDC risk
- **Two-flop synchronizers** for pointer crossing (R→W and W→R)
- **Full/Empty flag generation** using synchronized Gray pointers
- Simple self-checking testbench + **VCD waveform dump**

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
- `testbench.sv` - Dual-clock testbench + reference queue + VCD dump

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

## Testbench (`testbench.sv`)

The testbench:
- Generates two clocks:
  - `w_clk` period 10
  - `r_clk` period 20
- Performs writes and reads while observing `full` and `empty`
- Uses a **SystemVerilog queue** as a lightweight reference model
- Dumps waveforms:
  - Output file: `fifo.vcd`

### Expected Behavior
- No write should occur when `full == 1`
- No read should occur when `empty == 1`
- Data should be read out in the same order it was written (FIFO ordering)

