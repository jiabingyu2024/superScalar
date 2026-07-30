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

.PHONY: sim-rv32 sim-rv32-base sim-rv32-all sim-src sim-src-all sim-rv32-difftest sim-src-difftest verilator-build verilator-build-src difftest-prepare difftest-build difftest-build-src

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

difftest-prepare:
	$(PYTHON) scripts/prepare_difftest_upstream.py

difftest-build:
	$(PYTHON) scripts/run_difftest.py rv32 --test rv32ui-p-simple --build --build-only $(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) $(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),)

difftest-build-src:
	$(PYTHON) scripts/run_difftest.py src --test srcSmoke --build --build-only $(if $(BUILD_JOBS),--build-jobs $(BUILD_JOBS),) $(if $(BUILD_CXX),--build-cxx $(BUILD_CXX),)

sim-rv32-difftest:
	$(PYTHON) scripts/run_difftest.py rv32 $(if $(TEST),--test $(TEST),) $(if $(SUITE),--suite $(SUITE),) $(if $(DIFFTRACE),--difftrace,) $(COMMON_SIM_ARGS)

sim-src-difftest:
	$(PYTHON) scripts/run_difftest.py src $(if $(TEST),--test $(TEST),) $(if $(DIFFTRACE),--difftrace,) $(SRC_SIM_ARGS)
.PHONY: rtthread-images sim-rtthread sim-rtthread-all
.PHONY: rtthread-live-image sim-rtthread-live sim-rtthread-live-all

rtthread-images:
	python3 scripts/build_rtthread_images.py

sim-rtthread:
	python3 scripts/build_rtthread_images.py --test $(TEST)
	python3 scripts/run_verilator.py src --test rtthread-$(TEST) $(if $(NO_BUILD),--no-build,) --max-cycles $(or $(MAX_CYCLES),10000000)

sim-rtthread-all:
	python3 scripts/test_rtthread.py $(if $(NO_BUILD),--no-build-verilator,) --max-cycles $(or $(MAX_CYCLES),10000000)

rtthread-live-image:
	python3 scripts/build_rtthread_images.py --live

sim-rtthread-live:
	python3 scripts/test_rtthread_live.py --scenario $(TEST) $(if $(NO_BUILD),--no-build-verilator,) --max-cycles $(or $(MAX_CYCLES),12000000)

sim-rtthread-live-all:
	python3 scripts/test_rtthread_live.py $(if $(NO_BUILD),--no-build-verilator,) --max-cycles $(or $(MAX_CYCLES),12000000)
