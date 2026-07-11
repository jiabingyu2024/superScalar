# srcWithMext 当前 IPC / Fmax 优化状态与下一阶段路线

日期：2026-07-11

当前 RTL 提交：248b9c064d8fc5e3bd210adef664d6f2885231d2（STA fix and opt ipc）

历史分析：

- [061_ipc_fmax_joint_optimization_analysis.md](./061_ipc_fmax_joint_optimization_analysis.md)
- [061_vivado_100mhz_timing_baseline/README.md](./061_vivado_100mhz_timing_baseline/README.md)

目标：在不破坏 RV32 正确性、内存顺序和 routed sign-off 的前提下，提高完整 srcWithMext 的 IPC × Fmax，最终使 counter start 到 counter stop 的板上时间不超过 3 秒。

## 0. 证据边界

本文是 061 的状态收口和后续执行版，不重复把已经完成或已经否决的实验写成待办。

必须区分三类证据：

1. 历史完整性能基线来自旧版本完整 srcWithMext PASS：380,344,388 commits、544,821,211 个有效 cycles、IPC 0.698105、50 MHz 下 10.896 秒。
2. 当前提交 248b9c0 已有 RV32、srcSmoke、500k 和 50M 仿真证据，但尚未跑当前版本完整 srcWithMext PASS。
3. 唯一 routed 100 MHz 报告对应旧提交 66454dd，不包含当前 RTL。因此当前 Fmax 仍未知，不能用源码结构或旧报告的约 70.05 MHz 推断。

当前工作树在本文创建前为 clean，以下数据对应提交 248b9c0：

| 验证层级 | 结果 | 用途 |
| --- | ---: | --- |
| RV32UI / UM / MI | 40/40、8/8、4/4 PASS | ISA 与异常基本正确性 |
| full srcSmoke | 32,084,235 cycles，30,758,589 commits，IPC 0.958682 | 完整短程序回归 |
| srcWithMext 500k | 502,749 commits，IPC 1.005500，37+8、fail 0 | 快速方向判断 |
| srcWithMext 50M | 43,525,300 commits，IPC 0.870506，37+8、fail 0 | 当前组合态长窗口 |
| 当前完整 srcWithMext | 未运行 | 不能预测最终 SEG 时间 |
| 当前 clean routed Fmax | 未运行 | 不能宣称 100 MHz 已收敛 |

当前 50M 快照生成于 2026-07-11 15:17:34 +08:00，原始工作文件为 build/result/src/srcWithMext.json；该 build 路径会被后续仿真覆盖，本文表格是本次结果的冻结记录。

50M 和 500k 都是达到 max cycles 的预期 TIMEOUT，37+8、fail 0 只说明程序正常推进，不等价于完整 PASS。

## 1. 核心结论

1. 旧 routed top-3 路径族都已有定向 RTL 处理：
   - ROB/commit 到 BPU PHT：BPU update 输入打一拍；
   - ROB/recovery 到 DRAM DI：dirty victim writeback data 先寄存；
   - rename sRAT 到 MEM IQ payload：MEM-only dispatch buffer 加 CompressedQueue payload/reset 分离。
2. 这些修改在结构上切开了旧路径，但没有新 route，状态只能是“RTL 已覆盖、物理结果待验证”。
3. IPC 方面，P1A 后的 50M IPC 为 0.756193，当前组合态为 0.870506，再提高 15.12%；说明当前组合修改整体有效，但没有隔离 A/B 的单项不能独占这 15.12% 收益。
4. 当前最大剩余问题不是 DCache refill，也不是 MEM request slot：
   - MEM issue block 只剩 0.22%；
   - DCache stall 为 4.70%；
   - MEM IQ head-not-ready 为 67.26%，其中 91.67% 的周期存在 younger-ready 项；
   - INT IQ backpressure 为 65.16%。
5. 因此下一项高价值 IPC 优化应是“有顺序证明的 MEM bounded lookahead”，而不是继续扩大 load FIFO、直接增深 IQ 或再做无依据的 INT RRD。
6. 在任何新微架构修改前，应先对 248b9c0 做同配置 clean route。否则无法知道旧 top-3 消失后，瓶颈是否转移到 FreeList、queue compaction、BPU 内部、PRF 或 reset recovery。

## 2. 当前性能位置

### 2.1 IPC 演进

只比较相同窗口：

| 阶段 | 500k IPC | 50M IPC | full srcSmoke IPC | 说明 |
| --- | ---: | ---: | ---: | --- |
| P1A/P1R0 | 0.882140 | 0.756193 | 0.920968 | refill 与 payload/reset 分离后 |
| 当前 248b9c0 | 1.005500 | 0.870506 | 0.958682 | 含 BPU/MEM dispatch/LSU queue/writeback 定向修改 |
| 相对变化 | +13.98% | +15.12% | +4.10% | 当前组合态收益 |

历史旧版完整 IPC 0.698105 与当前 50M 不是相同软件阶段，不能直接把两者差值当作最终完整收益。

### 2.2 当前 50M 压力

| 事件 | cycles | 占 50M | 判断 |
| --- | ---: | ---: | --- |
| MEM IQ head not ready | 33,631,044 | 67.26% | 当前最强内存调度证据 |
| INT IQ backpressure | 32,577,721 | 65.16% | 严重，但可能由 load/MUL producer 传播 |
| dispatch block | 32,610,007 | 65.22% | 主要是 IQ 压力向前传播 |
| younger ready behind MEM head | 30,831,006 | 61.66% | 占 head-not-ready 的 91.67% |
| FetchBuffer backpressure | 27,811,462 | 55.62% | 前端不是 IROM 供给不足 |
| load pending | 17,207,486 | 34.41% | 已下降，但仍限制相关消费者 |
| ROB head wait MEM | 13,525,260 | 27.05% | 内存仍限制提交 |
| MEM IQ backpressure | 6,084,821 | 12.17% | 比旧完整基线 19.30% 下降 |
| ROB head wait MUL | 3,644,181 | 7.29% | 后续需要 producer 分类，不宜减 MUL pipeline |
| DCache stall | 2,348,629 | 4.70% | refill 已不再是第一瓶颈 |
| MEM issue block | 110,242 | 0.22% | request slot 串行瓶颈基本解除 |
| ROB full | 398 | 0.0008% | 不支持扩大 ROB |
| branch recovery | 30,519 | 0.061% | 不支持扩大 BPU 容量换 IPC |

DCache 50M 证据：

| 指标 | 当前值 |
| --- | ---: |
| DCache miss | 190,844 |
| DRAM read | 1,526,752 |
| reads / miss | 8.000 |
| DCache stall / miss | 12.31 cycles |
| DRAM write | 58,536 |
| dirty evictions | 7,317 |

宽度利用率也已改善：

| 指标 | 历史完整基线 | 当前 50M |
| --- | ---: | ---: |
| issue 0 cycle | 41.91% | 28.19% |
| issue >=2 cycle | 9.93% | 14.39% |
| commit 0 cycle | 44.80% | 34.52% |
| commit 2 cycle | 14.61% | 21.57% |

### 2.3 与 3 秒目标的距离

完整程序需要至少 126.781 MIPS。

按当前 50M IPC 0.870506 粗略代入：

| 假设 routed Fmax | 吞吐 | 由历史 commit 数估算时间 |
| ---: | ---: | ---: |
| 100 MHz | 87.05 MIPS | 4.37 s |
| 110 MHz | 95.76 MIPS | 3.97 s |
| 120 MHz | 104.46 MIPS | 3.64 s |
| 130 MHz | 113.17 MIPS | 3.36 s |

当前 IPC 若完全不再提高，需要约 145.64 MHz 才能达到 3 秒，这对当前 Kintex-7 OoO 结构风险过高。推荐目标仍是：

| 目标组合 | 吞吐 | 历史 commit 数估算时间 |
| --- | ---: | ---: |
| IPC 1.06 × 120 MHz | 127.2 MIPS | 2.99 s |
| IPC 1.10 × 120 MHz | 132.0 MIPS | 2.88 s |
| IPC 1.00 × 130 MHz | 130.0 MIPS | 2.93 s |

## 3. 已经完成并应保留的优化

### 3.1 状态总表

| 优化 | 当前状态 | IPC 证据 | Fmax 证据 | 结论 |
| --- | --- | --- | --- | --- |
| MEM IQ 后 registered request stage、load 与 INT issue 解耦 | 已完成 | 060 和后续结果为正 | 旧路径已移动 | 保留 |
| StoreBuffer full forwarding、no-alias cacheable load 放行 | 已完成 | 已进入完整/窗口结果 | 组合环已清理 | 保留 |
| MUL 3-stage、II=1、completion register | 已完成 | 功能和吞吐稳定 | 避免缩短 DSP pipeline | 保留 |
| P1A burst refill + critical-word-first | 已完成 | 50M stall/miss 约 12.3 | 当前 route 待验证 | 保留 |
| CompressedQueue payload/reset ownership 分离 | 已完成 | cycle-exact | /S 端点待 route 确认 | 保留 |
| BPU commit update 输入流水 | 已完成 | 组合态功能通过 | 旧 ROB→PHT 路径已切 | 保留，route pending |
| 4-entry MEM-only allocated dispatch buffer | 已完成 | 组合态为正，单项收益未隔离 | sRAT→MEM IQ 路径已切 | 保留，route pending |
| 2-entry MEM request queue | 已完成 | MEM issue block 降至 0.22% | ready 只看本地 occupancy | 保留 |
| 2-entry load metadata FIFO + killed response drain | 已完成 | load pending 降至 34.4% | 无 IQ→DCache ready 回环 | 保留 |
| cacheable response 同拍 replacement | 已完成 | 支持连续 hit/critical-return 后继请求 | 局部 registered ownership | 保留 |
| dirty writeback data register | 已完成 | 50M 7,317 次 dirty eviction 无断言失败 | 旧 victim LUTRAM→DRAM DI 直连已切 | 保留，route pending |

### 3.2 三条旧主路径的覆盖

| 旧路径 | 当前结构修改 | 结构判断 | 新 route 必查 |
| --- | --- | --- | --- |
| ROB head/retire → BPU choice PHT | update_valid_q 与 update payload q | 单周期跨模块路径已切开 | 起点应变为 BPU 内部 update 寄存器 |
| ROB head/recovery → DRAM BRAM DI | DC_WRITEBACK_PREP + writeback_data_q；IDLE wdata 不再由地址分类选择 | victim LUTRAM 不再直驱 DRAM DI | writeback DI 起点应为 writeback_data_q/Q |
| rename sRAT → MEM IQ entry payload /S | MEM dispatch buffer + payload reset 分离 | rename 与 MEM IQ 隔拍，/S ownership 移除 | /S 端点和原 -4.24 ns 家族应消失 |

尚未完全覆盖：

- cpu_rst_sync 的高扇出与 recovery violation；
- BPU 内部 update_valid_q 到多张表的局部高扇出；
- completion ROB index、commit recovery 和 PRF write-enable 网络；
- INT IQ/PRF/EXE 是否成为新最差路径。

这些项目必须由 248b9c0 的新 routed path 决定优先级。

## 4. 已确认不可行或当前形态不采用

这里的“不可行”分为两类：已有动态失败证据的候选，以及违反当前时序/顺序合同、无需再试的直接写法。部分架构思想可以在进入条件变化后重新设计，但不能复用已失败实现。

### 4.1 有实验数据的拒绝项

| 候选 | 证据 | 结论 | 允许重启的条件 |
| --- | --- | --- | --- |
| 当前版本的 INT IQ→RRD→PRF/EXE | 500k IPC 0.882140→0.812654，下降 7.88%；srcSmoke IPC 下降 5.42% | 回退，不合入 | 新 route 明确命中 INT IQ/PRF/EXE，且可证明 Fmax 至少提高 8.55% |
| 额外 MEM RRD | 500k IPC 0.812150，没有恢复 INT RRD 损失 | 回退 | 需要新的 MEM operand bypass/queue 架构，不能复用该实现 |
| early wakeup 广播给 INT/MEM/MUL 全部 consumer | st_ld 波形显示 MEM consumer 在 producer 写 PRF 同一边沿读到旧值 | 功能错误 | consumer 自身有 RRD 或同拍 result bypass |
| packed exec_complete 组合反馈 IQ wakeup | 形成 MEM IQ→PRF→completion→wakeup→MEM IQ UNOPTFLAT 环 | 结构错误 | wakeup 必须来自 registered metadata 或专用无环 early tag |
| 旧 full allocated rename/dispatch buffer 实现 | RV32UM DIV/REM timeout，已回退 | 当前实现形态不可用 | 重做 serial/mul ownership、原子 allocation 和 wakeup accumulation，并重新 A/B |

INT RRD 不是永久禁止。它只是没有命中 66454dd 的 top-600 路径，而且当前实现的 IPC 代价过大。只有新 routed report 把最差路径移动到 IQ select/PRF/ALU 后，才重新计算 IPC × Fmax，而不是因“标准乱序核通常有 RRD”就恢复它。

### 4.2 设计层面直接禁止的写法

1. 直接把 MEM IQ 的 HEAD_ONLY 改为 0：会允许 load 越过 older store、fence 或地址未知的 device access。
2. 直接把 INT IQ 8→16、MEM IQ 5→10：当前是压缩队列，深度会同步放大 wakeup compare、oldest select、任意 remove 和宽 payload compaction。
3. 直接扩大 ROB：当前 50M 只有 398 个 ROB-full cycles，收益证据为零，却会扩大 retire/completion/FreeList/PRF 布线。
4. 扩展 fetch/dispatch/commit 到 3-wide：当前 2-wide 仍有大量 0/1-wide cycle，三宽会同时放大 rename、ROB、PRF、IQ 和 bypass。
5. 减少 MUL pipeline：MUL 已经 II=1，降低 latency 的收益小于 Fmax 风险。
6. 把 DCache 改成大组合旁路：会重新连接 MEM IQ/AGU/StoreBuffer/DCache/DRAM。
7. 只提高 PLL、使用伪 multicycle/false path 或只换 implementation strategy：不能修复真实同步路径。
8. 用 200k/500k IPC 推导完整 SEG 时间：当前 500k IPC 1.0055，而 50M 只有 0.8705，已经再次证明短窗不能代表矩阵阶段。

## 5. 仍值得优化的项目

### 5.1 优先级矩阵

| 优先级 | 项目 | 主要收益 | 当前证据 | 进入条件 |
| ---: | --- | --- | --- | --- |
| P0 | 248b9c0 clean 100 MHz route | 获得真实 Fmax 和新路径排序 | 旧 top-3 已结构切分 | 立即执行 |
| P0-F | reset recovery、CDC 和约束 sign-off | 消除 recovery/ignored crossing 风险 | 旧 recovery WNS -0.589 ns、31 条 CDC-10 | 与 route 并行审查 |
| P1 | MEM IQ stable-slot bounded lookahead | 解除 HOL，提高 load MLP 和提交宽度 | head-not-ready 67.3%，其中 91.7% 后有 ready 项 | route 未显示更紧急结构问题 |
| P1-M | INT IQ blocked-PRD producer 分类计数 | 避免把传播压力误判为容量不足 | INT IQ block 65.2% | 可与 P1 并行，仅仿真计数 |
| P2 | INT IQ static-slot/bitmap/registered-select | 降 compaction 时序并可控扩容 | 只有在分类证明真实容量/选择瓶颈时 | 新 route 或 producer 分类命中 |
| P2-F | PC[2]=1 双 lane 取指 | 利用已有第二 IROM 口 | 当前仍强制 lane0-only，但前端被后端反压 | backend pressure 明显下降后 |
| P3 | load metadata depth 2→4 | 增加 hit/load overlap | 当前 MEM issue block 仅 0.22% | occupancy-full 计数证明 depth2 经常满 |
| P3 | 单 MSHR hit-under-miss | 降低 blocking miss 对 hit 的影响 | 当前 DCache stall 4.70% | lookahead 后 cache blocking 成为前五瓶颈 |
| P3-F | PRF replica/bank 或重新进入 RRD | 提高 Fmax | 旧 top-600 未命中 | 新 route 明确命中 PRF/EXE |
| P4-F | DCache tag/data 同步 BRAM | 降 LUTRAM 路径 | 会增加 hit latency | 新 route 明确命中 cache lookup，且 IPC × Fmax 为正 |
| P4-F | BPU table/reset 重构 | 降内部 decoder/reset 高扇出 | branch recovery 不是 IPC 瓶颈 | 新 route 仍命中 BPU 内部 |

### 5.2 P1：MEM IQ stable-slot bounded lookahead

这是当前最高价值的新微架构候选，但不能在现有 CompressedQueue 上简单关闭 HEAD_ONLY。

推荐把 MEM IQ 单独改为稳定槽位，而不是继续复用全 payload 压缩：

1. entry 进入固定 slot，使用 valid、ready bitmap 和 age tag 管理，不在每次 issue 后搬移所有 payload。
2. 每拍只检查最老的 2～3 个 slot，默认仍选择 head。
3. younger candidate 必须是 normal load；它前面的所有未完成 entry 都必须是 load。
4. 任何 older store、fence、serial 或 device/uncached 请求都阻止 bypass。
5. candidate slot 先置 probe_busy，寄存 slot id、ROB id 和 uop，再由下一 stage 读 PRF、计算地址。
6. 只有地址落在 cacheable normal-memory 区域，且 slot/ROB identity 仍匹配时，才能 remove 并 enqueue 现有 2-entry MEM request queue。
7. 若地址为 uncached/device、slot 已被 flush 或身份不匹配，取消 probe，不产生 DCache 请求。
8. load-load 可重排，但 DCache request/response 仍保持接受顺序；现有 load metadata FIFO 继续拥有 response mapping。
9. recover 清 probe valid；已经被 DCache 接受的 read 继续使用 killed metadata drain，不能丢 response owner。

不建议在同一拍串联：

MEM IQ 多项扫描 → PRF 读 → AGU → cacheable 判断 → arbitrary remove → request queue ready。

正确结构应为：

MEM stable-slot select → probe register → PRF/AGU/cacheability → request queue。

P1 的最低验收：

- RV32UI/UM/MI 全过；
- memory-order 定向测试覆盖 load/load、load/store、partial forwarding、MMIO、fence、misalign 和 recover；
- 500k 与 50M 的 37+8、fail 0；
- 50M IPC 至少提高 3%，或 IPC × routed Fmax 至少提高 3%；
- younger load 不得越过任何 older store/fence/device access；
- queue select 不得重新形成 PRF/DCache ready 组合环。

### 5.3 P1-M：INT IQ backpressure 的 producer 分类

当前 INT IQ block 65.2%，但不能直接解释为“8 entries 不够”。需要增加 VERILATOR_TB-only 计数：

1. dispatch 被 INT IQ 拒绝时，记录该 uop 的 src1/src2 是否 ready；
2. 对第一个 blocking PRD 记录 producer 类型：INT、MEM、MUL、未知；
3. 区分 queue full 且存在 ready issue、queue full 且所有 entry 等待、以及 issue port/downstream 阻塞；
4. 记录 ready-entry 数量直方图和 oldest-ready select 数量；
5. 记录被阻塞 uop 在多少周期后 wakeup。

决策规则：

- 若大多数 blocking PRD 来自 MEM：先完成 bounded lookahead，不改 INT IQ 深度；
- 若来自 MUL：评估安全的 registered wakeup/bypass，不减 MUL pipeline；
- 若 queue 中长期有多个 ready entry 却 dispatch 仍阻塞：优先重构 select/valid slots；
- 只有真实 occupancy pressure 持续存在，才把 static-slot INT IQ 从 8 增到 10/12。

### 5.4 P2-F：半组 PC 双 lane 取指

当前 IromFetch2 在 PC[2]=1 时只产生 lane0，CorePcGen 也只前进 4 bytes，lane1 predictor 同时被禁用。硬件 A/B 端口实际已经读取 PC 和 PC+4。

该优化在逻辑上可行，但当前 FetchBuffer backpressure 为 55.6%，说明前端大部分时间被后端压住，不能把它列为 P1。

进入前先增加：

- fetch_fire && PC[2] 计数；
- 每拍实际 0/1/2 lane fetch 与 decode consume；
- PC[2] 周期中 FetchBuffer 是否有空间；
- lane1 predicted-taken 命中和误预测数。

若计数证明有可见收益，再同时修改：

- IromFetch2：PC[2]=1 时也允许两个 lane，lane0 taken 仍屏蔽 lane1；
- CorePcGen：无预测时统一前进 8 bytes；
- core lane1 predictor：不再因 PC[2] 禁用；
- fetch packet prefix、branch redirect 和跨 8-byte group 顺序断言。

### 5.5 当前不应继续扩的内存结构

2-entry request queue 和 2-entry load metadata 已把 MEM issue block 降到 0.22%。在没有 occupancy histogram 前：

- 不把 load metadata 盲目扩到 4；
- 不引入多个 MSHR；
- 不做乱序 DCache response；
- 不把 blocking DCache 一次改成完整 non-blocking cache。

这些结构只有在 bounded lookahead 后，新的计数显示 queue full 或 DCache blocking 成为主瓶颈时才进入。

## 6. P0：当前提交的 Fmax 验证与 sign-off

### 6.1 clean route 要求

对提交 248b9c0 使用与 66454dd 基线完全一致的：

- part：xc7k325tffg900-2；
- Vivado 2023.2；
- 100 MHz CPU / 50 MHz system；
- flatten hierarchy、keep equivalent registers、power-opt、seed 和 strategy；
- srcWithMext memory profile；
- 同一套 report 导出脚本。

至少比较：

| 项目 | 旧基线 | 当前验收 |
| --- | ---: | --- |
| CPU WNS / TNS | -4.275 ns / -126,470.969 ns | 首先要求显著改善，最终 WNS>=0、TNS=0 |
| failing endpoints | 51,713 / 72,430 | 必须大幅下降 |
| ROB→BPU PHT | rank 1 | 原单周期路径必须消失 |
| ROB→DRAM DI | rank 2 | writeback 起点应为 writeback_data_q |
| sRAT→MEM IQ /S | rank 3 家族 | /S 端点和跨级 payload 路径必须消失 |
| route ratio | 约 88% | 检查新 stage 是否改善物理跨度 |
| cpu_rst_sync recovery | -0.589 ns | 必须单独报告 |
| high fanout | BPU/reset/completion | 重新排序，不沿用旧结论 |
| LUT/FF/control sets | 旧层次报告 | 比较当前增量和 reset cleanup |

只有新 route 后，才能决定是否重新进入 INT RRD、PRF replica、同步 DCache BRAM 或 BPU 内部重构。

### 6.2 reset recovery

旧报告中 cpu_rst_sync fanout 8,581，并有 32 个 recovery violation。当前已经把多处宽 payload 从异步 reset 进程中分离，但这只是减负，不是完整修复。

推荐方向：

1. 保持 reset 异步 assert、同步 deassert；
2. 按大层次复制本地 reset synchronizer/控制 reset，避免单网跨全核；
3. 宽 payload 不 reset，由 valid/count/state 拥有可见性；
4. 可用同步 clear 的控制寄存器不再挂全局异步 reset；
5. PHT/BTB/cache payload 若仍产生大量 control set，评估 valid/epoch 或启动 scrub，而不是给每个 bit 异步复位；
6. 不通过 set_false_path 隐藏 recovery，必须看 recovery/removal 报告。

### 6.3 时钟约束和 CDC

旧设计把同一 PLL 的 50 MHz 与 100 MHz 整域设为 asynchronous，忽略了 169 个跨域端点，并有 TIMING-47 与 CDC-10。

新 sign-off 必须：

- 列出每个 50↔100 crossing 的真实协议；
- 对真正异步的路径使用同步器/FIFO/Gray counter；
- 对相关时钟路径保留正确的 generated-clock 关系；
- 不使用 blanket clock group 掩盖未审查 crossing；
- 修复 Gray 同步器前组合逻辑和 multi-bit synchronizer warning；
- 保持 no_clock=0、unconstrained internal endpoints=0；
- 单独补齐板级 I/O delay，不把它与 CPU Fmax 混为一谈。

## 7. 新的实施顺序

推荐顺序不再沿用 061 中尚未更新状态的旧编号：

### R0：冻结 248b9c0 组合态基线

已完成：

- full srcSmoke；
- 500k srcWithMext；
- 50M srcWithMext；
- RV32UI/UM/MI；
- 当前 50M 压力分类。

待完成：

- 100 MHz clean synth/place/route；
- routed report 与 66454dd 同口径对比；
- current hierarchy utilization、control set 和 high-fanout；
- reset recovery、CDC、DRC、methodology。

R0 route 完成前，不再叠加 PRF、IQ 深度、BPU table 或 DCache BRAM 等大结构。

### R1：MEM IQ stable-slot bounded lookahead

只做以下范围：

- MEM IQ 从 payload compaction 改 stable slots；
- 最多检查 oldest 3 entries；
- 只允许 younger normal-cacheable load 越过 older load；
- registered probe，不跨越 store/fence/device；
- 复用现有 2-entry request 和 2-entry metadata；
- 增加 memory-order assertions 与 occupancy/probe 计数。

R1 不同时修改：

- INT IQ；
- PRF；
- ROB 深度；
- DCache MSHR；
- fetch width。

### R2：重新计数与 route

R1 后必须重新获得：

- 500k、50M IPC；
- MEM head-not-ready / younger-ready；
- INT IQ blocked producer 分类；
- request/load metadata occupancy；
- issue/commit width；
- routed WNS/TNS 和 path family。

分支：

- 若 MEM HOL 明显下降且 INT IQ 同步下降：说明 INT 压力主要由内存传播，继续保留 INT IQ=8；
- 若 MEM HOL 下降但 INT IQ 仍高，且 blocked producer 主要为 INT：进入 R3；
- 若 route 命中 PRF/EXE：重新评估 RRD/PRF，但必须重新计算 IPC × Fmax；
- 若 route 仍命中 BPU/rename/DRAM：先修对应结构，不能进入无关的 IQ 扩容。

### R3：条件性 INT IQ 重构

进入条件至少满足一个：

- 50M INT IQ block 仍高于 30%，且大多数 blocking PRD 不是 MEM；
- routed path 命中 INT IQ select/compaction；
- queue 中长期存在多个 ready entry，但当前 select/issue 不能有效排空。

推荐顺序：

1. 先 static slots + valid/ready bitmap；
2. 再将 oldest-ready select 输出寄存；
3. 保持 depth=8 做 IPC/Fmax A/B；
4. 只有 occupancy 证据充分时扩到 10/12；
5. 若增加 RRD，必须同时提供 consumer-local bypass/early wake，不得广播给无 RRD consumer。

### R4：条件性前端与 cache 优化

优先依据新计数选择：

- backend 反压下降后，PC[2] 双 lane fetch；
- DCache blocking 进入前五瓶颈后，单 MSHR hit-under-miss；
- metadata depth2 满事件明显后，扩到 4；
- route 命中 cache LUTRAM 后，同步 BRAM A/B；
- route 命中 BPU table 后，做 table/reset 局部重构。

### R5：频率阶梯与完整验收

频率顺序：

100 → 110 → 120 → 125/130 MHz

只有上一档同时满足以下条件才进入下一档：

- setup WNS>=0、TNS=0；
- hold WHS>=0、THS=0；
- recovery/removal 无违例；
- no_clock=0、unconstrained internal endpoints=0；
- CDC/ignored crossing 有逐项解释；
- 当前频率下 bitstream/板上功能通过。

达到 IPC × routed Fmax 候选门槛后，再运行当前版本完整 srcWithMext PASS 和板上 counter/SEG。完整运行成本高，不用于每个小补丁。

## 8. 联合验收标准

每个 retained phase 必须记录同一 RTL 的：

- 500k IPC；
- 固定 50M 窗口 IPC；
- full srcSmoke cycles/IPC；
- routed Fmax；
- IPC × Fmax；
- LUT/FF/BRAM/control-set 增量；
- top path family；
- 功能与 assertions。

联合指标：

time_est = 380,344,388 / (IPC × Fmax_MHz × 1,000,000)

合入规则：

1. 结构性 sign-off 修复可以 IPC 中性，但不得造成明显 IPC 回退。
2. 性能候选原则上要求 50M IPC 或 IPC × routed Fmax 提高至少 3%。
3. 若 IPC 下降，必须由同一版本 routed Fmax 证明联合吞吐净增加。
4. 单 phase 顶层 LUT/FF 增幅原则上不超过 5%；超过必须有相称吞吐收益。
5. 不能用旧版本 Fmax 与新版本 IPC 交叉相乘。
6. 不能用 500k IPC 替代 50M/完整结果。
7. 不能把 reference_enabled=false 的 commit-trace selfcheck 写成外部参考 difftest。

## 9. 更新后的里程碑

| 里程碑 | IPC 口径 | Fmax | 吞吐 | 估算时间 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| H0 历史完整基线 | full 0.698105 | 50 MHz | 34.91 MIPS | 10.896 s | 已完成 |
| H1 当前组合态 | 50M 0.870506 | 未知 | 未知 | 不估算 | 仿真完成、route 待做 |
| M1 当前 RTL route | 50M >=0.87 | >=100 MHz | >=87 MIPS | 约4.37 s | 下一里程碑 |
| M2 bounded lookahead | 50M >=0.95 | >=110 MHz | >=104.5 MIPS | <=3.64 s | 目标 |
| M3 INT/前端条件优化 | 50M >=1.02 | >=120 MHz | >=122.4 MIPS | <=3.11 s | 接近目标 |
| M4 最低收口 | full/window >=1.06 | >=120 MHz | >=127.2 MIPS | <=2.99 s | 3秒边界 |
| M5 推荐收口 | full/window >=1.10 | >=120 MHz | >=132 MIPS | <=2.88 s | 保留余量 |

里程碑 IPC 先用固定 50M 做工程筛选，最终必须用当前版本完整 PASS 校准。软件不同 phase 的 IPC 不完全相同，因此 M4/M5 不能只靠 50M 宣称板上达标。

## 10. 验证清单

### 10.1 每个 RTL phase

- [ ] Verilator myCPU/student_top/difftest 三个目标可编译；
- [ ] 无 MULTIDRIVEN、LATCH、UNOPTFLAT；
- [ ] RV32UI 40/40；
- [ ] RV32UM 8/8；
- [ ] RV32MI 4/4；
- [ ] full srcSmoke PASS；
- [ ] srcWithMext 500k 正常推进；
- [ ] phase 收口跑固定 50M；
- [ ] git diff --check；
- [ ] 性能计数只存在于 VERILATOR_TB。

### 10.2 MEM lookahead 专项

- [ ] younger load 不越过 older store；
- [ ] younger load 不越过 fence/serial/device；
- [ ] probe slot identity 在 compaction/flush/reuse 后不误命中；
- [ ] full/partial StoreBuffer forwarding 保持；
- [ ] misaligned load/store 仍在访问前产生异常；
- [ ] cacheable/uncached 分类使用最终有效地址；
- [ ] accepted wrong-path response 被 killed metadata drain；
- [ ] response 与 ROB/PRD metadata 严格按接受顺序；
- [ ] load/load bypass 不造成重复 issue；
- [ ] recover 与 response 同拍不丢 owner；
- [ ] DCache miss/refill/writeback 同时覆盖；
- [ ] 8 word refill 与 8 word writeback 无重复、遗漏和错位。

### 10.3 routed sign-off

- [ ] 固定 part/seed/strategy/约束；
- [ ] 100 MHz WNS/TNS/WHS/THS；
- [ ] top setup/hold paths；
- [ ] high fanout；
- [ ] control sets；
- [ ] hierarchy utilization；
- [ ] recovery/removal；
- [ ] CDC 与 clock interaction；
- [ ] DRC/methodology；
- [ ] no_clock/unconstrained；
- [ ] DRAM ENA/REGCEA 参数；
- [ ] 同一 commit 的 IPC JSON 和 bitstream。

## 11. 最终决策

当前最合理的执行主线是：

248b9c0 clean route
→ 验证旧 top-3 是否真正消失
→ MEM IQ stable-slot bounded lookahead
→ 重新测 50M IPC 与 INT blocked-producer
→ 根据新 route/计数决定 INT IQ、PRF/RRD 或前端
→ 120 MHz route
→ 完整 srcWithMext 与板上 3 秒验收。

当前不应做的事情是继续叠加大而无证据的结构。P1A 和 2-entry LSU 已经把 DCache refill/request slot 从一级瓶颈移开；下一轮收益应来自解除 MEM HOL，并根据 producer 分类判断 INT IQ 压力究竟是根因还是传播结果。
