#!/bin/bash
echo "=== SEAL-RV Verification Regression ==="
mkdir -p ../waves

echo "--- Running SystemVerilog Directed Tests ---"
iverilog -g2012 -o cpu_tb_sim ../tb/cpu_tb.sv ../../hw/rtl/cpu/*.sv
vvp cpu_tb_sim -lxt2

echo "--- Running Cocotb Randomized Tests ---"
export MODULE=test_cpu
export TOPLEVEL=cpu_core
export COCOTB_REDUCED_LOG_FMT=1
make -f Makefile.cocotb

echo "=== Regression Complete ==="
