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

仿真 DUT 按目标分流：rv32 正确性测试使用 `myCPU`，src 类测试使用 `student_top`。`core` 适合内部结构阅读和未来模块级测试。

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
| `MUL_LATENCY` | 2 | 乘法 IP/行为模型/metadata 均为 2 级；当前全 core 只例化一颗 `MUL_0`。 |
| `DIV_LATENCY` | 16 | Divider Generator manual latency 和行为模型为 16；RTL 以 `m_axis_dout_tvalid` 判完成。 |

## 3. 文件分层

| 文件/目录 | 职责 |
| --- | --- |
| `BasicTypes.sv` | 全局基础宽度、PC/预测元信息、寄存器/ROB/checkpoint 索引、执行管线类型、子操作类型。所有其他 `Types.sv` 的最底层依赖。 |
| `DecodeStage/DecodeTypes.sv` | 指令 opcode/funct 常量、译码函数、`InstInfoPath` 和 `LgcRegInfoPath`。这些是 decode 语义输出，不放在 `PipelineTypes`。 |
| `PipelineTypes.sv` | 各流水级之间传递的 payload，不拥有队列/恢复协议；当前 export `DecodeTypes/ROBTypes/StoreBufferTypes/RecoveryTypes` 以兼容已有模块。 |
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

### 3.1 `Types.sv` 编译依赖

Vivado 对 SystemVerilog package 的可见性比 Verilator 更严格，当前维护规则是：package 文件只在 package 作用域内 import 依赖，不依赖文件作用域 import 传播。

推荐依赖拓扑：

```text
BasicTypes
  -> DecodeTypes
  -> StoreBufferTypes
  -> ROBTypes
  -> RecoveryTypes
  -> PipelineTypes
  -> RenameTypes / ReadRegTypes / IssueTypes
```

边界约定：

1. `BasicTypes` 只放全局基础概念，例如 `PcPath`、`PredInfoPath`、`RobIndexPath`、`TubeTypePath`。
2. `DecodeTypes` 拥有 decode 输出控制结构：`InstInfoPath`、`LgcRegInfoPath`。
3. `PipelineTypes` 只定义级间 payload，例如 `IfToIdPath`、`IdToRnPath`、`RnToDsPath`、`IsToRrPath`。
4. `IssueTypes` 不能 import `PipelineTypes`；Payload 需要的预测信息从 `BasicTypes::PredInfoPath` 获取。
5. `ReadRegTypes` 不能 import `PipelineTypes`；bypass 写回记录需要的 ROB index 从 `BasicTypes::RobIndexPath` 获取。
6. `ROBTypes/StoreBufferTypes/RecoveryTypes` 只描述各自资源/恢复协议，不反向依赖级间流水 payload。

`scripts/filelists/core.f` 和 `fpga/create_vivado_project.tcl` 必须保持上述顺序，否则 Vivado 可能报 `xxx is not declared`。

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
| `PerfIF.core` | output | `cycle/commitCnt/branchCnt/branchMissCnt`，以及 `conditional/JAL/JALR` 分类计数。 |

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
| BTB | 256 entry，直接索引，12-bit tag，保存 target。 |
| BHB | local/global 两套 2-bit PHT + chooser，global history 8 位，local history 4 位。 |
| 更新来源 | CommitStage 对已退休分支发 `commitBranchUpdate*`，RecoveryManager 打一拍给 BPU。 |

预测命中 BTB 后，若 BHB 判断 taken，或 BTB target 小于当前 PC（后向分支启发式），则预测 taken；同包内只允许第一条 taken 指令生效，后续 lane 被压掉。

维护注意：预测器只在提交后更新，因此恢复路径正确性优先于预测器性能调优。后向分支启发式是 src 循环性能优化，不应改变 miss recovery 的精确性。

当前没有 return address stack。`JALR` 统一走普通 BTB/BHB 预测，因此函数返回类间接跳转在多调用点、helper 嵌套或历史冲突下容易 miss；这会直接触发 frontend/backend flush。

### 7.3 Branch miss 恢复代价

当前 branch miss 不是“前端 redirect 一下就结束”，而是 commit-based 精确恢复：

```text
BRC 执行算出 taken/target
  -> WB 回填 ROB done/isMiss
  -> 分支到达 ROB head 后 CommitStage 判断 miss
  -> RecoveryManager 下一拍 emit recoveryInfo
  -> Ctrl 对 PF/IF/ID 和 RN/DS/IS/RR/EX/WB 全部 flush
  -> PreFetch 重定向 IROM
  -> 新路径重新经过 IF/ID/RN/DS/IS/RR/EX/WB/CM
```

关键 RTL 后果：

1. `request_branch_recovery()` 设置 `frontendFlush=1` 和 `backendFlush=1`，并清 ROB/StoreBuffer 投机状态；一次 miss 会把后端窗口全部打空。
2. `RecoveryManager` 把恢复请求打一拍，因此 commit 发现 miss 后下一拍才对 Ctrl 生效。
3. `CommitStage` 对 branch miss 仍会停止并发起恢复；但 lane0 branch 若预测正确，且 lane1 是已 done 的普通非 serial、非 store、非 branch、非 exception、无 checkpoint 指令，则允许 lane1 同周期提交。
4. BPU/BTB/BHB 只在 commit 后更新，紧密循环和 helper 内数据相关分支会用较晚的历史信息训练。

因此当前 miss penalty 至少是 10 拍量级，且如果 ROB 中已经有较多错误路径 uop，还会额外损失窗口填充和后端重新热身时间。

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
IntIssueQueue/MemIssueQueue/MulIssueQueue 对应空间 >= packet 中对应类型 valid 数
如果有 store，则 StoreBuffer allocRdy
每个 valid lane 的 ROB push 响应有效
```

成功 dispatch 后：

```text
ROB entry: 保存提交、分支、store、checkpoint、异常相关信息
IssueQueue entry: 保存调度选择/源 ready/目的寄存器/延迟预测信息
Payload entry: 保存 PC、预测信息、立即数、CSR、操作类型、StoreBuffer index
```

维护注意：IQ push 的容量准入只看各队列 `FreeCount`。`IssuePushRes.done/payloadIndex` 是 dispatch 已经 fire 后给 Payload 和队列写入使用的分配结果，不能反过来参与 `dispatchEn/resourceReady` 的前置判断；否则 `dispatchEn` 等 `IssuePushRes.done`、`IssuePushReq.valid` 又等 `dispatchEn`，会形成 0 dispatch 的死锁。

### 10.2 ROB

ROB 是 32-entry 环形队列：

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

### 10.3 分布式 IssueQueue

后端 issue 宽度与前端 `WAY_NUM=2` 解耦。Dispatch 仍每周期最多写入 2 条 uop，但 IssueStage 可从已经缓存的队列中最多发射 5 条：

| 队列 | 接收类型 | 深度 | 发射宽度 | 顺序策略 |
| --- | --- | ---: | ---: | --- |
| `IntIssueQueue` | ALU / BRC / SYS | 16 | 3 | ready entry 中按全局 `age` 选更老项，允许乱序。 |
| `MemIssueQueue` | MEM load/store | 4 | 1 | FIFO head ready 才能发射，严格 in-order。 |
| `MulIssueQueue` | MUL / DIV / REM | 4 | 1 | FIFO head ready 才能发射，严格 in-order。 |

`IssueQueue` 顶层 wrapper 负责三件事：

1. Dispatch push 按 `tubeType` 路由到对应队列，并返回该队列分配出的 `payloadIndex`。
2. 从三个队列收集候选：Int 最多 3 个，Mem/Mul 各 1 个。
3. 对最多 5 个候选按全局 `age` 从老到新授权，并禁止同周期 RAW；被 RAW 阻塞的候选不会 pop，下一周期可重新参与选择。

全局 `age` 由 `IssueQueue` wrapper 在 dispatch 接收时分配，跨三个队列可比较。不能用 ROB 的 1-bit `position + robIndex` 直接比较年龄，因为 ROB 环形指针多次 wrap 后会出现 `rob15,pos1` 比 `rob0,pos0` 更老但被误判为更年轻的情况。这个年龄只用于 issue 仲裁，ROB 仍按原 `robIndex` 回填 done。

唤醒来源：

```text
WriteBackStage -> IssueWakeup[WB_PORT_NUM]
```

三个队列都会在发射生产者时检查等待同一物理目的寄存器的消费者。当前只对 `delay == 1` 的生产者，以及已校准为 4 个调度间隔的非 DIV/REM MUL 生产者启用保守预计唤醒：

```text
producer issue，delay=1
  -> consumer.srcMatched=1，srcShift=1
下一拍 IssueQueue 将 srcRdy 置 1
  -> consumer 可被选择发射
  -> 到达 EX 时依赖值应已能通过 WB bypass 或 negedge 写回后的 RegFile 读取得到
```

MEM load 和 DIV/REM 仍等待 `WriteBackStage` 的真实 `IssueWakeup`。这是因为 MEM load 可能经过 result buffer 多等 1 拍，DIV/REM 的长延迟 IP 相位也需要单独校准，直接全类型提前 ready 容易过早发射。

### 10.4 Payload

Payload 使用和分布式 IssueQueue 相同的全局 `payloadIndex`。索引空间按队列静态切分：

| 范围 | 所属队列 |
| --- | --- |
| `0..15` | IntIssueQueue |
| `16..19` | MemIssueQueue |
| `20..23` | MulIssueQueue |

IssueQueue 只保存调度所需字段，Payload 保存较大的执行静态字段，Issue 发射时两者重新合并为 `IsToRrPath`。Payload 写口仍是 Dispatch 的 2 路，读口扩展为 Issue 的 5 路。

IssueStage 的真实发射条件是：

```text
issueFire = !isPipe.stall && !isPipe.flush && {Int/Mem/Mul}IssuePopRes.done
```

只有 `issueFire` 为 1 时才允许：

1. 对应队列的 `IssuePopReq.valid=1`，让该队列删除该 entry。
2. `PayloadPopReq.valid=1`，让 Payload 删除同 `payloadIndex` entry。
3. `nextStage.valid=1`，把合并后的 uop 送入 ReadReg。

维护注意：Payload pop 必须和 IssueQueue pop 同步。若在 `isPipe.stall=1` 时只 pop Payload，会导致下一拍 IssueQueue 再发射同 entry 时 payload 已经丢失，ROB entry 永远无法 done。

## 11. StoreBuffer 与内存顺序

StoreBuffer 深度 8，承担四件事：

1. store 的地址源 ready 后，MEM IQ 允许它先进入 registered request queue。
2. Execute 建立带 `rob_idx/addr/mask/data_prd` 的有序 shell；data 未 ready 时继续按 PRD 监听 completion bus。
3. data 到达后，StoreBuffer 从寄存状态单独完成对应 ROB store entry，不把 CAM 组合回 Commit ready。
4. Commit 只允许已完成的 ROB head store 退休；StoreBuffer 再按序把 retired head 写到 DRAM。

Load 查询 StoreBuffer：

| 查询结果 | 行为 |
| --- | --- |
| 所需字节全部由 data-ready store 覆盖 | 直接转发数据到 WB。 |
| 有重叠字节但覆盖不完整，或最新同字节 store 的 data 尚未到达 | registered MEM request 原地等待，不读取 DCache 旧值。 |
| 同 word 但 byte mask 不重叠，或完全无 alias | cacheable load 可发起 DCache read。 |

维护注意：

1. store 对外提交时不在 core 内按 `addr[1:0]` 左移，统一交给 `dram_driver` 或 TB memory model 对齐。
2. StoreBuffer 内部 forwarding 仍需按 entry 地址临时对齐 `data/wstrb`，再按 load 地址右移成外部 DRAM 返回格式，保证 store-to-load forwarding 和外部 load 返回语义一致。
3. data-pending store 只阻塞与其 byte mask 真正重叠的 load；不能把同 word 的非重叠 byte 误当 barrier。
4. 多个同址 store 按老到年轻扫描；较年轻 pending store 必须撤销同 byte 上更老 store 已贡献的 forwarding mask，否则会转发旧值。
5. MEM IQ 不允许 load 越过 store/fence/device；因此 StoreBuffer 中可见的 store 对当前 load 都是 older owner。

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
| ALU | ADD/SUB/SHIFT/LOGIC/SLT | IntIssueQueue 最多发射 3 条，ReadRegStage pack 到 3 条 ALU lane，一拍输出 WB payload。 |
| BRC | branch/JAL/JALR | IntIssueQueue 最多发射 3 条，计算 taken、真实 target，JAL/JALR 写回 `pc+4`。 |
| MEM | load/store | MemIssueQueue 是 4 项严格 FIFO，每周期最多发射 1 条；MEM->WB 保留 2 个完成口，用于 load return 与当前 store/forward-hit load 同周期完成。 |
| MUL | RV32M mul/div/rem | MulIssueQueue 每周期最多发射 1 条；MUL 使用单实例 `MUL_0`，33x33 signed、DSP 构造、2 级；DIV/REM 使用单实例 `DIV_0`，unsigned 32/32、manual latency 16，外围处理 signed、除零和有符号溢出。 |
| SYS | CSR/ECALL/EBREAK/MRET/FENCE 类 serial | IntIssueQueue 可承载 SYS，但 Rename/Commit 的 serial 排干规则仍保证 CSR/ECALL/MRET/FENCE 类路径不乱序。 |

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

若 load 对 StoreBuffer 有部分字节命中，T0 同时把命中字节保存到 `loadIssueMeta.forwardData/forwardMask`。T2 用 `forwardMask` 覆盖 `dram.exReadData` 中对应字节，再执行 load subtype 的符号/零扩展。该路径用于处理同 word 的 `SB/SH` 后跟 `LW/LH/LB`，同时保持 core 对外仍输出 raw store data/mask。

当前采用 1-entry load return result buffer。MEM->WB 有 2 个完成口：旧 buffer 优先输出，当前 store/forward-hit load 可占另一个空口，DRAM 返回 load 若没有空口则进入 buffer；只有 buffer 满且新 load return 仍无法输出时才拉 `loadReturnBlocked`。这样避免旧实现中“load 返回 + 任意当前 MEM uop = 全 EX stall”的 0.5 IPC 节奏，同时保持 MemIssueQueue 本身每周期只发射 1 条。

### 13.3 M 扩展执行单元与 MUL_0/DIV_0 IP

当前 M 扩展路径的边界：

```text
CoreMulDivIssueQueue
  -> ready head 每周期最多发射 1 条 TUBE_TYPE_MUL
CoreExecuteCluster
  -> PRF/bypass 读出两个源操作数
CoreMulDivPipe
  -> 非 div/rem 送入单颗 MUL_0，并用 2-entry metadata valid 对齐 owner
  -> DIV/REM 只在 mul pipe 空时送入单颗 DIV_0
  -> normal DIV 等 m_axis_dout_tvalid，special DIV 走本地一拍路径
  -> flush 中止可见 owner；已启动 divider 的迟到 valid 由 div_drain_q 吸收
```

`MUL_0` 是 FPGA 侧 Vivado `mult_gen` IP 的仿真/综合同名边界。

| 项 | 当前约定 |
| --- | --- |
| 实例数 | 1 |
| 端口 | `CLK/A[32:0]/B[32:0]/P[65:0]` |
| 有符号性 | `A/B/P` 均按 signed 处理 |
| 宽度 | 33x33 -> 66 bit |
| 延迟 | 2 个 clk pipeline stage；Tcl 显式 `Use_Mults + Speed` |
| reset/CE | 无 reset、无 clock enable；flush 只清 metadata，旧 product 被 valid 丢弃 |

33 位操作数用于统一覆盖 `MULH/MULHSU/MULHU`：

1. `MULHU` 的 `A/B` 都补 0。
2. `MULHSU` 的 `A` 符号扩展，`B` 补 0。
3. `MULH` 的 `A/B` 都符号扩展。
4. `MUL` 只取低 32 位，符号扩展或零扩展不影响低 32 位结果。

`DIV_0` 是 FPGA 侧 Vivado `div_gen` IP 的仿真/综合同名边界：

| 项 | 当前约定 |
| --- | --- |
| 实例数 | 1 |
| 接口 | AXI4-Stream 风格：`s_axis_dividend_*`、`s_axis_divisor_*`、`m_axis_dout_*` |
| 操作数 | unsigned 32 bit dividend / unsigned 32 bit divisor |
| 输出 | `m_axis_dout_tdata[63:32] = quotient`，`[31:0] = remainder` |
| 延迟 | manual latency 16；完成仍由 `m_axis_dout_tvalid` 决定 |
| 吞吐 | 目标配置为每周期可接收一个输入，当前 core 仍只给单 M lane 输入 |

Vivado Tcl 将 `DIV_0` 配成 `FlowControl=Blocking`，输出侧没有 `m_axis_dout_tready`。`CoreMulDivPipe` 不假定 output valid 必在固定拍到达，而是保持唯一 active owner，直到 `m_axis_dout_tvalid=1` 才写回。

RISC-V signed 语义不交给 `DIV_0`：

1. `DIV/REM` 在进入 IP 前对操作数取绝对值。
2. `DIVU/REMU` 直接使用原操作数。
3. `divisor == 0` 和 `0x80000000 / -1` 溢出走 `MD_SPECIAL`，不启动 divider。
4. `div_valid` 到达时根据 active metadata 对 quotient/remainder 做符号恢复，再选择 `DIV/DIVU` 的商或 `REM/REMU` 的余数。

当前只放一颗 M 类 IP 入口，所以 `MulIssueQueue` 本身是单发 FIFO，保证同周期最多一条 `TUBE_TYPE_MUL` 进入 `ExecuteMulStage`。若误把 MulIssueQueue 扩成多发而不增加 IP 和写回仲裁，第二条 M 类 uop 会被单 IP 选择逻辑丢弃，最终 ROB 等不到对应 done。

后续若要提高 M 扩展吞吐，应先明确是增加第二套 `MUL_0/DIV_0`，还是拆分 MUL/DIV issue 类型和写回端口仲裁。

### 13.4 CSR/FENCE 支持边界

当前 CSR 白名单：

```text
mstatus 0x300
mtvec   0x305
mscratch 0x340
mepc    0x341
mcause  0x342
```

`mscratch` 是普通可读写 scratch CSR，用于通过 `rv32mi-p-csr` 中 CSRRW/CSRRS/CSRRC 及立即数变体的读旧值、写新值检查。`mstatus` 当前只保存 `MIE/MPIE` 两个已用 bit，`mtvec` 写入时低两位清零。

非白名单 CSR 读 0、写忽略，不承诺完整 privileged 架构；当前 `misa` 读 0，因此不会声明未实现的 U/S/F 等能力。`rv32mi-p-zicntr` 当前通过的前提是 counter CSR 写忽略、读 0 的测试约束，不表示已经实现真实 `cycle/instret` 计数器。FENCE/FENCE.I 由于当前无 cache，作为 serial NOP 使用。EBREAK 当前按 breakpoint trap 处理，写 `mepc=pc`、`mcause=3`，并跳转到 `mtvec`。

## 14. WriteBack

WriteBack 按实际完成端口汇总执行单元，因此总端口数为：

```text
BYPASS_WB_PORT_NUM = WB_PORT_NUM = 12
  = 3 ALU + 2 MEM + 1 MUL + 3 BRC + 3 SYS
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
| branch | 更新 BPU；如果 miss 则发 recovery 并停止；如果 lane0 预测正确，则 pop 并释放 checkpoint，且可继续提交安全的 lane1 普通指令。lane1 branch 仍不同周期提交，避免双 BPU update/双 checkpoint free。 |
| store | 等 StoreBuffer head 对应 entry 写出成功后再 pop；如果 lane0 store commit ready，且 lane1 是安全普通指令，则允许 lane1 同周期提交。lane1 store/branch/exception/serial 仍保守停止。 |
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
| `perf.condBranchCnt/condBranchMissCnt` | 条件分支提交数和 miss 数。 |
| `perf.jalCnt/jalMissCnt` | `JAL` 提交数和 miss 数。 |
| `perf.jalrCnt/jalrMissCnt` | `JALR` 提交数和 miss 数。 |
| `perf.*StallCycles` | 各流水级 `PipeCtrlPath.stall` 的周期计数，`frontendStallCycles` 使用 PF stall。 |
| `perf.robFullCycles` | `ctrlIF.robFull` 为 1 的周期数。 |
| `perf.issueQueueFullCycles` | `ctrlIF.issueQueueFull` 为 1 的周期数。 |
| `perf.freeListEmptyCycles` | `ctrlIF.freeListEmpty` 为 1 的周期数。 |
| `perf.storeBufferFullCycles` | Dispatch 因 store 需要分配但 `StoreBuffer.allocRdy=0` 相关的阻塞周期数。 |
| `perf.serialBlockCycles` | Commit/Rename 因 serial/system 指令顺序化产生的阻塞周期数。 |
| `perf.memLoadReturnBlockCycles` | `ExecuteMemStage` 因 load 返回和当前 MEM pipe 冲突拉起的阻塞周期数。 |
| `perf.memLoadAccessBlockCycles` | load 发起被 StoreBuffer/DRAM access ready 阻塞的周期数。 |
| `perf.storeCommitBlockedByLoadCycles` | StoreBuffer head store 已请求提交但同周期 DRAM 被 load 读优先占用的周期数。 |
| `perf.recoveryCycles` | `RecoveryManager` 发出恢复事件的周期数。 |
| `perf.dispatch/issue/commitWidth*Cycles` | 每周期 dispatch/issue/commit 宽度为 0/1/2 的分布。 |

这些计数通过 `VERILATOR_TB` 条件编译从 `myCPU/student_top` debug 口引出，不改变 FPGA 正式端口。stall/resource 计数不是互斥分类，同一周期可能同时命中多个桶；它们用于定位低 IPC 的主要现象，而不是直接相加还原总周期。

`srcSmoke` 当前实测 IPC 约 `0.422`，不是 TB wall-clock 口径，而是 `commitCnt / cycles`。分类计数显示：

| 类型 | count | miss_count | miss_rate |
| --- | --- | --- | --- |
| conditional | 12055013 | 3117626 | 0.258617 |
| JAL | 400076 | 80 | 0.000199962 |
| JALR | 400067 | 200064 | 0.500076 |

已定位的主要瓶颈：

1. `srcSmoke` 性能循环里每轮调用软件除法/取模 helper，dump 中 `0x800004dc/0x800004f4` 调到 `0x800013ac/0x80001328`，再进入 `0x80001330` 的移位减法循环。该 helper 内有大量数据相关条件分支，造成约 311 万次条件分支 miss。
2. 当前无 RAS，`JALR` 返回靠普通 BTB 预测，`srcSmoke` 中约 40 万次 `JALR` 有约 20 万次 miss。
3. CommitStage 对 branch miss 发 `REC_BRANCH_MISS`，frontend/backend 都 flush；正确预测 lane0 branch 现在可与 lane1 安全普通指令同周期提交，但 miss 恢复仍会显著压低二路提交利用率。

因此当前低 IPC 是 workload 和微架构共同造成的真实问题，不是结果 JSON 或 TB 统计错误。当前已完成保守 commit 宽度优化：lane0 正确预测 branch 或 commit-ready store 后，可继续提交 lane1 安全普通指令。后续更大的优化优先级仍是让有 M 扩展的 src profile 使用硬件 DIV/REM，或增加 RAS/改善条件分支预测。

### 17.1 为什么二发乱序没有 IPC > 1

`srcSmoke` 不是能自然喂满二发后端的顺序算术程序。当前动态特征：

```text
commit_count  = 30,758,700
cycles        = 72,814,875
IPC           = 0.422
branch_count  = 12,855,156
branch ratio  = 41.8% of committed instructions
branch miss   = 3,317,770
```

和顺序单发 `IPC=0.75` 比较，同样指令数理论周期约：

```text
30,758,700 / 0.75 = 41,011,600 cycles
```

当前多出的周期约：

```text
72,814,875 - 41,011,600 = 31,803,275 cycles
```

除以 branch miss 数：

```text
31,803,275 / 3,317,770 ~= 9.6 cycles / miss
```

这个反推值和当前 RTL 的 commit-based 全后端 flush 代价同量级，说明 branch miss 已足以解释“为什么比单发顺序还慢”。二发乱序的理论宽度被以下结构性因素压住：

| 因素 | 当前 RTL 行为 | 对 IPC 的影响 |
| --- | --- | --- |
| Branch miss 全后端恢复 | `REC_BRANCH_MISS` 同时 flush frontend/backend，并清 ROB/StoreBuffer | 每次 miss 都丢掉窗口内投机工作，前端重新填管。 |
| Commit 保守停止 | miss branch、exception、未完成 head 仍停止；lane0 正确 branch/store 已允许跟随 lane1 安全普通提交 | 高 branch/store 密度下仍受限，但正确路径退休宽度比旧实现更高。 |
| Decode 拆包 | 同包多 branch、多 store、serial+其他都会拆成 replay | branch 密集代码前端实际注入宽度低于 2。 |
| Rename checkpoint 限制 | branch/serial 需要 checkpoint，`chkptCount > 1` stall | 分支密集 packet 难持续双发。 |
| Issue MEM 保序单发 | MemIssueQueue 是 4 项 FIFO，head ready 才能发射，且每周期最多 1 条 | 访存片段不能利用多 MEM 发射，但选择逻辑更短、更容易保序。 |
| ExecuteMem load 返回合并 | load 返回占 MEM WB lane0；同周期单个当前 MEM uop 可占 lane1 | 避免 load-heavy 程序形成“返回一拍、发射一拍”的 0.5 IPC 节奏；两个当前 MEM uop 与返回 load 同时争用时仍保守 stall。 |
| 无 RAS | `JALR` return 走普通 BTB/BHB | return miss 约 50%，造成额外恢复。 |
| 软件除法 helper | `srcSmoke` 中 `0x80001330` 有大量数据相关条件分支 | 条件分支 miss 是最大来源。 |

结论：二发乱序只有在前端持续供给、预测稳定、窗口不频繁 flush、后端资源不退化单发时才可能 IPC > 1。当前 workload 和 RTL 都不满足这些条件。

### 17.2 分支命中率提升的理论上限

用当前实测数据做估算：

```text
branch_count = 12,855,156
current miss = 3,317,770  // hit rate ~= 74.19%
```

若总命中率提升到 90%，miss 数变为：

```text
12,855,156 * 10% ~= 1,285,516
```

减少 miss：

```text
3,317,770 - 1,285,516 ~= 2,032,254
```

按每次 miss 节省 10~12 cycle 估算：

| 假设 miss penalty | 90% hit 后 cycles | 估算 IPC |
| --- | --- | --- |
| 8 cycles | 56.56M | 0.544 |
| 10 cycles | 52.49M | 0.586 |
| 12 cycles | 48.43M | 0.635 |
| 15 cycles | 42.33M | 0.727 |

所以只把总分支命中率拉到 90%，大概率不能让 IPC 到 1。原因是：

1. 90% 命中率仍有约 128.6 万次 miss。
2. 即使 miss 完全消除，当前 commit/dispatch/MEM/Decode 的保守规则仍会限制宽度。
3. 当前条件分支占比极高，预测命中率提升会明显变快，但不等于二发持续满发。

若按 10~12 cycle/miss 的现实区间，90% 命中率后 IPC 约 `0.58~0.64`；按更乐观的 15 cycle/miss，约 `0.73`。要仅靠分支预测把 IPC 推到 1，必须接近 99% 命中率，或者当前每次 miss 的真实平均损失超过 20 cycle，这与现有反推不太一致。

更现实的优化路线：

1. 先跑 `srcWithMext`，确认是否用硬件 DIV/REM 消掉软件除法 helper。若动态条件分支大幅下降，IPC 会比单纯改 BPU 更明显。
2. 增加 RAS，目标是把 `JALR` return miss 从约 50% 降到接近 0，能节省约 200k 次恢复。
3. 给 BPU 增加 per-PC miss 统计，先定位 `0x80001330` helper 中哪些条件分支最差，再决定扩大 PHT/历史长度还是做 loop/biased predictor。
4. 优化 miss recovery：研究是否可在 branch execute/WB 早恢复，而不是等 commit；但这会改变精确恢复边界，风险高于加 RAS。
5. 继续优化 commit：当前只放开 lane1 安全普通指令；若要进一步允许 lane1 branch/store，需要补双 BPU update、双 checkpoint free 或 store commit 仲裁。

## 18. 当前维护风险与自检点

以下是阅读 RTL 后应重点验证的风险，不代表已经确认是 bug：

1. IROM 固定为地址寄存后一拍组合读；仿真模型若改成零延迟或两拍同步读，PC 和 inst 会错位。
2. `myCPU` 固定 `dromAccess.accessReady=1`，DRAM load 数据固定两拍返回；仿真模型必须和 `ExecuteMemStage` 的 metadata 延迟一致。
3. `DecodeStage` 拆包只保存 `decodedStage[1]`，需要确认 lane0 serial/branch/store 情况下 lane1 replay 是否覆盖所有组合场景。
4. `RenameStage` 同包 WAW 时 `oldDst` 指向前序 lane 新物理寄存器，这对提交释放链条很敏感，需要用同周期双写同一逻辑寄存器测试验证。
5. `ReadyTable.recoverReadyAll` 在 backend flush 时把所有物理寄存器置 ready，这简单但可能掩盖恢复后未完成生产者问题，需要结合 ROB/FreeList 恢复语义验证。
6. `IssueQueue` 的 delay/shift 机制和 WB wakeup 同时存在，实际 ready 是否过早或过晚，需要用 load-use、mul-use、div-use 测试验证。
7. `DispatchStage` 的 IQ 容量判断必须保持为 per-queue `FreeCount` 前置检查，不能把 `IssuePushRes.done` 接回 `resourceReady`，否则空队列也可能因 push valid 尚未拉高而永久不 dispatch。
8. `RegFile` 负沿写是重要时序假设，Verilator 和 FPGA 综合行为都要确认符合预期。
9. `ExecuteMemStage` 一次只允许一个 load，且 load 返回会阻塞当前 MEM uop；性能优化前先保证正确性。
10. `StoreBuffer` 对 load forwarding 的多 entry 字节合并要验证 store-load、partial byte、同 word 多 store 场景；特别是 `SH` 后紧跟 `LW` 时，不能因为部分命中把 MEM 永久 stall。
11. `CommitStage` 对 branch 和 exception 的 checkpoint/free 恢复路径不同，是后续精确异常和分支恢复 debug 的重点。
12. `RecoveryManager` 将恢复事件打一拍，Ctrl flush 也因此打一拍；调试 branch miss 时要按这个时序看波形。
13. `WriteBackStage` 当前不发起实际 recovery，`writeBackRecoveryReq` 保留但清零；如果未来要做早恢复，需要重新定义优先级和精确状态边界。

## 19. 推荐 debug 顺序

在完整 Verilator harness 可用后，建议按以下顺序验证：

1. 取指/顺序执行：`rv32ui-p-simple`、`addi/add/sub/logic`。
2. PRF/rename/commit：连续写同一寄存器、同包 RAW/WAW。
3. 分支：`beq/bne/blt/jal/jalr`，重点看 ROB `isMiss` 和 RecoveryManager。
4. Load/store：`lw/sw/lb/lh/sb/sh`，重点看 StoreBuffer 和 load metadata。
5. M 扩展：`mul/div/rem`，重点看 long latency wakeup。
6. CSR/system：`csr/ecall/ebreak/mret/fence`，重点看 serialBlock、trap redirect 和异常恢复。
7. src profile：优先跑带明确 pass/fail marker 的小量 profile；若只看到内部 test counter 完成但 marker 未闭合，应把 checker/软件结束条件和 RTL 功能结果分开记录。
