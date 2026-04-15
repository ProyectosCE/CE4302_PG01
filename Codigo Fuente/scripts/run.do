vlib work
vlog ../src/*.sv
vlog ../tb/*.sv
vsim types_tb
run -all
quit