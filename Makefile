IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
VERILATOR ?= verilator
BUILD_DIR ?= build

CPU_RTL = hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/rvc_decompress.sv hw/rtl/cpu/cpu_core.sv

.PHONY: all sim lint synth test-cocotb clean

all: sim test-cocotb lint synth

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

sim: | $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s counter_tb -o $(BUILD_DIR)/counter_tb hw/rtl/counter.sv hw/tb/counter_tb.sv
	$(VVP) $(BUILD_DIR)/counter_tb
	$(IVERILOG) -g2012 -Wall -s cpu_tb -o $(BUILD_DIR)/cpu_tb $(CPU_RTL) verification/tb/cpu_tb.sv
	$(VVP) $(BUILD_DIR)/cpu_tb
	$(IVERILOG) -g2012 -Wall -s cpu_tb -o $(BUILD_DIR)/cpu_hex_tb $(CPU_RTL) hw/tb/cpu_tb.sv
	$(VVP) $(BUILD_DIR)/cpu_hex_tb

lint:
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module counter hw/rtl/counter.sv
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module cpu_core $(CPU_RTL)

synth: | $(BUILD_DIR)
	$(YOSYS) -s scripts/synth.ys

test-cocotb: | $(BUILD_DIR)
	$(MAKE) -f verification/sim/Makefile.cocotb

clean:
	rm -rf $(BUILD_DIR) sim_build *.vcd
