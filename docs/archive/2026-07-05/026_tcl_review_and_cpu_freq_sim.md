# Vivado Tcl 审查与 src CPU 频率仿真参数记录

## 背景

用户要求审查当前 `fpga/create_vivado_project.tcl` 是否正确，并要求 src 类 Verilator 仿真默认 CPU core 频率为 50MHz、可通过 make 参数修改；SoC 部分的 50MHz counter/display 时钟保持不变。

## Tcl 静态审查结论

确定问题：

1. 原 Tcl 只查找 `fpga/constraints/digital_twin.xdc`，但当前仓库已有约束文件是 `fpga/digital_twin.xdc`。
2. 原 Tcl 只查找 `fpga/coe/<profile>/`，但当前可用 COE 在 `data/<profile>/`。
3. `MUL_0/DIV_0` 的 `CONFIG.*` 属性直接硬编码，Vivado 版本属性名差异时诊断不清楚。

本次修正：

1. COE 查找改为优先 `fpga/coe/<profile>/`，找不到则使用 `data/<profile>/`。
2. XDC 查找改为优先 `fpga/constraints/digital_twin.xdc`，找不到则使用 `fpga/digital_twin.xdc`。
3. 新增 `set_ip_config_required`，对影响 RTL 契约的 IP 属性做严格命中校验。
4. 新增 `set_ip_config_optional`，对 `MUL_0` 的 speed 优化目标做可选设置，避免非契约属性因版本差异阻塞工程创建。

未执行 Vivado。用户明确要求不用执行 Vivado；因此 IP 属性名仍属于静态审查结果，后续如果 Vivado 报属性不存在，应使用 `report_property [get_ips <IP>]` 对齐当前版本属性名。

## src 仿真频率修改

新增 Makefile 变量：

```sh
CPU_FREQ_MHZ ?= 50
```

用法：

```sh
make sim-src TEST=srcSmoke CPU_FREQ_MHZ=150
```

实现边界：

1. `main_student_top.cpp` 改为双时钟事件推进。
2. `w_cpu_clk` 按 `CPU_FREQ_MHZ` 翻转。
3. `w_clk_50Mhz` 始终按 50MHz 翻转。
4. `MemoryModel` 的 counter mirror 分成 request 推进和 counter clock 推进，避免 CPU 变频时错误改变 SoC counter 速度。
5. JSON 新增 `perf.cpu_freq_mhz`、`perf.elapsed_ms_by_cpu_freq`、`perf.soc_counter_freq_mhz`。

## 验证记录

已运行：

```sh
make verilator-build BUILD_JOBS=4
make verilator-build-src BUILD_JOBS=4
make sim-rv32 TEST=rv32ui-p-simple MAX_CYCLES=30000 NO_BUILD=1
make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1
make sim-src TEST=srcSmoke MAX_CYCLES=10000 CPU_FREQ_MHZ=150 NO_BUILD=1
make sim-src TEST=srcSmoke MAX_CYCLES=200000 CPU_FREQ_MHZ=150 NO_BUILD=1
```

结果：

1. rv32/myCPU 和 src/student_top Verilator 构建通过。
2. `rv32ui-p-simple` PASS。
3. `srcSmoke` 10000 周期短跑按预期 TIMEOUT，默认 50MHz 下 `elapsed_ms_by_cpu_freq=0.2`。
4. `srcSmoke` 10000 周期、150MHz 下 `elapsed_ms_by_cpu_freq=0.0666667`。
5. `srcSmoke` 200000 周期、150MHz 下 `elapsed_ms_by_cpu_freq=1.33333`，SoC counter ms 为 `1`，说明 CPU 频率换算和 SoC 50MHz counter 已解耦。

## 注意事项

1. 并行运行同一个 src test 会写同一个 `build/result/src/<test>.json`，结果文件会互相覆盖；对比不同频率时应顺序运行或改结果路径。
2. `correctness.counter.ms` 仍是 SoC counter 显示值，不是 CPU 频率换算值。
3. `perf.elapsed_ms_by_cpu_freq` 是性能分析用的 CPU 周期换算值。
