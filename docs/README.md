# 文档索引

本目录用于维护项目当前设计事实、仿真/FPGA 使用规则、debug 记录和修改归档。后续修改项目时，应优先更新对应的“当前事实文档”，再在 `archive/` 中记录本次修改背景。

## 当前设计文档

| 文档 | 内容 |
| --- | --- |
| `design/project_framework.md` | 项目目录职责、受保护文件、后续行动规约。 |
| `design/memory_and_test_contract.md` | `myCPU` 主 DUT、IROM/DRAM 时序、rv32/src 测试契约。 |
| `design/rtl_core_design.md` | 当前 `rtl/core` 微架构、流水级、队列资源、恢复路径和维护风险。 |

## 仿真文档

| 文档 | 内容 |
| --- | --- |
| `sim/verilator_plan.md` | 后续 Verilator 命令形态、测试选择方式、filelist 组织。 |

## 归档文档

| 文档 | 内容 |
| --- | --- |
| `archive/2026-07-02/001_framework_and_bringup_rules.md` | 工程框架、DUT 选择、filelist 和测试数据准备的初始决策。 |
| `archive/2026-07-02/002_docs_chinese_and_rtl_design.md` | docs 中文化和 `rtl/core` 详细设计文档更新记录。 |
| `archive/2026-07-02/003_rtl_review_risks_and_gaps.md` | 当前 `rtl/` 静态评审问题、不完善点和建议处理顺序。 |

## 后续维护规则

1. 设计实现变化时，优先更新 `design/`。
2. 仿真入口、数据格式、通过标准变化时，更新 `sim/`。
3. FPGA 工程、Tcl、约束或上板流程变化时，更新 `fpga/`。
4. 定位具体 bug 时，在 `debug/` 下新增记录。
5. 每次有意义的项目修改，在 `archive/` 下按日期新增归档。
