RTL = hw/rtl/counter.sv
TB = hw/tb/counter_tb.sv
SIM_EXEC = simv

all: sim synth

sim:
	iverilog -g2012 -o $(SIM_EXEC) $(RTL) $(TB)
	vvp $(SIM_EXEC)

synth:
	yosys -c scripts/synth_counter.tcl

clean:
	rm -f $(SIM_EXEC) *.vcd *.log synth_counter.v
