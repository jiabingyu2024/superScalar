# rtl/core 当前详细设计文档

> 本文基于当前仓库 `rtl/core` 源码整理，只描述当前实现事实和维护约束，不代表 RTL 已经通过仿真。后续修 bug 时，应同步更新本文。

## 1. 总体定位

`rtl/core` 实现一个固定 2-way 的 RV32 超标量、乱序执行、顺序提交 CPU 裸核，并通过 `myCPU.sv` 适配赛事要求的 IROM/DRAM/peripheral 扁平接口。

顶层关系：

```text
myCPU
  -> core
       -> PF/IF/ID/RN/DS/IS/RR/EX/WB/CM
       -> SpecRAT/ArchRAT/FreeList/ReadyTable
       -> ROB/IssueQueue/Payload/StoreBuffer
       -> RecoveryManager/Ctrl
```

主仿真 DUT 约定为 `myCPU`。`core` 适合内部结构阅读和未来模块级测试，`student_top` 只作为 SoC 集成 smoke。

## 2. 全局参数

| 参数 | 当前值 | 影响 |
| --- | --- | --- |
| `WAY_NUM` | 2 | 每周期最多取指、译码、rename、dispatch、issue、commit 2 条。 |
| `PC_STEP` | `WAY_NUM * 4 = 8` | 顺序取指 PC 步进。 |
| `LOGICREG_NUM` | 32 | RV32 架构寄存器数。 |
| `PHYREG_NUM` | 64 | 物理寄存器数，支持寄存器重命名。 |
| `ROB_DEPTH` | 16 | 乱序窗口提交边界。 |
| `ISSUE_QUEUE_DEPTH` | 16 | 调度窗口大小。 |
| `STORE_BUFFER_DEPTH` | 8 | 投机 store 暂存深度。 |
| `CHECKPOINT_NUM` | 8 | 分支/serial checkpoint 数量。 |
| `MUL_LATENCY` | 3 | 乘法流水固定 3 拍。 |
| `DIV_LATENCY` | 36 | 除法/取余流水固定 36 拍。 |

## 3. 文件分层

| 文件/目录 | 职责 |
| --- | --- |
| `BasicTypes.sv` | 全局基础宽度、PC/寄存器/ROB/checkpoint 索引、执行管线类型、子操作类型。 |
| `PipelineTypes.sv` | 各流水级之间传递的 payload，不拥有队列/恢复协议。 |
| `CtrlIF.sv` / `Ctrl.sv` | 全流水 stall/flush 生成。 |
| `PreFetchStage/` | PC、BPU、BTB、BHB、PF->IF 取指地址生成。 |
| `FetchStage/` | 保存 PF payload，并和 IROM 地址寄存后一拍的组合读指令绑定。 |
| `DecodeStage/` | RV32I/M/CSR 译码、立即数生成、2-way 包拆分。 |
| `RenameStage/` | 逻辑寄存器到物理寄存器映射、FreeList 分配、Ready 查询、checkpoint 创建。 |
| `DispatchStage/` | 分配 ROB/IQ/Payload/StoreBuffer 资源。 |
| `IssueStage/` | 从 IssueQueue 选择 ready uop，结合 Payload 发射到 RR。 |
| `ReadRegStage/` | 读物理寄存器堆，并按执行管线拆分。 |
| `ExecuteStage/` | ALU/MEM/MUL/BRC/SYS 五类执行。 |
| `WriteBackStage/` | 汇总执行结果，写 PRF、唤醒 IQ、标记 ROB done、提供 WB-only bypass。 |
| `CommitStage/` | ROB head 顺序退休，更新 ArchRAT/FreeList，处理 branch miss、异常和 store commit。 |
| `RecoveryManager` | 统一恢复请求、PC redirect、checkpoint 恢复、BPU 更新信息打一拍输出。 |
| `myCPU.sv` | 将 `core` 的 interface 适配为赛事 CPU 扁平端口。 |

## 4. 主流水

当前数据路径：

```text
PF -> IF -> ID -> RN -> DS -> IS -> RR -> EX -> WB -> CM
```

按阶段展开：

```text
PF: PC + BPU 选择取指地址，向 IROM 发出 iromAddr/ena
IF: 保存 PF 传来的 PC/预测信息，并绑定 IROM 地址寄存后一拍返回的指令
ID: 并行译码 2 条指令，必要时拆包 replay
RN: SpecRAT 查询/更新，FreeList 分配新目的物理寄存器，ReadyTable 查询源 ready
DS: 同时写 ROB、IssueQueue、Payload，store 额外分配 StoreBuffer entry
IS: 从 IssueQueue 选 ready uop，并读取 Payload
RR: 读物理寄存器堆，按 tubeType 分发到 ALU/MEM/MUL/BRC/SYS
EX: 各执行单元计算结果，MEM 访问 StoreBuffer/DRAM，BRC 计算真实跳转
WB: 写物理寄存器、ReadyTable、IssueQueue wakeup、ROB done，提供 bypass
CM: ROB head 顺序退休，更新 ArchRAT/FreeList，提交 store 或发起恢复
```

## 5. 顶层接口

### 5.1 `core`

| 接口 | 方向 | 语义 |
| --- | --- | --- |
| `clk/rst` | input | core 单时钟单复位。 |
| `IromAccessIF.core` | output/input | 前端取指通道，输出 `ena/iromAddr`，输入 `inst[2]`。 |
| `DramAccessIF` | output/input | MEM load 和 StoreBuffer commit store 共享的数据访问通道。 |
| `DebugIF.core` | input | 当前只有 `halt`，顶层固定为 0，RTL 内尚未实际使用。 |
| `PerfIF.core` | output | `cycle/commitCnt/branchCnt/branchMissCnt`。 |

### 5.2 `myCPU`

| 端口 | 语义 |
| --- | --- |
| `irom_addrA/irom_addrB` | 分别为 `iromAccess.iromAddr` 和 `+4`。 |
| `irom_dataA/irom_dataB` | 回填 `iromAccess.inst[0/1]`。 |
| `irom_enaA/irom_enaB` | 同一个 `iromAccess.ena`。 |
| `perip_addr/perip_wen/perip_mask/perip_wdata` | 将 `DramAccessIF` 扁平化到赛事 perip 总线。 |
| `perip_rdata` | 直接作为 `dromAccess.readData`。 |

维护注意：`myCPU` 当前将 `dromAccess.accessReady` 固定为 `1'b1`，语义是访问命令被接收，不代表 load 数据同拍有效。仿真 memory model 必须和 RTL 的 load 元信息延迟对齐，否则容易掩盖 load 时序 bug。

### 5.3 Reset 约束

当前 reset 不是完全统一风格，但已有可维护的层级语义：

| 层级 | reset 信号 | 语义 |
| --- | --- | --- |
| `top` | `pll.locked` | PLL 锁定后为 1，作为外设低有效 reset 的释放条件。 |
| `student_top` / CPU 域 | `w_clk_rst = ~locked` | 高有效 reset，连接到 `myCPU.cpu_rst`、`perip_bridge.rst`、`counter.rst`。 |
| `uart/twin_controller` | `rst_n = locked` | 低有效 reset，运行在 50MHz 外设域。 |
| `core` 内部 | `rst` | 高有效 reset；多数队列/状态是异步 reset，少量前端流水寄存器是同步 reset。 |
| `RegFile` | `posedge rst` + `negedge clk` 写 | PRF 负沿写是当前 WB/RR 时序假设的一部分。 |

后续新增 core 模块默认采用高有效 `rst`。若要统一成同步释放或同步 reset，应作为单独上板稳定性任务处理，不和功能 debug 混在一起。

## 6. 控制流与优先级

`Ctrl.sv` 根据各级 stall 请求和恢复事件生成每级 `PipeCtrlPath`。

### 6.1 普通 stall

| 阻塞源 | 影响 |
| --- | --- |
| `idStallReq/rnStallReq/dsStallReq` | 阻塞前端和 rename/dispatch 相关阶段。 |
| `robFull/issueQueueFull/freeListEmpty` | 阻塞前端，防止继续注入后端。 |
| `serialBlock` | 阻塞前端和 rename，使 serial/system 指令等待安全边界。 |
| `isStallReq/rrStallReq/exStallReq/wbStallReq` | 阻塞后端相关流水段，并反压前端。 |

### 6.2 恢复优先级

当 `recovery.recoveryInfo.valid` 为 1：

1. 根据 `frontendFlush/backendFlush` 拉各级 flush。
2. 所有 stage stall 被清零。
3. PreFetch 使用 `recovery.pcUpdate` 重定向 PC。
4. RecoveryManager 驱动 SpecRAT/FreeList checkpoint 恢复。

设计意图：flush 覆盖 stall，防止错误路径因为 stall 被“保留”。

## 7. 前端与分支预测

### 7.1 PC/PF

`PC.sv` 复位 PC 为 `0x8000_0000`。`PreFetchStage` 的 PC 来源优先级：

```text
Recovery redirect > BPU taken target > pcOut + PC_STEP
```

PF 每周期最多产生 2 个 `PfToIfPath`。如果 lane0 预测 taken，则 lane1 valid 被压掉，避免同包 taken 后面的顺序指令进入流水。

### 7.2 BPU/BTB/BHB

| 结构 | 当前实现 |
| --- | --- |
| BTB | 32 entry，直接索引，保存 tag 和 target。 |
| BHB | local/global 两套 2-bit PHT + chooser，global history 6 位，local history 4 位。 |
| 更新来源 | CommitStage 对已退休分支发 `commitBranchUpdate*`，RecoveryManager 打一拍给 BPU。 |

维护注意：预测器只在提交后更新，因此恢复路径正确性优先于预测器性能调优。

## 8. Decode 拆包规则

`DecodeStage` 并行译码 2 条指令，但会在以下情况拆包：

| 情况 | 行为 |
| --- | --- |
| 同包多条 branch | 只送 lane0，lane1 存入 `replaySlot`。 |
| 同包多条 store | 只送 lane0，lane1 replay。 |
| serial 指令和其他指令同包 | 只送 lane0，lane1 replay。 |

拆包原因：

1. 当前 checkpoint 创建一次只能服务一个 branch/serial。
2. StoreBuffer 分配接口当前每周期只分配一个 store entry。
3. serial/system 指令需要更严格的顺序边界。

## 9. Rename 与投机状态

### 9.1 SpecRAT/ArchRAT

| 结构 | 作用 |
| --- | --- |
| `SpecRAT` | rename 使用的投机逻辑寄存器到物理寄存器映射。 |
| `ArchRAT` | commit 使用的架构态映射，只在有序退休时更新。 |

`SpecRAT` 支持随机 checkpoint 恢复。创建 checkpoint 时，会保存到当前 branch lane 为止的 rename 更新结果。

### 9.2 FreeList

FreeList 用 `freeMask` 管理可用物理寄存器：

```text
reset: p0-p31 被占用，p32-p63 可分配
rename: 为写目的寄存器分配新物理寄存器
commit: 释放旧目的物理寄存器 phyPrevRegNum
recovery: 恢复 checkpoint mask，并可额外释放恢复相关物理寄存器
```

### 9.3 组内相关处理

Rename 对同包前序 lane 做检查：

| 相关 | 处理 |
| --- | --- |
| RAW | 后序 lane 源寄存器命中前序 lane 目的寄存器时，源物理寄存器改为前序 lane 新分配的物理寄存器。 |
| WAW | 后序 lane 目的逻辑寄存器命中前序 lane 目的寄存器时，`oldDst` 改为前序 lane 新分配物理寄存器。 |
| ready | 如果源来自同包前序 lane，则源默认 not ready，等待前序结果 wakeup。 |

### 9.4 Serial 处理

Rename 发现 serial 指令时，要求 `ds/is/rr/ex/wb` 均 empty 才允许继续 rename。否则拉 `rnStallReq`。Commit 处如果 ROB head 是未完成 serial，也会拉 `serialBlock`。

维护注意：serial 机制当前依赖各级 `*StageEmpty` 信号准确，否则 CSR/ECALL/MRET/FENCE 类路径容易乱序。

## 10. Dispatch、ROB、IssueQueue 和 Payload

### 10.1 Dispatch

Dispatch 只有在以下资源都满足时才 fire：

```text
ROB 空间 >= packet valid 数
IssueQueue 空间 >= packet valid 数
如果有 store，则 StoreBuffer allocRdy
每个 lane 的 ROB/IQ push 响应有效
```

成功 dispatch 后：

```text
ROB entry: 保存提交、分支、store、checkpoint、异常相关信息
IssueQueue entry: 保存调度选择/源 ready/目的寄存器/延迟预测信息
Payload entry: 保存 PC、预测信息、立即数、CSR、操作类型、StoreBuffer index
```

### 10.2 ROB

ROB 是 16-entry 环形队列：

```text
Dispatch 按程序序 push
WriteBack 通过 robIndex 回填 done/exception/branch actual
Commit 只能从 head 连续 pop
```

分支 miss 判断在 ROB done 回填时完成：

```text
isBranch &&
(
  takenPred != takenActual ||
  (takenActual && predPc != trueTargetPc)
)
```

### 10.3 IssueQueue

IssueQueue 保存轻量调度信息。选择策略：

1. entry valid 且未 issued。
2. 源 A ready，源 B ready 或源 B 是立即数/none。
3. 同周期已选 uop 不能和候选形成 RAW。
4. 每周期最多选择一个 MEM uop。
5. 在可选项中选 ROB 顺序更老的 entry。

唤醒来源：

```text
WriteBackStage -> IssueWakeup[WAY_NUM * 5]
```

另外，IssueQueue 会在发射时根据生产者 delay 设置 `srcAShift/srcBShift`，但当前 ready 实际主要由 WB wakeup 拉高。

### 10.4 Payload

Payload 使用和 IssueQueue 相同的 `payloadIndex`。IssueQueue 只保存调度所需字段，Payload 保存较大的执行静态字段，Issue 发射时两者重新合并为 `IsToRrPath`。

## 11. StoreBuffer 与内存顺序

StoreBuffer 深度 8，承担三件事：

1. Dispatch 为 store 分配 entry。
2. ExecuteMem 计算 store 地址、raw store data 和 raw byte mask 后写入 entry。
3. Commit 只允许 ROB head store 提交；StoreBuffer 负责把 head store 写到 DRAM。

Load 查询 StoreBuffer：

| 查询结果 | 行为 |
| --- | --- |
| 完全命中所需字节 | 直接转发数据到 WB。 |
| 部分字节冲突 | `block=1`，MEM 拉 `exStallReq` 等待。 |
| 无冲突 | 发起 DRAM read。 |

维护注意：

1. store 对外提交时不在 core 内按 `addr[1:0]` 左移，统一交给 `dram_driver` 或 TB memory model 对齐。
2. StoreBuffer 内部 forwarding 仍需按 entry 地址临时对齐 `data/wstrb`，再按 load 地址右移成外部 DRAM 返回格式，保证 store-to-load forwarding 和外部 load 返回语义一致。
3. store 每周期分配限制已经由 Decode/Dispatch 配合保证。

## 12. ReadReg、Bypass 和 PRF

`RegFile` 是 64-entry 物理寄存器堆：

```text
ReadRegStage: 组合读
WriteBackStage: 多写端口写回
RegFile 写时钟: negedge clk
```

Bypass 是 WB-only：

```text
ExecuteAlu/Mem/Mul/Brc/Sys 在执行前查询 BypassIF
Bypass 只匹配 WriteBackStage 当前周期的 wbForward
没有 EX-to-EX 前递
```

设计取舍：

1. PRF 负沿写 + 组合读可以缓解同周期 WB/RR 读写冲突。
2. WB-only bypass 简化网络，但要求 IssueQueue 的 wakeup/ready 时序和执行延迟估计足够保守。

## 13. 执行单元

| 单元 | 功能 | 关键行为 |
| --- | --- | --- |
| ALU | ADD/SUB/SHIFT/LOGIC/SLT | 组合计算，一拍输出 WB payload。 |
| BRC | branch/JAL/JALR | 计算 taken、真实 target，JAL/JALR 写回 `pc+4`。 |
| MEM | load/store | store 写 StoreBuffer；load 优先查 StoreBuffer，再发 DRAM read；一次只选一个 load。 |
| MUL | RV32M mul/div/rem | MUL 3 拍，DIV/REM 36 拍，处理除零和有符号溢出。 |
| SYS | CSR/ECALL/EBREAK/MRET/FENCE 类 serial | 维护项目 CSR 子集 `mstatus/mtvec/mepc/mcause`；ECALL/EBREAK 进入 `mtvec`，MRET 返回 `mepc`；FENCE/FENCE.I 在无 cache 设计中按 serial NOP。 |

### 13.1 IROM 取指时序

IROM 行为模型是 BRAM 风格的一拍地址寄存、寄存地址组合读：

```text
T0 posedge 前: PF/PC 给出 iromAddr 和 ena
T0 posedge:    IROM_0 寄存 addra/addrb，FetchStage 寄存 PF payload
T0 posedge 后: dout = mem[addr_q]，FetchStage 组合绑定 pipeReg PC + inst
```

因此 `FetchStage` 不是任意 ROM 延迟自适应模块，它假设 IROM 返回和 PF payload 在上述时序下对齐。TB 必须复刻这个模型。

### 13.2 MEM load 时序

`ExecuteMemStage` 用两级 metadata 管线对齐 DRAM 返回：

```text
T0: dram.exReadEn && exReadReady，记录 loadIssueMeta -> loadMetaPipe0
T1: loadMetaPipe0 -> loadMetaPipe1
T2: loadMetaPipe1.valid 时，使用 dram.exReadData 生成 WB 结果
```

如果 `loadMetaPipe1.valid` 且当前 MEM pipe 又有新有效 uop，则 `loadReturnBlocked` 拉高，阻塞 EX，避免 load 返回和新 MEM 输入抢同一输出口。

### 13.3 CSR/FENCE 支持边界

当前 CSR 白名单：

```text
mstatus 0x300
mtvec   0x305
mepc    0x341
mcause  0x342
```

非白名单 CSR 读 0、写忽略，不承诺 `mcycle/minstret/Zicntr`。FENCE/FENCE.I 由于当前无 cache，作为 serial NOP 使用。EBREAK 当前按 breakpoint trap 处理，写 `mepc=pc`、`mcause=3`，并跳转到 `mtvec`。

## 14. WriteBack

WriteBack 每个 lane 汇总 5 类执行单元，因此总端口数为：

```text
BYPASS_WB_PORT_NUM = WAY_NUM * 5 = 10
```

每个有效结果会同时：

1. 写 ROB done。
2. 如果写目的寄存器，写 PRF。
3. 提供 bypass。
4. `ReadyTable.markReady`。
5. `IssueQueue.IssueWakeup`。

当前 `writeBackRecoveryReq` 被清零，实际恢复主要由 CommitStage 发起。

## 15. Commit 与精确恢复

Commit 从 ROB head 开始按程序序最多查看 2 条。重要规则：

| ROB entry 类型 | 行为 |
| --- | --- |
| 未 done | 停止提交；如果是 serial，拉 `serialBlock`。 |
| 普通写寄存器 | pop ROB，更新 ArchRAT，释放旧物理寄存器。 |
| branch | 更新 BPU；如果命中预测则 pop 并释放 checkpoint；如果 miss 则发 recovery 并停止。 |
| store | 等 StoreBuffer head 对应 entry 写出成功后再 pop。 |
| exception | 发 recovery，flush ROB/StoreBuffer，并停止。 |

### 15.1 Branch miss recovery

Commit 发起：

```text
cause = REC_BRANCH_MISS
recoverPc = entry.truePc
chkptRecoverEn = entry.chkptValid
recoverFreeEn = entry.DstValid
recoverFreePhyRegNum = entry.phyPrevRegNum
frontendFlush = 1
backendFlush = 1
ROB flush = 1
StoreBuffer flush = 1
```

### 15.2 Exception recovery

Commit 发起：

```text
cause = REC_EXCEPTION
recoverPc = entry.truePc
recoverFreePhyRegNum = entry.phyRegNum
frontendFlush = 1
backendFlush = 1
ROB flush = 1
StoreBuffer flush = 1
```

维护注意：branch miss 和 exception 对 `recoverFreePhyRegNum` 的选择不同，后续 debug FreeList 泄漏/重复释放时要重点检查。

## 16. RecoveryManager

RecoveryManager 有两个状态：

```text
RM_IDLE -> 等待 commit/writeback recovery
RM_EMIT -> 保持打一拍后的 recoveryInfo，直到无新请求
```

仲裁优先级：

```text
commitRecoveryReq > writeBackRecoveryReq
```

输出：

1. `recoveryInfo` 给 Ctrl 生成 flush。
2. `pcUpdateEn/pcUpdate` 给 PreFetch 重定向 PC。
3. checkpoint recover 给 SpecRAT/FreeList。
4. commit branch update 打一拍给 BPU。

## 17. 性能计数

`core.sv` 内部维护：

| 计数器 | 语义 |
| --- | --- |
| `perf.cycle` | reset 后每周期加 1。 |
| `perf.commitCnt` | 每周期累加 `cmStageIF.commitValid` 数量。 |
| `perf.branchCnt` | `commitBranchUpdateValid` 时加 1。 |
| `perf.branchMissCnt` | `commitBranchMiss` 时加 1。 |

注意：`PerfIF` 没有从 `myCPU` 端口引出。后续若 testbench 需要读这些计数，应通过层级访问或 Verilator public 机制，默认不改 `myCPU.sv` 端口。

## 18. 当前维护风险与自检点

以下是阅读 RTL 后应重点验证的风险，不代表已经确认是 bug：

1. IROM 固定为地址寄存后一拍组合读；仿真模型若改成零延迟或两拍同步读，PC 和 inst 会错位。
2. `myCPU` 固定 `dromAccess.accessReady=1`，DRAM load 数据固定两拍返回；仿真模型必须和 `ExecuteMemStage` 的 metadata 延迟一致。
3. `DecodeStage` 拆包只保存 `decodedStage[1]`，需要确认 lane0 serial/branch/store 情况下 lane1 replay 是否覆盖所有组合场景。
4. `RenameStage` 同包 WAW 时 `oldDst` 指向前序 lane 新物理寄存器，这对提交释放链条很敏感，需要用同周期双写同一逻辑寄存器测试验证。
5. `ReadyTable.recoverReadyAll` 在 backend flush 时把所有物理寄存器置 ready，这简单但可能掩盖恢复后未完成生产者问题，需要结合 ROB/FreeList 恢复语义验证。
6. `IssueQueue` 的 delay/shift 机制和 WB wakeup 同时存在，实际 ready 是否过早或过晚，需要用 load-use、mul-use、div-use 测试验证。
7. `RegFile` 负沿写是重要时序假设，Verilator 和 FPGA 综合行为都要确认符合预期。
8. `ExecuteMemStage` 一次只允许一个 load，且 load 返回会阻塞当前 MEM uop；性能优化前先保证正确性。
9. `StoreBuffer` 对 load forwarding 的多 entry 字节合并要验证 store-load、partial byte、同 word 多 store 场景。
10. `CommitStage` 对 branch 和 exception 的 checkpoint/free 恢复路径不同，是后续精确异常和分支恢复 debug 的重点。
11. `RecoveryManager` 将恢复事件打一拍，Ctrl flush 也因此打一拍；调试 branch miss 时要按这个时序看波形。
12. `WriteBackStage` 当前不发起实际 recovery，`writeBackRecoveryReq` 保留但清零；如果未来要做早恢复，需要重新定义优先级和精确状态边界。

## 19. 推荐 debug 顺序

在完整 Verilator harness 可用后，建议按以下顺序验证：

1. 取指/顺序执行：`rv32ui-p-simple`、`addi/add/sub/logic`。
2. PRF/rename/commit：连续写同一寄存器、同包 RAW/WAW。
3. 分支：`beq/bne/blt/jal/jalr`，重点看 ROB `isMiss` 和 RecoveryManager。
4. Load/store：`lw/sw/lb/lh/sb/sh`，重点看 StoreBuffer 和 load metadata。
5. M 扩展：`mul/div/rem`，重点看 long latency wakeup。
6. CSR/system：`csr/ecall/ebreak/mret/fence`，重点看 serialBlock、trap redirect 和异常恢复。
7. src smoke：接入用户提供的 src pass/fail 逻辑后再看性能。
