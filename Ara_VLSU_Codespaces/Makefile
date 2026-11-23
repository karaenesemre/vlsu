.PHONY: sim
sim:
	mkdir -p build
	verilator --binary --timing --trace-fst -Wno-fatal -j 2 --top-module tb_vlsu -Iinclude -f sources.f tb/tb_vlsu.sv --Mdir build/obj
	cd build && ./obj/Vtb_vlsu
	test -s build/vlsu_load_store.fst
