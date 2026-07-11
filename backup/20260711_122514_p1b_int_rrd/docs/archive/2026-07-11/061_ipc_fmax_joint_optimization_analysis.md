# srcWithMext IPC / Fmax 联合优化分析

日期：2026-07-11

目标：缩短 FPGA 上 `srcWithMext` 从 counter start 到 counter stop 的真实时间，最终 SEG 显示不超过 3 秒。

分析输入：

- `build/result/difftest/src/srcWithMext.json`：完整 PASS 基线；
- `docs/archive/2026-07-10/vs/NOP-Core_vs_superScalar_current_microarchitecture_timing_review.md`；
- `docs/archive/2026-07-10/058_fpga_timing_improvement_plan.md`；
- `docs/archive/2026-07-10/059_ipc_optimization_plan.md`；
- `docs/archive/2026-07-10/060_nopcore_lsu_muldiv_ipc_timing_optimization.md`；
- 当前 `rtl/core`、`rtl/soc` 和 `fpga/create_vivado_project.tcl` 静态审查。

本文只做分析和实施规划，没有运行 Vivado，也没有用旧 routed report 推断当前修改后的 Fmax。

## 1. 结论

完整 PASS 基线为：

| 指标 | 当前值 |
| --- | ---: |
| CPU 频率 | 50 MHz |
| counter 时间 | 10,896 ms |
| counter 有效 CPU cycles | 544,821,211 |
| 完整运行 cycles | 544,823,935 |
| commit | 380,344,388 |
| IPC | 0.698105 |
| 有效吞吐 | 34.905 MIPS |

3 秒目标要求：

```text
required throughput
  = 380,344,388 instructions / 3 s
  = 126.781 MIPS

required speedup
  = 126.781 / 34.905
  = 3.632x
```

因此 3 秒不是“IPC 提高 20%”或“频率从 50 MHz 提到 60 MHz”可以完成的目标。即使 60 MHz 达到理论最大 IPC=2，运行时间仍约为 3.17 秒。实际设计必须同时进行较大幅度提频和后端并行度优化。

建议把设计目标定为至少 `130 MIPS`，给 counter CDC、route 波动和软件阶段差异留下约 2.5% 余量。优先目标组合为：

```text
120 MHz x IPC 1.10 = 132 MIPS -> 约 2.88 s
```

可接受备选组合：

```text
110 MHz x IPC 1.20 = 132 MIPS -> 约 2.88 s
130 MHz x IPC 1.00 = 130 MIPS -> 约 2.93 s
```

总体路线不是盲目扩大宽度，而是：

1. 用 NOP-Core 风格的 `ISS -> RRD -> EXE` 和 rename/dispatch 弹性边界换取 100～130 MHz 的可能性；
2. 用 fixed-latency early wakeup、局部 bypass 和足够的调度窗口抵消加深流水造成的依赖延迟；
3. 先把 DCache 8-word refill 改成流水 burst + critical-word-first，再把单 pending load 改成 2～4 项 load metadata FIFO；
4. 最后做受限 MEM IQ lookahead，只允许 cacheable load 越过 older load，禁止越过 store、fence 和 device access；
5. 保持 2-wide fetch/dispatch/commit。目标 IPC 约 1.1，不需要引入 3-wide/4-wide 前后端及其巨大时序代价。

## 2. 目标方程与频率/IPC 组合

同一程序动态指令数基本固定时：

```text
time_s = commit_count / (IPC x Freq_MHz x 1,000,000)

speedup = (IPC_new / 0.698105) x (Fmax_new / 50 MHz)
```

要进入 3 秒，`IPC_new x Fmax_new` 必须不低于 `126.781`：

| CPU 频率 | 3 秒所需 IPC | 相对当前 IPC 提升 | 判断 |
| ---: | ---: | ---: | --- |
| 60 MHz | 2.113 | +202.7% | 超过 2-wide 理论上限，不可行 |
| 75 MHz | 1.690 | +142.1% | 接近持续双发，不现实 |
| 80 MHz | 1.585 | +127.0% | 风险极高 |
| 90 MHz | 1.409 | +101.8% | 需要极强内存并行度 |
| 100 MHz | 1.268 | +81.6% | 可作为进取 IPC 路线 |
| 110 MHz | 1.153 | +65.1% | 较均衡 |
| 120 MHz | 1.057 | +51.3% | 推荐目标区间 |
| 125 MHz | 1.014 | +45.3% | 推荐目标区间 |
| 130 MHz | 0.975 | +39.7% | 偏重 Fmax |
| 140 MHz | 0.906 | +29.7% | 对当前 FPGA OoO 结构提频压力很大 |
| 150 MHz | 0.845 | +21.1% | IPC 容易达到，但 Fmax 风险最高 |

不能用表中某一个维度单独倒推方案。例如把流水加深到 150 MHz、但完整程序 IPC 降到 0.75，吞吐只有 112.5 MIPS，仍需要 3.38 秒。

## 3. 完整工作负载事实

### 3.1 短窗不能代表完整程序

060 文档记录的 200k 快速窗口 IPC 为 `0.836345`，证明上一轮 LSU/MUL 优化命中了早期执行路径，但完整 PASS IPC 只有 `0.698105`；当前 100M-cycle 长窗 IPC 也约为 `0.693325`。

结论：大矩阵阶段长期主导总时间。后续不能继续用启动阶段或 200k 窗口的 IPC 作为 3 秒目标验收值。快速窗口只服务功能和回归，性能决策必须使用：

- 完整 PASS；或
- 从 counter start 后按固定 50M/100M cycles 采样的矩阵稳定窗口；或
- 由软件 phase marker 明确切出的矩阵区间。

`srcSmoke` 完整 IPC `0.920966`，其内存与 M 扩展比例完全不同，同样不能代替 `srcWithMext`。

考虑完整程序包含大矩阵、日常仿真成本很高，采用分层窗口而不是把 baseline 一味放大：

| 层级 | 上限/范围 | 用途 | 已知参考 |
| --- | --- | --- | ---: |
| A | 200k | 极快正确性、37+8 和计数 sanity | IPC 0.836345，仅参考 |
| B | 500k | 日常改动的方向性 IPC 对照 | 旧稿记录 IPC 0.831074 |
| C | counter 后固定 50M/100M | Phase 收口的矩阵稳定窗口 | 当前 100M 总窗约 0.693325 |
| D | 完整 PASS | 3 秒目标和最终 cycles 的唯一基准 | IPC 0.698105，10.896 s |

500k 适合作为不太大的快速 baseline，但不能换算最终 SEG 时间；只有 C/D 层结果才能决定矩阵优化是否真实有效。

### 3.2 动态指令构成

| 类型 | issue 数量 | 占比 |
| --- | ---: | ---: |
| INT/branch/system | 238,063,029 | 62.48% |
| MEM | 132,320,854 | 34.73% |
| MUL/DIV/REM | 10,624,059 | 2.79% |

该程序每三条左右就有一条访存，且约每 36 条有一条 MUL。它不是纯整数前端负载，LSU 吞吐、load-use latency、缓存 refill 和调度窗口直接决定 IPC。

### 3.3 主要压力

| 事件 | cycles | 占总 cycles | 解释 |
| --- | ---: | ---: | --- |
| INT IQ backpressure | 325,253,683 | 59.70% | IQ 满并向 dispatch 传播；与 memory 压力高度重叠，仍需按 blocking PRD producer 分类 |
| MEM IQ head not ready | 289,289,204 | 53.10% | 有序 MEM 队头源未 ready |
| younger ready behind MEM head | 284,028,705 | 52.13% | 在 head-not-ready 周期中占 98.18%，HOL 证据很强 |
| load pending | 252,198,594 | 46.29% | 单 load metadata token 长期占用 |
| ROB head waiting MEM | 212,177,885 | 38.94% | 内存完成延迟直接限制提交 |
| MEM issue block | 121,266,138 | 22.26% | request stage、pending 和 DCache 等局部阻塞 |
| MEM IQ backpressure | 105,172,812 | 19.30% | MEM IQ 无法持续排空 |
| DCache stall | 55,895,636 | 10.26% | miss/refill/writeback/uncached 等真实 cache 阻塞 |
| ROB head waiting MUL | 31,104,477 | 5.71% | 约等于每 MUL 2.93 cycles，符合 3-stage MUL latency |
| branch recovery | 263,626 | 0.048% | 不是当前一级瓶颈 |

这些 cycle 指标可以重叠，不能直接相加成“可节省周期”。它们描述的是同一内存堵塞从 LSU、ROB、IQ、dispatch 到 frontend 的传播链。

### 3.4 DCache refill 的可量化事实

```text
DCache miss              = 1,632,748
external DRAM read       = 13,061,984
DRAM reads per miss      = 8.000
DCache stall per miss    = 34.23 cycles
```

当前 cache line 正好是 8 words，并且 `DC_REFILL_REQ -> DC_REFILL_WAIT` 每次只发一个 word、等一个 response，再发下一个。BRAM adapter 已具备 `ENA/REGCEA` 流水合同后，底层读端可以做到 II=1；继续在 DCache 中串行 8 次 request/wait 会浪费这个能力。

若将 refill occupancy 从约 34 cycles 降到 11～14 cycles，理论上可减少约 33M～38M DCache stall cycles，即完整运行 cycles 的约 6%～7%。这是上限估算，必须用新计数实测，不能与其他压力项重复相加。

### 3.5 宽度利用率

| 宽度事件 | cycles | 占比 |
| --- | ---: | ---: |
| issue 0 | 228,362,140 | 41.91% |
| issue 1 | 262,383,538 | 48.16% |
| issue >=2 | 54,078,255 | 9.93% |
| commit 0 | 244,073,801 | 44.80% |
| commit 1 | 221,155,876 | 40.59% |
| commit 2 | 79,594,256 | 14.61% |

当前问题不是 2-wide 上限不够，而是大量周期只能发/退 0～1 条。先提高现有两宽利用率，比扩大到三宽更有利于 FPGA Fmax。

## 4. 当前结构对联合目标的限制

### 4.1 已完成且应保留

060 已完成的结构不要回退：

- MEM IQ/PRF/AGU 后的 registered request stage；
- load pending 与 INT issue 解耦；
- StoreBuffer no-alias cacheable load 放行；
- full forwarding 和 partial-alias 保守等待；
- MUL 3-stage metadata pipeline、II=1；
- completion register 隔离 ROB/Busy/IQ wakeup。

这些边界既提升了 IPC，也切断了旧的 `MEM IQ -> PRF -> AGU -> SB -> DCache -> DRAM` 长反馈链。

### 4.2 仍然过长的组合阶段

当前 INT 路径仍大体是：

```text
IQ wakeup compare + oldest-ready select + full payload mux
  -> 64-entry / 8-read-port PRF combinational read
  -> operand/bypass mux
  -> ALU/branch target/compare
  -> PRF write/result generation
```

rename/dispatch 仍大体是：

```text
decode
  -> sRAT mapping + same-group RAW/WAW
  -> FreeList candidate + BusyTable query + ROB index
  -> target IQ ready + lane prefix fire
  -> ROB/PRF/IQ atomic allocation
```

058 的旧 routed 基线最差路径为 18.935 ns、35 logic levels、85.9% route。060 已切断其中 LSU 后半段，但没有新的 routed report，所以当前 Fmax 是未知量。要达到 120 MHz，单 stage 可用时间约 8.33 ns；仅靠 placement strategy 不足以把一个跨 IQ/PRF/EXE 的大 stage 稳定压到该范围。

### 4.3 压缩 IQ 不适合盲目增深

`CoreCompressedQueue` 每拍同时执行：所有 entry 与 wakeup 口比较、oldest-ready 多端口扫描、任意 remove、full payload 压缩和最多两项 push。

把 INT IQ 从 8 直接改为 16、MEM IQ 从 5 直接改为 10，会同时增加选择、比较、payload mux 和压缩布线。它可能提高仿真 IPC，却降低 Fmax，属于本计划明确禁止的盲目扩容。

### 4.4 request slot 与单 load token 共同限制 DCache hit 吞吐

`CoreDCache` 在 `DC_IDLE` 命中时可以每拍接受一个请求并在寄存边沿产生 response，但 `ExecuteCluster` 只有一个 `mem_load_pending_q/mem_load_uop_q`。因此 cache 本身的 hit throughput 没有被 LSU 使用。

此外，`mem_issue_ready_o = !mem_req_valid_q`，当前单项 request stage 必须先完全清空，下一拍才能接收新 MEM uop；即使 head request 本拍被 DCache 接受，也不能同拍 replacement，稳态最快只能隔拍进入一个 AGU request。

因此必须同时增加小型 registered AGU request queue 和 load metadata FIFO，MEM IQ lookahead 才有落点。只改 pending token，年轻 ready load 仍会被 request slot 串行化；只改 request slot，又会被单 response owner 拒绝。

## 5. 建议目标微架构

### 5.1 核心流水

建议逐步形成以下 stage contract，而不是一次重写整核：

```text
IF_REQ
  -> IF_RESP / FetchBuffer
  -> DEC
  -> REN_ALLOC
  -> allocated DispatchBuffer
  -> IQ_SELECT
  -> RRD / PRF_READ
  -> EXE / AGU
  -> WB / completion register
  -> ROB
  -> COMMIT
```

关键点：

1. 每个 stage 用 valid/ready/clear 管理 ownership，flush 只清 valid/state，不 reset 宽 payload。
2. IQ selection 结果先寄存，再驱动 PRF read；禁止重新形成 `execute ready -> IQ select` 组合环。
3. fixed-latency INT/MUL 采用 early wakeup + EXE/RRD bypass，保持 dependent ALU initiation interval 接近 1。
4. load 不做无闭环的 speculative wakeup；只有实际 response 或带 replay/poison 机制时才 mark ready。
5. branch resolve 延后 1～2 拍的代价很小：当前 miss 只有 263,622 次，即使每次多 2 cycles，也只增加约 0.10% 总 cycles。

### 5.2 内存流水

```text
MEM IQ candidate
  -> registered select / address probe
  -> small ordered load-address queue
  -> StoreBuffer older-store check
  -> DCache request
  -> load metadata FIFO
  -> in-order DCache response
  -> MEM completion

DCache miss
  -> critical word first
  -> 8 requests at II=1
  -> response word index pipeline
  -> fill bitmap / line-valid commit
```

初版继续保持 blocking DCache：miss/refill 时不接受其他 CPU request。先降低 miss latency 和 refill occupancy，再考虑 hit-under-miss；不要在同一阶段引入 non-blocking cache、多个 MSHR 和乱序返回。

## 6. 候选优化排序

| 候选 | IPC 影响 | Fmax 影响 | 证据 | 风险 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| DCache pipelined refill + critical word first | 中高正收益 | 中性/正向，控制局部寄存 | 8 reads/miss、34.23 stall/miss | 中 | P1 |
| `ISS -> RRD` registered boundary | 初版可能小幅负收益 | 高正收益 | 当前 IQ/PRF/EXE 同拍 | 中高 | P1 |
| fixed-latency early wakeup + bypass | 恢复/提高 dependent IPC | 需控制扇出，不能组合回 select | ALU/MUL 依赖链 | 高 | P1/P2 |
| PC[2]=1 时双口 IROM 两 lane 都有效 | 小到中正收益 | 基本中性 | 当前端口实际读取 PC 和 PC+4，却屏蔽 lane1 | 低 | P1，先加计数 |
| 2-entry AGU request queue + 2～4 项 load metadata FIFO | 高正收益 | 中性，若 FIFO/仲裁寄存 | request 隔拍 + load pending 46.3% | 高 | P2 |
| allocated DispatchBuffer | 小到中正收益；主要解耦 | 正收益，切断 IQ ready 到 rename | dispatch block 79%，但多为持续压力 | 中 | P2 |
| MEM IQ 2-entry bounded lookahead | 高潜力 | naive 实现负面；两阶段实现中性 | HOL 条件命中 98.18% | 很高 | P3 |
| INT IQ 静态槽/registered-select 重构后扩到 12 | 中正收益 | 先正后可控 | INT IQ backpressure 59.7% | 高 | P3/P4 |
| ROB 32 -> 48/64 | 未知 | 负面，增加完成/退休布线和 PRF 压力 | ROB full 仅 459 cycles | 高 | 暂缓 |
| DCache data/tag 改同步 BRAM | IPC 负面、Fmax 可能高正 | report-driven | 当前 async LUTRAM 可能成为后续路径 | 高 | P4 条件进入 |
| 改分支预测器/扩大 BTB | 小收益 | 可能负面 | recovery 仅 0.048% cycles | 中 | 低 |
| MUL 减少 pipeline stage | latency 小幅正收益 | 明显负面 | MUL II 已为 1 | 中 | 拒绝 |
| fetch/dispatch/commit 扩到 3-wide | 理论正收益 | 大幅负面 | 当前 2-wide 利用率很低 | 很高 | 拒绝 |

## 7. 分阶段实施路线

### Phase 0：冻结真实基线与补计数

目的：避免再次用短窗 IPC 或传播性 backpressure 误判优化。

必须新增或冻结：

1. counter start/stop 区间的 commit、IPC、branch、cache、IQ、load/mul 计数；
2. 每 50M cycles 一个分段快照，定位大矩阵稳定阶段；
3. `fetch_pc[2] && fetch_fire`、实际单 lane/双 lane fetch 数；
4. DCache hit accept-to-response latency、miss critical-word latency、full refill occupancy；
5. refill request width：每拍 request/response 数和 outstanding word 数；
6. load request accepted、load FIFO occupancy、response FIFO occupancy；
7. MEM IQ lookahead 候选分类：younger load/store、前方是否存在 store/fence、最终地址是否 cacheable；
8. timing path 分类：rename、IQ select、PRF read、ALU/branch、DCache、ROB completion/retire。

计数仍必须放在 `VERILATOR_TB`，不得进入 FPGA 网表。

Vivado 基线必须基于当前 BRAM `REGCEA` 修复后的 clean project。旧的 50 MHz WNS 只可作为历史，不可作为新结构的 Fmax。

### Phase 1A：DCache refill 流水化

实现：

1. miss 时先请求 `req_word_q` 对应 critical word，再按环形顺序请求其余 7 words；
2. 使用 `refill_issue_count/refill_resp_count/refill_valid_mask` 区分发出和返回；
3. `mem_req_ready=1` 时连续 8 拍发 read，不再每 word 回到 WAIT；
4. 将 word index 与 DramBramAdapter 的固定 response latency 同步流水；
5. critical response 到达时即可完成原 CPU load；line valid 必须等 8 words 全部写入后才能置 1；
6. refill 尚未完成时 DCache 继续 blocking，避免本阶段引入 MSHR；
7. dirty writeback 保持原有顺序，不能与 refill read 混淆 response ownership。

验收：

- `dram_read_count / dcache_miss` 仍严格为 8；
- refill word 无重复、无遗漏、无跨 line；
- stall/miss 从 34.23 明显下降；
- requested word 的 load completion 早于整 line valid；
- DCache request/response 控制不能组合回 MEM IQ。

### Phase 1B：形成 `ISS -> RRD -> EXE` 边界

该阶段只有在 Phase 0 新 routed report 的 top paths 确认经过 IQ select/PRF/EXE 时才优先实施；若最差路径落在 decode/rename/dispatch，则把 Phase 2B 的 allocated DispatchBuffer/rename 边界提前。不能因为 NOP-Core 有该 stage 就无视本设计真实路径盲目加拍。

先对 INT 路径实施：

1. IQ 输出寄存 selected index/uop，不直接驱动 PRF/ALU；
2. RRD stage 持有 PRF 地址和 uop；下游停顿时 payload 稳定；
3. EXE 接受 RRD operand 后完成 ALU/branch；
4. fixed-latency INT producer 在进入 EXE 时发 early-wakeup tag；
5. dependent consumer 在 RRD/EXE 边界选择同拍 bypass result；
6. clear/recover 必须同时杀死 issue、RRD、EXE valid，错误路径 early wakeup 不得存活。

初版若不做 early wakeup，必须先测 ALU dependency CPI；不能因为 Fmax 提高就接受完整程序 IPC 大幅下降。

阶段目标不是一次达到 120 MHz，而是让最差路径不再同时包含 IQ select、PRF read和 ALU。若新的最差路径落在 PRF 64:1 mux，再评估：

- 按执行 cluster 复制 PRF read storage；
- 减少/缓冲 writeback 端口；
- 对 PRF read address/data再加边界。

这些方案都必须由 routed path 触发，不预先复制 8 份 PRF。

### Phase 1C：修复半组取指带宽浪费

当前 `myCPU` 已经让 IROM A/B 端口分别读取 `PC` 和 `PC+4`，但 `IromFetch2` 在 `PC[2]=1` 时仍强制 `valid_mask=01`，并把无预测顺序 next PC 设为 `PC+4`。

若 Phase 0 证明该事件在 backend 解除后可见，则修改为：

```text
未发生 lane0 taken 时：两个 lane 均有效
无预测 next PC：PC + 8
lane1 predictor：不再因 PC[2] 被禁止
```

lane0 taken 仍必须屏蔽 lane1，保持程序 prefix。该修改不扩大 fetch width，只使用已经存在的第二 IROM 端口。

### Phase 2A：2-entry AGU request queue + 2～4 项 load metadata FIFO

首先把单项 `mem_req_q` 改为 2-entry registered queue。MEM IQ/PRF/AGU 只负责 enqueue，StoreBuffer/DCache 只看 queue head；当一个 head dequeue 的同拍，另一项可以保留或新 enqueue，不把 downstream ready 组合反馈到 IQ select。

再用 response metadata FIFO 替换单一 `mem_load_pending_q/mem_load_uop_q`：

```text
entry = {uop/rob_idx/prd, byte offset, exception metadata, epoch}
```

合同：

1. request queue enqueue ready 只依赖本地 registered occupancy；不能重新连接 SB/DCache combinational ready；
2. 仅在 DCache `exReadAccept` 时向 response metadata FIFO 入项；
3. DCache response 按接受顺序出 FIFO，并占一个 MEM completion slot；
4. response FIFO 接近 full 时停止发送新的 load，cache hit 可在容量允许时连续接受；
5. miss 时 DCache 自身拉低 ready，request head 保持，FIFO 不猜测接受；
6. recover 后不能简单忘掉已接受请求。使用 epoch/drop-count 吞掉旧 response，禁止写入新一代 ROB index；
7. StoreBuffer full/partial forwarding、misalign 和 MMIO 顺序保持现有规则。

先做深度 2，再根据 occupancy 提升到 4。当前目标 IPC 约 1.1，超过 4 项通常收益有限，却会扩大 recovery 和响应匹配验证面。

### Phase 2B：allocated DispatchBuffer

在 rename allocation 与目标 IQ push 之间加入 2 个双宽 packet 的 buffer：

```text
decode/rename
  -> ROB + PRF + DispatchBuffer 原子 allocate
  -> 后续周期按 tube push IQ
```

要求：

- buffer entry 已拥有 ROB/PRD，flush 必须清 valid，并由现有 recovery 重建 RAT/free；
- 等待 IQ 时继续接受 wakeup，或在真正 push IQ 时重新查询 BusyTable；
- lane prefix 和 packet 内 RAW/WAW 不变；
- buffer ready 只依赖本地 occupancy，不组合依赖目标 IQ 深层 ready。

它主要服务 Fmax 和短时解耦，不能解决持续 300M-cycle 的 IQ 满。只有后续 IQ 排空能力提升后，才评估 buffer 深度大于 2 packets。

### Phase 3：MEM IQ bounded lookahead

不能直接把 `HEAD_ONLY` 改为 0。第一版只允许：

```text
younger normal-cacheable load
  may bypass older load(s)
  must not bypass any older store/fence/serial/device access
```

建议最多检查前 2～3 项，并将 candidate index 先寄存。由于 cacheable 属性依赖运行时有效地址，不能在 IQ select 的同一拍串联 PRF+AGU+区域判断；应使用 address-probe/load-address queue：

1. 选中 younger load 后先保留其年龄/前序约束；
2. RRD/AGU 下一 stage 计算地址；
3. cacheable 才允许进入 load queue；
4. uncached/device 候选必须等待恢复为队头顺序，不能提前访问；
5. store 仍只允许 head issue，因此 StoreBuffer 中不会出现比被绕过 older load 更年轻的 store；
6. forwarding 仍只面对已离开 MEM IQ 的 older store。

若无法证明上述顺序，不实施 lookahead。该阶段必须配 memory-order scoreboard，不接受只靠 RV32 ISA 测试“看起来能跑”。

### Phase 4：窗口和存储结构的报告驱动调整

只有 Phase 1～3 后重新计数，满足以下条件之一才进入：

- INT IQ backpressure 仍超过 20%；
- ROB full 明显上升；
- timing report 指向 DCache/PRF/ROB。

候选包括：

1. 将 INT IQ 改为 static slots + valid/readiness bitmap + registered select，再从 8 增到 12；
2. ROB 只有 full 成为真实瓶颈才从 32 增加；同步评估 PHY_REG_NUM，不能让 FreeList/PRF mux 成为新瓶颈；
3. DCache async LUTRAM 路径成为 worst path 时，评估同步 BRAM lookup、同址 write bypass 和额外 hit latency；
4. PRF read mux 成为 worst path 时，评估 cluster replica 或额外 operand stage；
5. 两写口 writeback queue 只有在 PRF 多写扇出成为路径时评估，必须证明不会降低持续完成吞吐。

## 8. 不采用的“看似高 IPC”方案

1. **直接扩大 ROB/INT IQ/MEM IQ。** 当前 ROB full 只有 459 cycles；压缩 IQ 直接加深会恶化选择和压缩路径。
2. **直接 `HEAD_ONLY=0`。** 会让 load 越过地址未知 store，并破坏 StoreBuffer forwarding 年龄前提。
3. **减少 MUL DSP pipeline。** II 已为 1，缩短 latency 的小收益不值得牺牲 Fmax。
4. **把 DCache 全部改组合旁路。** 会恢复 MEM IQ/AGU/SB/DCache 长路径。
5. **先扩 fetch/commit 到 3-wide。** 目标 IPC 1.1，2-wide 足够；三宽会扩大 rename、ROB、PRF、IQ 和 bypass 全部端口。
6. **依赖 Vivado strategy、false path 或 multicycle 提频。** 目标是实际上板运行，不能隐藏真实 CPU 同步路径。
7. **只提高 PLL 频率。** 没有 routed WNS/TNS/WHS/THS 支撑的频率不是可运行频率。
8. **只看短窗 IPC。** 200k 窗口已经被完整 544M-cycle 结果证明不代表矩阵阶段。

## 9. 联合验收门槛

### 9.1 每阶段吞吐判据

每个候选记录同一版本的：

```text
full/window cycles
IPC
routed Fmax
IPC x Fmax
predicted full time = 380,344,388 / (IPC x Fmax x 1e6)
```

合入条件：

- `IPC x routed Fmax` 必须提高；
- 单阶段 predicted full time 至少改善 3%，否则不为复杂微架构承担验证成本；
- 目标阶段至少达到 130 MIPS；
- 不使用未约束路径、虚假 false path 或 multicycle。

### 9.2 功能验证

遵循当前验证约束：

1. RV32UI 40/40、RV32UM 8/8、RV32MI 4/4 全量；
2. 每个小阶段跑 `srcSmoke` 早期/部分，阶段收口跑完整；
3. `srcWithMext` 日常只跑小量 difftest，确认 commit trace 正常推进；
4. 每个 Phase 收口跑固定 50M/100M 矩阵性能窗口；
5. 只有候选达到联合吞吐门槛时才跑完整 `srcWithMext` PASS；
6. 当前 difftest 为 `reference_enabled=false` 的 commit-trace selfcheck，不能冒充 Spike/NEMU 外部参考模型。

内存阶段必须补：

- load/load bypass；
- load 不越过 older store/fence/MMIO；
- full/partial StoreBuffer forwarding；
- hit 连续返回与 FIFO mapping；
- miss、refill、writeback、recover 同时发生；
- wrong-path response drain/epoch；
- critical word 已返回但 line 尚未 valid；
- 8 个 refill word 的地址、index 和写入位置一一对应。

### 9.3 Vivado/QoR

不由本文直接启动长时间 Vivado。用户安排 clean build 后，每个里程碑保留：

- `report_timing_summary` 和最差 20 条 setup/hold path；
- hierarchical utilization；
- high fanout、control sets；
- DRC、CDC、methodology；
- 生成 IP 参数，尤其 DRAM `ENA/REGCEA`；
- 同一 commit 的 IPC JSON。

QoR 对比必须固定 part、seed、strategy、约束和 memory profile，`FPGA_ENABLE_POWER_OPT` 在架构 A/B 对比阶段保持 `false`。每个单阶段顶层 LUT/FF 增幅原则上不超过 5%；超过时必须有相称的 `IPC x Fmax` 收益。`no_clock` 和 unconstrained internal endpoints 必须为 0，不能用 blanket asynchronous clock group、false path 或伪 multicycle 隐藏 CPU 同步路径；既有 `TIMING-47`/CDC/HPDR 类问题必须单独解释。

频率阶梯建议：

```text
50 -> 55/60 -> 75 -> 90 -> 100 -> 110 -> 120 -> 125/130 MHz
```

只有上一档 `WNS>=0, TNS=0, WHS>=0, THS=0` 才进入下一档。PLL 的 system clock 保持 50 MHz，CPU clock 单独提高；counter 继续在 50 MHz `cnt_clk` 域计毫秒，因此 SEG 时间仍是真实 wall-clock time。CPU/counter CDC 必须继续检查。

## 10. 里程碑与预期组合

| 里程碑 | IPC 目标 | Fmax 目标 | 吞吐 | 预测时间 | 说明 |
| --- | ---: | ---: | ---: | ---: | --- |
| M0 当前完整基线 | 0.698 | 50 MHz | 34.9 MIPS | 10.90 s | 已测 |
| M1 refill + stage cut | >=0.75 | >=90 MHz | >=67.5 MIPS | <=5.63 s | 先接近 2x |
| M2 early wake + request/response FIFO | >=0.90 | >=110 MHz | >=99 MIPS | <=3.84 s | 解除 hit-load 隔拍与单 owner 串行化 |
| M3 bounded lookahead | >=1.05 | >=120 MHz | >=126 MIPS | 约3.02 s | 接近目标但余量不足 |
| M4 收口目标 | >=1.10 | >=120 MHz | >=132 MIPS | <=2.88 s | 推荐最终门槛 |
| 备选收口 | >=1.00 | >=130 MHz | >=130 MIPS | <=2.93 s | 偏 Fmax 路线 |

表中 IPC/Fmax 是联合工程目标，不是对单个 Phase 的收益承诺。任何阶段未达到目标时，应根据最新 bottleneck 和 routed path 重新排序，不能为追表格数字破坏正确性。

## 11. 推荐实施顺序

```text
P0  完整/矩阵窗口计数 + 当前 RTL routed baseline
 -> P1A DCache burst refill + critical-word-first
 -> P1B ISS/RRD/EXE stage cut
 -> P1C 半组 PC 的第二 IROM lane（计数证明后）
 -> 测 IPC x Fmax
 -> P2A 2-entry AGU request queue + 2-entry load response FIFO，再按 occupancy 决定 4-entry response
 -> P2B allocated DispatchBuffer
 -> fixed-latency early wake/bypass 收口
 -> 测 IPC x Fmax
 -> P3 2-entry MEM load lookahead + address probe/order proof
 -> 完整 RV/srcSmoke + 小量 srcWithMext difftest
 -> 120 MHz clean route
 -> 完整 srcWithMext PASS 和板上 counter/SEG 验收
 -> P4 仅按新 path/计数做 IQ/PRF/DCache/ROB 调整
```

第一实现批次不应同时改 IQ、PRF、load queue 和 DCache。建议先分别完成 P1A 和 P1B，以便区分 cycle 改善与 Fmax 改善；二者都通过后再合并评估 `IPC x Fmax`。

## 12. 实施记录

### 12.1 Phase 1A：DCache 流水回填

状态：**RTL 与动态验证已完成；routed Fmax 待用户安排 clean Vivado**。

本批次只修改 `rtl/core/memory/DCache.sv`，没有改 DCache 外部端口、`DramBramAdapter`、DRAM IP 参数、IQ、PRF 或 LSU queue。备份位于：

```text
backup/20260711_115311_p1a_dcache_refill/
```

实现合同：

1. `refill_issue_count_q` 和 `refill_resp_count_q` 分别拥有已接受 request 和已消费 response，取值范围为 0～8；
2. 请求 word 为 `(critical_word + issue_count) mod 8`，因此顺序为 critical first，然后环形覆盖其余 7 words；
3. `DC_REFILL_REQ` 在 `mem_req_ready=1` 时每拍接受一个 read，接受第 8 个请求后进入 `DC_REFILL_WAIT`，只排空返回；
4. response word 由有序返回序号计算，不把正确性硬编码为固定两拍延迟，因此允许 request ready 或 response valid 中间出现空洞，但要求下游保持 read response 顺序；
5. `refill_valid_mask_q` 记录已写入 word，只有第 8 个 response 到达且 mask 为全 1 时才同时提交 tag、valid、LRU；
6. load miss 在 critical response 到达时直接返回数据，store miss 仍等整行完成后进入 `DC_FINISH` 做 write-allocate merge；
7. dirty victim 的 8-word writeback 保持原有串行写顺序，writeback 完成后才开始 refill，不与 read response ownership 重叠；
8. uncached read/write 状态机保持原合同。

critical word 提前返回暴露了现有 `DramAccessIF` 的隐含前提：load request 是单拍 pulse，而且没有独立的 cache request-ready。当前 load 完成后，上游可能在整行尚未 valid 时发出下一项 load。为避免丢请求，DCache 内增加一个 `cpu_read_hold`：

- 只在 refill 期间捕获一项新的 read pulse；
- line fill 完成后优先于外部新请求重放；
- held read 重放的命中不会拉高外部 `cpu_req_ready`，避免同时到达的 StoreBuffer write 被误认为已经接受；
- 当前 LSU 只有一个 `mem_load_pending_q`，所以在该 held read 完成前不会出现第三项 read，深度 1 足够；
- Phase 2A 引入多 outstanding load 时，必须用正式 request ready/queue 合同替换这个过渡保护，不能继续扩大隐式 hold。

`VERILATOR_TB` 下新增断言覆盖：response 不得超过已发 request、response 必须有 owner、word 不得重复、critical word 不得重复、最终 mask 不得缺 word、read hold 不得溢出。任一断言失败都视为 P1A 不可合入。

阶段验收表：

| 项目 | 基线 | P1A 结果 | 状态 |
| --- | ---: | ---: | --- |
| RV32UI/UM/MI | 40/40、8/8、4/4 | 40/40、8/8、4/4 | PASS |
| `srcSmoke` | 33,398,179 cycles，IPC 0.920966 | 33,398,117 cycles，IPC 0.920968 | PASS |
| `srcWithMext` difftest 500k | 旧 500k IPC 0.831074 | 441,075 commits selfcheck；37+8、fail 0；IPC 0.882140 | PASS/TIMEOUT expected |
| `srcWithMext` 50M window | 旧 100M 总窗约 IPC 0.693325，不直接同比 | 37,809,630 commits；IPC 0.756193 | PASS/TIMEOUT expected |
| DRAM reads / miss | 8.000 | 500k 与 50M 均为 8.000 | PASS |
| DCache stall / miss | 34.23 cycles | 500k 17.76；50M 12.24；`srcSmoke` full 11.57 | PASS |
| 仿真断言 | - | 0 failure | PASS |
| routed Fmax | 当前可信值未知 | 用户后续 clean Vivado | deferred |

500k IPC 相对旧记录从 0.831074 提升到 0.882140，增幅约 6.14%。50M 窗口中 DCache stall 为 1,977,409 cycles，占窗口 3.95%；同一窗口有 161,595 misses、1,292,760 DRAM reads。每 miss 12.24 stall cycles 落在计划预估的 11～14 cycles 区间，说明原串行 request/wait occupancy 已被消除。

这些窗口尚不能代替完整 544M-cycle PASS，也不能在没有 route 的情况下声明真实 wall-clock 加速。P1A 已满足独立功能与周期方向门槛，因此保留；完整 `srcWithMext` 留到 P1A 与后续 Fmax stage-cut 合并成为里程碑候选时再跑。

Vivado 综合、布局布线和 IP regeneration 本批次均未自动调用。`fpga/build` 在当前 workspace 不存在，所以本批次不能生成或读取与当前 RTL 同 commit 的 routed Fmax；下一阶段只能先静态准备，最终优先级仍须由用户后续 clean routed report 复核。

## 13. 最终判断

3 秒目标在当前 2-wide 架构上不是理论不可达，但要求从 `34.9 MIPS` 提升到至少 `126.8 MIPS`，属于一次 3.63x 的联合优化，而不是参数微调。

最有希望的落点是 `120 MHz x IPC 1.10`。实现它需要：

- 通过明确 stage boundary 把当前大组合阶段切到 8 ns 量级；
- 通过 early wakeup/bypass 避免深流水摧毁依赖吞吐；
- 通过 burst refill、load FIFO 和保守 lookahead 处理完整程序中占 34.7% 的 memory uop；
- 保持两宽，提升 0/1-wide 周期的利用率，而不是扩大峰值宽度；
- 全程以 `IPC x routed Fmax` 和完整 counter 时间决定是否合入。

如果只做 IPC 路线，100 MHz 下需要 IPC 1.268；如果只做 Fmax 路线，IPC 0.698 需要约 182 MHz。两者对当前 Kintex-7 OoO 核都不现实。联合路线是达到 3 秒目标的必要条件。
