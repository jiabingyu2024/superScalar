# NOP-Core 与当前 superScalar 微架构及具体时序深度对比

> 日期：2026-07-10  
> 对比对象：`NOP-Core/src` 与当前 `superScalar/rtl/core`  
> 目标：找出迁移后已经一致、仅结构相似、以及仍需仿照 NOP-Core 优化的部分  
> 边界：不建议、也不规划实现 I-cache；只讨论双口同步 IROM 条件下仍有价值的前端契约  
> 方法：源码静态审查。本文没有用仿真结果代替源码结论，也没有进行编译、仿真、lint 或 CDC。

## 1. 模块定位

`NOP-Core` 与当前 `superScalar` 都是“寄存器重命名 + 分布式 IQ + ROB 顺序提交”的乱序超标量核，不是简单五级流水。当前 `superScalar` 的规模已经调整到与 NOP-Core 接近：ROB 都是 32 项，MEM IQ 都是 5 项，StoreBuffer 都是 8 项。

两者最大的差异不再是“有没有 OoO 结构”，而是**流水寄存切分和控制 contract**：NOP-Core 明确划分 ID/RENAME/DISPATCH、ISS/RRD/EXE/WB；当前 superScalar 的 decode/rename/dispatch 基本在同一组合周期，INT 的 IQ select/PRF read/bypass/ALU/branch resolve 也基本在同一组合周期。

因此，当前迁移的正确方向不是继续添加大结构，而是把 NOP-Core 已验证的阶段边界、flush 保留规则、load 推测失败处理、以及 unique-retire 规则迁移成清晰的 SV contract。

主要联动源码：

| 设计 | 文件 | 职责 |
|---|---|---|
| superScalar | `rtl/core/CoreConfigPkg.sv` | 宽度、ROB/IQ/PRF/Buffer 容量 |
| superScalar | `rtl/core/core.sv` | PC、IROM、FetchBuffer、BPU、backend 顶层连接 |
| superScalar | `rtl/core/backend/CoreBackend.sv` | rename/ROB/IQ/execute/store/commit 总连接和 serial 控制 |
| superScalar | `rtl/core/rename/{RenameUnit,FreeList,BusyTable}.sv` | RAT、物理寄存器分配和 ready 状态 |
| superScalar | `rtl/core/issue/CompressedQueue.sv` | INT oldest-ready 选择、唤醒和压缩 |
| superScalar | `rtl/core/execute/{ExecuteCluster,MulDivPipe,StoreBuffer}.sv` | PRF、执行、LSU、MDU 和 store 提交隔离 |
| superScalar | `rtl/core/dispatch/ROB.sv` | 分配、乱序完成、顺序退休 |
| superScalar | `rtl/core/commit/CommitUnit.sv` | ARAT/free、CSR、异常、mret、branch recovery |
| NOP-Core | `src/MyCPUConfig.scala`、`src/pipeline/core/MyCPUCore.scala` | 参数和全核 stage 图 |
| NOP-Core | `src/builder/Stage.scala`、`Pipeline.scala` | 统一 valid/stall/remove/flush contract |
| NOP-Core | `src/pipeline/decode/RenamePlugin.scala` | 3-wide rename、sRAT/aRAT/free list |
| NOP-Core | `src/pipeline/core/{ROBFIFOPlugin,CommitPlugin,PhysRegFilePlugin}.scala` | ROB、提交恢复、PRF/busy |
| NOP-Core | `src/pipeline/{exe,mem}/*IssueQueuePlugin.scala` | 分布式 IQ 和发射策略 |
| NOP-Core | `src/pipeline/mem/{MemExecutePlugin,StoreBufferPlugin}.scala` | LSU、推测唤醒、store buffer |

### 总结性判断

| 结论 | 当前状态 |
|---|---|
| OoO 基础语义 | 基本一致：rename、ROB、PRF、busy、IQ、顺序 commit 已闭环 |
| 资源规模 | 已趋于一致，superScalar 不再是旧文档中的 ROB128/IQ48 版本 |
| 前后端宽度 | NOP 为 4 fetch/3 decode/3 retire；superScalar 为 2/2/2 |
| stage 时序 | 明显不一致，是当前最高优先级的 Fmax 风险 |
| branch recovery | 都在 commit 触发精确恢复；superScalar 元数据和恢复 contract 更薄 |
| LSU | 基本功能闭环，但 superScalar 更保守，load pending 造成更大范围阻塞 |
| StoreBuffer flush | 关键语义一致：保留已退休 store，丢弃投机 store |
| CSR/异常 | superScalar 具备最小 M-mode 路径，但系统完整性显著弱于 NOP-Core |
| I-cache | 本项目明确不做；不影响借鉴 fetch mask、同步返回对齐和 flush token |

如果把历史文档中的“ROB128、PRF96、INT IQ48”继续当作当前事实，会误判时序瓶颈和优化优先级；当前真实参数以 `CoreConfigPkg.sv` 为准。

## 2. 接口速查表

### 2.1 全局宽度与资源

| 信号/参数 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| NOP `fetchWidth=4` | 配置 | 每拍最多取得 4 条 | IF1 发地址，IF2 形成 packet |
| superScalar `FETCH_WIDTH=2` | 配置 | 双口 IROM 每拍最多返回 2 条 | PC 8B 对齐时两 lane 有效；`pc[2]=1` 时只用 lane0 |
| NOP `decodeWidth=3` | 配置 | ID/rename/dispatch 三宽 | 各 lane 必须保持程序序 prefix |
| superScalar `DECODE/RENAME/DISPATCH_WIDTH=2` | 配置 | 两宽组合 rename/dispatch | lane1 只有在 lane0 fire 后才可 fire |
| NOP/superScalar `ROB_DEPTH=32` | 配置 | 最大 32 条 in-flight | full 必须反压 rename |
| NOP PRF=63 / superScalar PRF=64 | 配置 | 架构映射外分别约 31/32 个 speculative 目的寄存器 | 分配时置 busy，提交释放 old_prd |
| NOP INT IQ=7 / superScalar=8 | 配置 | oldest-ready 整数调度窗口 | 每拍分别最多选 3/2 条 |
| 两者 MEM IQ=5 | 配置 | head-only 访存 FIFO | 保持访存顺序，ready head 才发 |
| NOP MULDIV IQ=3 / superScalar=4 | 配置 | head-only 乘除 FIFO | MDU ready 才 pop |
| 两者 StoreBuffer=8 | 配置 | 隔离投机 store 与架构内存副作用 | execute push，commit mark retired，head drain |

### 2.2 superScalar 前端关键接口

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `fetch_req_valid` | core -> IromFetch2 | 发起同步 IROM 请求 | FetchBuffer 能容纳整个 packet、未 halt、未 recover |
| `fetch_req_ready` | IromFetch2 -> core | 内部 response slot 可接新请求 | `!valid_q || resp_ready_i`，支持一进一出 |
| `irom.ena/iromAddr` | core -> IROM | 双口 ROM 读使能和基地址 | `req_valid && req_ready && !clear` |
| `irom.inst[1:0]` | IROM -> core | 请求后一拍返回两条指令 | 必须与寄存的 `pc_q/pred_*_q/valid_mask_q` 对齐 |
| `fetch_valid[1:0]` | IromFetch2 -> FetchBuffer | 返回 lane 有效 | odd 8B 半组或 lane0 taken 时只允许 lane0 |
| `fetch_push_ready[1:0]` | FetchBuffer -> fetch | 整 packet 接收能力 | 当前实现 all-or-none，不允许只接一条后丢另一条 |
| `fetch_pop_valid/ready` | FetchBuffer <-> decode | 两宽出队 | lane prefix 必须连续；recover 时 FIFO clear |
| `backend_recover_valid/pc` | commit -> frontend/backend | 精确 redirect 与全局 squash | 优先级高于预测和顺序 PC；同拍禁止发旧请求 |
| `bpu_update_*` | commit -> BPU | 训练 BTB/PHT/RAS | 每拍最多训练一条已提交控制流指令 |

### 2.3 superScalar rename/dispatch/ROB 接口

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `decode_valid_i/decode_ready_o` | frontend <-> backend | decode uop 的接受握手 | ready 实际等于 lane_fire，不是单纯“有空间” |
| `free_alloc_req/valid/phy/accept` | Rename <-> FreeList | 请求、候选与最终消费 PRF | 只有 ROB 和目标 IQ 都接受时才 accept |
| `rob_alloc_valid/ready/idx` | Rename <-> ROB | 为 uop 分配精确顺序位置 | 分配与 IQ push 同一 fire，避免 ROB/IQ 单边成功 |
| `busy_query_*` | Rename <-> BusyTable | 初始化源 ready | 支持同拍 writeback forward 和同拍新目的 mark-busy 覆盖 |
| `rename_valid/ready/uop` | Rename <-> Dispatch | 传递 `prs/prd/old_prd/rob_idx` | 当前没有 rename-dispatch pipeline register |
| `int/mem/mul_push_*` | Dispatch <-> IQ | 按 tube 分流 | 每 lane 只依赖目标 IQ ready |
| `complete_*` | Execute -> completion FF -> ROB/Busy | 写结果、异常、branch miss 和 CSR 信息 | superScalar 特意打一拍后再写 ROB/wakeup |
| `retire_valid/ready/entry` | ROB <-> Commit | ROB head 连续退休 | lane1 只有 lane0 done/retire 后可见 |
| `commit_valid/arch/prd` | Commit -> ARAT/FreeList | 更新架构映射、释放 old PRF | 异常 lane 不 commit；它之前的 older lane 可 commit |

### 2.4 superScalar execute/LSU 接口

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `issue_valid/issue_ready` | IQ <-> ExecuteCluster | 发射握手 | valid 不依赖 ready，防止 ready-valid 组合环 |
| `wakeup_valid/phy` | completion FF -> IQ | 广播目的 PRF ready | 进入队列和已在队列的 uop 都做同拍 wakeup bypass |
| `prf_raddr/rdata` | ExecuteCluster <-> PRF | 组合读源数据 | 当前落在 IQ select 到 execute complete 的长路径中 |
| `prf_we/waddr/wdata` | execute -> PRF | 多路乱序写回 | exception/store 不写 PRF；load 返回和 MDU 完成占固定 completion slot |
| `store_push_*` | LSU -> StoreBuffer | 保存地址、数据、mask、ROB index | store 地址/数据 ready 且 buffer 有空间时 |
| `commit_valid/rob_idx` | Commit -> StoreBuffer | 将精确提交的对应 store 标 retired | 必须先标记再执行 flush 保留筛选 |
| `load_query_*` | LSU -> StoreBuffer | 对同字 older store 做字节级前递 | full coverage 可直接完成；否则必须等 StoreBuffer 全空后才访问内存 |
| `dmem.exRead*` | LSU <-> DCache/内存接口 | 单 outstanding load | pending 期间不再接受新 load |
| `dmem.storeWrite*` | StoreBuffer <-> DCache/内存接口 | 已退休 store drain | 只有 buffer head `valid && retired` 才可产生副作用 |

### 2.5 NOP-Core 对应控制语义

| 信号/概念 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `arbitration.isValid` | stage local | stage 当前拥有有效 uop | payload 只有 valid 时可被消费 |
| `haltItself/haltByOther` | plugin -> stage | 自身或外部原因停顿 | 形成 `isStuck`，保持 stage payload |
| `removeIt/flushIt/flushNext` | plugin -> stage | 删除当前或后续错误 uop | flush 优先于正常移动和副作用 |
| `isFiring` | stage -> plugin | `valid && !stuck && !remove` | IQ pop、ROB push、PRF 分配均应绑定 fire |
| `needFlush` | Commit -> pipelines | commit 当拍决定恢复 | 清前端/ROB 等控制 |
| `regFlush` | Commit -> PRF/IQ/SB | `needFlush` 延迟一拍 | 回滚 RAT/free/busy，保留 retired store |

## 3. 主数据流

### 3.1 NOP-Core 实际分拍

```text
IF1: PC + BTB/PHT/RAS + ICache read command
  -> IF2: tag/hit/mask/predict redirect + FetchBuffer push
  -> ID: 3-wide decode
  -> RENAME: sRAT read + intra-group RAW/WAW + PRF/ROB allocation
  -> DISPATCH: busy read + INT/MEM/MULDIV IQ push
  -> ISS: oldest-ready/head-ready select
  -> RRD: PRF read
  -> EXE/MEMADDR/MEM1/MEM2: execute or memory access
  -> WB: PRF write + busy clear + ROB random complete
  -> COMMIT: ROB head <=3, aRAT/free/store/CSR/recovery
```

每个箭头大体对应 stage 寄存边界。NOP-Core 的 `Stage` 框架保证 payload、valid、stall 和 flush 同步移动。

### 3.2 当前 superScalar 实际分拍

```text
C0: PcGen.pc_q + BPU combinational lookup
  -> edge
C1: IROM request metadata registered；同步 IROM 同时读
  -> C1 combinational: IROM data + registered PC/meta -> FetchBuffer push
  -> edge
C2: FetchBuffer head -> decoder -> sRAT/free/busy/ROB-ready
    -> dispatch target-IQ-ready -> ROB allocate + PRF allocate + IQ push
  -> edge
C3: IQ wakeup + oldest-ready select -> PRF combinational read/bypass
    -> ALU/BRU/CSR/AGU/forward query -> execute result or request
  -> edge（`complete_*` 再寄存一拍；IQ/PRF 也在本 edge 更新）
C4: completion FF -> BusyTable/IQ wakeup + ROB random complete
  -> edge
C5: ROB entry.done 可见 -> combinational retire/commit/recover
  -> edge
```

这里有两个决定性事实：

1. `FetchBuffer -> Decoder -> Rename -> Dispatch -> IQ/ROB` 是一个组合 stage，而不是 NOP-Core 的 ID、RENAME、DISPATCH 三个 stage。
2. `IQ select -> PRF read -> bypass -> execute/branch/CSR/AGU` 是一个组合 stage，而不是 NOP-Core 的 ISS、RRD、EXE 三个 stage。

因此当前 superScalar 在功能结构上接近 NOP-Core，在物理实现时序上却没有对齐。

### 3.3 Rename 数据依赖链

```text
rs1/rs2/rd
  -> sRAT lookup
  -> older-lane mapping bypass
  -> prs1/prs2/old_prd
  -> FreeList priority scan 得 prd
  -> BusyTable query/同拍 WB forward
  -> ROB space + target IQ space
  -> lane_fire
  -> 同一 edge: sRAT update + PRF mark busy + ROB entry + IQ entry
```

这条链的原子性处理是正确方向：只有 `lane_fire` 才同时消费 FreeList、更新 sRAT、写 ROB、写 IQ。若其中任何资源按 `valid` 而不是 `fire` 更新，会出现“ROB 有 uop 但 IQ 没有”或 PRF 泄漏。

### 3.4 执行与唤醒链

```text
IQ entry ready bits
  -> completion broadcast compare
  -> oldest-ready select
  -> PRF read + same-cycle writeback bypass
  -> ALU/branch/AGU
  -> PRF write（短执行）+ exec_complete
  -> completion FF
  -> ROB done + BusyTable ready + all IQ wakeup
```

superScalar 已将 `exec_complete -> ROB/IQ wakeup` 打一拍，切断了 execute-result 到 IQ select 的直接组合闭环；这是正确的。但 PRF 写回发生在 execute 当拍，BusyTable/IQ 的正式 wakeup 要到 completion FF 后，依赖链至少有一拍可优化空间。

### 3.5 Store 数据流

```text
MEM IQ head
  -> PRF base/data
  -> AGU + alignment check + byte mask
  -> StoreBuffer push(retired=0, rob_idx)
  -> ROB complete
  -> ROB head commit 匹配 rob_idx，标 retired=1
  -> StoreBuffer head 且 retired
  -> dmem.storeWrite valid/ready
  -> 架构内存副作用
```

该顺序与 NOP-Core 的核心原则一致。store execute 完成不等于可以写内存，只有 commit 才解除副作用屏障。

## 4. 控制流与优先级

### 4.1 PC 与前端优先级

```text
reset
  > backend recovery redirect
  > hold（请求未被接受）
  > predicted target
  > sequential PC（pc[2] ? +4 : +8）
```

`CorePcGen` 中 recovery 高于 hold 和 prediction，这与 NOP-Core backend jump 高于预测的原则一致。

如果 recovery 被 hold 覆盖，ROB 已清空但 PC 留在旧路径，会重新取回被 squash 的指令。

### 4.2 两宽 prefix 原则

当前 superScalar 的 lane1 依赖 lane0 fire：

```text
lane0: valid && ROB ready && PRF ready && target IQ ready
lane1: 上述条件 && lane0 fire
```

这保证程序顺序和 ROB 连续性，但也意味着 lane0 的目标 IQ 满会阻止 lane1 即使去另一个空 IQ。NOP-Core 同样强调连续 push/pop，但其 DISPATCH stage 和压缩 push mapping 更明确。

如果允许 lane1 绕过未接受的 lane0，ROB 年龄、同组 RAW/WAW 和精确异常都会失序。

### 4.3 Commit/recovery 覆盖关系

当前 `CoreCommitUnit` 每拍从 lane0 向 lane1 扫描：

```text
older normal commit
  -> exception: consume fault ROB entry, 不产生 commit_valid，trap redirect，停止 younger
  -> mret: 当前指令正常 commit，redirect mepc，停止 younger
  -> branch miss: branch 正常 commit，redirect actual target，停止 younger
  -> younger: 不退休
```

恢复广播后：

```text
Frontend IROM response clear
+ FetchBuffer clear
+ ROB clear
+ all IQ clear
+ Execute/MDU/load-pending clear
+ sRAT := 当拍 commit 后的 aRAT
+ FreeList 由当拍 commit 后的 aRAT 重建
+ BusyTable 仅把 aRAT 映射标 ready
+ StoreBuffer 丢 speculative、保留 retired
```

这个“commit 后再 recover”的组合次序很关键。`arat_map_o` 包含同拍 commit bypass，所以 branch 前同拍提交的 older lane 新映射不会被恢复丢掉。

### 4.4 StoreBuffer flush 优先级

superScalar 的实际顺序是：

```text
先按 commit_rob_idx 标记 marked_entry.retired
  -> 再计算 keep = valid && !popped && (!clear || retired)
  -> 压缩保留项
```

这与 NOP-Core `flush 时只清 !retired` 一致，也处理了“store commit 与 branch recovery 同拍”的边界。

如果 clear 直接把 count 清零，会丢失已经架构提交、但尚未真正写入 DCache/内存的 store，属于静默数据错误。

### 4.5 Load 与 issue backpressure

当前 LSU 只允许一个 outstanding load。load 未返回时：

```text
mem_load_pending_q=1
  -> MEM issue 不接新 load
  -> load return 占 MEM completion slot
  -> 两路 INT issue ready 全部拉低
```

NOP-Core 也会在 load 推测唤醒失败时停顿其他 RRD，但它只在实际 `MEM2 stuck && WRITE_REG.valid` 时触发 `wakeupFailed`，控制范围更接近“防止错误消费预测 ready”，而不是无条件把所有整数执行与 load pending 绑定。

优化原则：先保证单 outstanding 正确，再把“内存端口忙”“load 结果未回”“依赖此 load 的 consumer 不可发”拆成三个条件，避免无依赖整数指令被全局阻塞。

另一个保守点是 load admission：只有 StoreBuffer 对所需字节完全前递，或 StoreBuffer 完全为空且没有 drain token 时，load 才能发射。partial overlap 不会错误读取旧内存值，因此功能是安全的；代价是无地址冲突的 older store 也会阻止 load 访问内存。可仿照 NOP-Core 将“是否存在 older same-word byte overlap”和“buffer 是否为空”解耦。

### 4.6 Serial 指令

superScalar 对 CSR/system/fence 等 `is_serial` 指令采用：

```text
必须在 lane0
+ ROB 必须 empty
+ 一旦分配，serial_inflight 阻止新 decode
+ 直到它 commit 或 recover
```

这是正确但保守的实现。NOP-Core 用 `uniqueRetire`、`flushState` 和 commit mask 区分“必须单独提交”“需要提交后 flush”“真正改变全局状态”，粒度更细。

如果直接取消 serial 而没有 CSR forwarding，年轻 CSR read 可能读到尚未提交的旧值；如果所有 CSR 都 drain 全后端，功能正确但 IPC 会产生不必要长泡。

### 4.7 Replay、clear 与 pending token

当前 superScalar 没有通用 replay queue 或 selective replay：

```text
load miss/延迟返回 -> mem_load_pending_q 保存单条 uop，返回后直接 completion
MDU 长延迟       -> MulDivPipe 内部保持状态，ready=0 反压 MULDIV FIFO
branch/trap       -> 全后端 squash，从精确 PC 重新 fetch
```

这在单 outstanding memory 模型下足够简单可靠。NOP-Core 的 `SpeculativeWakeupHandler` 更接近局部 replay/制动 contract：load 提前 clear busy 后，如果 MEM2 不能按预期完成，则用 `wakeupFailed` 暂停可能消费错误 ready 的 RRD。

如果未来给 superScalar 增加 speculative load wakeup，不能只提前 mark-ready；还必须保存 consumer、在 miss 时重新置 busy 或 replay consumer，并防止它们提前写 ROB。没有这套闭环时，保持当前“返回后才 wakeup”更安全。

## 5. 关键代码块精讲

### 5.1 同组 RAW/WAW 映射前递

superScalar：

```systemverilog
mapped = srat_q[arch];
for (int i = 0; i < RENAME_WIDTH; i = i + 1) begin
    if ((i < lane) && lane_fire[i] && mapped_uop[i].alloc_prd &&
        (mapped_uop[i].uop.rd == arch) && (arch != '0)) begin
        mapped = mapped_uop[i].prd;
    end
end
```

为什么这样写：两条指令同拍 rename 时，lane1 必须看见 lane0 已经成功分配的新映射；用 `lane_fire` 而非 `in_valid`，避免 lane0 未被下游接受时虚假前递。

与 NOP-Core 是否一致：一致。NOP-Core 的 `RenamePlugin` 同样做组内 mapping bypass。

删掉/改错的 bug：`add x1,...; add x2,x1,...` 同拍进入时，第二条会读取旧 x1；同组 WAW 时 old_prd 也会记录错误，随后 FreeList 重复释放或泄漏。

### 5.2 ROB/FreeList/IQ 原子 fire

```systemverilog
lane_fire[i] = out_valid_o[i] && out_ready_i[i];
in_ready_o[i] = lane_fire[i];
rob_alloc_valid_o[i] = lane_fire[i];
free_alloc_accept_o[i] = lane_fire[i] && needs_prd[i];
```

为什么这样写：rename 本身不应提前占有资源；ROB、PRF、IQ 三方必须在一个逻辑事务中同时成功。

与 NOP-Core 是否一致：语义一致。NOP-Core 通过 stage `isFiring` 和各 push port ready 统一实现。

删掉/改错的 bug：用 `out_valid` 分配 PRF、用 `ready` 写 IQ 会在 backpressure 下造成 PRF 泄漏、ROB 孤儿项或 uop 重复入队。

### 5.3 completion 打一拍

```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst || clear_i || recover_i) begin
        complete_valid <= '0;
    end else begin
        complete_valid <= exec_complete_valid;
        complete_rob_idx <= exec_complete_rob_idx;
        // payload omitted
    end
end
```

为什么这样写：切断 execute/PRF 输出到全 IQ wakeup、BusyTable 和 ROB 多写口的高扇出路径；只 reset valid，降低 FPGA reset fanout。

与 NOP-Core 是否一致：意图一致，但 stage 位置不同。NOP-Core 通过 WB stage 自然形成寄存边界。

删掉/改错的 bug：直接组合广播会形成 `IQ wakeup -> select -> execute -> wakeup` 的超长路径，甚至因 ready/valid 接法形成组合环；flush 不清 valid 会让错路径完成写 ROB/唤醒 PRF。

### 5.4 INT oldest-ready 选择

```systemverilog
for (int p = 0; p < ISSUE_PORTS; p = p + 1) begin
    for (int e = 0; e < DEPTH; e = e + 1) begin
        if (!issue_valid_o[p] && valid_q[e] && !selected_mask[e] &&
            ready_entry[e].src1_ready && ready_entry[e].src2_ready) begin
            issue_valid_o[p] = 1'b1;
            issue_uop_o[p] = ready_entry[e];
            selected_mask[e] = 1'b1;
        end
    end
end
```

为什么这样写：压缩队列低 index 代表更老，逐端口扫描自然得到 oldest-ready，并用 mask 防止同一 entry 被两个端口选择。

与 NOP-Core 是否一致：基本一致；NOP-Core INT IQ 也是压缩式 oldest-ready，多端口 select。

删掉/改错的 bug：不做 `selected_mask` 会双发同一 uop；不在 wakeup 后判断 ready 会多等一拍；扩大 depth/issue width 会迅速恶化组合时序。

### 5.5 StoreBuffer flush 保留已退休项

```systemverilog
keep_entry[i] = marked_entry[i].valid &&
                !(pop_fire && (i == 0)) &&
                (!clear_i || marked_entry[i].retired);
```

为什么这样写：retired store 已成为架构状态，即使 branch/trap flush，也必须继续 drain；只有未提交 store 才能被 squash。

与 NOP-Core 是否一致：一致。NOP-Core `regFlush` 时只清 `!queueNext(i).retired`。

删掉/改错的 bug：丢 committed store 或让 wrong-path store 写内存，二者都会破坏精确状态。

### 5.6 ROB 不 reset 宽 payload

```systemverilog
if (rst) begin
    head_q <= '0;
    tail_q <= '0;
    count_q <= '0;
end
// entry_q payload is only consumed when count/valid owns it
```

为什么这样写：ownership 由 head/tail/count/valid 决定，无需 reset 大量 payload FF；可显著降低 FPGA reset 控制集和扇出。

与 NOP-Core 是否一致：设计原则一致，SpinalHDL 中许多 payload 同样由 Flow/Stream valid 管理。

删掉/改错的 bug：不是“不 reset payload”会错，而是若任何消费者忽略 valid/count，复位后 X/旧值就可能被当真；反过来给所有 payload 异步 reset 会恶化 Fmax/资源。

### 5.7 NOP-Core 的统一 stage arbitration

```scala
val haltItself, haltByOther = False
val removeIt, flushIt, flushNext = False
val isValid, isStuck, isFiring = Bool
```

为什么这样写：把“是否拥有 uop、是否移动、是否产生副作用、是否被 flush”变成全流水统一语义，插件只声明原因。

superScalar 当前差距：每个模块分别实现 `clear_i`、valid、ready 和内部 pending 清理，没有一个可审计的统一表。

删掉/改错的 bug：最典型是 IQ 已 pop 但执行级没接住、load request 已发但 pending token 被 flush 错误保留、或 wrong-path completion 在 recovery 后写新一代同 ROB index。

### 5.8 Commit mask 与 unique-retire

NOP-Core：

```scala
val readyMask = completeMask & excMask & uniqueMask & recoverMask & uncachedMask
```

为什么这样写：退休宽度不是简单的 `head.done` 前缀，还要同时满足异常、唯一提交、恢复和 uncached 事务规则。

superScalar 当前差距：有异常/branch/mret 的 stop-retire，但没有等价的通用 `uniqueMask/uncachedMask`；主要靠 rename 前全 drain 的 serial 策略绕开。

删掉/改错的 bug：CSR/fence/特殊访存可能和相邻指令同拍产生不允许的副作用；全部改成 drain 又会造成过度串行化。

## 6. 时序示例

### 6.1 正常路径：两条独立 ALU 同拍进入

假设 FetchBuffer 已有 `I0: add x5,x1,x2`、`I1: xor x6,x3,x4`，源均 ready，INT IQ 有空间。

| 周期 | 当前 superScalar | NOP-Core 对应行为 |
|---|---|---|
| C0 | FetchBuffer 输出；组合 decode + sRAT + FreeList + Busy + dispatch；edge 分配 ROB0/1、p32/p33 并入 INT IQ | ID 只 decode |
| C1 | INT IQ 组合选择两条；组合 PRF read/bypass + ALU；edge 写 PRF，并把 exec completion 写入 completion FF | RENAME 分配 PRF/ROB |
| C2 | completion 广播唤醒、写 ROB done；edge ROB 状态更新 | DISPATCH 入 IQ |
| C3 | ROB head 看见 done，组合 commit 两条；edge 更新 ARAT、释放旧 PRF | ISS 选择 |
| 后续 | 已退休 | RRD -> EXE -> WB -> COMMIT，延迟更长但每级逻辑短 |

结论：superScalar 的最短 ALU latency 看起来更低，但 C0/C1 两个周期的组合逻辑显著更长。若综合频率下降，低 cycle latency 不一定换来更高实际性能。

若 C0 lane0 的 INT IQ 满、lane1 实际是 MEM：prefix 规则会让两条都停。这是正确的 in-order dispatch 选择，不是 bug；要改善需增加 dispatch buffer/分阶段，而不是允许 lane1 越过。

### 6.2 异常路径：older store 已提交，younger branch 误预测

假设 StoreBuffer head 是 `S0`，已进入 buffer 但未写内存；ROB head 两 lane 为 `S0` 和 younger branch `B1`，B1 已标 miss。

| 周期 | 行为 |
|---|---|
| C0 组合 | Commit lane0 提交 S0，StoreBuffer 通过 ROB index 将其 `retired=1`；lane1 提交 B1 并产生 recovery target；停止更年轻退休 |
| C0 edge | ARAT/free 应用两个正常提交；PC redirect；ROB/IQ/execute 清；sRAT/free/busy 从包含同拍 commit 的 ARAT 恢复；StoreBuffer 先标 S0 retired，再仅丢弃未退休 younger stores |
| C1 | 新路径发 IROM 请求；S0 仍留在 StoreBuffer head，等待 `storeWriteReady` |
| C2+ | S0 最终写入内存并 pop；wrong-path store 永远不会产生写请求 |

这条路径当前 superScalar 与 NOP-Core 的关键精确语义一致。

如果 StoreBuffer 在 recovery 时无条件清空，S0 会丢失；如果分支 miss 在 execute 当拍直接清 ROB、但没有精确保留 older commit 状态，则 RAT/free/store 都可能恢复错误。

### 6.3 异常路径：load 未返回时发生 older trap

| 周期 | 行为 |
|---|---|
| C0 | younger load 已发 `exReadEn`，`mem_load_pending_q=1`；older ROB head trap commit |
| C0 edge | recovery 清 `mem_load_pending_q`、IQ、ROB 和 completion valid；PC 跳 `mtvec` |
| C1+ | 旧 load response 即使到达，也因 pending token 已清不能写 PRF/ROB |

这要求外部内存响应允许被丢弃，或带 epoch/tag 区分请求代际。当前接口只有单 outstanding 和无 ID response，依赖 clear 后 `mem_load_pending_q=0` 来忽略旧返回。

若未来允许多个 outstanding，必须增加 request ID/ROB tag/epoch；仅清一个 pending bit 已不够。

## 7. 我可以直接复用的设计模式

1. **资源分配绑定统一 fire**：`ROB allocate && PRF allocate && target IQ push` 必须同一事务成功；任何一个 ready 缺失就全部保持。

2. **lane prefix contract**：多宽 rename/dispatch/retire 只允许从 lane0 开始连续 fire。用 assertion 固化 `fire[1] -> fire[0]`。

3. **sRAT/aRAT 双映射恢复**：正常 rename 只写 sRAT，commit 只写 aRAT，整核 squash 时 `sRAT := aRAT_after_same_cycle_commit`。

4. **FreeList 可重建恢复**：小 PRF 下可像当前实现一样从 aRAT live mask 一拍重建；窗口扩大后再考虑 checkpoint，不要过早增加恢复复杂度。

5. **压缩式小 IQ**：INT 用 oldest-ready 压缩队列，MEM/MULDIV 用 head-only FIFO。当前 8/5/4 深度适合 FPGA，不建议先扩大。

6. **只 reset ownership，不 reset payload**：FIFO/ROB/IQ 只 reset valid/count/pointer；payload 在 valid=0 时不可观察。配套 assertion 比给宽 payload 异步 reset更有效。

7. **StoreBuffer retired barrier**：execute 只生成 speculative entry；commit 按 ROB index 标 retired；flush 只杀未 retired；内存写只看 retired head。

8. **统一 flush matrix**：为每个状态明确 reset、normal fire、stall、recovery 的行为，至少覆盖 PC token、IROM response、FetchBuffer、RAT、FreeList、Busy、ROB、IQ、MDU、load pending、StoreBuffer。

### 推荐的 SV stage contract

不需要照搬 SpinalHDL plugin，但应仿照它的语义：

```systemverilog
typedef struct packed {
    logic valid;
    payload_t payload;
} stage_slot_t;

fire = valid_o && ready_i;

always_ff @(posedge clk) begin
    if (reset || flush) begin
        valid_q <= 1'b0;
    end else if (ready_i) begin
        valid_q <= valid_i;
        if (valid_i) payload_q <= payload_i;
    end
end
```

对多 lane 再增加 prefix fire；所有 dequeue、allocation 和 side effect 只绑定 `fire`。

### 不做 I-cache 时仍应借鉴 NOP-Core 的前端模式

1. IROM 请求 PC、lane mask、prediction meta 必须和同步返回数据一起寄存。
2. fetch packet 不跨 8B 双口组；`pc[2]=1` 时只发 lane0。
3. lane0 预测 taken 时屏蔽 lane1。
4. recovery 同拍清 pending response token 和 FetchBuffer，并禁止发旧 PC 请求。
5. FetchBuffer 吸收 fetch=2 与后端瞬时 backpressure，不需要引入 cache miss FSM。

## 8. 常见坑与自检清单

- [ ] 所有多 lane fire 都满足连续 prefix，lane1 不可能单独分配 ROB/PRF/IQ。
- [ ] 同拍 `lane0.rd == lane1.rs1/rs2/rd` 时，lane1 使用 lane0 新 PRF，并记录正确 `old_prd`。
- [ ] FreeList 候选生成不依赖 accept，避免 ready-valid 组合环；真正删除只看 accept/fire。
- [ ] 同一 PRF 同拍 mark-busy 与 mark-ready 时优先级符合生命周期；新 allocation 不能被旧 writeback 错误标 ready。
- [ ] IQ wakeup 比较忽略无效 completion，目的 p0 不参与正常唤醒/写回。
- [ ] IQ valid 不依赖 execute ready，pop 只发生在 `valid && ready`。
- [ ] branch/trap recovery 清所有 wrong-path completion token，包括 completion FF、MDU state 和 load pending。
- [ ] StoreBuffer flush 保留 recovery 同拍刚 commit 的 store，且 wrong-path store 永远不能拉高 memory write enable。
- [ ] 异常 lane 之前的 older 指令可 commit；异常 lane 不更新 ARAT/free；异常之后不 retire。
- [ ] branch miss/mret 指令本身的合法架构写回先 commit，再用更新后的 aRAT 恢复。
- [ ] CSR 两写同拍时定义明确的程序顺序优先级；当前 for-loop 的高 lane NBA 后赋值会覆盖低 lane，应保证这就是期望的 younger-wins 语义。
- [ ] 每拍最多训练一条 BPU 时，明确选择 oldest committed branch；当前 superScalar 用 `!bpu_update_valid` 选择较老 lane，行为合理但会漏掉同拍第二条训练机会。
- [ ] load partial store-forward 不能直接忽略 forwarded bytes；当前实现通过等待 StoreBuffer 全空保证正确。若要优化，需做 byte merge 或精确相关性等待。
- [ ] 单 outstanding load 在 flush 后的迟到 response 必须被忽略；扩展到多 outstanding 前必须引入 tag/epoch。
- [ ] 性能计数事件绑定真实 fire，不把 valid-but-stalled 当 issue/commit。
- [ ] 不 reset payload 的模块都用 valid/count 完全门控读取，并有 assertion 防止 invalid payload 被消费。

### 当前差异与优化优先级

| 优先级 | 差异/风险 | 与 NOP-Core 的差距 | 建议动作 | 类型 |
|---:|---|---|---|---|
| P0 | decode->rename->dispatch 组合过长 | NOP 有 ID/RN/DS 三段 | 在 decode 后或 rename 后增加 elastic stage；先以综合关键路径决定切点 | 时序 |
| P0 | IQ select->PRF->ALU/BRU 组合过长 | NOP 有 ISS/RRD/EXE | 增加 issue-to-RRD 寄存，PRF read 后再 EXE；保持 flush/ready contract | 时序/控制 |
| P1 | load pending 阻塞范围偏大 | NOP 仅在推测唤醒失败时全局制动 | 区分 memory port busy、load dependency、completion slot conflict | 性能 |
| P1 | load 要求 StoreBuffer 全空 | NOP 可按地址/byte 做更细粒度 forwarding 与访问 | 无 overlap 时允许访存；partial overlap 做 byte merge 或只等相关 store | 性能 |
| P1 | serial 全 drain | NOP 用 uniqueRetire/flushState | 先引入 `unique_retire` commit mask，再逐类放松 CSR/fence | 性能/控制 |
| P1 | recovery packet 太薄 | NOP 带更多预测恢复信息 | 增加 recovery cause、epoch，必要时加 GHR/RAS snapshot；不涉及 I-cache | 可维护性 |
| P1 | flush contract 分散 | NOP 有统一 Stage arbitration | 建立 flush matrix 和 reusable elastic register，不必复制 plugin 框架 | 正确性 |
| P2 | BPU 每拍只训练一条 | NOP commit predictor contract 更丰富 | 保持 oldest-first；只有测得双 branch commit 常见再做双写/排队 | 性能 |
| P2 | FreeList 每拍全扫描 64 PRF | NOP 使用小队列式 free list | 若成为关键路径，改 bitmap 分组编码或多端口 FIFO；先看 timing report | 时序 |
| P2 | INT IQ 每拍全压缩宽 payload | NOP 深度更小且生成器优化 | 可改 valid/entry 分离、只搬 index，或分 bank；8 项下先测再改 | 时序/面积 |
| 不做 | I-cache/MMU 前端路径 | NOP 功能更完整 | 保留同步 IROM + fetch mask + flush token，不迁移 ICachePlugin | 范围外 |

### 建议实施顺序

```text
Phase 1: 固化 contract
  assertion + flush matrix + load/store ordering contract
    -> Phase 2: 切 INT 时序
       issue/RRD register + PRF/bypass/EXE boundary
         -> Phase 3: 切 rename 时序
            decode/RN/DS elastic boundary
              -> Phase 4: 放松 LSU/serial 全局阻塞
                 performance counter 验证收益
```

不要同时改 stage 切分、恢复协议和 LSU ordering；三者同时变化时，出现错提交很难定位。

## 最小实践任务

目标：手写一个不含 I-cache、D-cache、CSR、异常和 MDU 的 **2-wide rename + 2-wide INT OoO 核心切片**，重点练习 NOP-Core 的 stage contract，而不是追求完整 ISA。

功能边界：

```text
输入：每拍最多 2 条已 decode 的 ALU uop
资源：32 arch regs，40 phys regs，ROB8，INT IQ4
执行：2 个单周期 ALU
提交：2-wide in-order commit
恢复：只支持 branch miss，整核回滚到 aRAT
不做：memory、cache、CSR、exception、interrupt、mul/div、BPU
```

实现步骤：

1. 定义 `DecodeUop/RenamedUop/RobEntry/Completion` 四个最小 packed struct。
2. 写 2-wide sRAT/aRAT rename，先验证同组 RAW/WAW 和 x0。
3. 写 8-entry bitmap FreeList，并让 `ROB+PRF+IQ` 只在统一 lane fire 时分配。
4. 写 4-entry compressed IQ，支持 completion wakeup、oldest-ready 双选和 selected mask。
5. 在 IQ 与 PRF read 之间加一个 2-wide elastic register，明确 `valid/ready/flush`。
6. 写双组合读 PRF、两 ALU、completion register 和 ROB random complete。
7. 写 ROB 连续 2-wide commit、old_prd free、aRAT 更新和 branch miss 全清恢复。
8. 加最少 8 条 assertion：lane prefix、PRF 不重复分配、ROB count 边界、IQ 不双选、x0 恒零、wrong-path 不 commit、recovery 后 sRAT==aRAT、invalid payload 不消费。

完成标准：能够手工画出任意一条 uop 每拍位于哪个 ownership slot，并能证明 stall 或 flush 任意插入时，uop 不丢、不重、不产生错路径副作用。完成这个切片后，再把相同 contract 迁回当前 `CoreBackend`，比直接在全核上移动寄存器更容易验证。

## 最终结论

当前 superScalar 已完成 NOP-Core 核心 OoO 数据结构的迁移，特别是两宽组内 rename、ROB 精确提交、完成广播、分布式 IQ、以及 StoreBuffer retired 保留规则，方向和关键语义基本正确。

当前最值得仿照 NOP-Core 的不是 I-cache，也不是继续扩大 ROB/IQ，而是：

1. 把 decode/rename/dispatch 和 issue/RRD/execute 真正切成可停顿、可 flush 的 stage；
2. 用统一 fire/flush contract 替代分散的模块内隐含规则；
3. 将 LSU 的全局保守阻塞收敛为依赖相关的局部 backpressure；
4. 用 unique-retire/commit mask 逐步替代所有 serial 指令都 drain 全后端。

这四项完成后，当前 superScalar 才会从“结构仿照 NOP-Core”进一步变成“时序和控制工程也达到同类实现方法”。
