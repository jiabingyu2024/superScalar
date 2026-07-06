# 分布式 IssueQueue 改造记录

> 日期：2026-07-06  
> 目标：把原统一 IssueQueue 拆成 Int/Mem/Mul 三类队列，降低统一队列满载和选择逻辑压力，并为后续 per-pipe 调度优化建立接口边界。

## 改造结果

后端 issue 宽度从原先绑定 `WAY_NUM=2` 改为独立参数：

| 参数 | 值 | 含义 |
| --- | ---: | --- |
| `WAY_NUM` | 2 | 前端/dispatch/commit 宽度，保持不变。 |
| `INT_ISSUE_WIDTH` | 3 | IntIssueQueue 最大发射宽度，覆盖 ALU/BRC/SYS。 |
| `MEM_ISSUE_WIDTH` | 1 | MemIssueQueue 发射宽度，严格 FIFO。 |
| `MUL_ISSUE_WIDTH` | 1 | MulIssueQueue 发射宽度，严格 FIFO。 |
| `ISSUE_WIDTH` | 5 | IssueStage 到 ReadRegStage 的总 slot 数。 |
| `MEM_WB_WIDTH` | 2 | MEM 完成端口，保留 load return + current MEM 同周期完成能力。 |
| `WB_PORT_NUM` | 12 | WB/ROB done/ReadyTable/IssueWakeup/bypass 端口数。 |

## RTL 改动摘要

| 文件 | 改动 |
| --- | --- |
| `BasicTypes.sv` | 新增 issue/WB 宽度参数。 |
| `IssueTypes.sv` | 新增三队列深度、payload 静态切分、全局 `age` 字段。 |
| `IssueQueueIF.sv` | pop/free count 拆成 Int/Mem/Mul 三组。 |
| `IssueQueue.sv` | 原统一队列替换为 wrapper + `IntIssueQueue` + `InOrderIssueQueue` 两实例。 |
| `DispatchStage.sv` | 按 uop 类型检查对应队列 free count。 |
| `PayloadIF.sv` / `Payload.sv` | Payload 写口保持 2 路，读口扩为 5 路，深度扩为 24。 |
| `IssueStage.sv` / `IssueStageIF.sv` | 合并三队列 pop 结果，输出 5 个 IS->RR slot。 |
| `ReadRegStage.sv` / `ReadRegStageIF.sv` | 读 5 个 issue slot，并 pack 到 ALU/BRC/SYS 3 lane、MEM/MUL 1 lane。 |
| `Execute*Stage.sv` / `ExecuteStageIF.sv` | ALU/BRC/SYS 改 3 lane，MEM issue 输入 1 lane 但 WB 输出 2 lane，MUL 1 lane。 |
| `WriteBackStage.sv` / `ROBIF.sv` / `ROB.sv` | WB/ROB done/wakeup 端口改为 `WB_PORT_NUM=12`。 |
| `core.sv` | issue 宽度计数改为扫描 `ISSUE_WIDTH`；现有 w2 计数仍表示“2 条及以上”。 |

## 关键设计边界

1. Dispatch 仍整包接受，不做 partial accept；若 packet 中任一目标队列空间不足，整包 stall。
2. IntIssueQueue 是 16 项乱序 ready-select，最多给 3 个候选。
3. MemIssueQueue 和 MulIssueQueue 是 4 项严格 FIFO，只允许 head ready 发射。
4. wrapper 对最多 5 个候选按全局 `age` 从老到新授权，并禁止同周期 RAW。
5. Payload index 静态切分：Int `0..15`，Mem `16..19`，Mul `20..23`。
6. MEM 发射单路但完成双口，避免破坏既有 load return result buffer 优化。
7. 预计唤醒策略保持保守：MEM load 和 DIV/REM 仍等待真实 WB wakeup。

## 已修复问题

### Dispatch/IQ push 握手死锁

现象：第一次完整回归中大量 RV32 用例 2,000,000 cycle 超时；聚焦 `rv32ui-p-simple` 后看到 `commit_count=0`、dispatch/issue/commit 宽度全为 0，前端/ID/RN/DS 长期 stall。

根因：`DispatchStage` 的 `resourceReady` 仍保留旧统一队列写法：

```systemverilog
resourceReady &= !pipeReg[i].valid ||
                 (rob.RobPushRes[i].valid && issueQueue.IssuePushRes[i].done);
```

分布式队列改造后，IQ 容量已经由 `IntIssueFreeCount/MemIssueFreeCount/MulIssueFreeCount` 前置检查；而 `IssuePushReq.valid` 只有 `dispatchEn` 成立才会拉高。如果 `dispatchEn` 又反过来等待 `IssuePushRes.done`，就形成：

```text
dispatchEn -> IssuePushReq.valid -> IssuePushRes.done -> resourceReady -> dispatchEn
```

空队列也无法产生首个 dispatch。

修复：`DispatchStage` 的资源准入只保留 ROB push response 和 per-queue free count 检查：

```systemverilog
resourceReady &= !pipeReg[i].valid || rob.RobPushRes[i].valid;
```

实际队列写入仍由 `IssuePushReq.valid && IssuePushRes.done` 保护，`payloadIndex` 也仍来自队列分配结果。若未来把 `IssuePushRes.done` 再接回 `resourceReady`，会复现 0 dispatch 死锁。

## 待验证风险

1. 新增 12 写回/唤醒端口会增加 WB、ReadyTable、Bypass 的组合扇入。
2. IntIssueQueue 选择 3 个候选后，wrapper RAW 仲裁可能丢弃 younger candidate，但不会补选替代项，属于保守吞吐损失。
3. Mem/Mul FIFO 满时即使同周期 head pop，也不会同拍接收新 entry，可能多 1 拍 dispatch stall。
4. SYS 虽进入 IntIssueQueue，但 serial 排干仍依赖 Rename/Commit；需要回归 CSR/ECALL/MRET/FENCE。
5. 当前性能计数仍只有 issue w0/w1/w2，w2 已变成“>=2”，后续若要分析 3/4/5 发射需扩展 PerfIF/TB JSON。

## 验证结果

已执行：

```bash
make sim-rv32 TEST=rv32ui-p-simple BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32ui-p-add NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-jal NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lw NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32um-p-mul NO_BUILD=1 OBJCACHE=
make sim-rv32-all NO_BUILD=1 OBJCACHE=
make sim-src TEST=srcWithMext MAX_CYCLES=2000000 NO_BUILD=1 OBJCACHE=
```

结果：

1. `rv32ui-p-simple/add/jal/lw` 和 `rv32um-p-mul` 均 PASS。
2. `sim-rv32-all` 中 RV32MI、RV32I、RV32M 全部 PASS。
3. `rv32uzba/rv32uzbb/rv32uzbc/rv32uzbkb/rv32uzbkx/rv32uzbs` 仍 FAIL，属于 bitmanip 扩展覆盖，不作为本次 IssueQueue 改造通过条件。
4. `srcWithMext` 在小量上限内 TIMEOUT；结果文件显示内部计数已达到 `rv32i_count=37`、`mext_count=8`，`commit_count=10563639`、`ipc=0.528182`，但未看到 profile 配置的 pass marker。该结果记录为“src 软件/marker 未闭合”，不是 0 dispatch/0 commit 型 RTL 死锁。
