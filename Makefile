# ===========================================================================
# Icarus Verilog simulation flow
#
#   make run     compile RTL + testbench and run the simulation
#   make waves   run, then open the waveform in GTKWave
#   make clean   remove the sim/ build directory
# ===========================================================================

TOP      = apb_master_tb
RTL      = rtl/apb_master.v
TB       = tb/apb_master_tb.v

SIMDIR   = sim
OUT      = $(SIMDIR)/$(TOP).vvp
VCD      = $(SIMDIR)/$(TOP).vcd
LOG      = $(SIMDIR)/sim.log

IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave
IVFLAGS  = -g2012 -Wall

.PHONY: all run waves clean

all: run

$(SIMDIR):
	mkdir -p $(SIMDIR)

$(OUT): $(RTL) $(TB) | $(SIMDIR)
	$(IVERILOG) $(IVFLAGS) -o $(OUT) $(TB) $(RTL)

run: $(OUT)
	$(VVP) $(OUT) | tee $(LOG)

waves: run
	$(GTKWAVE) $(VCD) &

clean:
	rm -rf $(SIMDIR)
