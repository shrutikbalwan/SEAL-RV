yosys -import
read_verilog -sv hw/rtl/counter.sv
hierarchy -check -top counter
proc; opt; fsm; opt; memory; opt; techmap; opt; abc -g cmos2; opt; clean
write_verilog synth_counter.v
stat
