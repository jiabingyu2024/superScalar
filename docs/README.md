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
| `archive/2026-07-02/004_src_dump_generation.md` | src 测试 dump 补齐规则和脚本更新记录。 |
| `archive/2026-07-02/005_review_corrections_memory_csr_reset.md` | IROM/DRAM、CSR、无 cache 和 reset 约束的评审修订记录。 |
| `archive/2026-07-02/006_system_subtype_and_ebreak_fix.md` | SYSTEM/MISC-MEM subtype 与 EBREAK trap 的 RTL 修复记录。 |
| `archive/2026-07-02/007_verilator_tb_mycpu.md` | `myCPU` Verilator TB、rv32/src 判定和运行入口记录。 |
| `archive/2026-07-02/008_tb_replan_after_review.md` | TB 结构复盘、src profile 化 checker 和性能统计重规划。 |
| `archive/2026-07-02/009_verilator_tb_refactor.md` | 按 008 规划完成 Verilator TB 拆分、src profile 和 smoke 验证记录。 |
| `archive/2026-07-02/010_src_mext_lampseg_checker.md` | `srcWithMext/srcWithoutMext` dump 分析、新 LED/SEG 协议和 checker 更新记录。 |
| `archive/2026-07-03/011_tb_self_review_proposal.md` | Verilator TB 自审与优化提案，已被 012 的对齐边界决策覆盖。 |
| `archive/2026-07-03/012_store_alignment_boundary_fix.md` | store/load 对齐边界修正：core 输出 raw data/mask，SoC/TB memory model 负责对齐。 |
| `archive/2026-07-03/013_mycpu_soc_boundary_review.md` | `myCPU` 与 SoC 边界审查：IROM/DRAM/MMIO 时序、mask 和对齐职责。 |
| `archive/2026-07-03/014_soc_boundary_contract_fix.md` | 按 SoC 边界职责修正 DRAM 地址上界、对齐注释和当前设计文档。 |

## 后续维护规则

1. 设计实现变化时，优先更新 `design/`。
2. 仿真入口、数据格式、通过标准变化时，更新 `sim/`。
3. FPGA 工程、Tcl、约束或上板流程变化时，更新 `fpga/`。
4. 定位具体 bug 时，在 `debug/` 下新增记录。
5. 每次有意义的项目修改，在 `archive/` 下按日期新增归档。
