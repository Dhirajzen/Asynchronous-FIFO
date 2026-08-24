// Compile order: leaf modules, then top, then checkers, then bind + testbench.
// Works with VCS (-f), Xcelium (-f) and Questa (-f).

sources/fifo_mem.sv
sources/wfull.sv
sources/empty.sv
sources/sync_r2w.sv
sources/sync_w2r.sv
sources/top.sv

// Assertion checkers (bound onto the RTL, never instantiated inside it)
sources/fifo_sva.sv
sources/sync_sva.sv

simulation/bind_sva.sv
simulation/testbench.sv
