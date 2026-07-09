# NOP-Core 架构与微架构详解

> 参考工程：`resource/NOP-Core/`
> 参考版本：NSCSCC 2023 NOP-Core，Scala/SpinalHDL 实现，生成 `mycpu_top.v`
> 文档日期：2026-07-09
> 用途：作为 superScalar 手写 SystemVerilog 迁移时的微架构参考，而不是逐行照搬 SpinalHDL 代码。

---

## 1. 源码阅读范围

本次补充主要依据以下源码：

```text
src/MyCPUConfig.scala
src/pipeline/core/MyCPUCore.scala
src/pipeline/fetch/*
src/pipeline/decode/*
src/pipeline/exe/*
src/pipeline/mem/*
src/pipeline/core/*
src/pipeline/privilege/*
src/utils/CompressedQueue.scala
src/utils/CompressedFIFO.scala
```

NOP-Core 的实现不是一个传统硬连线顶层，而是插件化多流水框架：

- `MyCPUCore.scala` 定义所有 pipeline stage 和插件清单。
- 各插件通过 service 互相拿接口，例如 `CommitPlugin`、`ROBFIFOPlugin`、`PhysRegFilePlugin`。
- `Stageable` 是跨流水级传递 payload 的核心机制。
- 迁移到 superScalar 时不能照搬 plugin 机制，但应照搬它的“责任边界”：front/decode/rename/issue/execute/mem/commit/privilege 分离。

---

## 2. 总体参数与事实修正

### 2.1 全局默认参数

来自 `MyCPUConfig.scala`：

| 类别 | 参数 | 默认值 |
|---|---|---:|
| Frontend | `pcInit` | `0x1c000000` |
| Frontend | `fetchWidth` | 4 |
| Frontend | `fetchBufferDepth` | 8 |
| ICache | `sets` | 64 |
| ICache | `lineSize` | 64 B |
| ICache | `ways` | 2 |
| BPU | `sets` | 1024 |
| BPU | `phtSets` | 8192 |
| BPU | `historyWidth` | 5 |
| BPU | `counterWidth` | 2 |
| BTB | `sets` | 1024 |
| BTB | `lineSize` | 4 B |
| BTB | `ways` | 1 |
| RAS | `rasEntries` | 8 |
| Decode | `decodeWidth` | 3 |
| RegFile | `nArchRegs` | 32 |
| RegFile | `nPhysRegs` | 63 |
| Int IQ | `issueWidth` | 3 |
| Int IQ | `depth` | 7 |
| MulDiv IQ | `issueWidth` | 1 |
| MulDiv IQ | `depth` | 3 |
| Mem IQ | `issueWidth` | 1 |
| Mem IQ | `depth` | 5 |
| StoreBuffer | `storeBufferDepth` | 8 |
| ROB | `robDepth` | 32 |
| ROB | `retireWidth` | 3 |
| MUL | `multiplyLatency` | 2 |
| DIV | `divisionEarlyOutWidth` | 16 |
| TLB | `numEntries` | 16 |

### 2.2 Cache 容量说明

源码中 `ICacheConfig/DCacheConfig` 都有：

```scala
sets = 64
lineSize = 64
ways = 2
require(sets * lineSize <= (4 << 10), "4KB is VIPT limit")
```

这表示：

- 每 way 容量：`64 sets * 64 B = 4 KiB`
- 总容量：`4 KiB * 2 ways = 8 KiB`
- VIPT 约束检查的是单 way 的 index+offset 不超过 4 KiB 页内范围。

迁移文档里应避免写成“64 sets * 2 ways * 64B 但又受 4KB 限制”的模糊表述。

---

## 3. 顶层流水结构

`MyCPUCore.scala` 中的实际 stage：

```text
Fetch Pipeline:
  IF1 -> IF2

Decode Pipeline:
  ID -> RENAME -> DISPATCH

INT Pipeline x3:
  ISS -> RRD -> EXE -> WB

MulDiv Pipeline x1:
  ISS -> RRD -> EXE -> WB

Mem Pipeline x1:
  ISS -> RRD -> MEMADDR -> MEM1 -> MEM2 -> WB -> WB2

Global:
  PhysRegFile
  ROBFIFO
  Commit
  BypassNetwork
  IntIssueQueue
  MulDivIssueQueue
  MemIssueQueue
  SpeculativeWakeupHandler
  Timer64
  ExceptionHandler
  InterruptHandler
  CSR
  MMU
  WaitHandler
```

一个更接近源码的执行图：

```text
PC/BTB/BPU/RAS
   |
   v
IF1 -- ICache tag/data read cmd, BPU/BTB read
   |
   v
IF2 -- ICache hit/miss, prediction redirect, FetchBuffer push
   |
   v
FetchBuffer(4 push / 3 pop)
   |
   v
ID -- decoder array, exception tagging, uniqueRetire tagging
   |
   v
RENAME -- sRAT/aRAT/FreeList, ROB allocation
   |
   v
DISPATCH -- IntIQ/MulDivIQ/MemIQ enqueue, busy read
   |
   +--> INT IQ -> INT0/1/2 -> PRF/ROB/BPU update
   +--> MulDiv FIFO -> MulDiv pipe -> PRF/ROB complete
   +--> Mem FIFO -> Mem pipe -> DCache/StoreBuffer/PRF/ROB
   |
   v
ROB head commit <=3/cycle
   |
   +--> ArchRAT/FreeList update
   +--> StoreBuffer retired mark
   +--> CSR/TLB/cache op side effects
   +--> exception/mispredict/unique retire flush
```

---

## 4. 前端微架构

### 4.1 ProgramCounterPlugin

PC 由 `ProgramCounterPlugin.scala` 管理。

关键点：

- `regPC = RegNextWhen(nextPC, !IF1.stuck, init=pcInit)`。
- 默认下一 PC 不简单等于 `PC + fetchWidth * 4`，而是禁止跨 ICache line：

```text
pcOffset = regPC[2 + log2(lineWords) - 1 : 2]
defaultPC = regPC + min(fetchWidth, lineWords - pcOffset) * 4
```

也就是说 fetch packet 不跨 cache line，进一步也不跨页，减少 VIPT/MMU/异常复杂度。

PC 优先级：

1. backend jump/flush redirect，来自 commit/exception/branch resolve。
2. BPU/BTB/RAS predict target。
3. 默认顺序 PC。

源码里的 backend jump 通过 `backendJumpInterface` 进入 PC plugin，预测跳转通过 `setPredict()` 连接。

### 4.2 ICachePlugin

ICache 是 IF1/IF2 两级：

- IF1 发同步 RAM 读命令，读取 `infoRAM` 和每 way 的 data RAM。
- IF2 做 tag 比较、命中选择、LRU 更新、miss refill。

存储结构：

```text
valids[sets][ways]       Reg Bool
infoRAM[sets]            tag[ways] + lru
dataRAMs[ways][sets]     Vec(lineWords * 32-bit)
```

ICache 命中：

- `hits = valid && tag == physPC[tagRange]`
- `hitData = MuxOH(hits, dataRAMs read response)`
- IF2 形成 `FetchPacket`，每个 word 带 `valid` 和 `inst`。
- LRU：2 way 下命中 way0 时 `lru=1`，下次替换 way1；命中 way1 时反向。

ICache miss FSM：

```text
stateBoot
  -> waitAXI: 发 AXI AR, addr 对齐到 line
  -> readMem: 接收 lineWords 个 AXI R word，逐 word 写 data RAM
  -> commit: 写 tag/LRU/valid
  -> finish: doRefetch，重新从 IF1 取
```

对 superScalar 的启发：

- 如果不做 ICache，只做双端口 IROM，也要保留“fetch packet 不跨取指组”的 valid mask 思想。
- IF1/IF2 的 PC、prediction、instruction mask 必须同拍对齐，不能只把 ROM 数据拉出来。

### 4.3 FetchBufferPlugin

FetchBuffer 使用 `MultiPortFIFOVec`：

- push 端口数 = `fetchWidth=4`
- pop 端口数 = `decodeWidth=3`
- 深度 = 8

每个 entry：

```text
pc
inst
except
predInfo
predRecover
```

IF2 push 时：

- `fetchWordValid = fetchPacket.insts(i).valid && INSTRUCTION_MASK(i)`
- 第一条携带 fetch exception，后续指令 exception idle，减少 fanout。
- `pc = fetchPacket.pc + i * 4`
- 保存分支预测信息：
  - `predictBranch`
  - `predictTaken`
  - `predictAddr`
  - `recoverTop`
  - `predictCounter`
  - `ghr`

flush 直接清空 push/pop 指针。

### 4.4 GlobalPredictorBTBPlugin

NOP-Core 的方向预测器实际是全局相关预测器，不是 tournament predictor：

- `BPUConfig.useGlobal = true`
- `useLocal = false`
- `useHybrid = false`
- PHT 项数 8192。
- GHR 宽度 5。
- counter 2-bit 饱和。

PHT index 方式：

```text
pht_read_addr  = GHR @@ PC[phtPCRange]
pht_write_addr = recover_ghr @@ commit_pc[phtPCRange]
```

这更像“GHR 拼接 PC”的 correlated predictor，不是严格 XOR 形式的 GShare。之前文档如果写成 `PC XOR history`，作为迁移简化可以接受，但不应描述为 NOP 原版事实。

BTB：

- `sets=1024`
- `ways=1`
- lineSize=4B
- 用 `ReorderCacheRAM(BranchTableEntry, numEntries, fetchWidth, false)` 读出一个 fetch group 内最多 4 个 entry。
- `valid` 是独立 Reg Vec。
- entry 包含 tag、target[31:2]、isCall、isReturn。

预测流程：

1. IF1 根据 `nextPC` 发 BTB/PHT 读。
2. IF1/IF2 判断当前 fetch group 每个 way 是否 BTB hit。
3. 从高 way 到低 way 扫描，选中第一个预测 taken 的分支。
4. 若第 i 条预测 taken，`INSTRUCTION_MASK = (1 << (i+1)) - 1`，只允许分支之前和分支本身进入 FetchBuffer。
5. IF2 触发 `predictInterface.valid`，flushNext，让下一 fetch 从预测地址开始。
6. IF2 投机更新 GHR：

```text
branchCount = popcount(INSTRUCTION_MASK & BRANCH_MASK)
shiftedGHR = oldGHR << branchCount
newGHR = shiftedGHR | PREDICT_JUMP_FLAG
```

提交时更新：

- 如果原来预测是 branch 但实际不是：invalidate BTB entry。
- 如果原来不是 branch 但实际是：写 BTB，新建 PHT counter。
- 如果原来和实际都是 branch：更新 target/isCall/isRet 和 counter。
- 若 mispredict：恢复 GHR 到 `recover.ghr` 再拼入实际 taken。

### 4.5 ReturnAddressStackPlugin

RAS 深度 8，指针 `rasTopEntry`。

预测时：

- IF2 看到 BTB payload 标为 call：`rasTopEntry += 1`，写入 `PC + jumpWay + 1` 的 word 地址。
- IF2 看到 return：读 `ras(rasTopEntry)` 作为预测 target，`rasTopEntry -= 1`。

恢复时：

- 每条 FetchBuffer entry 保存 `recoverTop`。
- commit 更新时，如果发现非 branch 被预测成 branch，恢复 top。
- mispredict 时：
  - call：恢复 top 后重新 push 实际返回地址。
  - ret：恢复 top 后 pop。
  - 普通分支：恢复 top。

迁移时如果保留 RAS，必须也保留 recoverTop，否则 mispredict 后 RAS 会逐渐错位。

---

## 5. Decode 与 MicroOp

### 5.1 DecoderArray

DecoderArray 是 3 宽阵列，每个 lane 从 FetchBuffer pop 一个 `InstBufferEntry`。

流程：

1. 为所有 decode signal 设默认值。
2. `InstructionParser` 提取字段。
3. 对照 LoongArch encoding 表产生 `MicroOp`。
4. epilogue 做统一修正：
   - pc/inst 填入 uop。
   - predInfo/predRecover 填入 uop。
   - CSR 写读寄存器特殊处理。
   - timer 特殊 rd/rj 处理。
   - wbAddr 选择 rd/rj/ra。
   - illegal/syscall/break exception 标记。
   - privilege level 检查。
   - `branchLike`、`flushState`、`uniqueRetire` 标记。

### 5.2 MicroOp 字段

`DecodeMicroOP.scala` 中 `MicroOp` 包含：

```text
pc, inst
predInfo, predRecover
fuType
useRj/useRk/useRd
wbAddr/doRegWrite
immExtendType
aluOp
lsType/isLoad/isStore
cmpOp/isBranch/isJump/isJR/branchLike
writeCSR/readCSR
timer read flags
tlbOp/operateTLB
operateCache
isWait/isLL/isSC
uniqueRetire
signed
except
isErtn
flushState
```

`IntIQMicroOp`、`MulDivIQMicroOp`、`MemIQMicroOp`、`ROBMicroOp` 都是 `MicroOp` 的子集。NOP-Core 明确避免把完整 uop 到处传递，减少 fanout 和寄存器面积。

### 5.3 uniqueRetire 语义

`uniqueRetire` 不是“只提交自己”那么简单，它用于限制同拍 retire：

```text
uop.uniqueRetire =
  flushState
  || branchLike
  || isLoad
  || isStore
  || predInfo.predictBranch
```

`flushState` 又包括：

```text
isErtn
writeCSR
isWait
operateTLB
operateCache
barrier
LL/SC
```

Commit 里 uniqueMask 的实现表示：

- unique 指令要求在 retire port0。
- port0 后面的指令是否可同拍提交，还要受异常、mispredict、recoverMask、uncachedMask 共同限制。

迁移到 RISC-V 时，`ecall/ebreak/mret/fence/csr/branch/load/store` 的 retire 限制需要重新定义，不能只按 NOP 的 LA32R 字段照抄。

---

## 6. Rename、PRF 与恢复

### 6.1 RenamePlugin

NOP-Core 的 rename 在 `RENAME` stage 完成。

结构：

```text
sRAT[31]    speculative RAT，x1~x31
aRAT[31]    architectural RAT，x1~x31
freeList    多端口 FIFO，初始装入 p32~p62
```

注意：

- x0 固定映射到 p0，不进 RAT 表。
- 初始 x1~x31 映射 p1~p31。
- 总物理寄存器 63 个，空闲寄存器 31 个。

### 6.2 batch 内相关处理

每条指令生成：

- 两个读源：rj、rk/rd。
- 一个“读旧目的映射”端口，用于提交时释放旧 phys。
- 一个写端口，用于分配新 phys。

同 batch 内：

- older lane 写目的寄存器时，younger lane 读同架构寄存器会直接拿 older lane 新分配的 phys。
- WAW 由后 lane 覆盖前 lane 的 sRAT 写入。
- 写目的寄存器需要从 FreeList 连续 pop。

### 6.3 FreeList 恢复语义

提交时：

- `aRAT[arch] := newPhys`
- `freeList.push(oldPhys)`

flush/recover 时：

- `sRAT := aRAT`
- FreeList 执行 `pushPtr := popPtr`，把所有 speculative pop 视为回滚。

源码注释里强调：每条写指令 rename pop 一个新寄存器，commit push 一个旧寄存器；未提交部分的 pop 可以通过指针恢复全部撤销。

迁移 SV 时要保证：

- recover 周期不能同时进行 push/pop。
- FreeList pop payload 在 recover 后下一周期不应读到旧错误值。
- 异常/分支恢复时，BusyTable 也要恢复到与 aRAT/FreeList 一致的状态。

### 6.4 PhysRegFilePlugin

PRF 实现：

- `regs[nPhysRegs]`：寄存器数组。
- `busys[nPhysRegs]`：物理寄存器结果未就绪标志。
- rename pop free reg 时置 busy。
- 执行单元 clearBusy 时清 busy。
- 写回端口写 `regs(addr-1)`。
- 读 p0 返回 0，读其他寄存器返回 `regs(addr-1)`。

PRF 内部支持 write-to-read bypass：

- `writePort(bypass=true)` 的写端口可以前传给同周期读端口。
- `clearBusy` 也会前传给 `readBusy`，让正在 dispatch 的指令看到“即将 ready”。

### 6.5 BypassNetworkPlugin

BypassNetwork 是执行管线级旁路：

- 执行单元注册 writePort。
- 消费端按 phys addr 注册 readPort。
- 任一 writePort addr 命中时，readPort 输出 Flow(data)。

INT 执行在 RRD 级提前 clearBusy，EXE/WB 级通过 BypassNetwork 给下一条依赖指令数据。这个“提前唤醒 + 旁路取数”是性能关键，但也需要 miss/flush 失败恢复。

---

## 7. ROB 与提交

### 7.1 ROBFIFOPlugin

ROB 分成两类存储：

```text
robInfo: MultiPortFIFOSyncImpl
  - FIFO 顺序 push/pop
  - 保存提交不变信息 info

robState: Reg Vec
  - 随机写端口
  - 保存完成状态、异常、分支恢复、执行结果等动态状态
```

info 包含：

- `ROBMicroOp`
- rename record
- frontend exception flag

state 包含：

- `complete`
- `except`
- `mispredict`
- `actualTaken`
- `lsuUncached`
- `intResult`
- load/store/timer/csr/debug 信息
- `vAddr/pAddr/storeData`

写回端口：

- ALU port
- BRU port
- LSU port
- complete-only port for MDU

写回时还会检查写回 ROB idx 是否正好在当前 pop window 里，若是同步更新 pop payload，避免“同周期完成但 commit 看不到”。

### 7.2 CommitPlugin retire mask

提交宽度 3。提交资格由多个 mask 相与：

```text
readyMask = completeMask & excMask & uniqueMask & recoverMask & uncachedMask
```

含义：

- `completeMask`：从 port0 到当前 port 的所有指令 complete。
- `excMask`：左侧没有异常和 linear recover。
- `uniqueMask`：unique retire 约束，要求特殊指令在 port0。
- `recoverMask`：左侧没有 mispredict。
- `uncachedMask`：uncached load 需要特殊等待。

port0 是特殊端口：

- 处理中断/异常。
- 触发 needFlush。
- 触发 PRF recover。
- 触发 backend jump。
- 发 CSR/TLB/cache/StoreBuffer commit side effect。
- 发 BPU update。

### 7.3 flush/recover 分类

Commit 中的恢复分三类：

1. 异常/中断：跳 exception vector，保存 CSR。
2. branch mispredict：跳实际 target 或 `pc+4`。
3. linearRecover：指令本身不一定跳转，但改变架构状态或控制状态，需要 flush 后从 `pc+4` 继续。

`recoverPRF = regFlush`，也就是 flush 延后一拍用于 RAT/FreeList 恢复。迁移时要统一所有队列、ROB、FetchBuffer、StoreBuffer 对这个 flush/regFlush 的响应时序。

### 7.4 Store commit

Commit 对 store 不直接写 cache/内存，只发 `commitStore`。StoreBuffer 收到后把最早未 retired 的 store 标成 retired，由 memory pipe 后台执行 STD。

这是精确异常成立的关键：

- store execute 时只记录地址/数据。
- store commit 后才允许影响 cache/DRAM/MMIO。
- flush 只清除未 retired 的 StoreBuffer entry。

---

## 8. Issue Queue 与发射

### 8.1 IntIssueQueue

INT IQ 使用 `CompressedQueue`，不是 FIFO。

特点：

- depth=7。
- issueWidth=3。
- dispatch 最多接收 decodeWidth 条。
- 每个执行管线注册一个 grantPort。
- `genIssueSelect()` 对每个执行端口做 oldest-ready one-hot grant，并屏蔽已 grant slot。
- issue 后 queue 压缩。
- flush 直接清 valid。

每个 slot 保存：

```text
rRegs[2]  // Flow phys addr，valid 表示 ready
robIdx
uop
wReg
```

唤醒来源：

1. dispatch 入队时读 PRF busy。
2. global wakeup 监听 PRF clearBusy。
3. INT 本地 wakeup：ISS 选中后，如果写 reg，下周期可唤醒依赖 slot。

### 8.2 INT 执行管线

每条 INT pipe：

```text
ISS -> RRD -> EXE -> WB
```

pipe 分工由 config 决定：

- `bruIdx=0`
- `csrIdx=0`
- `timerIdx=1`
- `invTLBIdx=0`

也就是说：

- INT0：ALU + BRU + CSR + INVTLB
- INT1：ALU + Timer
- INT2：ALU

ISS：

- 扫描 IQ，计算该 pipe 可接受的 FU 类型。
- 与 ready 状态一起形成 issue request。
- 若无 grant，当前 pipe bubble/remove。
- 选中可写 reg 的 slot 时做本地唤醒。

RRD：

- 读 PRF。
- 对将写 reg 的指令提前 `clearBusy`。
- 若 `SpeculativeWakeupHandler.regWakeupFailed`，暂停 RRD。

EXE：

- ALU 计算。
- BRU 计算 actual target、actual taken、mispredict。
- CSR 读取当前 CSR 值，写 CSR 的新值先放 `ACTUAL_TARGET/intResult`，提交点才生效。
- Timer/INVTLB 也在这里形成结果。

WB：

- 写 PRF。
- 写 ROB state。
- BRU/CSR/INVTLB 走 `bruPort`，普通 ALU 走 `aluPort`。

### 8.3 MulDivIssueQueue 与 MulDivExecute

MulDiv IQ 使用 `CompressedFIFO`：

- depth=3。
- issueWidth=1。
- 只看 queue head。
- ready 后按 FIFO 发射，不做乱序 oldest-ready 扫描。

MulDiv pipe：

```text
ISS -> RRD -> EXE -> WB
```

乘法：

- 使用 `Multiplier` blackbox。
- NOP 原版 `multiplyLatency=2`。
- 通过 counter stall EXE，直到 latency 满足。
- 乘法提前一拍 clearBusy，用于唤醒后继。

除法：

- 使用 Spinal `math.UnsignedDivider`。
- 有 32-bit divider 和 16-bit divider。
- `divisionEarlyOutWidth=16` 时，如果被除数/除数高位均为 0，走 16-bit divider。
- signed DIV/MOD 在外部取绝对值，结果再二补码修正。

迁移 superScalar 时，DIV 已决定保留 Vivado `DIV_0` IP，因此这部分只参考“可变延迟 + valid 等待 + 特殊值处理”思想，不照搬 Spinal divider。

### 8.4 MemIssueQueue

Mem IQ 也使用 `CompressedFIFO`：

- depth=5。
- issueWidth=1。
- 只从 head 发射。

这意味着 NOP-Core 的 memory 发射是保守保序的，不是任意乱序 load/store 调度。好处：

- 降低 store-load 顺序和 StoreBuffer forwarding 复杂度。
- 更容易维持精确异常。
- 牺牲一部分内存级并行，但 FPGA timing 更可控。

---

## 9. Memory Pipeline、DCache 与 StoreBuffer

### 9.1 MemPipeline stage

实际 stage：

```text
ISS -> RRD -> MEMADDR -> MEM1 -> MEM2 -> WB -> WB2
```

`WB2` 注释说明：读 cache 需要预留两个周期冲突处理，所以增加一个空 WB stage 用于前传。

### 9.2 AddressGenerationPlugin

MEMADDR：

- 计算虚拟地址：`base + immField`。
- 根据 access type 产生 byte enable 和移位后的 store data。
- 检查 half/word misaligned，产生 ALE。
- 同时启动 directTranslate 和 tlbTranslate，并保存 CSR 翻译状态。

MEM1：

- 根据保存的 CSR 和 TLB/direct 结果完成最终 translate。
- 产生 physical address。
- 产生 cached bit。
- 产生 TLB/PIL/PIS/PPI/PME 等异常。

迁移到 superScalar 不做 MMU 时，可把 translate 简化为：

```text
physAddr = virtAddr
cached = addr in 0x8010_0000 ~ 0x8014_0000 and !uncached
```

但仍应保留 MEMADDR/MEM1 分级，否则 DCache tag/data 读和异常检查容易挤到一个长组合路径。

### 9.3 StoreBufferPlugin

StoreBuffer entry：

```text
retired
addr
be
data
isStore
isCached
wReg
lsType
robIdx
```

注意 NOP-Core 的 StoreBuffer 不只放 store，还扩展承载：

- cached store
- uncached store
- uncached load

原因：uncached load/store 需要提交点之后才能真正访问外部 udBus，保证精确异常和寄存器生命周期安全。

StoreBuffer 行为：

- MEM2 push 新 entry，`retired=false`。
- Commit 发 `commitStore`，将最早未 retired entry 标成 retired。
- MEM ISS 从 head pop retired entry 作为 STD/LDU/STU。
- flush 时清除未 retired entry，保留 retired entry。
- query 根据 word 地址匹配 cached store，byte enable 粒度前传，后面的 entry 覆盖前面的 entry。

### 9.4 MemExecutePlugin 调度

MEM ISS 同时考虑：

- Mem IQ head 的 load/STA/cache op。
- StoreBuffer head 的 retired STD/LDU/STU。

关键策略：

- StoreBuffer 接近满时停止发射新的 memory uop，避免死锁。
- retired STD 可以在没有新 memory uop 时发射；如果当前发射 store address，STD 也可以跟着发。
- load/STA 与 pipeline arbitration 绑定；STD 通过 `STD_SLOT` 随 pipeline 传播。

### 9.5 DCachePlugin 存储结构

DCache 是 2-way write-back/write-allocate：

```text
valids[sets][ways]             Reg Bool
dirtyBitsManager[sets][ways]   Reg Bits
infoRAM[sets]                  tags[ways] + lru
dataRAMs[ways]                 lineWords * sets 个 32-bit word
```

DCache 和 ICache 不同：

- ICache data RAM 每次读整行 Vec，方便 fetchWidth 取多 word。
- DCache data RAM 每次只读写一个 32-bit word，更省面积和延迟。

### 9.6 DCache MEMADDR/MEM1/MEM2

MEMADDR：

- 发 infoRAM 和 dataRAM 读命令。
- dataRAM 地址是 word address，即 index + word offset。

MEM1：

- 取 valid、dirty、infoRAM response。
- 计算 tag match。
- 传递 ROB_IDX、load/store 类型、write reg、读源 reg 等。

MEM2：

- 判断 load hit/miss。
- cached STD hit 时写 dataRAM、置 dirty。
- cached load hit 返回数据。
- cached load/store miss 触发 refill。
- uncached load/store 走 udBus。
- cache op 触发 invalidate/writeback。
- load 同时查询 pipeline 内 STD_SLOT 和 StoreBuffer 做 forwarding。

### 9.7 DCache miss/refill/writeback FSM

脏行写回 FSM：

```text
fetchCache -> waitAW -> writeMem -> waitB
```

用于：

- 正常替换脏行。
- uncached 访问命中 cached dirty line 时先写回并 invalidate。
- CACHE 指令要求 writeback/invalidate。

cached refill FSM：

```text
stateBoot
  -> waitAXI
  -> readMem
  -> commit
  -> finish
```

行为：

- miss 且 victim dirty 时先触发 writeback。
- AXI AR 对齐到 cache line。
- AXI R 按 word 写入 dataRAM。
- 如果当前 STD 正在 refill 同一 word，会用 STD 数据覆盖 refill word，实现 write-allocate store miss。
- commit 写 tag/LRU/valid/dirty。
- finish 触发 doRefetch，避免 MEM1 读不到刚写入的 cache 状态。

uncached load FSM：

```text
waitAXIU -> readMemU -> finishU
```

要求：

- 等 dirty writeback idle。
- 尽量不与 uncached store 重叠。
- 单 beat AXI read。

### 9.8 Load forwarding

MEM2 组装 `MEMORY_READ_DATA` 时按优先级覆盖：

1. cache hit/refill/storedWord 原始数据。
2. pipeline 内 STD_SLOT：同 word 地址，按 byte enable 覆盖。
3. StoreBuffer query：同 word 地址，按 byte enable 覆盖。
4. uncached load 强制使用 storedWord。

这保证 store 已经执行但尚未写入 cache 时，后续 load 能看到最新值。

### 9.9 SpeculativeWakeupHandler

NOP-Core 对 load 做推测唤醒：

- MEM1 中，如果 cached load 或 SC 等预计会产生写回，就提前 clearBusy。
- 依赖指令可提前 issue 到 RRD。
- 如果 MEM2 发现 pipeline stuck/miss 且该 load 的 WRITE_REG valid，设置 `wakeupFailed`。
- 下一拍 `regWakeupFailed` 会暂停其它执行管线的 RRD，避免依赖指令读到不存在的数据。

迁移建议：

- 第一版可以保守关闭 load speculative wakeup，等正确性稳定后再做。
- 如果做，必须同时实现 wakeup fail squash/重发机制；只做提前 clearBusy 会非常危险。

---

## 10. 分支执行与预测更新

BRU 在 INT0 EXE：

- 比较分支条件。
- 计算 actual target。
- 与 `predInfo.predictTaken/predictAddr` 比较，生成 mispredict。
- jump/link 的写回结果是 `pc + 4`。

Commit port0 更新 BPU：

- `predUpdate.valid := uop.branchLike || uop.predInfo.predictBranch`
- `isTaken := (mispredict ^ predictedTaken) || jump || jr`
- `isRet` 通过匹配 `jr ra` 指令编码。
- `isCall` 包含 BL 和链接到 RA 的 JIRL。
- `target := entry.state.intResult`

redirect target：

- jump/jr：actual target。
- branch：taken 时 target，不 taken 时 `pc+4`。
- linearRecover：`pc+4`。

因此 BPU 的训练在 commit 点完成，而不是 EXE 点立即训练。优点是和精确提交一致；缺点是训练稍晚。

---

## 11. CSR、异常、中断、MMU

### 11.1 ExceptionMuxPlugin

每条 pipeline 可注册异常源：

```text
stage
exception code/subcode
valid
badVAddr optional
priority
```

ExceptionMux 在各 stage 插入统一信号：

- `EXCEPTION_OCCURRED`
- `EXCEPTION_ECODE`
- `EXCEPTION_ESUBCODE`
- `BAD_VADDR`

优先级规则：

- 早期 stage 已有异常时，后续 stage 不覆盖。
- 同 stage 多个异常按 priority 选择。

### 11.2 ExceptionHandlerPlugin

负责 LA32R 特权 CSR：

- CRMD/PRMD/ECFG/ESTAT/ERA/BADV/EENTRY/SAVE0-3/LLBCTL 等。

异常提交时：

- 通过 PC backend jump 跳到 `EENTRY` 或 TLB refill entry。
- 更新 ESTAT_ECODE/ESUBCODE。
- 必要时更新 BADV、TLBEHI。
- 保存 PLV/IE 到 PRMD。
- CRMD 进入 kernel、关中断。
- ERA 保存异常 PC。

ERTN：

- 跳 ERA。
- 恢复 CRMD_PLV/IE。
- 清 LLBit 相关状态。

### 11.3 InterruptHandlerPlugin

实现：

- timer CSR：TCFG/TVAL/TICLR/TID。
- 外部中断输入 `intrpt[7:0]` 写入 ESTAT_IS_2。
- timer interrupt 写 ESTAT_IS_11。
- `intPending` 条件：

```text
(ECFG.LIE & ESTAT.IS).orR
  && CRMD_IE
  && !LLBCTL_LLBIT
```

Commit port0 把 pending interrupt 当作 exception 处理。

### 11.4 CSRPlugin

CSRPlugin 是通用 CSR 映射器：

- `r/rw/w/r0/w1/wAny` 注册 CSR 字段。
- read 是组合 mux。
- write 在 commit 点由 `CSRWrite` 触发。

迁移 RISC-V 时可保留这种“CSR 字段注册 + commit 写入”的组织思想，但 CSR 地址、字段、副作用要全部换成 RISC-V M-mode。

### 11.5 MMUPlugin

NOP-Core 支持：

- direct address mode：`CRMD_DA=1 && CRMD_PG=0`，物理地址=虚拟地址。
- DMW direct mapped window：DMW0/DMW1。
- TLB page translation：16 entries。
- TLB ops：TLBSRCH/TLBRD/TLBWR/TLBFILL/INVTLB。
- TLB exception：TLBR/PIF/PIL/PIS/PPI/PME。

迁移到 superScalar 当前目标时：

- 不做 TLB/MMU。
- 保留 “fetch/mem 地址检查 + cacheable 判定” 的接口位置。
- CSR 中不需要 DMW/TLB 系列寄存器。

---

## 12. AXI 与外部总线

NOP-Core 对外三路 AXI：

| 总线 | 来源 | 用途 |
|---|---|---|
| `iBus` | ICachePlugin | instruction cache refill |
| `dBus` | DCachePlugin | cached data refill + dirty writeback |
| `udBus` | UncachedAccessPlugin | uncached load/store |

所有总线 32-bit data、32-bit address、idWidth=4。

superScalar 当前 SoC 不支持这组三 AXI 边界，因此迁移时不能照搬 AXI：

- ICache 已决策不做。
- DCache refill/writeback 要转换为单 DMEM req/resp。
- uncached/MMIO 也走同一个 DMEM 地址译码。
- 当前桥不支持多个 outstanding，不支持乱序返回。

---

## 13. NOP-Core 中值得迁移的设计点

### 13.1 应保留的核心思想

1. `FetchBuffer` 解耦前端和 decode。
2. 每条指令保存预测恢复元数据。
3. sRAT/aRAT/FreeList 双表重命名。
4. ROB info/state 分离。
5. StoreBuffer 在 commit 后才写内存。
6. INT IQ 可乱序 oldest-ready 发射。
7. Mem/MulDiv FIFO 保守发射，降低复杂度。
8. DCache write-back + write-allocate。
9. CSR/异常在 commit 点生效。
10. BPU/RAS 需要 commit 恢复/更新，不只预测。

### 13.2 迁移时应裁剪或改写的部分

| 原版机制 | superScalar 处理 |
|---|---|
| LA32R decode | 全部改为 RV32I/M/MI |
| ICache + AXI iBus | 不做 ICache，改双端口 IROM |
| AXI dBus/udBus | 适配单 DMEM req/resp |
| TLB/MMU/DMW | 不做虚实转换 |
| LA32R CSR | 改 RISC-V M-mode CSR |
| 3 宽 decode/rename/commit | 先做 2 宽 |
| MUL latency 2 | superScalar 当前保持 MUL_0 三拍 |
| Spinal `UnsignedDivider` | 保留 Vivado `DIV_0` IP |
| CACOP/PRELD/LL/SC | 当前 RISC-V 目标不需要 |
| load speculative wakeup | 第一版建议保守化，后续再打开 |

---

## 14. 对 superScalar 文档和实现计划的影响

基于这次源码阅读，plan 目录的其它文档应同步采用以下修正：

1. NOP 原版 BPU 是 global correlating predictor + BTB + RAS，不是 local/global tournament。
2. 如果 superScalar 目标要做“全局与局部竞争历史预测器”，这是新增设计，不是 NOP 原样迁移。
3. NOP 原版 INT IQ 是可乱序压缩队列，Mem/MulDiv 是 FIFO；superScalar 第一版也应如此，利于可综合和保序访存。
4. NOP 原版 DCache 物理 data RAM 按 word 存，不是每次读整行；这对 FPGA 时序和资源更友好。
5. StoreBuffer 承载 uncached load/store 的做法值得借鉴，但 superScalar 的单 DMEM 边界需要重新定义状态机。
6. load speculative wakeup 不应放入第一版最小可用目标，除非同步实现失败恢复。
7. `uniqueRetire/flushState` 是精确异常和状态类指令的关键，不应只写“ROB 顺序提交”。

---

## 15. 仍需确认的问题

这些问题不是 NOP 原版问题，而是迁移到 superScalar 时的实现选择：

1. BPU 资源口径：你要求“全局与局部竞争历史预测器 + GShare 5bit + 512 项 PHT”。这里的 512 项是总预算，还是 global/local/choice 各 512 项？
2. DCache line size：在当前单 DMEM req/resp、无 burst 的 SoC 下，是否接受第一版用 16B line，后续再升到 32B/64B？NOP 原版是 64B line，但它有 AXI burst。
3. load speculative wakeup：第一版是否按保守设计关闭？我建议关闭，先跑通 OoO 正确性，再打开优化。
4. IROM 双端口形式：Vivado IP 是否可以直接生成 true dual-port ROM，还是需要两个同内容 ROM 复制来实现 2 read ports？如果板上 BRAM 资源允许，复制 ROM 会更简单稳定。

