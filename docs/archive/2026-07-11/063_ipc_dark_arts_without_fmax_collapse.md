# R1 后 IPC“邪修”优化候选：不显著牺牲 Fmax 的高收益路线

日期：2026-07-11

当前 RTL 提交：`4762e00314f73810344185077f002c4c7db0dea6`（`opt MEM ISQ`）

关联文档：

- [061_ipc_fmax_joint_optimization_analysis.md](./061_ipc_fmax_joint_optimization_analysis.md)
- [062_current_ipc_fmax_optimization_status_and_roadmap.md](./062_current_ipc_fmax_optimization_status_and_roadmap.md)
- [061_vivado_100mhz_timing_baseline/README.md](./061_vivado_100mhz_timing_baseline/README.md)

本文所说的“邪修”是指：利用 workload 特征、固定流水延迟、冷/热结构分离、精确 memoization 或可恢复推测，获得超出常规扩容的 IPC 收益；不包括硬编码 benchmark PC、伪造计数器、跳过指令、错误 memory ordering 或伪 false-path。

## 0. 结论先行

R1 已把 50M IPC 从 `0.870506` 提升到 `0.976866`，提高 `12.22%`。下一阶段最值得尝试的不是双端口 DCache、扩大 ROB 或直接加深现有 IQ，而是以下三项：

1. **INT IQ cold parking queue（冷指令停车场）**：保持 8-entry 热选择窗口不变，把长期等待 load/MUL 的 uop 停到不参与 issue select 的冷队列；它直接针对 58.05% 的 INT IQ backpressure，又不会把热 oldest-ready mux 扩到 12/16 项。
2. **store address/data split**：store 地址只依赖 `prs1`，数据依赖 `prs2`；允许地址先进入带 `addr_valid/data_valid` 的 Store Buffer shell，避免等待 store data 的指令长期占据 MEM IQ 并阻断 younger load。
3. **MUL 专用 early-tag + result bypass**：从 MUL 固定流水倒数一级广播 tag，下一拍给 INT consumer 使用真实 MUL result bypass；它修复旧 early-wakeup“读到旧 PRF”的根因，又不把 early wakeup 广播到所有 consumer。

次一级候选：

4. 4～8 entry 精确 L0 load-value buffer；
5. 单 miss 的 same-line follower/refill snoop；
6. rename/dispatch 后的常量 uop 预完成队列；
7. 带 violation recovery 的 memory-dependence predictor；
8. profile-guided stride/next-line prefetch；
9. MUL+ADD/MAC fusion，仅在动态画像证明机会足够大时研究。

在写任何新结构前，最划算的第一步是增加分类计数。当前数据能证明“压力很大”，但尚不能区分压力来自 load producer、MUL producer、store data、真实容量还是热点 opcode。

## 1. 证据边界

### 1.1 已测事实

当前提交的 50M `srcWithMext` 快照：

| 指标 | 当前值 | 占 50M | 解释 |
| --- | ---: | ---: | --- |
| commits | 48,843,293 | — | 37+8，fail 0 |
| IPC | 0.976866 | — | R1 前为 0.870506 |
| INT IQ backpressure | 29,024,558 | 58.05% | 当前最大资源压力 |
| MEM IQ head-not-ready | 35,066,233 | 70.13% | 仍然很高 |
| younger-ready behind MEM head | 29,679,662 | 59.36% | 占 head-not-ready 的 84.64% |
| MEM IQ 平均 occupancy | 3.331 / 5 | — | 不是空队列问题 |
| R1 probe launch | 4,012,902 | 8.03% | lookahead 确实在工作 |
| R1 probe accept | 4,012,822 | 99.998%/launch | 少量差值来自 recover/clear |
| load pending | 20,813,410 | 41.63% | load latency 继续传播到 INT |
| ROB head wait MEM | 12,649,994 | 25.30% | 提交仍明显受内存限制 |
| ROB head wait MUL | 4,109,116 | 8.22% | 固定流水依赖链值得优化 |
| DCache stall | 2,481,097 | 4.96% | 值得优化，但不是第一瓶颈 |
| DCache miss | 217,945 | 1.49%/access | stall/miss 约 11.38 cycles |
| MEM IQ backpressure | 3,671,699 | 7.34% | R1 后已显著低于 INT IQ |
| MEM issue block | 89,699 | 0.18% | 2-entry request queue 不是主瓶颈 |
| StoreBuffer block | 547 | 0.0011% | 不能据此直接扩大 SB |
| ROB full | 398 | 0.0008% | 扩大 ROB 没有证据 |
| recovery | 34,419 | 0.069% | 更大 BPU 不是当前 IPC 主线 |

宽度利用率：

| 指标 | 当前值 |
| --- | ---: |
| issue 0-wide cycles | 31.73% |
| issue >=2-wide cycles | 25.94% |
| commit 0-wide cycles | 33.73% |
| commit 2-wide cycles | 31.41% |

### 1.2 尚未证明的事情

1. 当前提交尚无 clean routed Fmax；所有“频率风险低”都只是结构判断，不是 sign-off 结果。
2. `INT IQ backpressure` 尚未按 blocking PRD producer 分类，因此不能直接认定“8 entries 太小”。
3. `MEM IQ head-not-ready` 尚未按 load/store、地址源/数据源分类，因此不能直接估算 store split 的收益。
4. 尚无 opcode/pair/reuse-distance 画像，常量预完成、fusion、L0 value buffer 和 prefetch 的收益都必须先计数。
5. 当前 uop 没有静态 device 属性。R1 能证明被提前执行的 younger load 自身为 normal-cacheable，并且不越过 store/fence/serial；如果要求证明一个地址尚未知的 older load 一定不是 device，需要新增 memory attribute 或 older-address probe。

## 2. 3 秒目标现在差多少

历史目标吞吐约为 126.781 MIPS。用当前 IPC 0.976866 估算：

| routed Fmax | 达标所需 IPC | 相对当前仍需提高 |
| ---: | ---: | ---: |
| 110 MHz | 1.15255 | +17.98% |
| 115 MHz | 1.10244 | +12.85% |
| 120 MHz | 1.05651 | +8.15% |
| 125 MHz | 1.01425 | +3.83% |
| 130 MHz | 0.97524 | 当前 IPC 理论上已够 |

因此后续不再需要一个“翻倍 IPC”的大手术。若 clean route 能达到 120 MHz，只需再取得约 8.2% IPC；这更适合由两个 3%～6% 的低频率风险侧车结构叠加完成。

## 3. 所有方案的频率保护原则

以下原则是本文候选能否采用的硬门槛：

1. **热选择窗口不扩深**：INT oldest-ready 仍只扫描 8 项；新增容量放在不参与当拍 select 的 cold queue。
2. **tag 早于 data**：early wakeup 只能来自寄存的固定流水 metadata；真实 operand 必须有对齐的 result bypass。
3. **select 不等于 remove**：任何 probe、prediction、parking transfer 都必须在下游接管并核对 identity 后才能删除原 owner。
4. **ready 不组合回 valid**：DCache、StoreBuffer、completion arbitration 不能组合穿回 IQ select。
5. **大 CAM 不进 hit path**：reuse、violation、refill follower 的比较应放在 request register 后，或将结果打一拍。
6. **预测错误必须可恢复**：没有 replay/flush owner 的预测不允许改变 architectural result。
7. **精确优化优先**：先做 exact L0、store split、定向 bypass，再考虑 value prediction。
8. **每项单独 route**：以 `IPC × routed Fmax` 判断，不以仿真 IPC 单独判断。

如果删掉这些边界：最常见结果不是“小幅掉频”，而是重新出现 `IQ → PRF → AGU/ALU → completion → wakeup → IQ` 组合环，或发生 flush 后误删复用 slot 的静默错误。

## 4. X1：INT IQ cold parking queue

### 4.1 为什么它比“INT IQ 8→12”更合适

当前 INT IQ 使用 8-entry `CoreCompressedQueue`，每拍执行：

```text
4路wakeup比较
→ 8项ready生成
→ 2个oldest-ready选择
→ 任意remove
→ 全payload压缩
→ 最多2项push
```

直接增到 12/16 会同时放大比较、选择、payload mux 和 compaction。cold parking 的核心是：容量可以增大，但热选择逻辑保持 8 项。

### 4.2 建议结构

```text
dispatch
  ├─ ready/短等待 uop ───────────────→ 8-entry active INT IQ
  └─ 等待MEM/MUL或双源未ready uop ─→ 4-entry cold parking
                                           │
                                  registered wakeup bitmap
                                           │
                                  2-entry reinject FIFO
                                           │
                                           └→ active INT IQ
```

第一版只在以下情况使用 parking：

- active IQ 满或只剩一个槽；
- incoming uop 至少一个源未 ready；
- cold queue 有空位；
- uop 不是 branch/serial/CSR；
- producer 类型明确为 MEM 或 MUL，或两个源都未 ready。

parking entry 保存：

```text
valid + ROB id + uop + prs1/prs2 + ready bits + global age
```

它只做 wakeup compare，不做 ALU 选择。两个源 ready 后进入 registered reinject FIFO；reinject 与新 dispatch 仲裁进入 active IQ。

### 4.3 为什么可能显著提高 IPC

长期等待的 uop 当前会占据 active IQ 槽位，使前端在仍有独立工作可做时停住。parking 不缩短 producer latency，却允许更多独立 uop 越过等待链，特别适合：

- load miss/load-use chain；
- MUL→ADD accumulation；
- 两条不同 dependency chain 交错的矩阵代码。

条件性收益预估：若超过一半 INT IQ block 是“满队列中至少 3 项等待 MEM/MUL”，50M IPC 有机会提高 5%～15%；若主要是所有新 uop 都依赖同一 load，收益会很低。

### 4.4 Fmax 风险控制

- active IQ 深度和 issue mux 不变；
- cold queue wakeup 结果打一拍；
- reinject ready 只看本地 FIFO occupancy；
- 不让 cold queue 直接竞争当拍 ALU issue port。

如果让 cold queue 和 active IQ 同拍共同做全局 oldest-ready：会变相得到 12-entry 2-port IQ，失去该方案的频率优势。

### 4.5 必须防的 bug

1. push 与 wakeup 同拍：新 entry 必须累积该次 wakeup，否则永久睡眠。
2. wakeup 与 reinject stall：ready 状态必须保留，不能做单周期脉冲。
3. recover：active、cold、reinject 三处只能保留一个 owner，全部 wrong-path valid 必须清除。
4. active→cold spill：只有 cold 明确 accept 后才能从 active 删除。
5. 饥饿：ready cold entry 需要 age/fairness，不能永远让新 dispatch 抢占 reinject。
6. 重复 issue：转移期间必须携带 `ROB id + PRD` identity。

如果 transfer 时先删 active、后发现 cold full：该 uop 会永久丢失，ROB 最终死锁。

## 5. X2：store address/data split

### 5.1 当前浪费

当前 MEM IQ 对 load/store 都要求：

```systemverilog
src1_ready && src2_ready
```

但 store 的两个源语义不同：

- `prs1`：地址 base；
- `prs2`：store data。

只要 data 晚到，store 就不能离开 MEM IQ；R1 又禁止 younger load 越过 store，因此一条“地址已知、数据未到”的 store 会形成全局 MEM barrier。

### 5.2 建议结构

Store Buffer entry 改为：

```text
valid / retired / rob_idx
addr_valid / addr
data_valid / data / mask
data_prd
exception_valid
```

执行分两条独立路径：

```text
store address ready
→ AGU
→ reserve/push SB shell(addr_valid=1, data_valid按当拍情况)

store data later wakeup
→ PRF读取或result capture
→ 按ROB id更新已存在SB shell.data
```

load 对 older store 的处理：

| older store 状态 | younger load 行为 |
| --- | --- |
| addr 未知 | 必须阻塞或走可恢复预测 |
| addr 已知、无 alias | 可以访问 DCache |
| addr 已知、full alias、data ready | StoreBuffer forwarding |
| addr 已知、alias、data 未 ready | 等 data，不能读旧 DCache 值 |
| partial alias | 等待或做 byte merge，第一版建议等待 |

### 5.3 ROB 完成语义

第一版最安全的完成条件：

```text
store_done = addr_valid && data_valid && no_exception_pending
```

地址先进入 SB 只代表 memory-order ownership 已建立，不代表 ROB 可以退休。否则 store 可能先退休，随后 recover 不能丢弃它，但数据还没有 owner。

如果把 `addr_valid` 误当成 store complete：retired store 可能以未初始化 data 写入 DRAM，属于静默破坏。

### 5.4 为什么可能显著提高 IPC

它同时解决三种压力：

1. store 更早离开 5-entry MEM IQ；
2. younger load 不再被“仅 data 未到”的 store 无条件挡住；
3. store 地址提前建立后，可进行精确 alias/no-alias 判定。

若计数证明 MEM head-not-ready 中大量是 `store.addr_ready && !store.data_ready`，该项可能取得 5%～20% IPC，是本文潜力最高的精确优化之一。

### 5.5 Fmax 风险

主要风险不是 AGU，而是 StoreBuffer 更新 CAM：按 ROB id 找 shell、按地址查 forwarding。建议：

- reserve/update 均在 registered 边界后；
- data update 与 load-query CAM 分开；
- 不在同拍串联 `MEM IQ select → AGU → SB CAM → DCache ready → IQ pop`；
- 如 8-entry ROB-id update CAM 变慢，可保存 SB slot token，后续按 slot+ROB identity 更新。

## 6. X3：MUL 专用 early-tag + result bypass

### 6.1 为什么旧 early wakeup 会错

旧试验把 early tag 广播到 MEM/MUL consumer，但 consumer 在 producer 写 PRF 的同一边沿读取，拿到旧值。只提前 ready bit、没有 operand bypass，本质上是错误的。

### 6.2 正确的定向结构

MUL 是固定延迟流水，可以从倒数一级得到稳定 metadata：

```text
cycle N:   MUL stage[-2] 保存 valid/prd/uop identity
cycle N+1: INT IQ 看到 registered early tag，选择 dependent consumer
cycle N+1: MUL result 同时到达 execute bypass input
cycle N+1: consumer operand mux 命中 prs==mul_result_prd
cycle N+2: consumer 完成
```

第一版只给 INT consumer：

```systemverilog
operand = mul_bypass_valid && (prs == mul_bypass_prd)
        ? mul_bypass_data
        : prf_rdata;
```

MEM consumer 暂不使用，因为 MEM probe/request 的 ownership 不同；MUL consumer 暂不使用，避免构造新的 pipeline feedback。

### 6.3 收益来源

当前 50M 有：

- 1,403,793 个 MUL；
- 4,109,116 cycles ROB head wait MUL；
- 典型矩阵代码常见 `mul → add` accumulation。

如果 MUL 结果的大量第一消费者是 INT ALU，可以减少一拍 dependency latency，并释放 INT IQ waiting slot。条件性预估为 2%～8%。

### 6.4 Fmax 风险控制

- early tag 必须来自 MUL pipeline 寄存器，不从组合乘法结果生成；
- bypass 只增加每个 INT source 一个 tag compare 和 2:1 mux；
- 若 mux 成为关键路径，可在 issue 后增加局部 operand capture，而不是恢复全局 RRD；
- 不允许 `result → wakeup → IQ select → result` 同拍闭环。

### 6.5 关键断言

```text
early_wakeup(prd, age) 在下一拍必须对应 valid MUL result(prd, age)
consumer 使用 bypass 时，prs 必须等于 bypass_prd
flush 后 early tag 和 result valid 同时失效
同一 PRD 不允许出现两个 result owner
```

如果 pipeline stall/flush 时 tag 和 data 错一拍：consumer 会计算出合法但错误的数，通常比直接 crash 更难排查。

## 7. X4：4～8 entry 精确 L0 load-value buffer

### 7.1 它不是 load value prediction

这是一个保存最近 normal-cacheable word 的精确小缓存：

```text
full word address + data + valid
```

load 地址在 registered request stage 后查 L0；full-address 命中且 StoreBuffer 没有 older conflicting store 时，直接生成 load response，不访问 DCache。

### 7.2 一致性规则

1. 只缓存 normal-cacheable、aligned word；byte/half load可从 word提取。
2. 任意 store 地址生成时，对相同 word 的 L0 entry invalidate；wrong-path store 导致多余 invalidate 是安全的。
3. StoreBuffer forwarding 优先于 L0。
4. DCache refill/eviction不要求 invalidate L0，因为单核无外部 coherence 时，L0 本身就是更高一级 cache。
5. uncached/device 永不进入 L0。
6. 若存在 DMA 或外部 master 修改 cacheable 区域，则必须增加 snoop/invalidate；否则该方案不可用。

### 7.3 收益与频率

该结构可同时减少：

- DCache hit latency；
- DCache port占用；
- load metadata占用时间；
- dependent INT 的等待时间。

但收益完全取决于 4/8-entry reuse hit rate。先用 trace 统计 full-word reuse distance；若 8-entry hit rate低于约 10%，不值得实现。

Fmax 保护：L0 lookup 放在 request register 后，不放在 MEM IQ/AGU 组合路径。4-entry fully-associative regs 或 8-entry direct-mapped+full-tag 都可先试。

如果只比较低位 index、不比较完整地址：不同 matrix 行会错误命中，产生静默数据错误。

## 8. X5：same-line miss follower，而不是完整多 MSHR

当前 DCache miss 率只有 1.49%，但每 miss 约产生 11.38 stall cycles。完整多 MSHR 复杂且容易影响 Fmax；更“邪修”的做法是只合并当前 refill line 的后继 load。

### 8.1 建议结构

```text
active miss: line address + current refill beat
follower[0:1]: full address + word offset + load metadata + killed
```

当 DCache 正在 refill：

- 新 load 与 active miss 同 line：进入 follower；
- 所需 beat 已经到达：从 refill word buffer 返回；
- beat 尚未到达：等待该 beat；
- 不同 line：仍然阻塞，不引入第二 MSHR。

### 8.2 为什么频率风险较低

只需比较一个 registered active-line tag；不修改常规 hit tag/data lookup，也不增加 replacement 并发 owner。

### 8.3 必须处理的顺序

- response 必须与 load metadata owner 对齐；
- younger follower 的 beat 即使先到，也不能破坏当前接口要求的 response 顺序；
- recover 后 follower 保留 killed owner直到应有 response 被消费，或在尚未接管外部事务时安全取消；
- store miss 和 uncached 请求不参与 follower。

如果 beat data 和 follower word offset 错位：会返回同一 cache line 的另一个合法 word，普通地址范围检查无法发现。

条件性收益预估 1%～5%；先统计“DCache busy时到达的同线 load”比例。

## 9. X6：常量/已知结果 uop 预完成

部分指令的结果在 rename/dispatch 后已经完全确定，不需要占用 INT IQ 和 ALU：

- `LUI`；
- `AUIPC`；
- `ADDI rd, x0, imm`；
- `XOR/SUB rd, rs, rs` 等可证明 zero idiom；
- 部分 `COPY_B` 类内部 uop。

建议加入 2-entry registered precompute completion queue：

```text
decode/rename classification
→ 已分配 ROB/PRD 后 enqueue(result, ROB id, PRD)
→ 与普通 completion 在 registered arbiter 仲裁
→ PRF write + ROB done
```

它不是 rename 同拍直写 ROB/PRF；否则会重新制造 rename→PRF/ROB 长路径。

第一版不要做 register move elimination。把 `addi rd,rs,0` 直接 RAT alias 到 `rs` 需要 physical register reference count；没有 refcount 就提前 free shared PRD，会导致后续读到被重分配的数据。

收益取决于 opcode 占比。若 eligible uop 超过 committed instructions 的 5%，它可能以很小的频率代价减少 2%～6% INT IQ 压力。

## 10. X7：memory-dependence predictor + violation recovery

这是本文第一个真正的高风险推测方案，只有在 store-barrier 计数证明机会很大时才做。

### 10.1 核心思想

R1 当前禁止 load 越过任何 older store。可用按 load PC 索引的小型 2-bit predictor 判断该 load 历史上是否与 older store 冲突：

```text
预测no-alias
→ younger normal-cacheable load probe/执行
→ 在LSQ中保存 speculative load addr/ROB age
→ older store地址生成时做violation compare
→ 命中则flush/replay该load及其所有younger uop
```

### 10.2 为什么可能有大收益

如果大量 MEM HOL 来自地址/数据未 ready 的 store，而 load 实际访问独立 matrix 区域，预测可绕开当前最保守 barrier，潜力可能达到 5%～20%。

### 10.3 为什么不能直接做“总是假设不相关”

必须补齐：

- speculative load queue；
- store address resolution compare；
- violation recover PC；
- sRAT/ROB恢复合同；
- predictor训练；
- load不得退休早于所有可能冲突的older store完成检查；
- device/uncached load永不推测；
- wrong-path load response继续正确drain metadata。

如果只允许 load 越过 store，却没有 violation detection：同地址时会读到旧值，属于架构错误，不是性能取舍。

### 10.4 Fmax 保护

violation CAM 放在 store address register 后；检测结果下一拍发 recover，不进入 AGU/DCache hit path。预测表在 MEM IQ probe 前打一拍，不允许 predictor read 直接控制当拍 IQ remove。

## 11. X8：profile-guided prefetch

矩阵/数组 workload 可能适合极小的 stride 或 next-line prefetcher：

```text
last miss line + signed stride + confidence
→ confidence足够时请求下一line
→ 放入1-entry prefetch buffer
→ demand命中时转为正常response/fill
```

建议先做 1-entry prefetch buffer，不直接污染主 DCache set。只在 DRAM idle、normal-cacheable、没有 writeback/uncached 请求时发起。

收益上限受当前 4.96% DCache stall 约束，通常不应排在 X1/X2/X3 前面。但若 miss address trace 显示稳定 stride，1%～5% IPC 可能很便宜。

如果 prefetch 与 demand 共用无优先级仲裁：可能增加 demand latency，IPC 反而下降。

## 12. X9：MUL+ADD / MAC fusion

这是更偏 workload 的 FPGA 邪修。DSP48 天然支持乘加，矩阵代码也常出现：

```text
mul t, a, b
add acc, acc, t
```

但不能只产生 MAC 最终值，因为两个 RISC-V 指令各自具有 architectural destination/ROB entry。安全 fusion 至少需要：

- 证明两条相邻或可配对；
- MUL intermediate PRD 没有第二消费者，或仍能输出中间乘积；
- 两个 ROB entry分别完成；
- exception/recover identity 对齐；
- DSP pipeline 同时保存 multiply intermediate 和 MAC final，或保留额外结果路径。

更实际的第一步是 X3 的 MUL→INT bypass。只有画像显示大量“一对一 MUL+ADD”、且 X3 后仍有明显 wait MUL，才研究 fusion。

如果仅依据相邻指令就假设 MUL destination 不再被使用：后续读取该寄存器时会得到错误状态。

## 13. 暂时不要做的“邪修”

| 方案 | 当前结论 | 原因 |
| --- | --- | --- |
| load value prediction | 暂不做 | 需要全依赖链 replay；错误值可能传播到 store/branch |
| 直接 INT IQ 8→16 | 不做 | 放大 wakeup/select/compaction，Fmax 风险直接 |
| 双端口 DCache | 不做 | 上游仍单 AGU/单 request consumer，DCache stall仅4.96% |
| 完整 2-MSHR DCache | 后置 | ownership、writeback、response tag复杂；先做same-line follower |
| 总是假设 load/store no-alias | 禁止 | 没有 violation recovery 就是功能错误 |
| register move elimination | 后置 | 需要PRD refcount与精确free ownership |
| execute→ROB/commit 组合 bypass | 禁止 | 会恢复旧 ROB/commit/BPU 长路径 |
| 同拍 load response→IQ wakeup→ALU | 禁止 | 极易形成大组合环或读旧PRF |
| benchmark PC触发/跳过循环 | 禁止 | 不属于合法通用处理器优化 |
| 虚假 multicycle/false path | 禁止 | 掩盖真实同步失败 |

## 14. 先加哪些计数

### 14.1 INT IQ 分类

1. occupancy 0～8 直方图；
2. ready-entry 数量 0～8 直方图；
3. dispatch block 时 active IQ 中等待 MEM/MUL/INT/未知 producer 的 entry 数；
4. 第一个 blocking PRD 的 producer 类型；
5. uop 从 push 到 ready、从 ready 到 issue 的等待周期；
6. 满队列时是否仍有 0/1/2 个 ready candidate；
7. 若存在 4-entry parking queue，理论上可接收的 blocked dispatch 次数。

### 14.2 MEM/store 分类

1. head 是 load 还是 store；
2. load 缺 address source 的周期；
3. store 的四种状态：addr/data 都 ready、仅 addr ready、仅 data ready、都未 ready；
4. younger load 被 store barrier 阻塞的周期；
5. store 地址已知后，younger load 实际 no-alias/full-alias/partial-alias 比例；
6. older 地址未知但 memory-dependence predictor 理论可放行的次数。

### 14.3 MUL dependency

1. MUL result 的第一消费者类型；
2. MUL→INT consumer 距离；
3. MUL completion 前一拍已有 dependent INT ready-except-that-source 的周期；
4. 同一 MUL PRD 的 consumer 数量；
5. `mul→add` opcode/PRD pair 次数。

### 14.4 L0/refill/prefetch

1. 最近 4/8/16 个 word 的 exact reuse hit rate；
2. DCache busy 时同 active refill line 的 load 次数；
3. miss line stride 分布与 confidence；
4. prefetch buffer 理论 useful/late/useless 次数；
5. L0 hit 被 older StoreBuffer alias 否决的次数。

这些计数必须是 `VERILATOR_TB` 或不进入综合的 debug sideband，不能为画像本身牺牲 routed Fmax。

## 15. 优先级与进入门槛

| 顺序 | 候选 | 潜在 IPC | Fmax 风险 | 正确性风险 | 开始条件 |
| ---: | --- | ---: | --- | --- | --- |
| P0 | 当前提交 clean route | 0 | 无新增 | 低 | 立即 |
| P0-M | 分类计数 | 0 | 仿真only | 低 | 立即 |
| P1 | INT cold parking | 5%～15% 条件性 | 低～中 | 中 | blocked producer/ready histogram命中 |
| P1 | store addr/data split | 5%～20% 条件性 | 中 | 高 | `addr_ready && !data_ready`占比高 |
| P1 | MUL early-tag+bypass | 2%～8% 条件性 | 低～中 | 中 | MUL→INT dependency画像命中 |
| P2 | exact L0 value buffer | 2%～8% 条件性 | 低～中 | 中 | 8-entry exact reuse hit高 |
| P2 | same-line follower | 1%～5% | 低 | 中～高 | refill期间同线load比例高 |
| P2 | constant precomplete | 2%～6% 条件性 | 低 | 中 | eligible opcode占比高 |
| P3 | stride prefetch | 1%～5% | 低 | 中 | miss stride稳定 |
| P3 | memory dependence prediction | 5%～20% 条件性 | 中 | 很高 | store barrier为主且有恢复预算 |
| P4 | MAC fusion | 未知 | 中 | 很高 | pair/profile与双完成合同充分 |

“潜在 IPC”是工程推断区间，不是已测结果。任何候选若画像不满足开始条件，应直接跳过。

## 16. 推荐实验顺序

### E0：冻结物理与动态基线

1. 对 `4762e00` 做 clean 100 MHz route；
2. 保存 top timing paths、WNS/TNS、LUT/FF/BRAM/DSP；
3. 冻结当前 500k、50M、srcSmoke JSON；
4. 增加第14节计数并重新跑50M。

### E1：优先选一个“容量侧车”和一个“延迟旁路”

- 若 INT blocked producer 主要是 MEM/MUL：先做 cold parking；
- 若 MEM head 大量是 store data 未 ready：先做 store split；
- 若 MUL→INT chain 密集：MUL early-tag+bypass可与前两者之一独立 A/B。

不要同时合入三项，否则 IPC/Fmax 变化无法归因。

### E2：利用精确局部性

- exact reuse hit高：L0 value buffer；
- refill同线请求高：same-line follower；
- miss stride稳定：prefetch。

### E3：最后才启用可恢复推测

只有精确方案仍无法达到 IPC×Fmax 目标，并且 store barrier 证据足够强，才实现 memory-dependence predictor。load value prediction 不在当前路线内。

## 17. 每项验收标准

功能：

- RV32UI 40/40、UM 8/8、MI 4/4；
- `srcSmoke` PASS；
- `srcWithMext` 500k、50M 均 37+8、fail 0；
- 完整 `srcWithMext` 最终 PASS；
- memory-order、flush/recover、stale identity、双 owner 断言全开。

性能：

- 单项 50M IPC 至少提高 2%，否则原则上不保留复杂结构；
- 或 IPC 提升较小但 routed Fmax 提高，使 `IPC × Fmax` 至少提高 3%；
- 比较必须使用相同 binary、max cycles、Verilator build 和 Vivado strategy。

频率：

- 单项 routed Fmax 降幅超过 IPC 增幅时回退；
- 新 top path 不得形成 IQ/PRF/Execute/DCache/ROB 的跨模块组合闭环；
- reset/recover/CDC 必须继续 sign-off；
- 不能用 unconstrained、false path 或 multicycle 掩盖功能路径。

资源：

- parking/L0/follower 优先使用小寄存器阵列，不为 4-entry 结构强行推导复杂 RAM；
- DSP 数量不因“优化 MUL latency”无依据翻倍；
- BRAM 复制只有 routed timing 和资源预算共同允许时才接受。

## 18. 最终建议

当前最可能达成“显著 IPC、频率不严重受损”的组合是：

```text
INT cold parking
    + store address/data split
    + MUL定向early-tag/result-bypass
```

三者分别增加冷容量、解除内存顺序假阻塞、缩短固定 producer dependency；都可以把新增状态放在 registered sidecar，而不扩大当前热 IQ、PRF 端口或 DCache hit mux。

推荐实际执行顺序：

```text
clean route
→ producer/source分类计数
→ cold parking 或 store split（二选一做单项A/B）
→ MUL定向bypass
→ exact L0 / same-line follower
→ 必要时才做memory-dependence prediction
```

最值得先验证的判断不是“要不要把 INT IQ 加深”，而是：**29M 个 INT IQ block 周期中，有多少槽位只是被长延迟 MEM/MUL consumer 占住；35M 个 MEM head-not-ready 周期中，有多少是 store 地址已经 ready、只有 data 未 ready。** 这两个数字将决定下一项 5%～15% IPC 收益究竟来自 cold parking 还是 store split。
