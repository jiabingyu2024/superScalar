# IPC < 0.5 根因分析与优化方案

> 日期：2026-07-05  
> 目标：分析双发射乱序 RISC-V 超标量 CPU IPC < 0.5 的根本原因，每条结论均有 RTL 文件:行号证据，并给出可执行的优化方案

---

## 摘要

当前 2-way 乱序超标量核在 `srcWithMext`（200k 周期抽样）上 IPC = 0.4977，`srcSmoke`（完整跑）IPC = 0.422。理论峰值 IPC = 2.0，实测不足理论峰值的 25%。

性能桶核心数据（srcWithMext，200k 周期）：

| 指标 | 绝对值 | 占总周期比 |
|---|---:|---:|
| commit_count | 99534 | — |
| **IPC** | **0.4977** | — |
| frontend_stall_cycles | 198171 | **99.09%** |
| rob_full_cycles | 148405 | **74.20%** |
| load_return_block_cycles | 98297 | **49.15%** |
| ex_stall_cycles | 98297 | 49.15% |
| is/rr_stall_cycles | 98297 | 49.15% |
| recovery_cycles | 131 | 0.065% |
| branch_miss_count | 130 | — |

宽度分布（平均发射/提交宽度）：

| 阶段 | w=0 | w=1 | w=2 | 平均 |
|---|---:|---:|---:|---:|
| dispatch | 149426 | 328 | 50246 | 0.5041 |
| issue | 100126 | 99319 | 555 | 0.5021 |
| commit | 100805 | 98856 | 339 | 0.4977 |

**关键结论**：`issue w2 = 555`（仅占 0.28%），说明二路能力几乎从未发挥。CPU 实际以"两拍走一条"的单发射节奏运行。

**瓶颈优先级排序**：

| 优先级 | 瓶颈 | 主要证据 | 估计 IPC 收益 |
|---|---|---|---:|
| P1 | MEM load 返回冲突 → 全局后端 stall | load_return_block=49.15% | +0.15~+0.35 |
| P2 | ROB 仅 16 项 + commit 策略保守 | rob_full=74.20%，commit w2=0.17% | +0.05~+0.15 |
| P3 | MEM/MUL/DIV 依赖等 WB 唤醒 | issue w2=0.28% | +0.05~+0.10 |
| P4 | DIV 34 周期阻塞 IQ 项 | delay_for=34 | +0.02~+0.05 |
| P5 | Decode packet-split 前端损失 | idStallReq 条件 | +0.02~+0.05 |
| P6 | JALR 无 RAS / 分支 miss 全后端恢复 | srcSmoke JALR miss=50% | +0.03~+0.10 |
| P7 | 仅 WB-only 旁路，无 EX-to-EX | Bypass.sv | +0.02~+0.05 |

---

## 各模块瓶颈详细分析

### A. MEM load 返回冲突 — 全局后端 stall（P1，最高优先级）

#### RTL 证据

**文件：`rtl/core/ExecuteStage/ExecuteMemStage.sv`**

```
行 133:  loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
行 213:  ctrl.memLoadReturnBlockReq = loadReturnBlocked;
行 215:  ctrl.exStallReq = loadReturnBlocked || loadAccessBlocked;
```

**文件：`rtl/core/Ctrl.sv`**

```
行 18-19:  backendBlock = ctrl.isStallReq | ctrl.rrStallReq |
                          ctrl.exStallReq | ctrl.wbStallReq;
行 20:     frontendBlock = ctrl.serialBlock | backendBlock | ctrl.robFull | ...
行 32:     ctrl.isPipe = '{stall: ctrl.isStallReq | ctrl.rrStallReq | ctrl.exStallReq, ...}
行 33:     ctrl.rrPipe = '{stall: ctrl.rrStallReq | ctrl.exStallReq, ...}
行 34:     ctrl.exPipe = '{stall: ctrl.exStallReq, ...}
```

#### 根因分析

load 执行为 3 拍流水（T0 发起→T1 meta推进→T2 读DRAM结果）。  
当 T2 时刻（`loadMetaPipe1.valid=1`），若当前 MEM pipe 中存在任意有效 uop（`currentMemValid=1`），则立即拉高 `exStallReq`，冻结整个 IS/RR/EX 流水线，并通过 `backendBlock` 反压 PF/IF/ID/RN/DS（Ctrl.sv:20）。

这意味着：**每发一条 load，3 拍后必然产生 1 拍全局停顿**（只要后续 MEM pipe 不为空）。  
由于 srcWithMext 访存比例约 29%，load 连续密集，形成"发 1 拍 + 停 1 拍"的振荡节律，直接把 IPC 压在 0.5 附近。

```
数据链：load_return_block_cycles=98297 ≈ ex_stall_cycles=98297 ≈ is_stall_cycles=98297
```

这三个计数完全相等，说明唯一来源就是 `loadReturnBlocked`。

#### 为何 031 的简单合并没有效果

031 尝试让 load 返回拍同时发起下一条 load，但 `DramAccessIF` 读优先（`writeEn = !exReadEn && storeWriteEn`），连续 load 会饿死 StoreBuffer 的 store 提交，反而导致 Dispatch stall。031 已回退。

---

### B. ROB 容量不足 + Commit 策略保守（P2）

#### RTL 证据

**文件：`rtl/core/BasicTypes.sv`**

```
ROB_DEPTH = 16
```

**文件：`rtl/core/DispatchStage/DispatchStage.sv`**

```
ctrl.robFull = packetValid && (int'(rob.RobFreeCount) < validCount);
```

**文件：`rtl/core/CommitStage/CommitStage.sv`**

```
行 118-124:  function automatic logic can_follow_complex_lane0(input RobEntryPath entry);
               return entry.done &&
                      !entry.exception &&
                      !entry.isBranch &&    // 行 121
                      !entry.isStore &&     // 行 122
                      !entry.isSerial &&    // 行 123
                      !entry.chkptValid;    // 行 124
行 161:  if (i==1 && !can_follow_complex_lane0(rob.RobPopRes[1].entry)) stopCommit = 1;
行 178-179: (store 后 lane1) 同样限制
```

#### 根因分析

ROB 仅 16 项，而当前流水线深度约 11 级，加上 MEM 3 拍延迟，ROB 很容易被未完成的 load/MUL/DIV 项塞满。  
`rob_full_cycles = 148405`（74.2%）说明 ROB 头部长期处于"等完成"状态，前端无法分发新指令。

同时，CommitStage 的 `can_follow_complex_lane0` 限制极严（行121-124）：  
lane1 必须是"已完成 + 无异常 + 非分支 + 非store + 非serial + 无checkpoint"才能跟随 lane0 同周期提交。  
实测 `commit w2 = 339`（占 0.17%），双发提交几乎从未触发，平均提交宽度紧贴 IPC 数值。

这两点形成正反馈：MEM stall → ROB 项淤积 → Dispatch 停止 → 前端气泡 → IPC 下降。

---

### C. MEM/MUL/DIV 依赖链等 WB 唤醒（P3）

#### RTL 证据

**文件：`rtl/core/DispatchStage/IssueQueue.sv`**

```
行 205-214:  // producer issue 时写入 consumer 的 srcMatched/srcShift
             if (entries[j].srcA == self.IssuePopRes[i].entry.dst && !entries[j].srcARdy) begin
                 if (self.IssuePopRes[i].entry.delay == ShiftType'(1)) begin  // 行 206
                     entries[j].srcAMatched <= 1'b1;                         // 行 207
                     entries[j].srcAShift   <= self.IssuePopRes[i].entry.delay; // 行 208
                 end
             // delay > 1 的生产者（MEM/MUL/DIV）：不写入，消费者不会被预计唤醒
行 141-155:  // shift logic（已修复置 ready）
             if (entries[i].srcAMatched && !entries[i].srcARdy) begin
                 if (entries[i].srcAShift == ShiftType'(1)) begin  // 行 142
                     entries[i].srcARdy <= 1'b1;                   // 行 143
                 end else if (...) srcAShift 移位
             end
行 159-162:  // 真实 WB wakeup 路径（所有生产者）
             if (!entries[i].srcARdy && wakeup_match(entries[i].srcA)) begin
                 entries[i].srcARdy <= 1'b1;
             end
```

**文件：`rtl/core/DispatchStage/DispatchStage.sv`**

```
行 192-193:  TUBE_TYPE_MUL: cycles = (subtype 为 DIV/DIVU/REM/REMU) ? 34 : 3;
行 197:      delay_for = ShiftType'(1) << (cycles - 1);
// MEM 同理 cycles=3，delay=ShiftType'(1)<<2
```

#### 根因分析

当前 IssueQueue 的预计唤醒（srcShift 机制）仅对 `delay == 1`（ALU/BRC）的生产者启用（行206）。  
MEM（3拍）、MUL（3拍）、DIV（34拍）的生产者发射后，消费者的 `srcAMatched` 不会被设置，必须等到生产者真正到达 WriteBackStage 才能通过 `IssueWakeup` 被唤醒。

以 load-use 链为例：
```
T0: load 进 IQ 选中，issue
T1: load RR
T2: load EX，读 DRAM 发起
T3: DRAM 数据返回 (loadMetaPipe1 valid)
T4: load 进 WB，发出 IssueWakeup
T5: consumer srcARdy=1，下一次选择窗口才能 issue
T6: consumer RR, EX...
```
消费者距 load 发射至少需要等 5 拍，而理论最短 pipeline 间距仅需 4 拍。

这是导致 `issue w2 = 0.28%` 的直接微架构原因：依赖链在 MEM/MUL/DIV 后形成串行等待流，IQ 中大量 entry 因等待唤醒而无法发射。

---

### D. DIV 34 周期单路阻塞（P4）

#### RTL 证据

**文件：`rtl/core/DispatchStage/DispatchStage.sv`**

```
行 192-193:  TUBE_TYPE_MUL: cycles = (subtype inside {DIV,DIVU,REM,REMU}) ? 34 : 3;
行 197:      delay_for = ShiftType'(1) << (cycles - 1);
// DIV delay = ShiftType'(1) << 33，即第 34 周期 WB wakeup
```

**文件：`rtl/core/ExecuteStage/ExecuteMulStage.sv`**

```
行 ~210:  divMetaPipe[0:34]  // 34 级 meta 流水，每级 1 拍
// 仅有 1 个 DIV_0 IP 实例，每次 DIV/REM 占用 34 拍
```

**文件：`rtl/core/DispatchStage/IssueQueue.sv`**

```
// MUL 仅允许从 slot 0 发射：
if (!(i != 0 && tubeType == TUBE_TYPE_MUL))  // 即 MUL only from slot 0
// 每周期最多 1 条 MUL（mulSelected 互斥标志）
```

#### 根因分析

一条 DIV 指令发射后，该 DIV_0 IP 占用 34 周期才完成。在此期间：
- 依赖该 DIV 结果的所有消费者必须在 IQ 中等待 34 拍 WB wakeup；
- 这 34 拍期间，MUL tube 的 IQ slot 被占用（`mulSelected` 互斥），其他 MUL 指令无法发射；
- 若 DIV 结果是后续长依赖链的起点，整个依赖树被串行化。

srcWithMext 中 M 扩展指令占约 1.76%（静态），DIV/REM 类型若频繁出现，每次均付出 34 周期代价。

---

### E. Decode Packet-Split 前端损失（P5）

#### RTL 证据

**文件：`rtl/core/DecodeStage/DecodeStage.sv`**

```
// packet-split 条件（具体行号由 multiBranch/multiStore/serialSplit 计算）：
splitPacket   = multiBranch || multiStore || serialSplit;
ctrl.idStallReq = idStallReqReg || replayValid || splitPacket;

// split 时：lane0 正常前送，lane1 存入 replaySlot，下周期回放
// replayValid 状态寄存器使前端再 stall 1 拍
```

**文件：`rtl/core/BasicTypes.sv`**

```
WAY_NUM = 2  // fetch 2 指令/周期
PC_STEP = 8  // 每次取指步长 8 字节
```

#### 根因分析

Decode 对以下情况进行 packet split，每次浪费 1 拍前端吞吐：

| 触发条件 | 处理方式 |
|---|---|
| 同一 packet 有 2 条分支（multiBranch） | lane0 过，lane1 下周期回放 |
| 同一 packet 有 2 条 store（multiStore） | lane0 过，lane1 下周期回放 |
| serial 与普通指令共存（serialSplit） | serial 单独发射，浪费 1 拍 |

静态分析（srcWithMext.dump）：multi_branch packet ≈ 2.98%，multi_store ≈ 3.97%，serial_with_other ≈ 1.72%。  
动态上对 `srcWithMext` 来说 split 不是第一主因，但对 `srcSmoke`（分支密度高）损耗更大。

---

### F. 分支预测弱 + 全后端恢复代价高（P6）

#### RTL 证据

**文件：`rtl/core/PreFetchStage/BPU.sv`**（无 RAS 结构）

```
// BPU 内部：BTB(256 项直接映射) + BHB(锦标赛预测器)
// 无 Return Address Stack。JALR 按普通间接分支处理
// 向后跳转启发（btbTarget < lookupPc）预测 taken，但 target 仍靠 BTB
```

**文件：`rtl/core/CommitStage/RecoveryManager.sv`**

```
行 41-42:  RM_IDLE: if (commitRecoveryReq.valid) begin
               recoveryReg <= commitRecoveryReq;   // 本周期 commit 检测到 miss
               state <= RM_EMIT;
           end
行 66:     self.recoveryInfo = recoveryReg;        // 下一周期才生效
// 即：miss 检测 → +1 拍 → flush 生效
```

**文件：`rtl/core/CommitStage/CommitStage.sv`**

```
// branch miss 在 ROB commit 时检测（非 EX 时）：
行 149-155:  if (entry.isBranch) begin
                 update_bpu(entry);
                 if (entry.isMiss) begin
                     request_branch_miss_recovery(entry);
                     stopCommit = 1;
                 end
             end
```

#### 根因分析

**恢复代价分析**：  
分支 miss 在 CommitStage 检测（流水线末尾）。RecoveryManager 引入 1 拍额外延迟（行41-42，行66），flush 在 miss 后 2 拍生效。  
流水线深度 ≈ 11 级（PF→IF→ID→RN→DS→IS→RR→EX→WB→Commit）。  
每次分支 miss 惩罚周期约为 **12-13 拍**（从 commit 检测到前端重新取到正确指令）。

**无 RAS 的代价**（srcSmoke 实测）：
```
JALR miss_rate = 50.0%（400067 次中 200064 次 miss）
conditional miss_rate = 25.9%
```
JALR 典型场景为函数返回（`ret`），无 RAS 导致 return address 靠 BTB 预测，BTB 为直接映射容易被同 index 的其他 JALR 替换，命中率约 50%。对 call-heavy workload（如 srcSmoke 调用软件除法 helper），这是重大性能损失。

对 `srcWithMext`（200k 抽样）：recovery_cycles=131，branch_miss_count=130，影响较小（< 0.1%）；但对 `srcSmoke` 分支 miss 是主要瓶颈。

---

### G. 仅 WB-only 旁路（P7）

#### RTL 证据

**文件：`rtl/core/WriteBackStage/Bypass.sv`**

```
// Bypass 数据来源：WriteBackStage 当前周期的 wbForward[10]（5×WAY_NUM 端口）
// 无 EX-to-EX forwarding
// 消费者（ALU/BRC/MEM/MUL/SYS execute stage）在 EX 开始时查询 Bypass
```

**文件：`rtl/core/ReadRegStage/RegFile.sv`**

```
// PRF 写端口：negedge clk（WriteBack 时写）
// PRF 读端口：异步（组合读）
// 同周期写+读：PRF 写在 negedge，读在 posedge，不能同拍完成
```

#### 根因分析

当前 bypass 路径：  
`WB 阶段（cycle N）写 wbForward → EX 阶段（cycle N+1 前）读 Bypass`

这意味着 ALU 生产者在 WB 的同一拍，消费者若在 EX，可以通过 WB→EX bypass 拿到正确数据。  
但如果消费者需要在 WB 之后才 issue（等 IQ wakeup），则需要额外 1 拍（issue→RR→EX 才能用 bypass）。

没有 EX-to-EX 旁路意味着：同周期两条指令如果 lane0 ALU 结果是 lane1 的输入，lane1 的 `srcRdy` 必须是已 ready 状态（来自上一周期 WB wakeup），而不能在 EX 内部直接用 lane0 的组合结果。

---

### H. Serial 指令全流水排干等待（补充说明）

#### RTL 证据

**文件：`rtl/core/RenameStage/RenameStage.sv`**

```
行 58:   backendDrained = ctrl.dsStageEmpty && ctrl.isStageEmpty && ctrl.rrStageEmpty &&
                          ctrl.exStageEmpty && ctrl.wbStageEmpty;
行 75:   serialPresent = 1'b1;  // 当前 packet 有 serial 指令
行 81:   localStall = resourceStall || chkptStall ||
                      (serialPresent && !backendDrained) ||  // serial 等全流水排干
                      (chkptCount > 1);
行 92:   ctrl.rnStallReq = localStall;
```

**文件：`rtl/core/CommitStage/CommitStage.sv`**

```
行 140-141:  if (entry.isSerial) begin
                 ctrl.serialBlock = 1'b1;  // 阻塞前端 Rename 及以上
             end
```

#### 根因分析

FENCE、FENCE.I、所有 CSR 指令、ECALL/EBREAK/MRET 均被标记为 serial。  
每条 serial 指令执行前，必须等 DS/IS/RR/EX/WB 全部排空（行58），然后才能进入 Rename。  
执行期间，CommitStage 持续拉 `serialBlock`（行141），阻止前端向 Rename 供应新指令。  
对 `srcWithMext` 的 CSR 密集初始化段（0.95% serial 指令），此代价显著。

---

## 优先级排序与根因总结

下表综合 RTL 证据和性能数据，对各瓶颈按实测影响力排序：

| 优先级 | 瓶颈名称 | 核心 RTL 位置 | 实测占比 | IPC 估算收益 | 修复难度 |
|---|---|---|---:|---:|---|
| **P1** | MEM load 返回全局 stall | ExecuteMemStage.sv:133,215 / Ctrl.sv:18-20 | 49.15% | +0.15~+0.35 | 中（需 result buffer） |
| **P2** | ROB 16项容量 + commit 保守 | BasicTypes.sv / CommitStage.sv:118-124 | rob_full 74.2% | +0.05~+0.15 | 低（扩ROB）/ 中（放开commit） |
| **P3** | MEM/MUL/DIV 等 WB wakeup | IssueQueue.sv:206 / DispatchStage.sv:192-193 | 间接：issue w2=0.28% | +0.05~+0.10 | 低（逐类校准delay_for） |
| **P4** | DIV 34 周期单路阻塞 | DispatchStage.sv:192 / ExecuteMulStage.sv | M 指令占 1.76% | +0.02~+0.05 | 低（不改 IP，仅校准） |
| **P5** | Decode packet-split | DecodeStage.sv: splitPacket | 静态 ~8% | +0.02~+0.05 | 中 |
| **P6** | 无 RAS + 全后端恢复 | BPU.sv（无RAS）/ RecoveryManager.sv:41-42 | srcSmoke 主因 | +0.03~+0.10 | 高（RAS） |
| **P7** | WB-only 旁路 | Bypass.sv | 间接依赖链 | +0.02~+0.05 | 高（EX-to-EX） |
| **P8** | Serial 全排干 | RenameStage.sv:58,81 / CommitStage.sv:141 | CSR 密集段 | +0.01~+0.02 | 低 |

---

## 具体优化方案

### 方案 1：引入 MEM load return result buffer（对应 P1）

**改动位置**：`rtl/core/ExecuteStage/ExecuteMemStage.sv`

**当前行为**（行133,215）：
```systemverilog
loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
ctrl.exStallReq   = loadReturnBlocked || loadAccessBlocked;
```

**改动思路**：增加 1-entry load return result buffer，load 返回结果先存入 buffer；若 WB lane 有空位则直接输出。这样 T2 load 返回时，即使 MEM pipe 有新 uop，不再立刻拉 `exStallReq`，只在 buffer 满且又有 load 返回时才 stall。

**具体改法**：

```systemverilog
// 新增字段（行 25 附近）
ExMemToWbPath memResultBuf;
logic         memResultBufValid;

// T2 处理（行 133 附近替换）
always_ff @(posedge clk) begin
    if (rst || ctrl.exPipe.flush) begin
        memResultBufValid <= 1'b0;
        memResultBuf      <= '0;
    end else if (loadMetaPipe1.valid) begin
        // 优先直接输出 lane0；否则存入 buffer
        if (!memResultBufValid) begin
            // 直接放入 lane0 输出，buffer 不需要
        end else begin
            memResultBuf      <= [T2 load result];
            memResultBufValid <= 1'b1;
        end
    end else if (memResultBufValid && [WB lane 有空]) begin
        memResultBufValid <= 1'b0;
    end
end

// 修改 loadReturnBlocked 定义：
// 改为：buffer 满 且 T2 又有 load 返回
loadReturnBlocked = loadMetaPipe1.valid && memResultBufValid && !ctrl.exPipe.flush;
```

**验证重点**：
1. `rv32ui-p-lw/sw/lb/lh/lbu/lhu/sb/sh` 全部 PASS
2. store-to-load forwarding（partial byte）正确性
3. `load_return_block_cycles` 下降
4. `store_commit_blocked_by_load_cycles` 不上升

**预期收益**：`load_return_block_cycles` 从 49.15% → < 10%，IPC 估算从 0.50 → 0.65~0.85

---

### 方案 2：扩大 ROB 并放开 Commit lane1 限制（对应 P2）

**改动位置 1**：`rtl/core/BasicTypes.sv`

```systemverilog
// 当前：
parameter ROB_DEPTH = 16;
// 改为：
parameter ROB_DEPTH = 32;  // 或 24，根据综合面积预算决定
```

注意：ROB 扩容会同步影响 `ROB.sv`（循环FIFO逻辑）和 `DispatchStage.sv`（push/full判断），参数化设计无需手工修改这些文件。

**改动位置 2**：`rtl/core/CommitStage/CommitStage.sv` 行 118-124

当前 `can_follow_complex_lane0` 拒绝 lane1 有 branch/store/serial/chkpt 的情况。放开步骤：

**步骤 2a**（低风险）：允许 lane1 为已正确预测的无 miss 分支后安全指令跟随，即放开 `!entry.chkptValid` 条件，改为只检查 `!entry.isMiss`。  

```systemverilog
// 行 74 周边：checkpointValid 的 commit 策略
// 改为：chkpt 有效但分支预测正确时，lane1 可跟随
function automatic logic can_follow_complex_lane0(input RobEntryPath entry);
    return entry.done &&
           !entry.exception &&
           !entry.isBranch &&
           !entry.isStore &&
           !entry.isSerial;
    // 移除 !entry.chkptValid 限制（checkpoint 在 commit 时已确认正确）
endfunction
```

**步骤 2b**（中风险）：允许 lane1 commit 正确预测的分支指令。需同步确保 BPU update、checkpoint free、FreeList free 在同周期内完成（当前 CommitStage 已有 lane1 BPU update 路径，需验证）。

**预期收益**：commit w2 从 0.17% → 15%+，IPC 估算 +0.05~+0.15

---

### 方案 3：为 MEM/MUL 校准预计唤醒 delay_for（对应 P3）

**改动位置**：`rtl/core/DispatchStage/DispatchStage.sv` 行 188-197 + `IssueQueue.sv` 行 206

**当前限制**（IssueQueue.sv:206）：
```systemverilog
if (self.IssuePopRes[i].entry.delay == ShiftType'(1)) begin  // 仅 ALU delay=1
    entries[j].srcAMatched <= 1'b1;
    entries[j].srcAShift   <= self.IssuePopRes[i].entry.delay;
end
```

**放开步骤**：先对 MUL（3拍）验证：

1. 写定向微测试（MUL-use pattern）：
   ```
   mul  a0, a1, a2    // T0 issue
   add  a3, a0, a4    // 依赖 a0，应在 T? issue
   ```
2. 在波形中确认 `mul WB forward` 发生在哪一拍（T+3 or T+4）；
3. 根据实测相位调整 `delay_for` 的 cycles 值（若 MUL WB 在 T+3，cycles=3 正确；若 T+4，需改为4）；
4. 确认后，将 IssueQueue.sv:206 的条件改为：
   ```systemverilog
   if (self.IssuePopRes[i].entry.delay != '0) begin  // 对所有 delay > 0 启用
   ```
5. 回归 `rv32um-p-mul/div`，确保正确性。

**MEM（load）同理**：load 实际 bypass 可用在 T+3（`loadMetaPipe1` 结果出来后 WB），但若加入 result buffer 后相位略有变化，需重新校准。

**预期收益**：load-use/mul-use 依赖链等待周期减少 1-2 拍，IPC 估算 +0.05~+0.10

---

### 方案 4：DRAM 读写公平仲裁（对应 P1 后续，防止 store 饥饿）

**改动位置**：`rtl/core/DramAccessIF.sv`（或 `myCPU.sv` 中仲裁逻辑）

当前读优先：
```systemverilog
readEn  = exReadEn;
writeEn = !exReadEn && storeWriteEn;
```

**改法**：加入 store aging 计数器，当 StoreBuffer head store 连续被 load 抢占超过阈值 N（建议 N=8）拍后，暂停 load 发起，优先 store commit：

```systemverilog
logic [3:0] storeStarveCnt;  // 饥饿计数
logic       storeForce;      // 强制优先 store

always_ff @(posedge clk) begin
    if (storeWriteEn && exReadEn)
        storeStarveCnt <= storeStarveCnt + 1;
    else
        storeStarveCnt <= '0;
end
assign storeForce = (storeStarveCnt >= 8) && storeWriteEn;

assign readEn  = exReadEn && !storeForce;
assign writeEn = storeWriteEn && (!exReadEn || storeForce);
```

**预期收益**：防止方案1 实施后 store commit 被长期压制，保持 StoreBuffer 水位稳定

---

### 方案 5：增加 Return Address Stack（对应 P6，srcSmoke 专项）

**新建文件**：`rtl/core/PreFetchStage/RAS.sv`  
**修改文件**：`rtl/core/PreFetchStage/BPU.sv`

**设计要点**：

1. RAS 深度建议 8-16 项（圆形缓冲），checkpoint 时快照 RAS TOS pointer。
2. 识别规则：
   - Call：`JAL rd, offset`（rd=x1 或 x5）→ push `pc+4`
   - Return：`JALR x0, 0(x1)` 或 `JALR x0, 0(x5)` → pop，使用 RAS TOS 作为预测 target
3. 与 BTB/BHB 整合：return 类 JALR 不查 BTB，直接用 RAS top 作 target
4. 恢复：branch miss 时需回滚 RAS pointer（通过 checkpoint 保存/恢复）

**预期收益（srcSmoke）**：JALR miss 从 50% → < 5%，branch_miss_count 减少约一半，IPC 估算 +0.03~+0.08

---

### 方案 6：Decode 多 store packet 不拆包（对应 P5）

**改动位置**：`rtl/core/DispatchStage/StoreBuffer.sv` + `DispatchStage.sv`

当前限制：每周期 StoreBuffer 只能分配 1 项（`storeCount == 1 && storeBuffer.allocRdy`），导致 multi_store packet 被拆包。

**改法**：给 StoreBuffer 增加双路分配端口（`allocReq[2]`），Dispatch 时同周期为两条 store 各分配一个 StoreBuffer slot：

```systemverilog
// StoreBuffer.sv：增加双分配支持
input StoreBufferAllocPath allocReq[2],   // 原来是 [1]
output logic [1:0] allocRdy,
// 当 freeCount >= 2 时，两路均可分配
```

同步修改 `DispatchStage.sv` 取消 `multiStore` 的 split 条件，允许两条 store 同周期 dispatch。

**注意**：需同步修改 `DecodeStage.sv` 的 `splitPacket` 条件，移除 `multiStore` 触发。

**预期收益**：multi_store split（静态 ~4%）消除，前端吞吐 +1-2%，IPC 估算 +0.01~+0.03

---

## 推荐执行顺序

```
阶段 1（最优先，中等风险）
  → 方案 1：MEM load return result buffer
  → 方案 4：DRAM store fairness（配合方案1，防回退）
  → 回归：rv32ui load/store，srcWithMext 200k 周期
  → 观测：load_return_block_cycles / rob_full_cycles / store_commit_blocked_by_load_cycles

阶段 2（低风险，确定收益）
  → 方案 2a：ROB 扩容 16→32
  → 方案 3：MUL 预计唤醒校准（先 mul，再 load）
  → 回归：rv32um-p-mul/div，srcWithMext 200k 周期

阶段 3（针对 srcSmoke，中等风险）
  → 方案 5：RAS
  → 回归：srcSmoke 完整 PASS + rv32ui-p-jalr

阶段 4（中等风险，酌情）
  → 方案 2b：放开 lane1 branch commit
  → 方案 6：双 store dispatch
  → 回归：rv32ui-p-sw + srcWithMext + srcSmoke

阶段 5（高风险，暂缓）
  → EX-to-EX 全旁路（Bypass.sv 大改，关键路径风险高）
```

---

## 预期总体收益估算

| 阶段 | 累积优化 | srcWithMext IPC 估算 | srcSmoke IPC 估算 |
|---|---|---:|---:|
| 基线（当前） | — | 0.50 | 0.42 |
| 阶段 1 后 | MEM result buffer + store fair | 0.65~0.80 | 0.45~0.50 |
| 阶段 2 后 | ROB 扩容 + MUL 预计唤醒 | 0.75~0.90 | 0.50~0.60 |
| 阶段 3 后 | RAS | 0.75~0.90 | 0.60~0.75 |
| 阶段 4 后 | lane1 branch commit + 双 store | 0.80~1.00 | 0.65~0.80 |

注：上述估算基于性能桶分析的线性叠加，实际收益因瓶颈交互而不完全线性。每阶段后应重新跑性能桶，根据新的主瓶颈调整下一阶段计划。

---

## 附：验证回归矩阵

| 优化方案 | 必须通过的回归测试 |
|---|---|
| 方案1（MEM buffer） | rv32ui-p-lw/sw/lb/lh/lbu/lhu/sb/sh，rv32ui-p-store，store-to-load forwarding |
| 方案2（ROB/commit） | rv32ui-p-simple/add/sub/and/or/jal，多分支场景 |
| 方案3（MUL wakeup） | rv32um-p-mul/mulh/mulhu/mulhsu，rv32um-p-div/rem |
| 方案4（DRAM fair） | rv32ui-p-sw，srcWithMext（store_commit_blocked不升高） |
| 方案5（RAS） | rv32ui-p-jalr，call-return 嵌套测试，srcSmoke |
| 方案6（双store） | rv32ui-p-sw，store buffer 顺序性验证 |

