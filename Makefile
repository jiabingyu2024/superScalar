.PHONY: sim-rv32 sim-rv32-all sim-src sim-src-all verilator-build

verilator-build:
	python3 scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only

sim-rv32:
	python3 scripts/run_verilator.py rv32 $(if $(TEST),--test $(TEST),) $(if $(SUITE),--suite $(SUITE),)

sim-rv32-all:
	python3 scripts/run_verilator.py rv32 --all

sim-src:
	python3 scripts/run_verilator.py src $(if $(TEST),--test $(TEST),)

sim-src-all:
	python3 scripts/run_verilator.py src --all
