# 项目工程框架

## 仓库定位

本仓库定位为一个完整流程的简单超标量处理器项目：

1. 固定支持 RV32 + M 扩展的 CPU RTL 设计。
2. 基于 Verilator 的正确性与性能仿真。
3. 基于赛事 SoC 模板的 FPGA 上板集成。

当前阶段的优先级是先建立稳定、可维护、可复现的工程与调试框架，再进入 core RTL bug 修复。

## 目录职责

| 路径 | 职责 |
| --- | --- |
| `rtl/core/` | CPU 裸核和赛事 CPU 接口适配层 `myCPU`。core RTL 不应依赖 FPGA IP 具体实现。 |
| `rtl/soc/` | 赛事 SoC 壳、外设桥、UART/display glue、FPGA 顶层集成逻辑。 |
| `rtl/ip/` | 生成型 FPGA IP 的仿真行为模型。允许修改实现，但对外端口和行为必须与上板 IP 保持一致。 |
| `data/` | 测试输入。缺失的 `.hex/.dump` 等生成物直接补在原测试目录下。 |
| `tb/` | 后续 Verilator testbench 源码。主正确性 DUT 使用 `myCPU`，`student_top` 只作为 SoC smoke DUT。 |
| `scripts/` | 构建辅助脚本和稳定 filelist。后续 Makefile 仍作为用户可见入口。 |
| `build/` | 编译中间文件、日志、波形、结果汇总等生成物，必须被 git 忽略。 |
| `docs/design/` | 当前设计事实和工程约定。设计事实变化时必须维护。 |
| `docs/sim/` | 仿真使用方式、测试数据规则、debug 流程。 |
| `docs/fpga/` | FPGA/Vivado 流程说明。 |
| `docs/debug/` | 具体 bug 的定位和修复记录。 |
| `docs/archive/` | 按时间归档的重要修改记录。 |
| `fpga/` | 上板脚本和约束。Tcl 流程应适配当前仓库结构，不反向要求移动 `data/` 或 `fpga/` 文件。 |

## 受保护文件

`rtl/soc/counter.sv` 是赛事评价相关逻辑，默认禁止修改。除非用户明确授权，否则后续工作只能读取和引用该文件。

## 后续行动规约

1. Verilator 主正确性/性能 DUT 固定为 `myCPU`。
2. `student_top` 只在 `myCPU` 仿真稳定后用于 SoC 级 smoke/regression。
3. 默认不修改 `myCPU.sv` 端口。
4. Makefile 作为用户可见命令入口；脚本可承担测试发现、批量调度、路径展开、结果汇总。
5. 每次有意义的项目修改都要更新 `docs/archive/`。
6. 当前设计事实变化时，必须同步维护 `docs/design/` 或 `docs/sim/`。
7. 仿真超时是失败，不允许作为通过。

## 计划中的命令形态

后续仿真框架完成后，预期入口如下：

```sh
make sim-rv32 TEST=rv32ui-p-add
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=src0
make sim-src-all
make fpga-project TEST=src0
```

