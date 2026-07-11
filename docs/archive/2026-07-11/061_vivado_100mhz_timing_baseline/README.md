# `srcWithMext` 100 MHz routed 时序基线

本目录归档 `digital_twin_srcWithMext` 在提交 `66454dd3b80e952fbf7b9e57c0aa89303e66e430`（`fix the bug of dram_0`）上的 routed 结果，供 `061_ipc_fmax_joint_optimization_analysis.md` 后续做优化前后对照。

## 1. 归档边界

- 源 checkpoint：`digital_twin.runs/impl_1/top_routed.dcp`；生成时间为 2026-07-11 12:23:01 +08:00。
- 器件与工具：`xc7k325tffg900-2`，Vivado 2023.2 build 4029153。
- checkpoint 内恢复出的时钟：系统域 `clk_out1_pll=50 MHz`，CPU 域 `clk_out2_pll=100 MHz`。
- 本次只用 `open_checkpoint` 查询已有 routed 设计，没有重新运行 synth、opt、place、route、phys_opt 或 bitstream。
- 该结果对应提交基线，不包含当前工作树中的 P1A DCache refill 和 P1B INT RRD 修改，不能用来宣称这些修改已经通过 routed Fmax。

注意：原工程目录中的 PLL/IP 文件在 routed DCP 生成后又有更新；判断本次基线频率必须以 `top_routed.dcp`、`export_metadata.txt` 和原始 routed timing report 为准，不能以工程目录当前的 XCI 状态倒推。

## 2. 核心结论

| 项目 | 结果 | 判断 |
| --- | ---: | --- |
| CPU period / frequency | 10.000 ns / 100 MHz | 目标约束 |
| CPU setup WNS | -4.275 ns | FAIL |
| CPU setup TNS | -126470.969 ns | FAIL |
| CPU setup failing endpoints | 51,713 / 72,430 | 大面积违例，不是少量离群路径 |
| async recovery WNS / TNS | -0.589 ns / -8.730 ns | 32 个 reset recovery 端点违例 |
| 全设计 setup WNS / TNS | -4.275 ns / -126479.688 ns | FAIL |
| CPU hold WHS / THS | +0.068 ns / 0 ns | PASS |
| 50 MHz system setup WNS | +16.605 ns | PASS |
| 内部无时钟端点 | 0 | PASS |
| unconstrained internal endpoints | 0 | PASS |

按 `1000 / (10.000 + 4.275)` 计算，单条最差路径的倒数估计约为 `70.05 MHz`。这只是同一 placement/routing 下的粗略下界参考；由于 TNS 和 failing endpoints 很大，不能把它当作已经验证的 routed Fmax。

## 3. 最差路径族

| 排名 | 起点 → 终点 | Slack | Data path | Route 占比 | 工程含义 |
| ---: | --- | ---: | ---: | ---: | --- |
| 1 | ROB head/retire → BPU choice PHT | -4.275 ns | 13.869 ns | 87.57% | commit/retire 结果跨大范围组合更新 BPU 表 |
| 2 | ROB head/retire → DRAM BRAM data input | -4.265 ns | 13.621 ns | 89.27% | retire/恢复控制传播到 memory request 与 BRAM 写数据路径 |
| 3 | rename sRAT → MEM IQ entry payload | -4.243 ns | 13.425 ns | 88.78% | rename、dispatch acceptance 与压缩队列 payload 写入仍在同一拍 |

前 10 条 setup 路径的 logic levels 为 21～29，而 route 占比约 87.5%～89.4%。因此基线不是单个算术单元慢，而是 BPU 更新、rename/dispatch/MEM IQ、ROB/commit/memory 等跨模块控制和宽 payload 布线共同失控。

高扇出报告进一步给出：

- `cpu_rst_sync` fanout 8,581，并产生最差 `-0.589 ns` recovery violation；
- `bpu_update_valid` fanout 2,377；
- 多个 `bpu_update_pc[*]` fanout 1,200～2,255，且落在约 `-3.1 ns`～`-4.3 ns` 路径；
- completion ROB index、commit recovery、PRF write-enable 也属于高扇出负 slack 网络。

## 4. 约束与 sign-off 风险

1. `clk_out1_pll` 和 `clk_out2_pll` 来自同一个 PLL，但被 `set_clock_groups -asynchronous` 整域切断。clock interaction 中 50→100 MHz 有 104 个、100→50 MHz 有 65 个端点被忽略；methodology 给出 2 条 `TIMING-47`。因此域内 setup 失败是真实问题，但跨域并未完成时序 sign-off。
2. CDC 报告有 31 条 `CDC-10 Critical`，均指向 counter Gray 值同步器前存在组合逻辑；另有 4 条 multi-bit synchronizer warning。
3. `check_timing` 的 `no_clock=0`、`unconstrained_internal_endpoints=0`，但 `i_uart_rx` 缺 input delay，69 个 UART/LED/SEG 输出缺 output delay。
4. DRC 有 20 条 `REQP-1839`：带异步 set/reset 的寄存器驱动 IROM/BRAM 控制输入；另有 `CFGBVS-1`。
5. methodology 共 1,215 条 warning，其中 `TIMING-16=1000`、`HPDR-2=203`、`SYNTH-5=8`、`TIMING-28=2`、`TIMING-47=2`。

## 5. 资源背景

物理利用率为 77,711 Slice LUT、30,510 Slice Register、2,151 LUT as Memory、68 RAMB36、0 DSP。层次报告中的主要 LUT 使用者为：

| 层次 | LUT |
| --- | ---: |
| `u_core` | 72,490 |
| `u_backend` | 59,399 |
| `u_rob` | 18,882 |
| `u_execute` | 15,806 |
| `u_bpu` | 11,107 |
| `u_int_iq` | 10,704 |
| `u_prf` | 9,590 |
| `u_dcache` | 4,532（其中 LUTRAM 1,520） |

这些数字用于解释布线压力，不应单独作为 RTL 优先级；后续仍应以新 routed path family 和 `IPC × Fmax` 联合收益验收。

## 6. 文件索引

| 文件 | 用途 |
| --- | --- |
| `timing_summary_max100.rpt` | 主报告：全局/分时钟 summary、约束检查和每组 top 100 路径 |
| `setup_top200.rpt` | setup 详细路径集合 |
| `hold_top100.rpt` | hold 详细路径集合 |
| `clocks.rpt` | checkpoint 中的时钟定义 |
| `clock_interaction.rpt` | 域内/跨域端点及被忽略路径统计 |
| `cdc.rpt` | CDC 结构检查 |
| `high_fanout_nets.rpt` | top 200 高扇出网络及其 worst slack/delay |
| `check_timing.rpt` | no-clock、unconstrained、I/O delay 等覆盖检查 |
| `methodology.rpt` | methodology warning 明细 |
| `drc.rpt` | routed DRC 明细 |
| `utilization_hier.rpt` | routed 层次资源分解 |
| `original_top_timing_summary_routed.rpt` | implementation run 自动生成的原始报告，未改名内容只做归档 |
| `original_top_route_status.rpt` | 原始 route 完整性报告 |
| `original_top_clock_utilization_routed.rpt` | 原始 clock utilization 报告 |
| `original_top_control_sets_placed.rpt` | 原始 control-set 报告 |
| `original_impl_util_hier.rpt` | 原始 implementation 层次资源报告 |
| `export_metadata.txt` | checkpoint、工具、器件和时钟元数据 |
| `export_routed_reports.tcl` | 从 routed DCP 复现报告导出的脚本 |
| `SHA256SUMS` | 归档文件完整性校验 |

## 7. 后续对比规则

P1A/P1B 或后续优化完成后，应从新的 clean routed DCP 用同一脚本导出，并至少比较：CPU WNS/TNS/failing endpoints、前三个 path family、route 占比、high-fanout 前 20、recovery timing、CDC/ignored crossings、层次 LUT/FF，以及完整工作负载 IPC。不得只比较一条 WNS 或用本报告的约 `70.05 MHz` 粗估值代替新 route。
