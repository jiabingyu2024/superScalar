# 当前提交的 100 MHz routed 时序归档

本目录已更新为 Windows 工程 `digital_twin_srcWithMext` 在提交
`4762e00314f73810344185077f002c4c7db0dea6` 上的 routed 结果，供后续 AI
直接定位关键路径族、资源热点、拥塞和约束风险。旧的 `66454dd` 基线报告已被
当前结果替换；旧数值仅在“与旧基线比较”一节保留。

## 1. 归档边界

- 源 checkpoint：`digital_twin.runs/impl_1/top_routed.dcp`，生成时间
  `2026-07-11 19:08:02 +08:00`，大小 41,339,483 bytes。
- Windows 工程 HEAD：`4762e00314f73810344185077f002c4c7db0dea6`。
- 器件与工具：`xc7k325tffg900-2`，Vivado 2023.2 build 4029153。
- checkpoint 内时钟：系统域 `clk_out1_pll=50 MHz`，CPU 域
  `clk_out2_pll=100 MHz`。
- 本次只对已有 routed DCP 执行查询型 `report_*`；没有重新综合、布局、布线、
  physical optimization 或生成 bitstream。
- 为补足原 top-1000 样本覆盖不足，本目录随后用同一 DCP 只读导出了
  `setup_violating_endpoints_all.csv`：47,536 行，一行对应一个失败 endpoint 的
  最差 setup 路径，与 timing summary 的失败 endpoint 总数完全一致。
- WSL 工作树在归档时另有未提交修改；这些修改晚于 Windows 已生成工程，不能
  视为 checkpoint 内容。后续结论必须绑定上述 Windows HEAD 和 DCP 时间戳。

## 2. 核心结论

| 项目 | 当前结果 | 判断 |
| --- | ---: | --- |
| CPU period / frequency | 10.000 ns / 100 MHz | 目标约束 |
| CPU setup WNS | -4.495 ns | FAIL |
| CPU setup TNS | -127382.055 ns | FAIL |
| CPU setup failing endpoints | 47,536 / 73,199 | 大面积违例 |
| 全设计 setup WNS / TNS | -4.495 ns / -127382.055 ns | FAIL |
| CPU hold WHS / THS | +0.056 ns / 0 ns | PASS |
| CPU recovery WNS | +5.070 ns | PASS，旧基线异步 recovery 违例已消失 |
| 50 MHz system setup WNS | +16.581 ns | PASS |
| fully routed nets | 81,386 / 81,386 | PASS |
| QoR assessment | score 2 | Implementation completes; timing will not meet |

按 `1000 / (10.000 + 4.495)` 粗估，当前 placement/routing 下最差单路径对应约
`68.99 MHz`。这不是已验证 Fmax；47,536 个失败端点和巨大 TNS 表明不能只修一条
路径，也不能用该粗估值代替下一次 routed 验证。

## 3. 当前最差路径与优化含义

### 3.1 第一关键路径

`complete_prd_reg[1][0]` 经 MEM IQ 选择、PRF 组合读、execute completion、异常与
PRF 写使能逻辑，最终到 `u_prf/regs_q_reg[27][14]/CE`：

- slack：`-4.495 ns`；data path：`14.037 ns`；logic levels：30；
- logic delay：`1.976 ns (14.1%)`；route delay：`12.061 ns (85.9%)`；
- 路径含 4 级 CARRY4、29 级 LUT/MUX，且经过多个高扇出节点；
- 工程含义：issue 选择、PRF 异步读、execute completion 和 PRF 写回使能被串在
  同一个周期，既有结构深度问题，也有严重的跨区域布线问题。

这条路径不能靠局部布线选项根治。优先检查 completion/PRF write-enable 是否能
在 execute 与 writeback 之间增加明确寄存边界，以及 PRF 读地址/读数据是否需要
分级或减少组合端口。

### 3.2 反复出现的路径族

| 路径族 | 报告证据 | 优化方向 |
| --- | --- | --- |
| completion/wakeup → MEM IQ → PRF read → completion → PRF CE | WNS `-4.495 ns`，30 levels，route 85.9% | 切断同拍 issue-to-writeback 环；寄存 completion/WE |
| rename sRAT → INT IQ / ROB payload | QoR paths `-4.328`～`-4.380 ns`，29 levels，route 89.3%～89.4% | 简化 dispatch acceptance；拆 payload 写入；降低压缩队列全局选择 |
| IQ `prs1/prs2/issue_uop` 高扇出 | 多个 512～1272 fanout 网络，worst slack 到 `-4.425 ns` | 复制局部控制、分 bank、减少组合广播范围 |
| PC/BPU lookup | `pc_o`、`bpu_lookup_pc` fanout 1060+，worst slack 约 `-3.50 ns` | BPU 查询流水化或减表；缩短 PC→BTB/PHT→next-PC 路径 |
| DCache data/write address | 多个 585～1057 fanout LUT 网络，worst slack 到 `-3.82 ns` | 检查 LUTRAM 写地址广播与 refill/write mux 分级 |
| commit recovery | `recover_valid_o` fanout 1014，worst slack `-3.820 ns` | 局部生成 clear/kill，避免宽 payload 全局同步清除 |

QoR assessment 还识别出 3 个 level-5 以上全局拥塞区域。QoR suggestion 明确定位
PRF 区域的高 MUXF 使用，并建议 `MUXF_REMAP`、critical LUT remap 和 critical-net
replication。这些选项可作为 RTL 改完后的实现策略对照，不应替代流水化和扇出治理。

## 4. 与旧 `66454dd` 基线比较

| 项目 | 旧基线 | 当前 | 变化 |
| --- | ---: | ---: | ---: |
| CPU WNS | -4.275 ns | -4.495 ns | 恶化 0.220 ns |
| CPU TNS | -126470.969 ns | -127382.055 ns | 恶化 911.086 ns |
| failing endpoints | 51,713 | 47,536 | 减少 4,177 |
| CPU recovery WNS | -0.589 ns | +5.070 ns | recovery 违例消失 |
| Slice LUT | 77,711 | 76,183 | 减少 1,528 |
| Slice registers | 30,510 | 31,544 | 增加 1,034 |
| `u_core` LUT | 72,490 | 71,050 | 减少 1,440 |
| `u_backend` LUT | 59,399 | 58,362 | 减少 1,037 |
| `u_bpu` LUT | 11,107 | 10,688 | 减少 419 |

当前版本改善了资源和 recovery，但 setup WNS/TNS 没有收敛，且最差路径已转为
completion/MEM-IQ/PRF/writeback 同拍长环。下一轮应按当前路径族优化，不能继续按
旧基线的“ROB retire → BPU update”为唯一首要目标。

## 5. 资源、拥塞与扇出背景

| 层次/资源 | 当前值 |
| --- | ---: |
| Slice LUT / register | 76,183 / 31,544 |
| LUT as Memory | 2,151 |
| RAMB36-equivalent tiles / DSP | 68 / 0 |
| `u_core` LUT | 71,050 |
| `u_backend` LUT | 58,362 |
| `u_rob` LUT / FF | 17,357 / 8,835 |
| `u_execute` LUT / FF | 15,464 / 7,062 |
| `u_int_iq` LUT / FF | 10,842 / 2,658 |
| `u_bpu` LUT / LUTRAM / FF | 10,688 / 630 / 6,156 |
| `u_prf` LUT / FF | 9,253 / 2,016 |
| `u_dcache` LUT / LUTRAM / FF | 4,441 / 1,520 / 958 |

最高扇出是 `cpu_rst_sync=8,674`，但当前 worst slack 为正；真正要先处理的是带负
slack 的 IQ 选择/operand、PRF write enable、PC/BPU、DCache 写地址和 recovery
网络。只按 fanout 数值排序会把优化精力错误地集中到 reset。

## 6. 约束、CDC 和 DRC 风险

1. 50 MHz 与 100 MHz 来自同一 PLL，却被异步 clock group 整域切断；两个方向的
   跨域路径仍是 user ignored。methodology 继续报告 2 条 `TIMING-47`。
2. `report_cdc` 有 `CDC-10 Critical=31`，均为 Gray counter 同步器前存在组合逻辑；
   另有 `CDC-6 Warning=4` 多 bit 同步器。
3. `report_exceptions -coverage` 显示“无 timing exceptions”，与 clock interaction
   中 user ignored clock-group 路径需联动核对；不能据此宣称跨域 sign-off 完成。
4. DRC 共 22 条：`REQP-1839=20`，仍是带异步 set/reset 的寄存器驱动 IROM BRAM
   地址/控制；另有 `CFGBVS-1=1`。
5. methodology 仍包含大量 `TIMING-16`、`HPDR-2` 及 `TIMING-28/47`，详细实例以
   `methodology.rpt` 为准。
6. `report_design_analysis -congestion` 在 Vivado 2023.2 上触发工具自身
   `EXCEPTION_ACCESS_VIOLATION`。稳定导出脚本不再调用该命令；崩溃日志已归档，
   拥塞信息由 QoR assessment/suggestions 提供。

## 7. 文件索引

| 文件 | 后续 AI 用途 |
| --- | --- |
| `timing_summary_max100.rpt` | 全局/分时钟 WNS、TNS、hold、recovery 和约束覆盖 |
| `setup_violations_top1000.rpt` | 带 input pins/full clock 的 1000 条 setup 违例详情 |
| `setup_top200.rpt` / `hold_top100.rpt` | 按 path group 排序的 setup/hold 详细路径 |
| `setup_paths_top1000.csv` / `setup_violations_top1000.csv` | 可程序化聚类的 setup 路径属性 |
| `setup_violating_endpoints_all.csv` | 全部 47,536 个失败 endpoint 的最差 setup 路径，用于全量模块/路径族聚类 |
| `hold_paths_top500.csv` | 可程序化检查 hold 裕量与端点 |
| `design_analysis_timing.rpt` | 最差路径的 logic/net delay、逻辑结构和高扇出特征 |
| `design_analysis_complexity.rpt` | Rent 指数、层次复杂度、MUXF 与 LUT 结构热点 |
| `qor_assessment.rpt` / `qor_suggestions.rpt` | 拥塞等级、超预算路径和 Vivado 建议 |
| `high_fanout_nets.rpt` | top 200 fanout、worst slack 与 delay |
| `utilization_hier.rpt` / `utilization_flat.rpt` | routed 层次与全局资源分解 |
| `route_status.rpt` / `clock_utilization.rpt` / `control_sets.rpt` | routing、时钟资源和 control-set 诊断 |
| `clocks.rpt` / `clock_interaction.rpt` / `exceptions_coverage.rpt` | 时钟与 timing exception 审计 |
| `cdc.rpt` / `check_timing.rpt` / `methodology.rpt` / `drc.rpt` | sign-off 风险 |
| `power.rpt` | vectorless、medium-confidence 功耗参考，不能作为实测功耗 |
| `implementation_runme.log` | 本次 implementation/bitstream 的完整执行证据 |
| `original_top_*` | implementation run 自动生成的原始 routed/placed 报告 |
| `export_metadata.txt` / `archive_context.txt` | DCP、commit、工具、时钟和归档边界 |
| `export_routed_reports.tcl` | 从 routed DCP 复现全部稳定报告的脚本 |
| `export_all_setup_endpoints.tcl` | 从 routed DCP 复现全失败 endpoint 索引的只读脚本 |
| `TIMING_OPTIMIZATION_ANALYSIS.md` | 全量违例定位、RTL 根因、100 MHz 可达性与分阶段优化方案 |
| [`../065_100mhz_timing_rtl_optimization_implementation.md`](../065_100mhz_timing_rtl_optimization_implementation.md) | 后续 RTL 实施、A/B 性能、RV/src 回归和新 routed 验收清单 |
| `vivado_congestion_report_crash.log` | congestion report 工具崩溃证据 |
| `SHA256SUMS` | 归档完整性校验 |

## 8. 后续优化验收规则

每次 RTL 优化后必须从新的 clean routed DCP 用同一脚本导出，并至少比较：CPU
WNS/TNS/failing endpoints、前 5 个路径族、logic/route 占比、level-5 congestion、
负 slack 高扇出网络、层次 LUT/FF/MUXF、CDC/ignored crossings、DRC，以及相同
workload 下的 IPC。不能只比较一条 WNS，也不能把 Vivado 自动 QoR suggestion 当作
RTL 时序修复的替代品。

## 9. 后续 RTL 实施状态

当前工作树已经完成 registered writeback、allocated dispatch buffer、ROB retire
stage 和 BPU lookup/update 重构，并通过 RV32MI/UI/UM、`srcSmoke` 及指定的
`srcWithMext` 500k/50M 窗口验证。完整数据见
[`../065_100mhz_timing_rtl_optimization_implementation.md`](../065_100mhz_timing_rtl_optimization_implementation.md)。

该实施按用户要求没有运行 Vivado；本目录中的 routed WNS/TNS 仍只代表提交
`4762e003`，不能作为当前 RTL 已达到 100 MHz 的证据。
