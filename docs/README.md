# 文档索引

本目录用于维护项目当前设计事实、仿真/FPGA 使用规则、debug 记录和修改归档。后续修改项目时，应优先更新对应的“当前事实文档”，再在 `archive/` 中记录本次修改背景。

## 当前设计文档

| 文档 | 内容 |
| --- | --- |
| `design/project_framework.md` | 项目目录职责、受保护文件、后续行动规约。 |
| `design/memory_and_test_contract.md` | rv32/src DUT 分流、IROM/DRAM 时序、测试契约。 |
| `design/rtl_core_design.md` | 当前 `rtl/core` 微架构、流水级、队列资源、恢复路径和维护风险。 |

## 仿真文档

| 文档 | 内容 |
| --- | --- |
| `sim/verilator_plan.md` | 后续 Verilator 命令形态、测试选择方式、filelist 组织。 |

## FPGA 文档

| 文档 | 内容 |
| --- | --- |
| `fpga/vivado_project.md` | Vivado Tcl 生成工程、IP 生成参数和上板源文件边界。 |

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
| `archive/2026-07-03/015_rv32ui_mycpu_debug_fixes.md` | 定位并修复 myCPU rv32ui bring-up 问题：store 译码、flush、recovery、wakeup、MEM 保序、Issue/Payload pop 同步。 |
| `archive/2026-07-03/016_rv32mi_rv32um_debug_fixes.md` | 定位并修复当前 SYS/CSR 与 RV32M div/rem 问题，完成 `rv32mi/rv32um` 回归。 |
| `archive/2026-07-03/017_srcSmoke_bringup.md` | 完成 `srcSmoke` bring-up：StoreBuffer 部分转发、BPU 小幅调优、LED-only checker 和回归结果。 |
| `archive/2026-07-03/018_src_student_top_harness.md` | 将 src 类 Verilator DUT 切换到 `student_top`，拆分 rv32/src harness，并记录当前 `srcSmoke` student_top 结果。 |
| `archive/2026-07-03/019_make_src_entry_and_dram_model_fix.md` | 固定 make 仿真入口，设置 src 默认大周期上限，并修复 `DRAM_0` 行为模型使 `srcSmoke` 在 student_top 下 PASS。 |
| `archive/2026-07-03/020_result_json_perf_and_interrupt.md` | 精简结果 JSON，加入分支命中率统计，并支持 TIMEOUT/中断时输出部分结果。 |
| `archive/2026-07-04/021_srcSmoke_seg_and_ipc_review.md` | 审查 `srcSmoke` 最终 SEG/counter 显示是否满足 `0x37xxxxxx`，并分析当前 IPC 偏低是否为 TB 统计问题。 |
| `archive/2026-07-04/022_srcSmoke_seg_fix_and_ipc_breakdown.md` | 修复 SoC MMIO/counter 读返回相位，使 `srcSmoke` 最终 SEG 正常，并用分支分类计数定位 IPC 低的主要来源。 |
| `archive/2026-07-05/023_srcSmoke_ipc_low_deep_rtl_analysis.md` | 深入分析 `srcSmoke` IPC 偏低的 RTL 原因，估算分支命中率提升到 90% 后的理论 IPC 上限。 |
| `archive/2026-07-05/024_single_mul_ip_replacement.md` | 将乘法路径替换为单实例 `MUL_0` IP 边界，并更新 Verilator/Vivado filelist 与验证记录。 |
| `archive/2026-07-05/025_single_div_ip_replacement.md` | 将除法/取余路径替换为单实例 `DIV_0` IP 边界，固定 34 拍，并更新回归记录。 |
| `archive/2026-07-05/026_tcl_review_and_cpu_freq_sim.md` | 审查并修正 Vivado Tcl 输入路径/IP 参数诊断，新增 src 仿真 CPU 频率 make 参数和双时钟推进。 |
| `archive/2026-07-05/027_commit_width_branch_store.md` | 保守放开 lane0 正确 branch/store 后的 lane1 普通提交，并记录 checkpoint free 覆盖问题和回归结果。 |
| `archive/2026-07-05/028_vivado_tcl_console_profile_fix.md` | 修正 Vivado GUI Tcl Console 中 profile 参数传递方式，区分 `source` 与命令行 `-tclargs`。 |
| `archive/2026-07-05/029_vivado_package_constant_visibility_fix.md` | 整理 `types/package` 的包内可见性与编译顺序，修复 Vivado 综合对 `WAY_NUM` 等共享常量的可见性问题。 |
| `archive/2026-07-05/030_div_ip_blocking_output_port_fix.md` | 修正 `DIV_0` blocking flow-control 输出端口契约，删除不存在的 `m_axis_dout_tready` 连接。 |
| `archive/2026-07-05/031_execute_mem_load_return_merge.md` | 优化 ExecuteMem load 返回与当前单个 MEM uop 的同周期合并，减少 load-heavy 路径全局 stall。 |
| `archive/2026-07-05/032_srcWithMext_low_ipc_microarch_analysis.md` | 分析 `srcWithMext` 低 IPC 和 031 无明显收益的微架构原因，给出兼顾 IPC/频率的优化顺序。 |
| `archive/2026-07-05/033_issuequeue_wakeup_and_perf_buckets.md` | 回退 031，修复 IssueQueue `delay==1` 保守预计唤醒，并新增 stall/resource/width 性能分桶 JSON。 |
| `archive/2026-07-05/034_ipc_bottleneck_optimization_plan.md` | 基于新增性能分桶重新分析 `srcWithMext` IPC 瓶颈，并制定 MEM/ROB/唤醒优化计划。 |
| `archive/2026-07-05/035_ipc_lt05_root_cause_and_optimization.md` | 汇总 IPC < 0.5 根因，执行阶段 1/2 优化并记录 MEM result buffer、store fairness、ROB32 与 MUL 预计唤醒结果。 |
| `archive/2026-07-05/036_srcWithMext_post_phase12_ipc_root_cause.md` | 基于阶段 1/2 后 100M 长窗口重新定位 IPC 仍低原因，确认新主瓶颈为 IssueQueue 满且缺少 ready 项。 |
| `archive/2026-07-08/049_srcWithMext_current_result_optimization_space.md` | 基于当前单发射阻塞核的完整 `srcWithMext` PASS 结果，重新归因 memory/MulDiv stall 并给出优化优先级。 |
| `archive/2026-07-08/050_fpga_board_all_zero_bringup_review.md` | 审查 Tcl 建工程上板后 SEG/LED 全 0 的原因，修复 FPGA source 边界和 reset 同步释放，并记录官方模板对比。 |
| `archive/2026-07-10/053_vivado_implementation_and_fpga_optimization_plan.md` | 针对混合 reset 控制、重复时钟、CDC 加载和 FPGA 资源热点制定分阶段综合上板优化计划。 |
| `archive/2026-07-10/054_vivado_implfix_phase1_4_execution.md` | 执行计划 Phase 1-4：修复 reset/clear 结构与时钟/CDC 约束，整理 GUI Tcl Console 流程并完成分层 Verilator 回归。 |
| `archive/2026-07-10/055_fpga_reset_fanout_cleanup.md` | 删除额外 Vivado 启动 Tcl，整理 GUI 文档，并清理 valid/count 已门控 payload 的大范围 reset fanout。 |
| `archive/2026-07-10/056_dcache_distributed_ram_qor.md` | 将 DCache data/tag 重构为每 way 的 distributed RAM 模板，保持 hit latency 并完成分层回归。 |

## 后续维护规则

1. 设计实现变化时，优先更新 `design/`。
2. 仿真入口、数据格式、通过标准变化时，更新 `sim/`。
3. FPGA 工程、Tcl、约束或上板流程变化时，更新 `fpga/`。
4. 定位具体 bug 时，在 `debug/` 下新增记录。
5. 每次有意义的项目修改，在 `archive/` 下按日期新增归档。
