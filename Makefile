PYTHON ?= python3
SRC_MAX_CYCLES ?= 100000000
CPU_FREQ_MHZ ?= 50

COMMON_SIM_ARGS = \
	$(if $(MAX_CYCLES),--max-cycles $(MAX_CYCLES),) \
	$(if $(TRACE),--trace,) \
	$(if $(BUILD),--build,) \
	$(if $(NO_BUILD),--no-build,) \
	$(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) \
	$(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),)

SRC_SIM_ARGS = \
	$(if $(MAX_CYCLES),--max-cycles $(MAX_CYCLES),--max-cycles $(SRC_MAX_CYCLES)) \
	$(if $(TRACE),--trace,) \
	$(if $(BUILD),--build,) \
	$(if $(NO_BUILD),--no-build,) \
	$(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) \
	$(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),) \
	--cpu-freq-mhz $(CPU_FREQ_MHZ) \
	$(if $(SRC_SEG_GRACE),--src-seg-grace $(SRC_SEG_GRACE),)

.PHONY: sim-rv32 sim-rv32-base sim-rv32-all sim-src sim-src-all verilator-build verilator-build-src

verilator-build:
	$(PYTHON) scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only $(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) $(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),)

verilator-build-src:
	$(PYTHON) scripts/run_verilator.py src --test srcSmoke --build --build-only $(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) $(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),)

sim-rv32:
	$(PYTHON) scripts/run_verilator.py rv32 $(if $(TEST),--test $(TEST),) $(if $(SUITE),--suite $(SUITE),) $(COMMON_SIM_ARGS)

sim-rv32-base:
	$(MAKE) sim-rv32 SUITE=rv32ui $(if $(NO_BUILD),NO_BUILD=$(NO_BUILD),) $(if $(MAX_CYCLES),MAX_CYCLES=$(MAX_CYCLES),)
	$(MAKE) sim-rv32 SUITE=rv32mi NO_BUILD=1 $(if $(MAX_CYCLES),MAX_CYCLES=$(MAX_CYCLES),)
	$(MAKE) sim-rv32 SUITE=rv32um NO_BUILD=1 $(if $(MAX_CYCLES),MAX_CYCLES=$(MAX_CYCLES),)

sim-rv32-all:
	$(PYTHON) scripts/run_verilator.py rv32 --all $(COMMON_SIM_ARGS)

sim-src:
	$(PYTHON) scripts/run_verilator.py src $(if $(TEST),--test $(TEST),) $(SRC_SIM_ARGS)

sim-src-all:
	$(PYTHON) scripts/run_verilator.py src --all $(SRC_SIM_ARGS)
