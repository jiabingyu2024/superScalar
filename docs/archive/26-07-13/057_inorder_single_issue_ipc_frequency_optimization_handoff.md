# 顺序单发射 Core IPC/频率优化阶段收口与综合交接

> 日期：2026-07-13  
> 参考架构：`052_cva6_inorder_single_issue_core_microarchitecture.md`、`053_superscalar_framework_inorder_single_issue_core_architecture.md`  
> 优化方案：`056_ipc_200mhz_optimization_architecture.md`  
> 本文性质：当前 RTL 的阶段性收口记录，不把尚未完成的 implementation 或全量回归写成已通过。

## 1. 当前结论

当前版本已经完成 DCache hit/refill、Load 发射、依赖定位和若干时序边界优化。固定 20M `srcWithMext` 短窗口中，可比基线 IPC 从 `0.596700` 提升至最高 `0.764203`；加入分支寄存边界后的最新 20M 结果为 `0.763360`，相对基线提升约 27.9%。此后增加的 tag+valid BRAM、DMem slice 和延迟 RF 写回只完成了 500k/基础指令回归，没有再跑 20M，因此 `0.763360` 是最新可比证据，不是对最终当前 RTL 的精确 IPC 声明。

功能方面，最终当前 RTL 已通过 RV32UI 40 项、RV32MI 4 项、RV32UM 8 项，共 52 项；`srcSmoke` 和 `srcWithMext` 的 500k 诊断窗口持续前进、无 fail marker/断言，且分别观察到 RV32I=37，以及 RV32I=37、M=8。500k 因达到人为窗口上限而报告 `TIMEOUT`，它不是正式全量 PASS。

频率方面，最后一份有效 200 MHz routed 报告仍是 iteration6：WNS=`-4.310 ns`、TNS=`-18012.287 ns`、负 slack endpoint/path 共 `11,644` 条。它对应的是最终一批时序隔离修改之前的 RTL。此后已针对全量路径的主要来源修改 RTL，但按用户要求在此停止，没有新的 routed 结果，所以当前不能声称 200 MHz 已闭合。

最后一次 Vivado 尝试没有形成新的时序结果：复用的 XPR 没有自动加入新文件 `dmem_regslice.sv`，综合入口报 `module 'dmem_regslice' not found`。`fpga/run_implementation.tcl` 已修正为复用工程时重新扫描 `core.f`/`soc.f` 并补加新源文件；此脚本修复尚未再次调用 Vivado 验证。

## 2. 当前微架构快照

Core 仍保持顺序单发射、顺序提交，不是照搬 CVA6，也没有改成双发射或乱序发射：

```text
Frontend/Fetch Queue
    → Decode + RF/旁路取数
    → 单发射 Issue
    → Fixed Execute / MulDiv / LSU 地址生成
    → Scoreboard（允许长延迟执行单元乱序完成）
    → 严格顺序 Commit
```

性能关键的 memory 子路径为：

```text
Issue 边界锁存 exec_mem_addr_q
    → Load 直接送 DCache（不再强制先进入 Load Queue）
    → 同步 tag/data lookup
    → hit：下一拍返回，完成与下一请求可重叠
    → miss：critical-word-first，首个目标 word 到达即 early restart
    → 外部请求/响应经过 dmem_regslice
    → SocMemBridge / DRAM
```

必须保持的行为合同：

1. 单周期只能发射一条 uop，架构状态只在 commit 更新。
2. Producer Map 只加速源操作数生产者定位，不能改变按年龄提交和精确异常语义。
3. Store 只有提交后才允许成为 external write；`store_committed_q` 与 Store Buffer entry 分离。
4. DCache refill 未写满 4 个 word 之前不得置 line valid；early restart 只提前完成当前 load。
5. flush/kill 后仍要 drain 已握手的外部 response，但不得把它完成到新的 transaction。
6. DCache 初始化用 `DC_INIT` 每拍清一个 tag+valid entry，共 2048 拍，避免 reset 生成 2048 个 valid FF 及大扇出清零网络。

## 3. 已落地的 RTL 优化

| 优化项 | 实现位置 | 设计目的 | 若删除或改错的直接后果 |
|---|---|---|---|
| 删除独立 `DC_RESP` bubble | `rtl/core/memory/dcache.sv` | hit response 与下一次 lookup 可在相邻/重叠周期推进 | 连续 load hit 退化为约每两拍一个 |
| critical-word-first + early restart | `dcache.sv` | miss 首先请求原 load word，首个响应即可唤醒依赖链 | 每次 miss 必须等待完整四字 refill，load-use 延迟明显增加 |
| DCache 从 8 KiB 增至 32 KiB | `core_config_pkg.sv`，`DCACHE_LINES=2048` | 降低 `srcWithMext` 热点容量/冲突 miss | 20M miss 从约 11.4 万回升，IPC 下降 |
| 四个同步 data bank | `dcache_data_bank.sv` | 推断 BRAM，避免大容量异步数组形成深 LUT MUX | 容量增大后频率和资源都会恶化 |
| tag+valid 合并同步 BRAM | `dcache.sv` | 消除独立 2048-bit valid FF 阵列及动态选择路径 | iteration6 的 `commit/tag → valid/DCache` 大量路径可能保留 |
| Load EX→DCache direct path | `core_top.sv` | 在没有旧 load 时绕过 Load Queue 安装/取出拍 | 20M IPC 从约 0.647 跳到约 0.764 的主要收益消失 |
| response+next request 同拍替换 active metadata | `core_top.sv` | 防止 response 后人为空拍 | 连续 hit 仍会被 `load_active` 串行化；若优先级写错会丢 transaction ID |
| Producer Map | `core_top.sv` | 用 `rd→trans_id` 直接定位依赖，替代每次反向扫描 Scoreboard CAM | 恢复长比较链；清除条件错误会读到已提交或被 flush 的生产者 |
| early AGU 寄存 `exec_mem_addr_q` | `core_top.sv` | 阻断 `exec_q.op1 + imm → cache/SoC` 的跨模块组合路径 | 地址加法、range decode、cache/bridge 控制会串成关键路径 |
| 分支解析/预测器更新/redirect 寄存 | `core_top.sv` | 阻断 Execute 直接控制 Frontend、Decode、Scoreboard 全局更新 | iteration6 中 Execute→全局控制的 17~19 级逻辑路径会保留 |
| 分支解析当拍禁止 issue | `core_top.sv` | 避免寄存 redirect 前错误发射 younger uop | 可能在 redirect 建立前发射错误路径指令；代价约 0.11% IPC |
| RF 写回延后一拍并提供 WB bypass | `core_top.sv` | 阻断 `commit_ptr/commit mux → RegFile D` | iteration6 的 1984 条 Core.Other→RegFile 路径会保留；无 WB bypass 则紧邻消费者读旧值 |
| DMem request/response register slice | `dmem_regslice.sv` | 切断 DCache 与 SoC MemBridge/DRAM 的双向长组合路径 | iteration6 最差的 DCache→SoC 1613 条和 SoC→DCache 160 条路径仍跨边界 |
| Store committed 位独立存储 | `core_top.sv`、`core_types_pkg.sv` | 减少 Store entry 宽控制依赖并明确提交所有权 | write-through store 可能提前发出或永远无法发出 |
| DRAM 高位等值 decode | `core_top.sv`、`dcache.sv` | 用固定 256 KiB 窗口的高位比较代替两个 32-bit magnitude compare | LSU/cache 请求允许条件路径加深 |

新增模块已经加入 `scripts/filelists/core.f`：

- `rtl/core/memory/dcache_data_bank.sv`
- `rtl/core/memory/dmem_regslice.sv`

## 4. IPC 优化的可比数据

以下 A/B 均为 `srcWithMext` 固定 20,000,000 周期窗口。iteration6 保存的同名 JSON 后来被 500k 诊断覆盖，因此表中不伪造其 20M 文件链接；iteration5 与 iteration6 的 20M 控制台结果相同，最终有文件证据的当前时序边界版本是 iteration7。

| 版本 | 主要变化 | commit | IPC | DCache miss | load-return stall |
|---|---|---:|---:|---:|---:|
| 原始 8 KiB 基线 | 优化前 | 11,934,008 | 0.596700 | 113,680 | 8,047,426 |
| iteration1 | hit 无 `DC_RESP` bubble + early restart，8 KiB | 12,272,212 | 0.613611 | 116,923 | 7,708,742 |
| iteration2 | 16 KiB | 12,513,762 | 0.625688 | 81,090 | 7,466,836 |
| iteration3 | 32 KiB | 12,945,533 | 0.647277 | 15,532 | 7,034,429 |
| iteration4 | EX→DCache direct load | 15,284,038 | 0.764202 | 16,023 | 4,692,500 |
| iteration5 | Store timing 拆分 | 15,284,050 | **0.764203** | 16,023 | 4,692,512 |
| iteration7 | 分支寄存边界；最终 tag+valid/WB 版尚未跑 20M | 15,267,208 | **0.763360** | 16,023 | 4,709,287 |

阶段性结果：

- 最新有 20M 证据的版本比基线多提交 3,333,200 条指令，IPC 相对提升约 27.9%。
- load-return stall 减少 3,338,139 拍，约 41.5%。
- DCache miss 从 113,680 降至 16,023，约减少 85.9%；这部分收益包含 cache 容量变化，不能全部归因于流水控制。
- 距离短窗 IPC 0.8 还差 0.03664（约为目标的 4.58%）。
- 若全量 commit 仍为 380,344,388 且全量 IPC 恰为 0.76336，理论时间约为 2.49 s @ 200 MHz；IPC 0.8 对应约 2.38 s，严格 2.00 s 需要约 0.95 IPC。
- 当前没有跑优化后全量，因此不能用短窗线性外推作为最终成绩。

对应 JSON 均保存在 `056_ipc_200mhz_optimization_results/`。

## 5. 最终当前 RTL 的功能验证

### 5.1 RV32 基础回归

2026-07-13 20:35 的最终当前 RTL 回归：

| Suite | 数量 | 结果 |
|---|---:|---|
| RV32UI | 40 | 40 PASS |
| RV32MI | 4 | 4 PASS |
| RV32UM | 8 | 8 PASS |
| 合计 | 52 | **52 PASS** |

54 个归档文件（52 个 RV32 JSON + 2 个 src 短窗 JSON）位于：
`056_ipc_200mhz_optimization_results/final_short_regression/`。

### 5.2 src 500k 诊断窗

| 测试 | 状态 | commit / IPC | 关键正确性观察 |
|---|---|---:|---|
| `srcSmoke` | TIMEOUT（预期窗口结束） | 377,409 / 0.754818 | RV32I=37，fail=0，无 fail marker |
| `srcWithMext` | TIMEOUT（预期窗口结束） | 354,717 / 0.709434 | RV32I=37、M=8、lamp=`0x00020001`，fail=0 |

这里的 TIMEOUT 不能改写为 PASS。它只说明短窗口内功能持续前进且已通过早期测试点；正式 PASS 仍需跑到各自 checker 的最终 marker/lamp 合同。

### 5.3 本阶段未运行的测试

- 优化后 `srcSmoke` 全量窗口。
- 优化后 `srcWithMext` 1.2B 上限全量窗口。
- 最新 RTL 的 Vivado synthesis/implementation。

这是按“在此停止，后续由用户综合”的要求主动收口，不是把这些 gate 静默视为通过。

## 6. iteration6 全部 11,644 条 setup 违例

这次不是只保存最差若干条。导出条件为：

```tcl
get_timing_paths -setup -slack_lesser_than 0.0 -max_paths 100000 -nworst 1
```

完整性核对：

- routed timing summary 的 failing endpoints：`11,644`。
- CSV：`11,645` 行，其中 1 行表头、`11,644` 行路径。
- raw RPT 中 `Slack (VIOLATED)`：`11,644` 次。
- 细粒度起终点聚类：558 族。
- 模块级起点→终点组合：33 组。
- 所有模块级组的计数总和为 11,644；CSV/RPT 保留每一条原始路径，聚类没有删除路径。

完整证据：

- `iteration6_all_violating_setup_paths.rpt`：Vivado 原始全文，约 94.5 MB。
- `iteration6_all_violating_setup_paths.csv`：每条路径的 slack、requirement、data delay、logic levels、startpoint、endpoint。
- `iteration6_all_violating_path_clusters.md`：558 个细粒度族和全部 33 个模块级组合。
- `iteration6_all_violating_setup_paths_summary.txt`：导出参数与总数。

全部 33 个模块级组合如下，不使用 top-N 截断：

| # | 数量 | 最差 slack/ns | 起点 | 终点 |
|---:|---:|---:|---|---|
| 1 | 1613 | -4.310 | DCache | SoC MemBridge |
| 2 | 2096 | -3.378 | Execute | Scoreboard |
| 3 | 628 | -3.171 | DCache | DCache |
| 4 | 55 | -3.110 | Execute | Producer Map |
| 5 | 199 | -3.012 | Execute | Execute |
| 6 | 419 | -2.992 | Execute | Frontend |
| 7 | 204 | -2.966 | Execute | Decode |
| 8 | 48 | -2.738 | Execute | Core Other |
| 9 | 62 | -2.656 | DCache | Execute |
| 10 | 129 | -2.511 | DCache | Core Other |
| 11 | 160 | -2.384 | SoC MemBridge | DCache |
| 12 | 723 | -2.345 | DCache | Scoreboard |
| 13 | 2 | -2.170 | MulDiv | Execute |
| 14 | 45 | -2.160 | MulDiv | Scoreboard |
| 15 | 4 | -2.087 | Execute | SoC Other |
| 16 | 164 | -2.037 | DCache | Load Queue |
| 17 | 416 | -1.821 | Core Other | Core Other |
| 18 | 72 | -1.789 | Core Other | Load Queue |
| 19 | 1984 | -1.667 | Core Other | RegFile |
| 20 | 225 | -1.564 | Core Other | Store Buffer |
| 21 | 1823 | -1.514 | Core Other | DCache |
| 22 | 125 | -1.502 | Core Other | MulDiv |
| 23 | 100 | -1.340 | Execute | MulDiv |
| 24 | 73 | -1.151 | Core Other | Frontend |
| 25 | 4 | -0.909 | DCache | Store Buffer |
| 26 | 30 | -0.655 | Frontend | Frontend |
| 27 | 63 | -0.516 | SoC Other | Scoreboard |
| 28 | 150 | -0.481 | SoC Other | Frontend |
| 29 | 13 | -0.230 | Core Other | Producer Map |
| 30 | 6 | -0.230 | SoC Other | Decode |
| 31 | 5 | -0.108 | Scoreboard | Scoreboard |
| 32 | 3 | -0.108 | Scoreboard | Core Other |
| 33 | 1 | -0.031 | Core Other | Execute |

注意：这 11,644 条路径已全部提取并用于分类整改，但不能说它们在最终 RTL 中已经全部消失，因为最终 RTL 还没有重新 route。正确结论是“全量提取完成、主要组合路径已采取结构性隔离、消除效果待下一次全量 implementation 报告验证”。

## 7. 全量路径驱动的最后一批修改

| iteration6 路径集合 | 路径数 | 后续 RTL 处理 | 预期影响 |
|---|---:|---|---|
| DCache→SoC MemBridge | 1613 | 请求侧 `dmem_regslice` | 切断 tag/refill/store 控制直达 DRAM/bridge 的地址、WE、EN 路径 |
| SoC MemBridge→DCache | 160 | response 寄存 | 切断 DRAM BRAM output 直达 DCache data/tag update |
| DCache→DCache | 628 | tag+valid 同步 BRAM、`DC_INIT` | 消除 async valid/tag MUX 和大清零网络 |
| Core Other→DCache | 1823 | 同上，并使请求地址来自已锁存 AGU | 缩短 commit/control 到 metadata update 的组合影响 |
| Execute→Scoreboard/Frontend/Decode/Execute/Producer Map/Other | 3021 | 分支解析、redirect、predictor update 寄存；issue 当拍 gate | 避免 `exec_q.op1` 经分支比较后扇出到全局状态更新 |
| Core Other→RegFile | 1984 | commit 后增加 WB 寄存和 WB bypass | 把 RegFile D 数据选择从 commit pointer 大 MUX 后移一拍 |

其余路径族仍保留在完整聚类文件中。下一次 route 后必须重新导出全部负 slack 路径，不能只看新的 top20；路径排序可能在主要大类被切断后发生显著变化。

## 8. Vivado 交接步骤

### 8.1 运行最新 RTL 的 200 MHz implementation

在仓库根目录调用 Vivado 2023.2：

```text
vivado -mode batch -source fpga/run_implementation.tcl \
  -tclargs srcWithMext 8 200 1
```

参数依次为 profile、并行 job 数、CPU MHz、是否复用已有 XPR。`reuse=1` 现在会重新读取 `scripts/filelists/core.f` 和 `soc.f`，补加新增 RTL，更新 compile order，再 reset synthesis run。

如果复用工程仍出现任何源文件/IP 状态异常，改用 `reuse=0` 创建干净工程；不要用旧 DCP 的 WNS 代表当前 RTL。

implementation 完成后先检查：

1. `IMPLEMENTATION_RESULT` 中 WNS/TNS。
2. synthesis utilization 中 tag+valid 和四个 data bank 是否推断为 RAMB，而不是 2048 个 valid FF/LUTRAM。
3. routed utilization 是否超过器件资源或出现高拥塞。
4. methodology/clock report 是否出现新的 unconstrained/clocking 问题。

### 8.2 导出当前实现的全部负 slack 路径

即使 WNS 只剩少量负值，也继续导出全部路径：

```text
vivado -mode batch -source fpga/export_all_violating_paths.tcl \
  -tclargs srcWithMext 100000 iteration8

python3 scripts/cluster_timing_paths.py \
  fpga/build/digital_twin_srcWithMext/reports/iteration8_all_violating_setup_paths.csv \
  docs/archive/26-07-13/iteration8_all_violating_path_clusters.md
```

核对 summary 的 `exported_path_count` 必须等于 timing summary 的 setup failing endpoints。若超过 100,000 条，应提高 `max_paths` 后重导，不能接受被上限截断的文件。

### 8.3 何时再跑全量软件回归

建议顺序：

1. implementation 有明确结果后，先重跑 RV32 base 52。
2. 再跑 `srcSmoke/srcWithMext` 500k，比较最终当前归档值，确认没有工具/源集差异。
3. 只有候选 RTL 不再继续修改时，运行一次全量 `srcSmoke` 和一次全量 `srcWithMext`。
4. 最终时间只能用全量 cycle、最终 routed 可用频率计算；仿真 JSON 中把 `CPU_FREQ_MHZ=200` 写入只改变换算字段，不证明 FPGA 能跑 200 MHz。

## 9. 当前遗留风险

1. **最新时序未知。** register slice、WB 寄存、tag+valid BRAM 可能移除主要路径，也可能暴露新的次关键路径；没有 route 前不能定论。
2. **BRAM 推断待验证。** `ram_style="block"` 是意图，不等于综合器一定按期望映射；尤其 tag 宽度和同步读写模板需看 synthesis report。
3. **DMem regslice 非 fall-through。** 外部 miss/write-through store 会增加拍数，而且当前 slice 不支持 pop/push 同拍；DCache hit 不经过外部口，因此短窗主收益预计保留，但全量需量化。
4. **分支安全 bubble 有 IPC 代价。** iteration5→iteration7 约损失 0.000843 IPC；在未证明安全的情况下不要直接删除 gate。
5. **WB 延后一拍依赖 bypass。** 修改 RF 写回时必须联动检查 decode source resolver，避免 commit 后紧邻消费者读旧寄存器。
6. **`DC_INIT` 延长启动 2048 拍。** 当前 500k 已覆盖启动行为；若 reset/FENCE 合同变化，要重新检查初始化期间请求是否被可靠 backpressure。
7. **全量成绩未知。** 20M 热区数据不能代替 604M 周期完整 workload，最终 IPC 可能高于或低于短窗。
8. **目标定义差异。** IPC 0.8 @ 200 MHz 对当前全量 commit 数约为 2.38 秒；接近 2.0 秒实际需要约 IPC 0.95 或更高频率。

## 10. 交付文件索引

| 文件/目录 | 内容 |
|---|---|
| `056_ipc_200mhz_optimization_architecture.md` | 优化前的定量瓶颈和方案 |
| `stage3_microarch_analysis.json` | datapath/control/performance/hazard 分析 |
| `stage4_rtl_architecture.json` | RTL 边界、接口所有权和实施顺序 |
| `056_ipc_200mhz_optimization_baseline/` | 优化前全量基线 |
| `056_ipc_200mhz_optimization_results/` | iteration1~7、timing、全量路径与短回归证据 |
| `fpga/run_implementation.tcl` | 200 MHz synth+route；已修复复用工程源文件刷新 |
| `fpga/export_all_violating_paths.tcl` | 全部负 slack setup 路径导出器 |
| `scripts/cluster_timing_paths.py` | 原始 CSV 的无损计数聚类 |
| `rtl/core/memory/dcache_data_bank.sv` | 同步 BRAM data bank |
| `rtl/core/memory/dmem_regslice.sv` | Core/SoC DMem 时序寄存切片 |

## 11. 阶段验收状态

| Gate | 状态 |
|---|---|
| RV32UI/MI/UM 52 项 | PASS |
| src 500k 诊断 | 已完成，预期 TIMEOUT，无早期错误 |
| 20M IPC A/B | 已完成到 iteration7，最新证据 IPC 0.763360；最终当前 RTL 未重跑 20M |
| iteration6 全部违例提取 | 已完成，11,644/11,644 |
| 全量违例聚类 | 已完成，558 细粒度族、33 模块级组合 |
| 最后一批路径隔离 RTL | 已实现，待 implementation 验证 |
| 最新 synthesis/implementation | 未完成 |
| 200 MHz timing closure | 未证明 |
| 优化后 src 全量回归 | 未运行 |
| “接近 2 秒”最终成绩 | 未证明 |

本阶段到此收口。后续从第 8 节开始即可，不需要重新做 iteration6 的全量路径提取。
