# 100 MHz routed 时序违例全量定位与优化方案

> 分析对象：Vivado routed DCP，提交 `4762e00314f73810344185077f002c4c7db0dea6`  
> 器件 / 工具：`xc7k325tffg900-2` / Vivado 2023.2  
> CPU 时钟：`clk_out2_pll`，10.000 ns / 100 MHz  
> 分析日期：2026-07-11  
> 当前工作树 HEAD：`78f41bbe0dd0fc799dc16d37feea38b0875d8e20`，**不是本报告对应的实现版本**

## 0. 结论先行

100 MHz **有实现可能，但当前 netlist 不能靠 implementation directive、局部复制或修一条 WNS 路径收敛**。当前 CPU setup WNS 为 `-4.495 ns`，TNS 为 `-127382.055 ns`，47,536 / 73,199 个 CPU endpoint 失败；最差路径的数据延迟为 14.037 ns，需要至少削减约 4.495 ns（约 32%）才能刚好归零。

决定性证据是：47,536 个失败 endpoint 的最差路径源头高度集中在三个结构链上：

1. `u_rename/srat_q`：20,145 个 endpoint，42.38%；
2. `u_rob/head_q`：19,478 个 endpoint，40.98%；
3. `complete_prd`：5,139 个 endpoint，10.81%。

三者合计覆盖 94.16% 的失败 endpoint。它们分别对应：

- rename 映射结果同拍穿过 dispatch，写入 ROB / IQ 的宽 payload；
- ROB head 同拍选 retire entry、做 commit/recovery 判定，并把 recovery/clear 或请求控制扩散到全核、DCache 和 DRAM；
- completion/wakeup 同拍驱动 IQ 选择、PRF 异步读、执行/异常判定，再回到 PRF 写使能。

因此达到 100 MHz 的主路径是增加明确流水边界、稳定槽位/分 bank、局部化恢复与存储控制；实现选项只能作为 RTL 重构后的增益项。

## 1. 分析边界与“全量”的定义

### 1.1 版本边界

- 所有数值和路径均绑定归档提交 `4762e003...` 的 `top_routed.dcp`。
- 当前工作树为 `78f41bbe...`，其 RTL 已修改，但没有与本归档同口径的新 routed 证据。
- 文中的 RTL 行号指 `git show 4762e003:<path>` 得到的归档版本，不应直接套用当前文件行号。
- 后续 AI 开始改 RTL 前必须先运行：

```bash
git rev-parse HEAD
git diff --stat 4762e00314f73810344185077f002c4c7db0dea6..HEAD -- rtl/core
```

### 1.2 全量 endpoint 索引

原有 [`setup_violations_top1000.csv`](setup_violations_top1000.csv) 受 `-max_paths 1000 -nworst 100` 限制，只覆盖 20 个唯一 endpoint，不足以代表 47,536 个失败 endpoint。

本次新增：

- [`setup_violating_endpoints_all.csv`](setup_violating_endpoints_all.csv)：47,536 行，每个失败 endpoint 保留一条最差 setup 路径；
- [`export_all_setup_endpoints.tcl`](export_all_setup_endpoints.tcl)：只读打开 routed DCP，使用 `-max_paths 100000 -nworst 1 -slack_lesser_than 0` 复现全量索引。

这里的“全量”指 **全部失败 endpoint 的最差路径覆盖**，与 Vivado timing summary 的 47,536 完全一致。它不枚举同一 endpoint 的所有次差组合路径；需要查看同一 endpoint 的多条替代路径时，应联动 20.7 MB 的 [`setup_violations_top1000.rpt`](setup_violations_top1000.rpt)。

## 2. 全局时序状态

| 检查项 | 结果 | 判断 |
| --- | ---: | --- |
| CPU period / frequency | 10.000 ns / 100 MHz | 目标约束 |
| CPU setup WNS | -4.495 ns | FAIL |
| CPU setup TNS | -127382.055 ns | FAIL |
| CPU setup failing endpoints | 47,536 / 73,199 | 64.94% endpoint 失败 |
| 全设计 setup endpoints | 47,536 / 82,679 | 失败全部来自 CPU 域 |
| CPU hold WHS / THS | +0.056 ns / 0 ns | PASS |
| CPU async recovery WNS | +5.070 ns | PASS |
| 50 MHz system setup WNS | +16.581 ns | PASS |
| Pulse width | 最差 +1.100 ns | PASS |
| Routed nets | 81,386 / 81,386 | 全部完成布线 |
| QoR assessment | score 2 | Implementation completes; timing will not meet |

粗略 `Fmax = 1000 / (10.000 + 4.495) = 68.99 MHz`，只代表当前 placement/routing 的最差单路径等效值，不是稳定 Fmax。

### 2.1 裕量分布

| Slack 区间 | endpoint 数 | 占全部失败 endpoint |
| --- | ---: | ---: |
| `< -4.0 ns` | 1,503 | 3.16% |
| `[-4.0, -3.0) ns` | 20,724 | 43.60% |
| `[-3.0, -2.0) ns` | 14,232 | 29.94% |
| `[-2.0, -1.0) ns` | 6,844 | 14.40% |
| `[-1.0, -0.5) ns` | 2,554 | 5.37% |
| `[-0.5, -0.2) ns` | 1,247 | 2.62% |
| `[-0.2, 0) ns` | 432 | 0.91% |

关键含义：

- 46.76% 的失败 endpoint 比目标差 3 ns 以上；
- 76.70% 比目标差 2 ns 以上；
- 91.10% 比目标差 1 ns 以上。

这不是“尾部少量路径没收敛”，而是流水边界不足导致的大面积结构性违例。

### 2.2 逻辑深度

失败 endpoint 中有 23,025 条代表路径达到 27～32 个逻辑级，占 48.44%。最差路径为 30 levels；rename 相关路径最高 32 levels。即使单 LUT 延迟不高，大量级联选择器和跨区域 net delay 也会使 10 ns 无法收敛。

## 3. 全部失败 endpoint 的位置矩阵

### 3.1 按路径源寄存器归类：覆盖 47,536 / 47,536

| 源寄存器族 | endpoint 数 | 占比 | 最差 slack | 中位 slack | 主要含义 |
| --- | ---: | ---: | ---: | ---: | --- |
| `u_rename/srat_q` | 20,145 | 42.38% | -4.472 | -3.200 | rename 映射同拍写 ROB/IQ/dispatch |
| `u_rob/head_q` 复制体 | 19,478 | 40.98% | -3.820 | -2.772 | retire/commit/recovery 扩散到全核和存储系统 |
| `complete_prd` | 5,139 | 10.81% | -4.495 | -3.477 | wakeup→issue→PRF→execute→PRF/complete |
| BPU `update_pc_q` 复制体 | 2,048 | 4.31% | -1.752 | -0.749 | predictor table read-modify-write |
| `complete_rob_idx` | 478 | 1.01% | -1.900 | -0.559 | completion 写 ROB 多端口 decode |
| PC `pc_q` | 138 | 0.29% | -3.504 | -1.693 | PC→双 lane BPU/next-PC |
| `complete_valid` | 82 | 0.17% | -0.812 | -0.204 | completion 有效位写 ROB |
| BPU 非复制 `update_pc_q` | 27 | 0.06% | -0.514 | -0.242 | predictor update 局部路径 |
| 其他单点 | 1 | <0.01% | -0.093 | -0.093 | 非主因 |

该表是后续优化的最重要索引：每完成一个优化阶段，都应重新生成同表，确认源路径族数量真实下降，而不是 WNS 仅换了名字。

### 3.2 按目的模块归类：覆盖 47,536 / 47,536

| 目的模块 | endpoint 数 | 占比 | 最差 slack | 中位 slack | 最大 levels |
| --- | ---: | ---: | ---: | ---: | ---: |
| ROB | 13,923 | 29.29% | -4.380 | -3.014 | 31 |
| DCache | 11,505 | 24.20% | -3.820 | -3.032 | 24 |
| INT IQ | 6,191 | 13.02% | -4.472 | -3.414 | 32 |
| PRF | 4,032 | 8.48% | -4.495 | -3.666 | 32 |
| BPU | 2,195 | 4.62% | -1.752 | -0.754 | 16 |
| MEM IQ | 1,834 | 3.86% | -2.816 | -1.723 | 22 |
| Dispatch | 1,627 | 3.42% | -4.411 | -1.905 | 31 |
| SoC / 外部 DRAM BRAM | 1,553 | 3.27% | -3.642 | -1.654 | 22 |
| Store Buffer | 1,188 | 2.50% | -2.797 | -1.712 | 13 |
| Commit / CSR | 903 | 1.90% | -2.421 | -0.697 | 11 |
| Execute（不含 PRF） | 824 | 1.73% | -2.692 | -0.958 | 22 |
| Backend 其他 | 470 | 0.99% | -2.914 | -1.165 | 31 |
| Rename | 372 | 0.78% | -2.849 | -2.136 | 26 |
| Fetch Buffer | 344 | 0.72% | -3.448 | -0.527 | 28 |
| MulDiv IQ | 207 | 0.44% | -4.299 | -2.753 | 32 |
| PCGen | 101 | 0.21% | -3.504 | -2.148 | 20 |
| Fetch | 71 | 0.15% | -1.705 | -1.308 | 17 |
| CPU 顶层其他 | 70 | 0.15% | -2.649 | -2.489 | 21 |
| Busy Table | 63 | 0.13% | -2.683 | -2.244 | 27 |
| Free List | 63 | 0.13% | -3.347 | -3.014 | 27 |

### 3.3 主要源→目的路径族

| 源→目的 | endpoint 数 | 最差 slack | 中位 slack | 平均 / 最大 levels |
| --- | ---: | ---: | ---: | ---: |
| Rename→ROB | 13,351 | -4.380 | -3.058 | 28.2 / 31 |
| ROB head→DCache | 11,505 | -3.820 | -3.032 | 21.9 / 24 |
| Rename→INT IQ | 5,394 | -4.472 | -3.483 | 27.4 / 32 |
| Completion→PRF | 4,032 | -4.495 | -3.666 | 29.0 / 32 |
| BPU update→BPU tables | 2,075 | -1.752 | -0.738 | 12.3 / 13 |
| ROB head→MEM IQ | 1,834 | -2.816 | -1.723 | 21.0 / 22 |
| ROB head→外部 DRAM | 1,553 | -3.642 | -1.654 | 17.1 / 22 |
| ROB head→Store Buffer | 1,188 | -2.797 | -1.712 | 12.5 / 13 |
| ROB head→Commit | 903 | -2.421 | -0.697 | 9.3 / 11 |
| ROB head→Dispatch | 896 | -2.518 | -1.540 | 20.1 / 22 |
| Completion→Execute | 824 | -2.692 | -0.958 | 13.5 / 22 |
| ROB head→INT IQ | 797 | -2.674 | -1.190 | 13.7 / 15 |
| Rename→Dispatch | 731 | -4.411 | -2.956 | 27.0 / 31 |
| Rename→MulDiv IQ | 207 | -4.299 | -2.753 | 28.1 / 32 |
| PC→PCGen | 71 | -3.504 | -2.276 | 19.0 / 20 |

## 4. 路径族 A：completion/wakeup→MEM IQ→PRF→execute→PRF

### 4.1 最差路径

```text
complete_prd_reg[1][0]/C
→ MEM IQ wakeup compare
→ oldest-ready / issue_slot / issue_uop 选择
→ issue_uop.prs2
→ 64-entry、8-read-port PRF 异步读 MUXF8/LUT
→ MEM 地址加法（4×CARRY4）
→ misaligned/exception 判定
→ prf_we / 64-entry写地址译码
→ u_prf/regs_q_reg[27][14]/CE
```

| 属性 | 数值 |
| --- | ---: |
| Slack | -4.495 ns |
| Data path | 14.037 ns |
| Logic / route | 1.976 ns / 12.061 ns |
| Route 占比 | 85.9% |
| Logic levels | 30 |
| 结构 | 4 CARRY4、29 LUT/MUX、1 MUXF8 |

路径在 [`setup_violations_top1000.rpt`](setup_violations_top1000.rpt) 第一条。关键 net 包括：

- `complete_prd → u_mem_iq/wakeup_phy_i`，fanout 93；
- `u_mem_iq issue_uop.prs2[2] → PRF raddr`，fanout 128；
- execute 中间结果，fanout 120；
- PRF 写译码中间 net，fanout 114 / 32。

### 4.2 RTL 根因

归档版相关文件：

- `rtl/core/backend/CoreBackend.sv:326-437`：completion 同时广播给 INT/MEM/MUL IQ 和 Execute；
- `rtl/core/issue/MemIssueQueue.sv:61-130`：completion 参与所有 entry 的 ready 比较和同拍 oldest-ready 选择；
- `rtl/core/execute/ExecuteCluster.sv:402-464`：issue payload 直接形成 PRF 地址；
- `rtl/core/execute/ExecuteCluster.sv:437-520`：PRF 数据继续参与 ALU/AGU、异常和写回控制；
- `rtl/core/execute/PhysRegFile.sv:17-31`：64×32、8R4W 的 FF/LUT 多端口 PRF。

设计意图是实现“完成即唤醒、同拍选择、下一边沿写回”的低延迟后端，但 FPGA 上把 IQ CAM/select、PRF 大 mux、32-bit 加法、异常判断和多写口译码串成了一个周期。

### 4.3 推荐修改

优先方案：在 issue/execute 与 PRF writeback 之间建立真实寄存边界。

1. IQ 输出先进入 `issue_q/issue_valid_q`，grant 与完整 uop 同拍锁存；
2. 下一周期用稳定 `issue_q.prs1/prs2` 读 PRF；
3. execute 结果进入 `wb_q = {valid, prd, result, exception, rob_idx...}`；
4. PRF write enable/address/data只由本地 `wb_q` 生成；
5. completion/wakeup 与 PRF 数据可见时刻严格对齐。

若只加一级，优先加 `wb_q`，切断异常/ALU→PRF CE；若 routed 后 completion→issue→`wb_q` 仍超时，再给 issue grant/operand 增加一级。

必须保持的时序契约：

- 不能先广播 `complete_prd`，下一周期才写 PRF；否则消费者会读旧值；
- 若 PRF 写和 completion 在同一边沿发生，无组合 bypass 时，消费者最早应在该边沿后选择，并在后续边沿捕获操作数；
- load、mul/div 的可变延迟结果必须共用或仲裁到同一 completion/WB 协议；
- flush 必须清 `wb_valid`，payload 可不清。

如果删错/对齐错：会出现“依赖指令已被唤醒但 PRF 仍是旧值”、flush 后幽灵写回、同一 PRD 多写口冲突。

## 5. 路径族 B：sRAT→rename→dispatch→ROB/IQ 宽 payload

### 5.1 覆盖范围

`srat_q` 是 20,145 个失败 endpoint 的源头：

| 目的 | endpoint 数 |
| --- | ---: |
| ROB | 13,351 |
| INT IQ | 5,394 |
| Dispatch | 731 |
| Rename 自身 | 372 |
| MulDiv IQ | 207 |
| Free List | 63 |
| Fetch Buffer | 15 |
| Busy Table | 11 |
| 其他 | 1 |

最差代表路径：

```text
u_rename/srat_q_reg[15][0]/C
→ map_with_older_lane()
→ mapped_uop.prs*/old_prd
→ busy table query/ready
→ rename lane prefix + ROB/free-list/dispatch acceptance
→ wide CoreRenamedUop payload mux/compaction
→ INT IQ entry_q 或 ROB entry_q 的 D/CE/S/R
```

最差 slack 为 -4.472 ns，31 levels，14.351 ns data path。QoR 报告中的同类路径 route 占比达 89.3%～89.4%。

### 5.2 RTL 根因

- `RenameUnit.sv:46-63`：每 lane 对 sRAT 做映射并旁路更老 lane；
- `RenameUnit.sv:89-115`：同拍形成完整 `CoreRenamedUop`，查询 Busy Table；
- `RenameUnit.sv:120-140`：free-list、ROB、dispatch 和 lane-prefix 共同决定 fire；
- `DispatchUnit.sv:66-117`：INT/MUL 仍保持同拍 dispatch；
- `CompressedQueue.sv:129-153`：队列每拍压缩并重写宽 payload；
- `ROB.sv:166-199`：2 路分配和 4 路完成对 32-entry 宽 payload 做多端口写译码。

这是“组合 rename + 原子资源分配 + 同拍入 ROB/IQ”的大锥。两发射依赖旁路和 prefix 规则又增加了跨 lane 依赖。

### 5.3 推荐修改：allocated dispatch buffer

不要只在 `out_uop_o` 后随手打一拍；必须连同资源所有权一起重构：

1. rename 接收 lane 时，同时确认 free-list、ROB 容量和 dispatch-buffer 空间；
2. 在接收边沿分配 PRD、ROB index，更新 sRAT，并把完整 mapped uop 写入 buffer；
3. buffer 成为已分配 uop 的唯一所有者，后续等待 IQ ready；
4. ROB allocation 与 buffer enqueue 保持原子；不能出现 PRD 已消耗而 uop 未入 buffer；
5. recovery 清 buffer valid，sRAT 从 ARAT 恢复；
6. 两 lane 继续遵守 prefix：lane1 不得在 lane0 未接收时单独推进。

队列侧建议：

- INT/MUL IQ 由“每拍压缩宽 payload”改为 stable-slot + valid + age/tag；
- ready compare 与 payload 存储分离；
- 选择器输出 grant index，下一拍再读 payload；
- 若保持双发射，将 IQ 分 bank 或 hot/cold，减少每个 payload bit 的全局 mux；
- ROB 至少拆分 `valid/done/exception/branch` 热控制与 `pc/inst/result` 冷 payload，避免每个小控制变化重建整条宽数据选择网络。

如果只注册 payload、不处理资源原子性：会发生 ROB index 重用、PRD 泄漏、lane1 越过 lane0、recovery 后残留已分配 uop。

## 6. 路径族 C：ROB head→retire/commit/recovery→全核与存储系统

### 6.1 覆盖范围

`head_q` 复制体是 19,478 个失败 endpoint 的源头，最主要目的为：

- DCache：11,505；
- MEM IQ：1,834；
- 外部 DRAM BRAM：1,553；
- Store Buffer：1,188；
- Commit/CSR：903；
- Dispatch：896；
- INT IQ：797；
- Fetch Buffer：329；
- BPU / PCGen：150。

高扇出报告中 `u_commit/recover_valid_o` fanout 1,014，worst slack `-3.820 ns`，与本族最差值一致。

### 6.2 RTL 根因

组合链为：

```text
ROB head_q
→ wrap_add + 32-entry entry_q 动态选择
→ retire_entry_o / retire_valid_o
→ CommitUnit 两 lane 顺序检查
→ exception / mret / branch_miss
→ recover_valid_o + recover_pc_o
→ CoreBackend recover_i / 各队列 clear_i
→ frontend clear/redirect、StoreBuffer、Execute、DCache/DRAM 请求控制
```

归档版位置：

- `ROB.sv:113-129`：head 指针驱动 retire payload 的组合选择；
- `CommitUnit.sv:90-156`：两 lane 顺序 commit、trap 和 recover 组合生成；
- `core.sv:120-149,168-214`：recover 直接控制 fetch、PCGen、FetchBuffer，并反馈到 Backend；
- `CoreBackend.sv:280-459`：recover 直接并入 ROB/IQ/Execute/StoreBuffer clear；
- `DCache.sv` 与 DRAM bridge：backend 请求状态变化继续影响 LUTRAM/BRAM 写地址、WE、DI。

### 6.3 推荐修改：恢复事件与广域 flush 分级

建议把恢复分成两个概念：

- `redirect_event`：携带 PC 的单次事件；
- `flush_q`：注册后的、供后端和存储结构使用的广域 kill/clear。

实施顺序：

1. Commit 组合判断只写入本地 `recover_event_q = {valid, pc, cause}`；
2. `flush_q` 从该寄存事件产生，并在本地按模块复制，禁止一条组合 net 驱动上千 endpoint；
3. frontend 可从注册事件 redirect；若性能要求更高，branch miss 应在 execute 提前 redirect，commit 只负责精确 trap/mret；
4. recovery 事件出现到广域 clear 生效之间，必须立即阻断不可撤销副作用：store drain、uncached/MMIO write、CSR 二次提交；
5. PRF speculative 写可以在 ROB clear 后自然失效，但 free-list/sRAT/ROB 所有权必须在同一恢复协议下重建；
6. DCache/DRAM 接口增加本地 request register，外部请求只能由注册状态发起，不能由 recover 组合锥直接改变 RAM WE/WADR/DI。

注意：单纯给 `recover_valid_o` 加 `MAX_FANOUT` 或让 Vivado 自动复制，只能改善扇出后的 route，无法消除 `head_q→entry mux→commit decision` 的前半段长锥。

如果恢复打一拍但未阻断副作用：分支错误预测后的 store/MMIO 可能在 flush 前一拍对外生效，形成不可恢复的架构错误。

## 7. 路径族 D：DCache LUTRAM 与外部 DRAM

### 7.1 证据

- DCache 目的 endpoint：11,505，最差 -3.820 ns，中位 -3.032 ns；
- 外部 DRAM BRAM endpoint：1,553，最差 -3.642 ns；
- `data_way*` 高扇出 net 达 1,057，worst slack 到 -3.820 ns；
- `data_write_addr[0:5]` fanout 591，worst slack 到 -3.575 ns；
- 11,505 条 DCache 路径全部由 ROB `head_q` 启动，说明首要问题是跨模块控制锥进入 cache RAM 写控制，而不只是 cache 内部 hit 逻辑。

### 7.2 推荐修改

短期：

1. DCache request/response 用持有式寄存器切断 backend recovery/ready 组合传播；
2. LUTRAM `WE/WADR/WDATA` 只由本地注册 FSM 和注册请求产生；
3. writeback/refill payload、地址和 valid 成组寄存，直到下游 ready；
4. 将 recovery 解释为“取消尚未发出的 speculative load”，不能组合改写已登记的外部总线事务；
5. uncached/MMIO store 必须在 commit 后才允许进入不可撤销请求阶段。

中期：

- 当前 2-way、128-set、8-word/line 数据阵列每 way 为 1024×32 异步读 LUTRAM。考虑改为同步 BRAM 读，接受 1-cycle tag/data lookup；
- tag/data 访问流水化：`REQ → TAG/DATA READ → HIT/MISS → RESP`；
- refill/writeback 走独立小队列，避免与 hit path 共享大 mux；
- 通过 load queue / miss status 保持吞吐，而不是用同拍异步读换低 hit latency。

如果只改 RAM style 而不修改协议：Vivado 可能无法推断 BRAM，或读延迟改变后 CPU 仍按零周期 hit 消费旧数据。

## 8. 路径族 E：PC / BPU

### 8.1 证据

- `pc_o[2]` fanout 1,106，worst slack -3.488 ns；
- `bpu_lookup_pc[1][2:5]` fanout 436～1,061，worst slack -3.504 ns；
- PC `pc_q` 启动 138 个失败 endpoint；
- BPU `update_pc_q` 启动 2,075 个失败 endpoint；
- predictor update 目的以 512-entry `choice_pht_q/local_pht_q` 为主。

### 8.2 推荐修改

1. lookup 增加 `lookup_pc_q`，BPU 预测结果与 fetch request 的 PC/epoch 同步；
2. 512-entry PHT 改同步 RAM 或分 bank，prediction 至少两级：index/register → table read/resolve；
3. BTB tag/target 同样同步化，或先缩到 128/256 entries 验证时序/IPC权衡；
4. update RMW 分成读旧 counter、计算饱和新值、写回三个局部阶段；
5. redirect 使用 epoch 丢弃旧预测结果，不能只清 valid 而遗漏延迟返回的 BPU/ICache 响应。

BPU 不是当前 WNS 第一优先级，但在前三大路径族修复后，很可能成为新的 WNS，应提前设计成可流水化协议。

## 9. PRF、ROB 和 IQ 的 FPGA 化取舍

### 9.1 PRF

当前 PRF 是 64×32、8 read、4 write。其资源为约 9,253 LUT / 2,016 FF，并处于 QoR level-5 拥塞区域。建议按以下顺序评估：

1. 保持 FF PRF，但寄存读地址/写回，局部化 one-hot decode；
2. 将每个执行 lane 的读口放在局部副本，所有写回广播到副本；
3. 降低同周期写端口数，用 completion queue 仲裁写回；这会影响峰值 IPC，必须测 workload；
4. 如果使用 BRAM 复制实现多读口，先解决多写口冲突和副本一致性，不能只声明 `ram_style="block"`。

### 9.2 ROB

ROB 使用 17,357 LUT、8,835 FF、2,182 MUXF，是全核最大的结构热点。建议：

- 热字段与冷字段拆阵列；
- retire head payload 注册读取；
- completion 只写热字段和必要结果；
- 按 entry bank 分散 2 alloc / 4 complete 写译码；
- valid/done 作为可清状态，宽 payload 无 reset；
- commit 只看到注册 retire bundle，而不是直接动态 mux 32-entry 宽结构体。

### 9.3 IQ

- stable slot 优先于每拍压缩；
- wakeup compare 输出 ready bit，payload 不随 ready 更新而全体重写；
- grant/index 注册后再读 payload；
- INT 双发射按端口/功能或奇偶 bank；
- completion tag 广播按 cluster 复制，不用一条跨后端全局 net；
- 对同拍 wakeup-select 设明确策略：可以牺牲 1 cycle latency换频率，或只给最关键 bypass 保留 fast path。

## 10. 分阶段优化计划

### Phase 0：建立可比较的新基线

1. 在当前 HEAD `78f41bbe...` clean build；
2. 使用相同器件、100 MHz XDC、Vivado 2023.2、同一 report 脚本；
3. 导出全量 endpoint CSV；
4. 确认当前代码是否已经消除归档中的某些族，禁止用旧 DCP 判断新 RTL；
5. 保存 commit、DCP mtime/size、utilization、WNS/TNS、IPC。

验收：报告与 commit 一致；无 unconstrained internal endpoint；hold/recovery 不退化。

### Phase 1：切断 completion→PRF 最差路径

1. 增加 WB bundle register；
2. PRF WE/WADDR/WDATA 仅由 WB register 驱动；
3. completion/wakeup 与 PRF 可见性对齐；
4. 必要时注册 IQ grant/issue payload；
5. 用 dependency chain、load-use、mul/div、flush-during-WB 测试。

预期：`complete_prd` 源族 5,139 个 endpoint 大幅下降，PRF 不再是 WNS endpoint。该预期必须由 routed 结果验证。

### Phase 2：allocated dispatch buffer + stable-slot IQ

1. 先实现 rename/ROB/free-list/buffer 原子接收；
2. 再将 INT/MUL IQ 从宽 payload compaction 改为 stable slot；
3. ROB 热/冷字段拆分；
4. 加 prefix、PRD ownership、ROB uniqueness、flush ownership assertions。

预期：`srat_q` 源族 20,145 个 endpoint 消失或只剩短路径；ROB/INT IQ destination 数量大幅下降。

### Phase 3：注册 recovery 与存储请求边界

1. commit 输出注册恢复事件；
2. branch redirect 与 precise trap flush 分离；
3. broad clear 改注册、本地复制；
4. DCache/DRAM request register；
5. recovery pending 立即阻断 store/MMIO 副作用。

预期：`head_q` 源族 19,478 个 endpoint 大幅下降，DCache/DRAM 不再由 ROB head 启动。

### Phase 4：DCache/BPU 同步化

1. DCache tag/data BRAM pipeline；
2. BPU lookup/update pipeline；
3. 对每一级增加 epoch/kill 处理；
4. 测 miss、refill、writeback、redirect 与延迟响应交叉场景。

### Phase 5：实现侧收尾

仅在结构路径已被切断后尝试：

- `MUXF_REMAP=1`；
- critical LUT remap；
- critical net replication；
- `place_design` / `phys_opt_design` / `route_design` 的 Explore 类 directive；
- 针对 PRF/ROB/IQ 的局部 floorplan，而非全核大 Pblock；
- 2～3 种实现策略复跑，确认不是偶然 route seed。

当前最差路径 route 占比 85.9%，QoR 也给出 MUXF remap 和 replication 建议；这些可提供收尾增益，但不应被当成 4.495 ns 的主要修复手段。

## 11. 不应采用的“修复”

1. 不得给同一 `clk_out2_pll` 的真实单周期路径加 false path；
2. 不得无协议依据加 multicycle path；
3. 不得只看 WNS，忽略 47,536 endpoints 和 TNS；
4. 不得只按 fanout 排序，`cpu_rst_sync` fanout 8,674 但 slack 为正；
5. 不得只复制 `recover_valid`，忽略前端 ROB/commit 组合锥；
6. 不得只改 `ram_style`，不修改同步 RAM 带来的协议延迟；
7. 不得让 completion 在数据写入 PRF 前广播；
8. 不得为了时序清空所有 payload reset，却失去 valid/ownership 保护；
9. 不得用当前 HEAD 的源码行号解释 `4762e003` DCP；
10. 不得在未跑 routed 前宣称某个 RTL patch 已解决 100 MHz。

## 12. 功能与时序联合验证清单

### 12.1 每个 RTL patch 必测

- 单 lane / 双 lane rename，含 lane0→lane1 RAW/WAW；
- ROB full 边界、free-list empty、dispatch backpressure；
- INT 双发射、同拍 wakeup、多 completion 冲突；
- load-use、store data late wakeup、store-forward、cache miss/refill；
- mul/div 完成与普通 ALU 同拍；
- branch miss、exception、mret、flush 与 WB 同拍；
- flush 前后 PRD、sRAT、ARAT、ROB、IQ 所有权一致；
- MMIO/store 在错误路径上绝不对外生效；
- 延迟 BPU/DCache 响应被 epoch 正确丢弃。

### 12.2 建议 assertions

- lane1 fire → lane0 fire；
- 每个已分配 PRD 恰由一个在飞 uop 拥有；
- ROB index 不被两个有效 uop 同时拥有；
- `wakeup_valid(prd)` → 同边沿或更早 PRF 已写入对应 data；
- flush 后所有 pipeline valid 在限定周期内清零；
- store/MMIO request → 对应 ROB entry 已 commit；
- WB queue 不溢出，写口仲裁不丢 completion；
- IQ grant 只指向 valid、ready 且未被其他端口选择的 entry。

### 12.3 每轮 routed 必比指标

| 类别 | 必比内容 |
| --- | --- |
| Timing | WNS、TNS、failing endpoints、slack 分布、27+ levels 数量 |
| Path family | 前述源寄存器族计数和源→目的矩阵 |
| Physical | logic/route 占比、level-5 congestion、负 slack 高扇出 net |
| Resource | 全局及 ROB/PRF/IQ/DCache/BPU 的 LUT/FF/LUTRAM/BRAM/MUXF |
| Sign-off | hold、recovery、CDC、DRC、unconstrained、ignored clock crossings |
| Performance | 同 workload IPC、branch miss penalty、load-use latency、cache miss penalty |

最终通过标准：

- CPU setup WNS ≥ 0，TNS = 0，failing endpoints = 0；
- hold/recovery/pulse-width 全部通过；
- 不新增伪 false path/multicycle；
- 至少保留建议 +0.2～0.3 ns routed margin，避免接近 0 的偶然收敛；
- 功能回归全过，IPC 退化在项目可接受范围内。

## 13. 约束与 sign-off 风险

这些不是当前 CPU WNS 的成因，但最终 100 MHz sign-off 必须处理：

1. 50 MHz 与 100 MHz 来自同一 PLL，却被 async clock group 整域切断；两个方向为 user ignored，应确认真实 CDC 协议；
2. `report_cdc` 有 `CDC-10 Critical=31`、`CDC-6 Warning=4`；
3. `i_uart_rx` 无 input delay，69 个 output port 无 output delay；
4. DRC 有 `REQP-1839=20`，IROM BRAM 地址/控制由异步 set/reset 寄存器驱动；
5. methodology 有 `TIMING-16`、`TIMING-28/47`、`HPDR-2`；
6. `report_design_analysis -congestion` 在 Vivado 2023.2 对该 DCP 崩溃，拥塞判断应使用 QoR assessment/suggestions 和 placement GUI 交叉确认。

CPU 内部违例全部是 `clk_out2_pll → clk_out2_pll` 的真实单周期 setup path，不能用上述 CDC/IO 约束问题解释或豁免。

## 14. 后续 AI 接手顺序

后续 AI 应按以下顺序执行，不要直接开始随机改 RTL：

1. 读取本文件、`README.md`、全量 endpoint CSV；
2. 核对当前 HEAD 与 DCP commit；
3. 对当前 HEAD clean routed，重新生成全量矩阵；
4. 一次只选择一个结构路径族；
5. 先写周期级协议和 flush/ready/valid 对齐表，再改 RTL；
6. 先做功能仿真和 assertions，再综合/routed；
7. 每轮保存 commit、patch、WNS/TNS/endpoints、资源和 IPC；
8. 若 WNS 改善但 endpoint/TNS 恶化，不接受该 patch；
9. 直到 WNS/TNS/endpoints 全通过，再做实现策略收尾。

建议第一项实际优化任务：**在归档 RTL 语义基础上设计并实现 registered writeback bundle，使 PRF write 与 completion/wakeup 对齐，并切断 `complete_prd→MEM IQ→PRF→execute→PRF CE` 路径；暂不同时修改 rename 和 recovery。** 这样改动边界清晰，容易用 dependency-chain 与 flush-during-WB 测试证明正确性，也能直接验证当前 WNS 路径族是否消失。

## 15. 证据文件索引

| 文件 | 用途 |
| --- | --- |
| [`setup_violating_endpoints_all.csv`](setup_violating_endpoints_all.csv) | 全部 47,536 失败 endpoint 的最差路径索引 |
| [`export_all_setup_endpoints.tcl`](export_all_setup_endpoints.tcl) | 全量 endpoint 索引复现脚本 |
| [`timing_summary_max100.rpt`](timing_summary_max100.rpt) | 全局、分时钟 WNS/TNS/hold/recovery |
| [`setup_violations_top1000.rpt`](setup_violations_top1000.rpt) | 最差路径的完整 pin/clock/net 延迟详情 |
| [`design_analysis_timing.rpt`](design_analysis_timing.rpt) | 最差路径 logic/net 特征 |
| [`high_fanout_nets.rpt`](high_fanout_nets.rpt) | 高扇出、worst slack 和 worst delay |
| [`qor_assessment.rpt`](qor_assessment.rpt) | 拥塞等级、失败 endpoint 和预算 |
| [`qor_suggestions.rpt`](qor_suggestions.rpt) | MUXF remap、LUT remap、net replication 建议 |
| [`design_analysis_complexity.rpt`](design_analysis_complexity.rpt) | ROB MUXF/Rent/结构复杂度 |
| [`utilization_hier.rpt`](utilization_hier.rpt) | 模块级资源热点 |
| [`clock_interaction.rpt`](clock_interaction.rpt) | ignored clock crossings |
| [`cdc.rpt`](cdc.rpt) | CDC critical/warning 路径 |
| [`check_timing.rpt`](check_timing.rpt) | unconstrained I/O 检查 |
| [`methodology.rpt`](methodology.rpt) / [`drc.rpt`](drc.rpt) | methodology 与 DRC 风险 |
