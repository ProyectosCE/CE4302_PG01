SRC_FILES = system_params_pkg.sv model_pkg.sv top.sv
all: run waves

sim: top.sv
	verilator --binary --trace-structs --trace-max-array 128 --trace-fst --timing $(SRC_FILES) --top-module top
run: sim
	./obj_dir/Vtop
waves:
	gtkwave -f waves.fst &
clean:
	rm -rf obj_dir *.fst

.PHONY: all run sim waves clean
