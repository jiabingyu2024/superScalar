# 当前版本定型文档索引

本文档集记录 2026-07-08 当前仓库版本的 RTL、Verilator 仿真框架、Vivado Tcl 工程和文件级可综合性审查结论。

本轮按用户要求只做文件级审查和文档整理，没有调用 Vivado，也没有重新运行综合。这里的“可综合”结论表示：从 RTL/Tcl/XDC 文件结构看，主设计路径具备综合条件；最终仍应以后续 Vivado `synth_1` 实际结果为准。

## 文档列表

| 文档 | 内容 |
|---|---|
| [current_version_overview.md](current_version_overview.md) | 当前版本总览、入口、已知测试结果和定型边界。 |
| [rtl_frozen_design.md](rtl_frozen_design.md) | RTL 层级、CPU/SoC/IP 接口、内存映射、关键设计取舍和风险点。 |
| [simulation_frozen_design.md](simulation_frozen_design.md) | Verilator 构建入口、src 判定逻辑、JSON 结果格式和误判边界。 |
| [fpga_tcl_project_review.md](fpga_tcl_project_review.md) | Vivado Tcl 工程创建流程、IP 参数、XDC 覆盖和 Tcl 审查结论。 |
| [synthesizability_static_review.md](synthesizability_static_review.md) | 当前 RTL/Tcl 的文件级可综合性审查、已确认项、未确认项和 tape-out 前自检清单。 |

## 当前定型结论

1. 当前可交付主路径是 `top -> student_top -> myCPU -> riscv_cpu`。
2. 当前 CPU 实现不是乱序/超标量实现，而是面向 SRC 测试稳定通过的单发射阻塞式实现：取指带简单 BTB 预取，Load/MulDiv 会阻塞等待。
3. 仿真框架以 `student_top` 为 src 类 DUT，`srcWithMext/srcWithoutMext` 的最终判定已经从单纯 LED 值扩展为：最终对号/错号标记、右侧 8 灯 mask、SEG 高位计数共同判断。
4. FPGA Tcl 会创建真实 Vivado IP：`pll/IROM_0/DRAM_0/MUL_0/DIV_0`，不会把 `rtl/ip` 的仿真模型加入 FPGA 工程。
5. 文件级可综合审查没有发现主路径上的明显不可综合语句；但本轮未运行 Vivado，因此不能替代 `synth_1` 日志。

## 建议冻结使用的命令

```sh
make verilator-build-src BUILD_JOBS=1
python3 scripts/run_verilator.py src --test srcSmoke --no-build
python3 scripts/run_verilator.py src --test srcWithMext --max-cycles 2000000000 --no-build
```

FPGA 工程创建命令：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
vivado fpga/build/digital_twin_srcSmoke/digital_twin.xpr
```

注意：当前 Tcl 只创建工程和 IP，并设置综合/实现 run 属性；它不自动执行综合和实现。
