# dev-v3.0：250 MHz routed 全量时序违例分析与优化方案

## 1. 分析范围

本文分析对象是 `dev-v3.0` 当前 RTL 在 Kintex-7 `xc7k325tffg900-2` 上、CPU 时钟 250 MHz（4.000 ns）的最终 routed checkpoint：

```text
fpga/build/digital_twin_srcWithMext_250.000MHz/
  digital_twin.runs/impl_1/top_routed.dcp
  reports/timing_summary_250.000MHz.rpt
  reports/utilization_routed_250.000MHz.rpt
  reports/deep_timing/
```

除原有 timing summary 外，本次从 routed checkpoint 额外导出了：

- 全部 11,906 个负 slack endpoint 的 summary；
- 最差 500 条 setup 完整路径；
- 最差 200 条 hold 路径；
- 前 200 个高扇出网络；
- control-set、QoR assessment 和 logic-level distribution。

路径分类依据层次名称做启发式聚类，因此分类数字用于判断结构占比，不替代 Vivado 原始报告。

## 2. 总结论

当前设计不是“差一点过 250 MHz”，而是流水边界仍按 100--150 MHz 级别组织。250 MHz 失败不是单个关键路径，而是三个大面积路径族共同造成：

1. LSU/DCache 请求组合穿过地址解析、cache 判定、SoC 地址译码和外部 BRAM 控制；
2. 外部 BRAM 返回组合穿过 SoC mux、DCache refill/formatter，再进入大量 DCache 状态；
3. completion gearbox 的 tag/data 同拍参与 EX 旁路、LS 唤醒和全局 stall/CE，形成反向控制传播。

此外，CPU reset 仍直接驱动 1,927 个异步 reset 负载，单独造成 628 个 recovery 失败端点。

因此：

- `phys_opt_design`、更激进 directive、简单 pblock 不足以消除约 3.9 ns WNS；
- 必须增加真正的 registered request/response 边界；
- 必须把 queue wakeup 与全局 ready/CE 解耦；
- DCache 最终需要同步 BRAM 化，或至少增加 L0 快速小缓存以保持 IPC；
- reset 必须改成异步置位、同步释放后只驱动同步 reset/valid。

## 3. 全局时序健康度

### 3.1 Setup/recovery/hold

| 项目 | 结果 |
|---|---:|
| CPU clock | 250.000 MHz / 4.000 ns |
| CPU setup WNS | `-3.892 ns` |
| CPU setup TNS | `-19,995.914 ns` |
| CPU setup failing endpoints | 11,278 / 19,688 |
| recovery WNS (`async_default`) | `-3.157 ns` |
| recovery TNS | `-564.167 ns` |
| recovery failing endpoints | 628 / 1,212 |
| 合计负 slack endpoint | 11,906 |
| hold worst slack | `+0.062 ns` |
| pulse-width worst slack | `+1.232 ns` |

按 WNS 粗略反推，最差路径对应的有效周期接近 `4.000 + 3.892 = 7.892 ns`，约 126.7 MHz。这个数不是正式 Fmax，但说明 250 MHz 需要架构级切段，而不是亚纳秒级微调。

### 3.2 Slack 分布

| Slack 区间 | Endpoint 数量 | 占比 |
|---|---:|---:|
| `<= -3 ns` | 1,280 | 10.8% |
| `(-3, -2] ns` | 3,849 | 32.3% |
| `(-2, -1] ns` | 3,436 | 28.9% |
| `(-1, 0) ns` | 3,341 | 28.1% |

有 5,129 个 endpoint 低于 `-2 ns`。即使消除当前 WNS，后面仍有大批同等级路径，不能用逐条 ECO 的方式收敛。

### 3.3 前 500 条最差路径特征

| 指标 | 统计 |
|---|---:|
| 平均 data path delay | 7.216 ns |
| 平均 logic delay | 1.685 ns |
| 平均 route delay | 5.532 ns |
| 平均 route 占比 | 76.7% |
| route 占比 `>= 70%` | 500 / 500 |
| route 占比 `>= 80%` | 15 / 500 |
| 平均 logic levels | 17.7 |
| logic levels 范围 | 13--21 |

最差 1,000 条路径的逻辑级分布中，17 级有 636 条，20 级有 183 条，21 级有 11 条。问题同时包含“逻辑太深”和“网络跨得太远”；不能因为 route 占比高，就误判为只需 floorplan。

## 4. Endpoint 与路径族聚类

### 4.1 按 endpoint 模块

| Endpoint 类别 | 数量 | 主要含义 |
|---|---:|---|
| DCache | 5,713 | refill、data/tag RAM、response、cache update |
| Execute/M unit | 2,914 | queue bypass、乘除输入、CSR/EX 控制 |
| External DRAM BRAM | 1,416 | BRAM enable/write-enable/address |
| Register file | 426 | 写回和 operand 数据路径 |
| ID/C1 register | 377 | decode/RF/issue 和全局 CE |
| Core other | 369 | hazard、PC、BPU、局部控制 |
| ID/LS register | 238 | 地址/数据 pending、hold、CE |
| IF/ID register | 225 | stall/flush/PC/instruction CE/D |
| SoC memory bridge | 187 | request/response mux、MMIO/DRAM decode |
| C1/C2 register | 36 | EX completion/control |
| LS/WB register | 1 | load metadata |

### 4.2 按 source 模块

| Source 类别 | 数量 | 主要含义 |
|---|---:|---|
| SoC memory bridge | 5,020 | 外部 BRAM 返回到 DCache |
| Completion queue | 2,868 | `wbq0/wbq1` tag/data 广播和 ready 反馈 |
| LS/WB | 2,060 | load valid、LS completion 到 memory/control |
| CPU reset | 631 | recovery 和少量普通控制路径 |
| External DRAM BRAM | 515 | BRAM read data 到 DCache |
| C1/C2 | 405 | EX result/metadata 到旁路和 RF |
| ID/C1 | 203 | EX/M/branch 数据路径 |
| Execute | 82 | EX 内部/M unit |
| IF/ID | 67 | decode/RF/issue |
| ID/LS | 55 | memory request 到 bridge |

### 4.3 最大路径族

| Source -> Endpoint | 数量 | 结论 |
|---|---:|---|
| SoC memory bridge -> DCache | 5,020 | 最大路径族，外存 response 没有局部寄存边界 |
| Completion queue -> Execute | 1,972 | queue tag/data 直接进入 EX/M operand 网络 |
| LS/WB -> External DRAM BRAM | 1,416 | store/request 组合直达 68 个 BRAM tile |
| Completion queue -> ID/C1/core/IF/LS | 806 | queue wakeup 反向传播到全局 CE/stall |
| External DRAM BRAM -> DCache | 515 | BRAM read data 进入 refill/response/cache write |
| CPU reset -> Execute/core/ID/LS | 596+ | 异步 reset 高扇出 recovery |
| C1/C2 -> Execute/RF | 405 | 普通结果旁路仍较分散 |

## 5. 关键路径族逐项分析

### 5.1 LS/WB -> DCache -> SoC -> external DRAM BRAM

最差 setup 路径：

```text
u_reg_ls_wb/o_valid
  -> completion/LS dependency and stall logic
  -> 32-bit address selection/addition
  -> DCache cacheable/hit/request mux
  -> SocMemBridge DRAM range decode and address subtract
  -> DramBramAdapter enable/write-enable
  -> DRAM_0 RAMB36E1 ENARDEN/WEA
```

报告数据：

- WNS：`-3.892 ns`；
- data path：7.428 ns；
- logic：1.534 ns（21%）；
- route：5.894 ns（79%）；
- logic levels：20；
- 路径包含 7 个 CARRY4。

根因不是 BRAM 本身慢，而是同一拍内串联了：地址依赖解析、AGU carry、cache hit/range、SoC range/subtract、BRAM enable。外部 DRAM 是 256 KiB、68 个 RAMB36 tile，单一 enable/address 网络天然跨越多个 BRAM column。

特别值得修正的 RTL：

- `SocMemBridge` 已经知道 DRAM 范围是 `0x8010_0000--0x8013_FFFF`，但仍执行 32-bit 比较和 `req_addr - P_DRAM_ADDR_START`；
- `DramBramAdapter.req_ready` 恒为 1，却仍把 ready/valid 当作组合握手反向传播；
- store 在 DCache idle 状态直接组合穿透到外部 memory request；
- BRAM `ena` 由深组合逻辑驱动，而不是固定使能或局部寄存 token。

### 5.2 SoC/DRAM response -> DCache

5,535 个 endpoint 属于 `Soc bridge/DRAM -> DCache`。当前读返回路径为：

```text
DRAM_0 synchronous output
  -> DramBramAdapter byte shift
  -> SocMemBridge DRAM/MMIO response mux
  -> DCache refill shift / resp mux / data RAM write
  -> resp_rdata_q, tag/data RAM, fill state
```

外部 BRAM 已经提供同步读，但 BRAM 输出后的 formatter、response arbitration 和 DCache refill update 仍处于同一个 4 ns 周期。这个路径只在 miss/refill/uncached load 上活跃，却拖累全部实现。

### 5.3 Completion gearbox -> EX/LS/global CE

当前 completion gearbox 用通用 `for` 循环构造候选顺序，同时把 `wbq0/wbq1` 的 rd/data 广播给：

- C0 RF bypass；
- C1 EX operands；
- LS pending address/data 比较；
- `ls_operands_ready`；
- `ls_busy -> hazard_unit -> IF/ID、ID/C1、ID/LS CE/hold`。

最差 queue 路径由 `wbq1_rd[0]` 出发，进入 IF/ID D 或 ID/LS/ID/C1 CE，约 17 logic levels、7.45--7.69 ns。这里最危险的不是 5-bit rd comparator，而是“数据唤醒结果在同一拍决定全核是否前进”。

Queue 的精确顺序价值是正确的，但它不应该兼任全局 combinational scheduler。

### 5.4 IF/ID -> decode/RF -> ID/C1

methodology 报告还显示多条：

```text
IF/ID instruction bits
  -> decode + RF address
  -> asynchronous RF read / issue bypass
  -> ID/C1 operand register
```

slack 约 `-1.0 ... -1.8 ns`。即使 memory/queue 大路径被切断，当前 C0 仍不足以稳定达到 250 MHz。寄存器堆本身只有约 113 LUT，不是面积问题；问题是 instruction decode、异步读、多个 bypass source 和 operand capture 串在一拍。

### 5.5 DCache distributed RAM 高扇出

当前 DCache 映射为约 258 个 `RAM64M`。高扇出报告显示：

- `data_write_index_c[0..5]` 每位 fanout 约 960；
- `dram_addr[4..9]` fanout 约 668--732；
- tag/data bank 分布跨大量 SLICEM；
- DCache 本体约 1,778 LUT，其中 880 个 LUT 用作 memory。

芯片总 LUT 利用率只有 5.38%，没有全局拥塞；高 route delay 来自一个逻辑地址同时驱动大量物理分散 RAM pin，而不是资源耗尽。

### 5.6 M unit 与 EX 高扇出

`rs2_ip` 多个位 fanout 约 199，`rs1_ip[31]` fanout 246；当前 M unit 实例化三套乘法器，对相同 operand 做 signed/unsigned 扩展。即使 M unit 不是 WNS 第一名，它形成了大量 `-2.x ns` 路径，也是 2,914 个 EX endpoint 的组成部分。

### 5.7 Reset recovery

`cpu_rst_sync` fanout 为 1,927，其中 1,880 个是异步 set/reset pin。典型路径：

```text
cpu_rst_sync_reg/Q
  -> 5.842 ns routed reset net
  -> m_unit orig_rs1_q[*]/CLR
```

- recovery data path：6.046 ns；
- logic levels：0；
- route 占比：96.6%；
- recovery slack 约 `-2.60 ns`，path-group WNS 最差 `-3.157 ns`。

这是纯 reset 架构问题，不应通过普通 placement 解决。

### 5.8 Hold、约束和实现质量

- hold 全部通过，最差 `+0.062 ns`；后续增加局部寄存器时要重新检查，但当前无需 hold ECO；
- 没有 unconstrained internal endpoint、multiple-clock register 或 combinational loop；
- 顶层仍有 1 个 input、69 个 output 未设置 I/O delay；不影响当前内部 CPU WNS，但最终板级 signoff 必须补齐；
- QoR congestion 和 utilization 均为 5/5，说明不是容量问题；
- QoR 发现一个 `DONT_TOUCH`：整个 `student_top` 实例被 `keep_hierarchy + dont_touch`，同时综合采用 `flatten_hierarchy none`。这会限制跨 core/DCache/bridge 边界的复制、重定时和布线优化。

## 6. 推荐优化方案

### 6.1 P0：先切断三条结构性长链

### P0-A：固定延迟、寄存化的 memory request 边界

在 DCache 与 `SocMemBridge` 之间增加 request register/小 StoreBuffer：

```text
DCache request
  -> {valid, write, addr, data, mask, uncached} register
  -> SocMemBridge/BRAM
```

要求：

- 外部 BRAM `req_ready` 恒 1 的事实在接口中显式化，不再让 ready 组合回到 core；
- cache miss request、uncached request、write-through store 都只由寄存器驱动外部端口；
- 2-entry StoreBuffer 支持每拍接受 store，避免增加 CPI；
- load 遇到未排空 store 时做地址比较和 byte forwarding，MMIO/fence 必须先排空；
- branch kill 只能丢弃尚未对外 handshake 的年轻 store。

这项直接针对 1,416 个 LS/WB -> DRAM endpoint 和最差 WNS。

### P0-B：miss-only response register

在 DCache 外部 response 入口增加本地寄存器：

```text
mem_resp_valid/rdata
  -> refill_resp_q
  -> DCache write/critical-word response
```

它只给 miss/refill/uncached load 增加一拍，不改变 DCache hit latency。当前 miss rate 约 4.25%，因此 CPI 影响远小于给所有 load 增加一拍，却能切断 5,535 个 response-to-DCache endpoint。

### P0-C：LS dependency 只在寄存边界唤醒

当前 `wbq tag -> match -> ls_operands_ready -> request/stall` 是同拍组合路径。改为：

1. queue/current WB 命中 pending rd 时，只写入 `reg_id_ls` 的 resolved operand 并清 pending；
2. 本拍仍视为 not-ready；
3. 下一拍由已寄存的 `mem_addr/store_data` 发请求。

这样 dependent load/store 多一拍，但独立访存不受影响。应先增加动态 counter，测量 address/data dependency 命中次数，再评估 IPC。

### P0-D：reset 分层同步化

- 顶层保留两级 async-assert/sync-deassert synchronizer；
- synchronizer 输出只作为 CPU 域同步 reset condition，不再驱动 1,927 个异步 CLR/PRE；
- pipeline 只 reset valid/epoch/busy，不 reset payload；
- DCache data/tag payload 不 reset，只 reset valid；
- 对 M unit、DCache、core front 各增加一个本地同步 reset replica，允许物理复制；
- 不对 recovery 路径简单设 false path，除非内部逻辑已真正同步释放。

### 6.2 P0：针对固定内存映射的偏门快路径

### P0-E：去掉 32-bit DRAM 地址减法

DRAM 范围是对齐的 256 KiB：

```text
0x8010_0000 -- 0x8013_FFFF
```

因此 BRAM word address 可以直接使用：

```systemverilog
dram_word_addr = req_addr[17:2];
dram_sel       = (req_addr[31:18] == 14'h2004); // 需由脚本/常量精确生成
```

无需 `req_addr - 32'h8010_0000`，也无需两个 32-bit 大小比较串行决定地址。高位等值比较、低位地址和请求 valid 可以并行。报告最差路径中的 7 个 CARRY4 很可能有相当部分来自 AGU/range/subtract；这是针对固定映射非常有效的 FPGA 特化。

实现时不能手写错误常量，应该从 `P_DRAM_ADDR_START` 和容量参数推导 prefix/offset width，并加 elaboration assertion 检查对齐和 2 的幂大小。

### P0-F：BRAM enable 常开，valid token 单独流水

对同步读 DRAM，可考虑：

- `ena = 1'b1`，BRAM 每拍读取当前 registered address；
- 请求有效性用独立 `read_valid_q` 控制 response；
- write enable 仍由注册后的 StoreBuffer 驱动。

这样可以完全消除大量 `... -> RAMB36 ENARDEN` setup 路径，代价是 BRAM 动态功耗增加。对于比赛 FPGA、资源和功耗余量充足时，这是很实用的偏门技巧。

### P0-G：外部 DRAM 物理分银行

当前 68 个 RAMB36 共用 enable/address。可把 256 KiB DRAM 切成 4 或 8 个物理 bank：

- 用高地址位在 request register 前生成 one-hot bank select；
- 每个 bank 只驱动 8--16 个 RAMB36；
- bank-local address/enable register 靠近对应 BRAM column；
- read response 用已寄存 bank id 选择。

这不会改变软件地址空间，却显著降低地址/enable fanout。相比给单一 700+ fanout 网络加 `max_fanout`，物理银行有更稳定的布局结果。

### 6.3 P0/P1：重构 completion gearbox

### 方案 1：控制与数据分离

- queue `count/full/empty` 可以参与全局 stall；
- queue `rd/data` 只进入 consumer-local bypass；
- rd match 不允许同拍反向驱动 IF/ID、ID/C1、ID/LS CE；
- 每个 consumer 有本地命中寄存器或 wakeup register。

这是必须先做的基础方案。

### 方案 2：`q0 fast + q1 cold spill`

当前最差 queue 路径从 `wbq1_rd[0]` 发出。先增加 q1 occupancy counter；如果 q1 极少使用：

- q0 保持普通旁路；
- q1 不接入全核 fast bypass；
- q1 valid 时冻结一拍，先把 q0 commit、q1 移到 q0；
- 下一拍恢复。

这用极低概率的一拍 stall 换掉 q1 的全局 tag/data 广播。它比为罕见双碰撞构建永久 fast crossbar 更符合 FPGA。

### 方案 3：Shadow Result Map

用 32-entry shadow value/valid map 替代多 entry tag CAM 广播：

```text
shadow_valid[rd] = 1
shadow_data[rd]  = result
shadow_seq[rd]   = producer sequence
```

消费者用 rs 地址直接索引 shadow map；commit 时只有 sequence 匹配才清 valid。这样把多个 5-bit comparator/priority tree 转成 RAM read。需要解决同拍两个 producer 写不同 rd 的双写问题，可以用两份 bank + newest-select，或只把 cold producer 延后一拍。

### 方案 4：显式 case 状态机替代通用 for-loop gearbox

Queue 深度固定为 2，可以按 `{q_count, ls_valid, ex_valid}` 写出 12 个明确 case。Vivado 更容易得到局部 mux，而不是从整数 `keep_count` 和循环推导通用优先网络。面积差别小，但可能显著改善结果可预测性。

### 6.4 P1：DCache 同步 BRAM 化并保护 IPC

### 基础结构

- 数据阵列改为一个 `1024 x 32` RAMB36E1，使用 byte write enable；
- CPU lookup 用端口 A，refill/store update 用端口 B；
- tag/valid 同步读，C0 地址、C1 lookup、C2 load WB；
- 每个 word 独立 valid，避免必须填满整行；
- read-during-write 冲突用 pending store forwarding。

这会消除 258 个 RAM64M 和 `data_write_index_c[*]` fanout 960 的网络。

### 偏门 IPC 保护：L0 hot-line register cache

为避免所有 hit 因同步 BRAM 增加一拍，可在 BRAM DCache 前放一个 1-line 或 2-word 的寄存器 L0：

- 保存最近命中/critical word 的 tag、data、byte valid；
- L0 hit 维持当前一拍 load path；
- L0 miss 才走两拍 BRAM DCache；
- store 同时更新 L0 和排队更新 L1；
- refill critical word 优先进入 L0，后台写 L1。

对数组遍历、栈和热点循环，极小 L0 可能覆盖大部分连续 load；它用几十个 FF 换取同步 BRAM 的 Fmax，同时避免 IPC 大幅下降。

### 偏门布局：每 bank 本地复制 index register

如果暂时保留 LUTRAM，可为 4 个 word bank 各复制一份 registered index/write command，让每份只驱动 4 个 byte lanes。不要依赖综合器从一个 fanout-960 LUT 输出自动复制；显式局部寄存器更容易贴近 SLICEM bank。但这只是过渡方案，无法根治异步 read mux。

### 6.5 P1：C0 decode/RF 分段

在 memory/queue 路径修复后，IF/ID -> ID/C1 会成为下一瓶颈。推荐二选一：

1. `D0 predecode/RF address -> D1 RF data/bypass/dispatch`；
2. 在 IROM 输出边界预先寄存 rs1/rs2/opcode/imm type，把复杂 decode 与 RF read 并行化。

为控制 branch penalty，可让 branch/JAL 的 PC-relative target 继续在早期计算，普通 ALU operand 延后一拍。新增一级本身不会降低稳态 IPC，但会增加 branch mispredict penalty；当前 branch miss 很低，频率收益更重要。

### 6.6 P1：M unit 局部化

- 三套 multiplier 合并为一套可选符号扩展的 33x33 signed multiplier；
- rs1/rs2/sign mode 在 M unit 入口本地寄存；
- 普通 EX 不再驱动三套乘法输入网络；
- DIV quotient/remainder 同时缓存，匹配的后续 REM/DIV 一拍返回；
- M busy/done 通过本地 completion token 进入 queue，不直接控制大范围 operand mux。

这既降低 M input fanout，也可能提高 IPC。

### 6.7 P2：物理实现与综合策略

结构改完后再做：

- 删除 `student_top` 整体 `dont_touch`，必要时只保护真正需要的 debug/CDC 寄存器；
- `flatten_hierarchy` 从 `none` 改为 `rebuilt` 做 A/B 实验；
- 对 request/response、reset local replica 使用 `MAX_FANOUT` 或显式寄存器复制；
- IF/RF/EX、DCache、DRAM bank 分别建立宽松 pblock，保留约 20% 空白；
- DCache 靠 SLICEM/BRAM，M unit 靠 DSP column，外部 DRAM bank 沿 BRAM column 分布；
- 使用 `Performance_Explore`/`AggressiveExplore` 和 post-route phys-opt 做最后数百 ps 收敛；
- 不要在当前 WNS `-3.9 ns` 时用多个 seed/directive 暴力搜索。

## 7. 不建议采用的“假优化”

- 对 CPU 数据路径直接设 multicycle：协议并没有保证数据多拍稳定，会掩盖功能错误；
- 把 reset recovery 全部 false-path：当前 reset 确实直达异步 CLR，释放不同步；
- 恢复通用 EX -> AGU 组合旁路：会重新制造 ALU + AGU 反馈；
- 双边沿 RF 或人为 useful skew：在 4 ns 周期下验证和 hold 风险过高；
- 只加 pblock/LOC：路径平均 17.7 级，floorplan 无法替代寄存边界；
- 只优化 branch predictor：branch miss 对当前 CPI 贡献很小；
- 为所有 load 固定插一拍：可能把 IPC 从 0.826 拉回 0.8 以下，应采用 hit/miss 分离和 L0 快路径。

## 8. 推荐实施顺序

### Phase A：低 IPC 风险、直接减少大路径族

1. reset 同步化和 payload 免复位；
2. 删除 32-bit DRAM subtract/range carry，改 prefix compare + low-bit address；
3. registered memory request + 2-entry StoreBuffer；
4. miss-only response register；
5. 删除顶层 `dont_touch`，用 `flatten_hierarchy rebuilt` 做一次实现对比。

预期主要消除：1,416 个 LS->DRAM、5,535 个 response->DCache、628 个 recovery endpoint。

### Phase B：queue/control 切段

1. 加 q0/q1 occupancy 和 LS dependency 动态 counter；
2. LS wakeup 改为寄存后下一拍 request；
3. queue tag/data 与 global CE 分离；
4. 评估 `q0 fast + q1 cold spill`；
5. 显式 case gearbox 或 shadow result map。

预期主要消除：2,868 个 completion queue source endpoint。

### Phase C：同步存储体系

1. RAMB36 DCache；
2. sector valid；
3. L0 hot-line/critical-word register cache；
4. external DRAM 4/8 bank 物理化；
5. BRAM enable 常开方案做功耗/时序 A/B。

### Phase D：剩余前端/执行路径

1. predecode/RF 分段；
2. 单 multiplier 和 M operand local register；
3. BPU 同步 lookup/epoch flush；
4. 最终 pblock、replication、directive 和 seed 探索。

## 9. 每阶段验收指标

每一轮只跑一次 Vivado，但在 RTL 合并前必须满足：

- RV32 directed 全套 PASS；
- `srcSmoke` 和 `srcWithMext` 功能计数无退化；
- `srcWithMext` 5M IPC `>= 0.80`；
- gearbox overflow、StoreBuffer overflow、duplicate request、store replay 均有 assertion；
- routed setup/hold/recovery 全部记录；
- 对比 failing endpoint 数和路径族，不只看 WNS；
- 目标顺序应是：先把 `<= -2 ns` endpoint 从 5,129 降到接近零，再做最后物理收敛。

## 10. 最终判断

250 MHz 在该器件和低利用率下并非资源上不可能，但当前 RTL 需要从“组合 ready/旁路驱动全局流水”转为“局部 elastic slot + registered token”。最有价值的三个改动不是更复杂的预测器或更宽执行，而是：

1. 固定映射特化的 registered memory port；
2. queue wakeup 与全局 CE 解耦；
3. BRAM DCache + 极小 L0 快缓存。

其中“低地址直通代替 32-bit subtract”“BRAM enable 常开”“q1 cold spill”“L0 hot-line register cache”“外部 DRAM 物理分银行”是本项目上最值得实验的偏门方案。它们都利用了 FPGA 的真实物理结构和 workload 特征，而不是把 ASIC 风格的全局组合网络硬搬到 4 ns 周期中。
