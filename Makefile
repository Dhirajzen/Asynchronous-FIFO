# ---------------------------------------------------------------------------
# Asynchronous FIFO - simulation makefile
#
#   make vcs      compile + run with Synopsys VCS
#   make xrun     compile + run with Cadence Xcelium
#   make questa   compile + run with Siemens Questa
#   make clean    remove build artefacts
#
#   Add DUMP=1 to any run target to dump waveforms to fifo.vcd
#     e.g.  make vcs DUMP=1
#
# Assertions live in sources/fifo_sva.sv and sources/sync_sva.sv and are
# attached to the RTL by simulation/bind_sva.sv - no RTL file contains an
# assertion, so the design compiles for synthesis unchanged.
# ---------------------------------------------------------------------------

TOP      := testbench
FILELIST := filelist.f

PLUSARGS :=
ifdef DUMP
PLUSARGS += +DUMP
endif

.PHONY: help vcs xrun questa clean

help:
	@echo "Targets:"
	@echo "  make vcs     - Synopsys VCS"
	@echo "  make xrun    - Cadence Xcelium"
	@echo "  make questa  - Siemens Questa"
	@echo "  make clean   - remove build artefacts"
	@echo ""
	@echo "Options:"
	@echo "  DUMP=1       - dump waveforms to fifo.vcd"

vcs:
	vcs -full64 -sverilog -timescale=1ns/1ps -assert svaext \
	    -f $(FILELIST) -l compile.log -o simv
	./simv $(PLUSARGS) -l sim.log

xrun:
	xrun -64bit -sv -timescale 1ns/1ps -access +rwc \
	     -f $(FILELIST) $(PLUSARGS) -l xrun.log

questa:
	vlib work
	vlog -sv -f $(FILELIST) -l vlog.log
	vsim -c $(TOP) -voptargs="+acc" $(PLUSARGS) -do "run -all; quit" -l vsim.log

clean:
	rm -rf simv simv.daidir csrc *.log *.vcd *.key vc_hdrs.h \
	       xcelium.d INCA_libs .simvision waves.shm work transcript \
	       novas.* verdiLog DVEfiles
