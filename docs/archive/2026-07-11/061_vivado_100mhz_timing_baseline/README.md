# 当前提交的 100 MHz routed 时序归档

本目录已更新为 Windows 工程 `digital_twin_srcWithMext` 在提交
`c24d8588372f7b5b68c68b4138bc3842c7a0276d` 上的 routed 结果，供后续 AI
直接定位关键路径族、资源热点、拥塞和约束风险。旧的 `66454dd` 基线报告已被
当前结果替换；旧数值仅在“与旧基线比较”一节保留。

## 1. 归档边界

- 源 checkpoint：`digital_twin.runs/impl_1/top_routed.dcp`，生成时间
  `2026-07-11 23:11:19 +08:00`，大小 41,600,775 bytes。
- Windows/WSL 工程 HEAD：`c24d8588372f7b5b68c68b4138bc3842c7a0276d`。
- 器件与工具：`xc7k325tffg900-2`，Vivado 2023.2 build 4029153。
- checkpoint 内时钟：系统域 `clk_out1_pll=50 MHz`，CPU 域
  `clk_out2_pll=100 MHz`。
- 本次只对已有 routed DCP 执行查询型 `report_*`；没有重新综合、布局、布线、
  physical optimization 或生成 bitstream。
- 为补足原 top-1000 样本覆盖不足，本目录随后用同一 DCP 只读导出了
  `setup_violating_endpoints_all.csv`：36,724 行，一行对应一个失败 endpoint 的
  最差路径（36,713 setup + 11 recovery），与全设计失败 endpoint 总数一致。
- Windows 与 WSL 仓库在导出时均为上述提交。后续修改不能视为 checkpoint 内容；
  结论必须绑定上述 HEAD 和 DCP 时间戳。

## 2. 核心结论

| 项目 | 当前结果 | 判断 |
| --- | ---: | --- |
| CPU period / frequency | 10.000 ns / 100 MHz | 目标约束 |
| CPU setup WNS | -2.868 ns | FAIL，但较上轮改善 1.627 ns |
| CPU setup TNS | -40279.301 ns | FAIL，较上轮改善 68.4% |
| CPU setup failing endpoints | 36,713 / 69,510 | 仍是大面积违例 |
| 全设计 setup WNS / TNS | -2.868 ns / -40279.938 ns | FAIL |
| CPU hold WHS / THS | +0.055 ns / 0 ns | PASS |
| CPU recovery WNS / TNS | -0.454 ns / -0.638 ns | FAIL，11 个 recovery 端点 |
| 50 MHz system setup WNS | +16.651 ns | PASS |
| fully routed nets | 81,386 / 81,386 | PASS |
| QoR assessment | score 2 | Implementation completes; timing will not meet |

按 `1000 / (10.000 + 2.868)` 粗估，当前 placement/routing 下最差单路径对应约
`77.71 MHz`。这不是已验证 Fmax；36,713 个失败端点和巨大 TNS 表明不能只修一条
路径，也不能用该粗估值代替下一次 routed 验证。

## 3. 当前最差路径与优化含义

### 3.1 第一关键路径

`u_rob/retire_stage_valid_q_reg[1]` 经 retire/recovery 广播和 execute completion/
writeback 异常选择，最终到 `u_execute/wb_exception_cause_q_reg[2][0]/D`：

- slack：`-2.868 ns`；data path：`12.567 ns`；logic levels：35；
- logic delay：`2.186 ns (18%)`；route delay：`10.381 ns (82%)`；
- 关键路径经过 `recover_valid_o`（fanout 1066）、`complete_valid_o` 和 MEM IQ operand
  选择，最终进入 writeback exception payload；
- 工程含义：ROB retire/recovery、全局 flush、completion 选择和 writeback payload
  仍跨多个物理区域串在同一周期。

优先检查 recovery 是否可以在各执行单元局部打一拍/局部译码，以及 writeback
exception payload 是否能与全局 recover 解耦。若直接延迟 architectural flush，
必须同时证明错误路径不会产生可见写回或内存副作用。

### 3.2 反复出现的路径族

| 路径族 | 报告证据 | 优化方向 |
| --- | --- | --- |
| ROB retire/recover → execute writeback exception | WNS `-2.868 ns`，35 levels，route 82% | recovery 局部化；切断 flush-to-payload 同拍路径 |
| rename sRAT → dispatch buffer payload | QoR `-2.522`～`-2.743 ns`，27～32 levels，route 87%～89% | 简化 dispatch acceptance；拆 payload/ready 写入 |
| memory request state → DCache LUTRAM write enable | QoR `-2.429 ns`，21 levels，route 85.9% | 将 refill/write decode 靠近 DCache 或打一拍 |
| completion/ROB index/PRD 广播 | fanout 550～1322，多条负 slack | 局部复制 completion 元数据；减少跨模块宽广播 |
| DCache data/write address | fanout 585～1057，worst slack 约 `-2.14 ns` | 分级 refill/write mux 和 LUTRAM 写地址 |
| reset recovery | `cpu_rst_sync` fanout 4042，recovery WNS `-0.454 ns` | 同步释放、局部 reset tree，避免直接异步清深层寄存器 |

QoR assessment 识别出 2 个 level-5 以上全局拥塞区域，较上轮减少 1 个。QoR suggestion 明确定位
PRF 区域的高 MUXF 使用，并建议 `MUXF_REMAP`、critical LUT remap 和 critical-net
replication。这些选项可作为 RTL 改完后的实现策略对照，不应替代流水化和扇出治理。

## 4. 与上一轮 `4762e00314f7` 比较

| 项目 | 旧基线 | 当前 | 变化 |
| --- | ---: | ---: | ---: |
| CPU WNS | -4.495 ns | -2.868 ns | 改善 1.627 ns |
| CPU TNS | -127382.055 ns | -40279.301 ns | 改善 68.4% |
| CPU failing endpoints | 47,536 | 36,713 | 减少 10,823 |
| CPU recovery WNS | +5.070 ns | -0.454 ns | 新增 11 个 recovery 违例 |
| Slice LUT | 76,183 | 79,323 | 增加 3,140 |
| Slice registers | 31,544 | 27,586 | 减少 3,958 |
| `u_core` LUT | 71,050 | 74,208 | 增加 3,158 |
| `u_backend` LUT | 58,362 | 69,055 | 增加 10,693（层次归属也发生变化） |
| `u_bpu` LUT | 10,688 | 3,173 | 减少 7,515 |
| `u_int_iq` LUT | 10,842 | 15,286 | 增加 4,444 |
| `u_rob` LUT | 17,357 | 20,956 | 增加 3,599 |
| DSP | 0 | 4 | 乘法逻辑成功映射到 DSP |

当前版本显著改善 setup WNS/TNS，并消除了上一轮 completion→PRF CE 的最差路径；
代价是 LUT 增长和 recovery 重新违例。下一轮应优先处理 retire/recover→writeback、
rename→dispatch buffer 和 memory-state→DCache write-enable 三类路径。

## 5. 资源、拥塞与扇出背景

| 层次/资源 | 当前值 |
| --- | ---: |
| Slice LUT / register | 79,323 / 27,586 |
| LUT as Memory | 2,151 |
| RAMB36-equivalent tiles / DSP | 68 / 4 |
| `u_core` LUT | 74,208 |
| `u_backend` LUT | 69,055 |
| `u_rob` LUT / FF | 20,956 / 9,396 |
| `u_execute` LUT / FF / DSP | 15,233 / 5,143 / 4 |
| `u_int_iq` LUT / FF | 15,286 / 3,819 |
| `u_bpu` LUT / LUTRAM / FF | 3,173 / 630 / 1,501 |
| `u_prf` LUT / FF | 9,149 / 2,016 |
| `u_dcache` LUT / LUTRAM / FF | 4,432 / 1,520 / 958 |

最高扇出 `cpu_rst_sync=4,042` 已从正 slack 变成 recovery 违例，应修同步释放和
局部 reset tree；setup 侧则优先处理 `recover_valid_o=1,066`、completion 广播、
rename/dispatch 和 DCache 写地址。两类路径必须分开治理。

## 6. 约束、CDC 和 DRC 风险

1. 50 MHz 与 100 MHz 来自同一 PLL，却被异步 clock group 整域切断；两个方向的
   跨域路径仍是 user ignored。methodology 继续报告 2 条 `TIMING-47`。
2. `report_cdc` 有 `CDC-10 Critical=31`，均为 Gray counter 同步器前存在组合逻辑；
   另有 `CDC-6 Warning=4` 多 bit 同步器。
3. `report_exceptions -coverage` 显示“无 timing exceptions”，与 clock interaction
   中 user ignored clock-group 路径需联动核对；不能据此宣称跨域 sign-off 完成。
4. DRC 共 29 条：`REQP-1839=20`；新增 DSP pipeline 建议 `DPIP-1=2`、
   `DPOP-1=2`、`DPOP-2=3`；另有 `CFGBVS-1=1` 和 rule-limit `CHECK-3=1`。
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
| `setup_violating_endpoints_all.csv` | 当前全部 36,724 个失败 endpoint 的代表最差路径，用于全量模块/路径族聚类 |
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
| `TIMING_OPTIMIZATION_ANALYSIS.md` | 当前全量违例分布、路径族与 RTL 根因分析 |
| `TIMING_CLOSURE_OPTIMIZATION_PLAN.md` | 分阶段 RTL/复位/约束/QoR 优化与验收方案 |
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

当前 routed 提交已经包含 registered writeback、allocated dispatch buffer、ROB
retire stage、issue elastic stage、ROB payload 分组和 BPU lookup/update 重构。
这些修改已把旧 WNS 从 `-4.495 ns` 改善到 `-2.868 ns`，但仍未达到 100 MHz。
此前的功能实施记录见
[`../065_100mhz_timing_rtl_optimization_implementation.md`](../065_100mhz_timing_rtl_optimization_implementation.md)。

后续应按 `TIMING_CLOSURE_OPTIMIZATION_PLAN.md` 分阶段修改，每个阶段重新运行功能
回归与 clean Vivado route，不能再用 `4762e003` 的旧路径族指导当前优化。
