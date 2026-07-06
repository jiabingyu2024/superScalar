# 阶段 1/2 后 srcWithMext IPC 仍低的根因再定位

> 日期：2026-07-05  
> 输入样本：`build/result/src/srcWithMext.json`，100,000,000 cycle 长窗口  
> 当前 RTL：已完成 `035_ipc_lt05_root_cause_and_optimization.md` 中阶段 1/2，即 MEM result buffer、DRAM store fairness、ROB 32、MUL 预计唤醒校准

---

## 1. 结论摘要

当前 `srcWithMext` 长窗口 IPC = **0.5455**。这不是阶段 1/2 没生效，而是短窗口瓶颈被消掉后，长时间 steady-state 暴露出新的第一瓶颈：

```text
IssueQueue 满 -> Dispatch/前端长期停顿 -> Issue 平均宽度只有 0.5487 -> Commit 只能跟着低吞吐运行
```

最关键证据：

| 指标 | 当前 100M 值 | 占周期比 |
|---|---:|---:|
| IPC | 0.545538 | - |
| frontend_stall_cycles | 72,042,283 | 72.04% |
| ds_stall_cycles | 71,964,714 | 71.96% |
| issue_queue_full_cycles | 71,983,804 | 71.98% |
| rob_full_cycles | 168 | 0.000168% |
| load_return_block_cycles | 0 | 0% |
| ex_stall_cycles | 0 | 0% |
| wb_stall_cycles | 0 | 0% |

因此当前不是 MEM 返回冲突、ROB full、EX/WB 后端停顿或分支恢复主导，而是 **IQ 容量/唤醒/选择导致的调度窗口被占满**。

---

## 2. 阶段 1/2 的效果与长窗口差异

阶段 1/2 后，200k 短窗口曾达到 IPC 0.7658；但当前 100M 长窗口 IPC 下降到 0.5455。二者不矛盾：

| 指标 | 阶段前 200k | 阶段后 200k | 当前 100M |
|---|---:|---:|---:|
| IPC | 0.4977 | 0.7658 | 0.5455 |
| load_return_block_cycles | 98,297 | 0 | 0 |
| rob_full_cycles | 148,405 | 168 | 168 |
| issue_queue_full_cycles | 3 | 118,083 | 71,983,804 |
| issue w2 cycles | 555 | 39,121 | 5,416,132 |

解释：

1. 200k 短窗口主要覆盖早期阶段，MEM result buffer 能直接消掉 load return 全局 stall。
2. 100M 长窗口进入实际 steady loop 后，IQ 长期填满；issue 端平均只吐 0.5487 条/周期。
3. ROB 扩到 32 后，ROB 不再顶住 Dispatch，但 IQ 仍只有 16 项，成为新的最小乱序窗口。

---

## 3. 当前数据流瓶颈链

当前平均宽度：

| 阶段 | w0 | w1 | w2 | 平均宽度 |
|---|---:|---:|---:|---:|
| Dispatch | 72,199,704 | 163,864 | 27,636,432 | 0.5544 |
| Issue | 50,545,442 | 44,038,426 | 5,416,132 | 0.5487 |
| Commit | 57,953,260 | 29,539,661 | 12,507,079 | 0.5455 |

关键观察：

1. `issue average = 0.5487` 与 `commit average = 0.5455` 基本相等，说明 Commit 不是当前第一限速点。
2. `issue w0 = 50.55%`，但同一时间 `issue_queue_full = 71.98%`。这说明 IQ 很多周期是“满但无可发射项”，不是“没有指令可调度”。
3. `dispatch average = 0.5544` 也贴近 issue/commit，说明前端被 IQ 反压后，只能跟随 issue 的低吞吐节奏。

当前实际链路：

```text
长延迟/依赖 uop 留在 IQ
  -> IQ 16 项很快填满
  -> DispatchStage 看到 IssueFreeCount < packet validCount
  -> ctrl.issueQueueFull = 1
  -> Ctrl 把 issueQueueFull 扩散到 frontendBlock 和 dsPipe.stall
  -> 前端/Dispatch 72% 周期停顿
  -> Issue 平均宽度只有 0.55
  -> Commit/IPC 被同步压低到 0.545
```

---

## 4. RTL 证据

### 4.1 IQ 深度仍是 16

`rtl/core/DispatchStage/IssueTypes.sv:16`

```systemverilog
localparam ISSUE_QUEUE_DEPTH = 16;
```

阶段 2 已把 ROB 扩到 32：

`rtl/core/BasicTypes.sv:47`

```systemverilog
localparam ROB_DEPTH = 32;
```

当前后端窗口变成：

```text
ROB = 32
IQ  = 16
```

这意味着 Dispatch 可以有更大的 ROB 容量，但真正可等待执行的调度窗口仍只有 16 项。对 load-use、MUL-use、DIV-use 这种依赖密集流，IQ 会先满。

### 4.2 Dispatch 因 IQ free count 不足整体停顿

`rtl/core/DispatchStage/DispatchStage.sv:106-111`

```systemverilog
ctrl.robFull = packetValid && (int'(rob.RobFreeCount) < validCount);
ctrl.issueQueueFull = packetValid && (int'(issueQueue.IssueFreeCount) < validCount);

resourceReady = !ctrl.robFull &&
                !ctrl.issueQueueFull &&
                (storeCount == 0 || (storeCount == 1 && storeBuffer.allocRdy));
```

`rtl/core/DispatchStage/DispatchStage.sv:174-176`

```systemverilog
ctrl.dsStallReq = packetValid && !ctrl.dsPipe.flush && !resourceReady;
dispatchEn = packetValid && !ctrl.dsPipe.flush && !ctrl.dsPipe.stall && resourceReady;
```

含义：

1. 若当前 packet 有 2 条有效 uop，但 IQ 只剩 1 个 free slot，整包不 dispatch。
2. 当前没有“只 dispatch lane0、lane1 replay”的后端分发策略。
3. 当 IQ 长期接近满时，即使每隔一拍释放 1 项，也可能因为 `validCount=2` 而继续 stall。

### 4.3 IQ full 被全局前端反压

`rtl/core/Ctrl.sv:20-30`

```systemverilog
frontendBlock = ctrl.serialBlock | backendBlock | ctrl.robFull | ctrl.issueQueueFull |
                ctrl.freeListEmpty | ctrl.idStallReq | ctrl.rnStallReq |
                ctrl.dsStallReq;

ctrl.pfPipe = '{stall: frontendBlock, flush: 1'b0};
ctrl.ifPipe = '{stall: frontendBlock, flush: 1'b0};
ctrl.idPipe = '{stall: frontendBlock, flush: 1'b0};
ctrl.rnPipe = '{stall: ctrl.serialBlock | ctrl.rnStallReq | ctrl.dsStallReq | ctrl.robFull |
                      ctrl.issueQueueFull | ctrl.freeListEmpty,
                flush: 1'b0};
ctrl.dsPipe = '{stall: ctrl.dsStallReq | ctrl.robFull | ctrl.issueQueueFull,
                flush: 1'b0};
```

因此 `issueQueueFull` 一旦拉高，会直接阻塞 PF/IF/ID/RN/DS。当前 72.04% 的 frontend stall 与 71.98% 的 issueQueueFull 高度一致。

### 4.4 IQ 满但无法发射的原因：ready/选择约束很多

`rtl/core/DispatchStage/IssueQueue.sv:78-85`

```systemverilog
if (valid[j] && !selected[j] && !entries[j].issued &&
    entries[j].srcARdy && (entries[j].srcBRdy || entries[j].srcBIsImm) &&
    !has_same_cycle_raw(entries[j], selected) &&
    !memBlockedByOlder[j] &&
    !(memSelected && entries[j].tubeType == TUBE_TYPE_MEM) &&
    !(mulSelected && entries[j].tubeType == TUBE_TYPE_MUL) &&
    !(i != 0 && entries[j].tubeType == TUBE_TYPE_MUL)) begin
```

一条 IQ entry 要发射，需要同时满足：

1. 两个源操作数 ready；
2. 与同周期已选 uop 没有 RAW；
3. MEM uop 没有更老 MEM uop 阻塞；
4. 本周期还没选过 MEM；
5. 本周期还没选过 MUL；
6. MUL 只能在 issue lane0 发射。

这组条件很保守。结果就是：IQ 可能有 16 项 valid，但 ready 且可被当周期选择的很少，导致 `issue w0` 高达 50.55%。

### 4.5 MEM/MUL/DIV 预计唤醒仍未完全放开

当前 `delay_for()` 已给 MEM、MUL、DIV 设置预计延迟：

`rtl/core/DispatchStage/DispatchStage.sv:188-197`

```systemverilog
TUBE_TYPE_MUL: cycles = div/rem ? 34 : 4;
TUBE_TYPE_MEM: cycles = 3;
delay_for = ShiftType'(1) << (cycles - 1);
```

但 IssueQueue 预计唤醒白名单只有 ALU 和非 DIV/REM MUL：

`rtl/core/DispatchStage/IssueQueue.sv:25-28`

```systemverilog
predict_wakeup_allowed =
    (entry.delay == ShiftType'(1)) ||
    (entry.tubeType == TUBE_TYPE_MUL && entry.delay == (ShiftType'(1) << 3));
```

也就是说：

| Producer | 当前预计唤醒 |
|---|---|
| ALU/BRC 等 `delay==1` | 开启 |
| 非 DIV/REM MUL | 开启，delay 校准为 4 |
| MEM load | 未开启，等真实 WB wakeup |
| DIV/REM | 未开启，等真实 WB wakeup |

`srcWithMext` 当前动态访存很重：

| 动态事件 | 次数 | 相对 commit |
|---|---:|---:|
| DRAM read | 13,382,683 | 24.53% |
| DRAM write | 3,133,557 | 5.74% |

因此大量 load producer 的消费者仍要等真实 WB wakeup；这些 consumer 会占住 IQ entry，形成“IQ 满但不 ready”的主因之一。

---

## 5. 已排除的旧瓶颈

### 5.1 MEM load return 全局 stall 已消除

当前：

```text
load_return_block_cycles = 0
ex_stall_cycles          = 0
```

RTL 上，load return 现在优先输出到 MEM->WB 空 lane，或进入 `memResultBuf`：

`rtl/core/ExecuteStage/ExecuteMemStage.sv:276-285`

```systemverilog
if (!memWbSlotUsed[0]) ...
else if (!memWbSlotUsed[1]) ...
else if (!memResultBufValid || memResultBufPop) ...
else begin
    loadReturnBlocked = 1'b1;
end
```

所以旧的“load 返回 + 当前 MEM uop = 全 EX stall”已经不是当前 IPC 低的原因。

### 5.2 ROB full 已消除

当前：

```text
rob_full_cycles = 168 / 100,000,000 = 0.000168%
```

ROB 32 足够覆盖当前长窗口，不再是第一瓶颈。

### 5.3 分支恢复不是主因

当前：

```text
branch_miss_count = 39,208
recovery_cycles   = 39,212 = 0.039%
```

即使按每次 miss 10-15 周期粗估，总损失也远小于 71.98M 的 IQ full 周期。JALR miss rate 仍高，但 JALR 只有 71 次，不影响 `srcWithMext` 当前长窗口。

### 5.4 StoreBuffer full 不是主因

当前：

```text
store_commit_blocked_by_load_cycles = 3,038,002 = 3.04%
store_buffer_full_cycles            = 68
```

读优先导致 store commit 等待仍存在，但 StoreBuffer 几乎没有满，不会解释 72% 的前端停顿。

---

## 6. 当前根因排序

### P1：IssueQueue 满且缺少 ready 项

证据：

```text
issue_queue_full_cycles = 71.98%
issue w0 cycles         = 50.55%
is/rr/ex/wb stall       = 0
```

判断：

IQ 中积压的是等待源操作数或被选择规则挡住的 uop。它不是后端流水 stall，而是调度窗口质量问题。

### P2：IQ 深度 16 与 ROB 32 不匹配

ROB 扩容后，系统能容纳 32 个 in-flight ROB entry，但只有 16 个能在 IQ 中等待执行。对当前访存比例和长延迟依赖，IQ 比 ROB 更早成为窗口边界。

注意：直接把 IQ 从 16 扩到 32 可能提升 IPC，但 IssueQueue 选择逻辑是全队列扫描，且有 `memBlockedByOlder` 的 O(N^2) MEM older 检查。综合频率风险比 ROB 扩容高。

### P3：MEM load 依赖仍等真实 WB wakeup

当前 load 动态占比约 24.53% commit。MEM result buffer 解决了返回端口冲突，但没有提前唤醒 load consumer。load-use consumer 仍会留在 IQ 中等待真实 WB，增加 IQ 占用时间。

### P4：调度选择策略过于统一和保守

当前所有 uop 共用一个 16-entry IQ，并用全局 oldest-first 选择。MEM、MUL、ALU/BRC/SYS 混在一起，选择条件又叠加：

1. MEM in-order；
2. 每周期最多 1 MEM；
3. 每周期最多 1 MUL；
4. MUL 只能 lane0；
5. 同周期 RAW 禁止双发；
6. oldest-ready 优先。

这会降低 `issue w2`，当前 `issue w2` 只有 5.42%。

### P5：Dispatch 不能部分接收 packet

若 IQ 剩 1 个空位而当前 packet 有 2 条，Dispatch 整体 stall。当前 IQ 长期接近满，这种 all-or-nothing 分发会放大 `issueQueueFull` 对前端的影响。

---

## 7. 需要补的观测计数

当前 perf bucket 已经足以定位到 IQ，但还不能精确区分 IQ full 的内部原因。建议下一步优先加以下计数，不先大改 RTL：

| 计数 | 定义 | 目的 |
|---|---|---|
| `iq_occupancy_sum` | 每周期 IQ valid entry 数累加 | 看 IQ 是否长期 15/16 满载 |
| `iq_full_free0_cycles` | packet valid 且 IQ free=0 | 区分真满 |
| `iq_full_free1_need2_cycles` | packet 2 条且 IQ free=1 | 评估 partial dispatch 收益 |
| `iq_no_ready_cycles` | IQ valid 但无 ready selectable entry | 验证“满但不 ready” |
| `iq_ready_count_sum` | 每周期 ready entry 数累加 | 看 ready 压力 |
| `iq_wait_srcA_cycles` / `iq_wait_srcB_cycles` | valid entry 源未 ready 累加 | 定位依赖等待 |
| `iq_wait_mem_producer_cycles` | consumer 等 load producer | 校准 MEM 预计唤醒收益 |
| `iq_mem_older_block_cycles` | ready MEM 被 older MEM 阻塞 | 看 MEM 保序损失 |
| `iq_same_cycle_raw_block_cycles` | lane1 因同周期 RAW 被挡 | 看双发损失 |
| `iq_mul_lane1_block_cycles` | MUL ready 但因 lane1 限制不能发 | 看 MUL 单 lane 损失 |
| `issue_by_tube_{alu,mem,mul,brc,sys}` | 实际 issue 类型分布 | 判断哪类管线吞吐低 |

如果只加一组，优先：

```text
IQ occupancy / ready_count / no_ready / full_free0 / full_free1_need2 / issue_by_tube
```

这些计数都不进控制关键路径，风险低。

---

## 8. 后续优化建议

### 建议 1：先做 IQ 观测计数

原因：当前第一瓶颈已经定位到 IQ，但还没区分是容量、依赖不 ready、MEM older、MUL lane 限制，还是 dispatch all-or-nothing。先补计数可以避免盲目扩 IQ。

### 建议 2：实验性把 IQ 16→24/32 做性能 A/B

目的：快速测上限。

注意：

1. 只作为性能实验，不建议直接带进综合收敛。
2. 当前 IssueQueue 组合选择逻辑随深度扩大明显变重：
   - alloc 扫描全队列；
   - issue 选择扫描全队列；
   - `memBlockedByOlder` 做 MEM-vs-MEM 全队列比较；
   - `has_same_cycle_raw()` 再扫 selected mask。
3. 若 IQ32 IPC 明显提升，说明容量确实是必要条件；正式实现应考虑分 bank / 分类型 issue queue。

### 建议 3：校准并放开 MEM load 预计唤醒

当前 MEM load consumer 等真实 WB。建议用波形校准：

```text
load issue cycle
load DRAM read grant cycle
load result direct-output / result-buffer cycle
WB forward valid cycle
consumer issue/RR/EX cycle
```

由于阶段 1 引入 result buffer，MEM load latency 可能是固定主路径 + 偶发 buffer 延迟。稳妥做法：

1. 先用保守 delay，例如比最短路径多 1 拍；
2. 或在 `memResultBuf`/load return 输出时给 IQ 发专门 early wakeup；
3. 不建议直接把现有 `TUBE_TYPE_MEM: cycles=3` 全量打开，之前长延迟预计唤醒已经导致过 M 扩展错误。

### 建议 4：支持 Dispatch partial accept

当 IQ free=1 且 packet 有 2 条时，只 dispatch lane0，把 lane1 replay 到下一周期。这个优化可降低 IQ 临界满载时的前端全停，但它不是根治项；如果 IQ 里大多数 entry 不 ready，partial accept 只能减少泡泡，不能把 issue 平均宽度拉到 1+。

### 建议 5：中期拆分 IssueQueue

如果计数证明 MEM/MUL/ALU 混队造成选择效率低，建议拆成：

```text
ALU/BRC/SYS IQ
MEM IQ
MUL/DIV IQ
```

好处：

1. 减少全队列扫描；
2. MEM older 只在 MEM queue 内处理；
3. lane/pipe 选择更清晰；
4. 更容易做 per-pipe ready count 和发射仲裁。

代价：Dispatch 分配、Payload 索引、年龄仲裁、flush/recovery 需要同步重构。

---

## 9. 当前不建议优先做的方向

1. **继续扩大 ROB**：`rob_full_cycles` 已经几乎为 0，ROB 不是当前瓶颈。
2. **继续优化 MEM result buffer**：`load_return_block_cycles=0`，旧 MEM 返回端口瓶颈已消除。
3. **优先做 RAS/BPU**：`srcWithMext` 当前分支恢复占比极低；RAS 对 `srcSmoke` 更重要。
4. **优先改 StoreBuffer fairness**：store 被 load 抢占有 3.04%，但 `store_buffer_full_cycles=68`，暂未扩散成前端主 stall。
5. **直接做 EX-to-EX 全旁路**：可能有收益，但关键路径/验证风险高；当前更直接的瓶颈是 IQ 满和调度等待。

---

## 10. 最短下一步计划

推荐下一轮按这个顺序：

1. 新增 IQ 观测计数：
   - occupancy
   - ready count
   - no-ready
   - full free0/free1
   - issue by tube
   - MEM older / same-cycle RAW / MUL lane1 block
2. 跑 `srcWithMext` 200k、1M、100M 三档，对比早期和 steady-state。
3. 做 IQ 16→24/32 的仿真实验，估算容量收益上限。
4. 若容量收益明显，再设计正式分 bank 或分类型 IQ。
5. 同步校准 MEM load 预计唤醒，优先减少 load-use consumer 在 IQ 中等待真实 WB 的停留时间。

当前一句话结论：

```text
阶段 1/2 已把 MEM/ROB 瓶颈移除；IPC 仍低，是因为 16 项统一 IssueQueue 在长窗口里被未 ready/受限 uop 填满，导致 72% 前端反压和仅 0.55 的 issue/commit 平均宽度。
```
