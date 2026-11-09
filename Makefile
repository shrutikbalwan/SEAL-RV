IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
VERILATOR ?= verilator
BUILD_DIR ?= build

CPU_RTL = hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/rvc_decompress.sv hw/rtl/security/seal_pmp.sv hw/rtl/security/pmp_checker.sv hw/rtl/cpu/cpu_core.sv
BUS_RTL = hw/rtl/bus/wb_error_slave.sv hw/rtl/bus/wb_address_decoder.sv hw/rtl/bus/wb_arbiter.sv hw/rtl/security/wb_firewall.sv hw/rtl/bus/wb_interconnect.sv hw/rtl/bus/wb_cpu_adapter.sv
PERIPHERAL_RTL = hw/rtl/peripherals/wb_uart.sv hw/rtl/peripherals/wb_gpio.sv hw/rtl/peripherals/wb_spi.sv hw/rtl/peripherals/wb_i2c.sv hw/rtl/peripherals/wb_timer.sv hw/rtl/peripherals/wb_watchdog.sv hw/rtl/peripherals/interrupt_controller.sv hw/rtl/peripherals/wb_debug_perf.sv hw/rtl/peripherals/wb_power_ctrl.sv hw/rtl/peripherals/peripheral_subsystem.sv
SECURITY_RTL = hw/rtl/security/seal_pmp.sv hw/rtl/security/pmp_checker.sv hw/rtl/security/wb_firewall.sv

.PHONY: all sim lint synth test-cocotb security-test cpu-pmp-test clean

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
	$(IVERILOG) -g2012 -Wall -s wb_interconnect_tb -o $(BUILD_DIR)/wb_interconnect_tb $(BUS_RTL) hw/tb/wb_interconnect_tb.sv
	$(VVP) $(BUILD_DIR)/wb_interconnect_tb
	$(IVERILOG) -g2012 -Wall -s wb_cpu_adapter_tb -o $(BUILD_DIR)/wb_cpu_adapter_tb $(BUS_RTL) hw/tb/wb_cpu_adapter_tb.sv
	$(VVP) $(BUILD_DIR)/wb_cpu_adapter_tb
	$(IVERILOG) -g2012 -Wall -s memory_subsystem_tb -o $(BUILD_DIR)/memory_subsystem_tb $(CPU_RTL) hw/rtl/bus/wb_cpu_adapter.sv hw/rtl/memory/wb_sram.sv hw/rtl/memory/boot_rom.sv hw/rtl/memory/memory_subsystem.sv hw/tb/memory_subsystem_tb.sv
	$(VVP) $(BUILD_DIR)/memory_subsystem_tb
	$(IVERILOG) -g2012 -Wall -s peripheral_subsystem_tb -o $(BUILD_DIR)/peripheral_subsystem_tb $(PERIPHERAL_RTL) hw/tb/peripheral_subsystem_tb.sv
	$(VVP) $(BUILD_DIR)/peripheral_subsystem_tb
	$(IVERILOG) -g2012 -Wall -s peripheral_cpu_irq_tb -o $(BUILD_DIR)/peripheral_cpu_irq_tb $(CPU_RTL) hw/rtl/bus/wb_cpu_adapter.sv hw/rtl/memory/wb_sram.sv hw/rtl/memory/boot_rom.sv hw/rtl/memory/memory_subsystem.sv $(PERIPHERAL_RTL) hw/tb/peripheral_cpu_irq_tb.sv
	$(VVP) $(BUILD_DIR)/peripheral_cpu_irq_tb
	$(IVERILOG) -g2012 -Wall -s security_tb -o $(BUILD_DIR)/security_tb $(SECURITY_RTL) hw/tb/security_tb.sv
	$(VVP) $(BUILD_DIR)/security_tb
	$(IVERILOG) -g2012 -Wall -s cpu_pmp_tb -o $(BUILD_DIR)/cpu_pmp_tb $(CPU_RTL) hw/tb/cpu_pmp_tb.sv
	$(VVP) $(BUILD_DIR)/cpu_pmp_tb

security-test: | $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s security_tb -o $(BUILD_DIR)/security_tb $(SECURITY_RTL) hw/tb/security_tb.sv
	$(VVP) $(BUILD_DIR)/security_tb

cpu-pmp-test: | $(BUILD_DIR)
	$(IVERILOG) -g2012 -Wall -s cpu_pmp_tb -o $(BUILD_DIR)/cpu_pmp_tb $(CPU_RTL) hw/tb/cpu_pmp_tb.sv
	$(VVP) $(BUILD_DIR)/cpu_pmp_tb

lint:
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module counter hw/rtl/counter.sv
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module cpu_core $(CPU_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module wb_interconnect $(BUS_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module wb_cpu_adapter $(BUS_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module memory_subsystem hw/rtl/memory/wb_sram.sv hw/rtl/memory/boot_rom.sv hw/rtl/memory/memory_subsystem.sv
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module peripheral_subsystem $(PERIPHERAL_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module seal_pmp $(SECURITY_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module pmp_checker $(SECURITY_RTL)
	$(VERILATOR) --lint-only --Wall -Wno-fatal --top-module wb_firewall $(SECURITY_RTL)

synth: | $(BUILD_DIR)
	$(YOSYS) -s scripts/synth.ys

test-cocotb: | $(BUILD_DIR)
	$(MAKE) -f verification/sim/Makefile.cocotb

clean:
	rm -rf $(BUILD_DIR) sim_build *.vcd
