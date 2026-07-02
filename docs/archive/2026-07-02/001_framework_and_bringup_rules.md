# 工程框架与启动规则归档

## 背景

当前项目结构已经基本搭好，但 core RTL 已知存在 bug。当前目标不是直接修 core，而是先建立可维护、可复现的工程与仿真框架。

## 已确认决策

1. 保持当前仓库目录结构。
2. 测试数据生成物直接补在 `data/` 原位置。
3. 后续 FPGA Tcl 适配当前 `data/<profile>/*.coe` 和 `fpga/digital_twin.xdc`，不移动目录迁就旧 Tcl。
4. Verilator 主 DUT 使用 `myCPU`。
5. `student_top` 只作为后续 SoC smoke DUT。
6. 默认不修改 `myCPU.sv` 端口。
7. `rtl/soc/counter.sv` 默认禁止修改。
8. rv32 使用严格 `tohost` 通过/失败语义。
9. 稳定 filelist 放在 `scripts/filelists/`。
10. 后续 Makefile 作为用户可见命令入口。

## 已新增文件

| 文件 | 用途 |
| --- | --- |
| `.gitignore` | 忽略 build、波形、Vivado、Verilator 等生成物。 |
| `scripts/filelists/core.f` | core RTL 稳定编译列表。 |
| `scripts/filelists/soc.f` | SoC RTL 稳定编译列表。 |
| `scripts/filelists/ip_verilator.f` | 仿真专用 IP 行为模型列表。 |
| `scripts/filelists/verilator_mycpu.f` | 主 DUT filelist。 |
| `scripts/filelists/verilator_student_top.f` | SoC smoke DUT filelist。 |
| `scripts/prepare_test_data.py` | 原地补齐 `.hex/.dump` 的数据准备脚本。 |
| `docs/design/project_framework.md` | 仓库职责与后续行动规则。 |
| `docs/design/memory_and_test_contract.md` | DUT、存储和 pass/fail 契约。 |
| `docs/sim/verilator_plan.md` | Verilator 命令形态和 filelist 规划。 |

## 尚未完成

1. Verilator C++ testbench。
2. Makefile 命令入口。
3. FPGA Tcl 路径适配。
4. core RTL bug 修复。
