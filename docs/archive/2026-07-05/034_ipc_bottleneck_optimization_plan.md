# srcWithMext IPC 瓶颈复盘与优化计划

## 背景

本轮基于新增 `perf.stalls/resources/mem_stalls/width` 结果，重新分析当前 `srcWithMext` 的 IPC 限制。目标是形成后续 RTL 优化计划，不在本文档对应步骤中直接修改 RTL。

当前重点样本：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=
```

结果为预期 TIMEOUT，但性能桶已经足够暴露当前短窗口瓶颈。

## 关键数据

`build/result/src/srcWithMext.json` 中的当前短窗口数据：

| 指标 | 值 | 占 200000 周期比例 |
| --- | ---: | ---: |
| `commit_count` | 99534 | - |
| `ipc` | 0.49767 | - |
| `frontend_stall_cycles` | 198171 | 99.09% |
| `rob_full_cycles` | 148405 | 74.20% |
| `load_return_block_cycles` | 98297 | 49.15% |
| `ex_stall_cycles` | 98297 | 49.15% |
| `is_stall_cycles` / `rr_stall_cycles` | 98297 | 49.15% |
| `store_commit_blocked_by_load_cycles` | 15 | 0.0075% |
| `recovery_cycles` | 131 | 0.0655% |
| `branch_miss_count` | 130 | - |

宽度分布：

| 阶段 | w0 | w1 | w2 | 平均宽度 |
| --- | ---: | ---: | ---: | ---: |
| dispatch | 149426 | 328 | 50246 | 0.5041 |
| issue | 100126 | 99319 | 555 | 0.5021 |
| commit | 100805 | 98856 | 339 | 0.4977 |

结论：当前机器实际稳定在“约每两拍一条”的节奏运行。二路能力几乎没有发挥，`issue/commit` 平均宽度和 IPC 基本一致。

## 主要瓶颈判断

### 1. 第一瓶颈：MEM load 返回冲突被扩散成全局后端 stall

对应 RTL：

- `rtl/core/ExecuteStage/ExecuteMemStage.sv`

```systemverilog
loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
ctrl.exStallReq = loadReturnBlocked || loadAccessBlocked;
```

当前行为：

```text
上一条 load 两拍后返回
  -> 当前 MEM pipe 中只要有任意有效 uop
  -> loadReturnBlocked=1
  -> exStallReq=1
```

然后在 `rtl/core/Ctrl.sv` 中：

```systemverilog
backendBlock = ctrl.isStallReq | ctrl.rrStallReq |
               ctrl.exStallReq | ctrl.wbStallReq;
frontendBlock = ctrl.serialBlock | backendBlock | ctrl.robFull | ...

ctrl.isPipe = '{stall: ctrl.isStallReq | ctrl.rrStallReq | ctrl.exStallReq, ...};
ctrl.rrPipe = '{stall: ctrl.rrStallReq | ctrl.exStallReq, ...};
ctrl.exPipe = '{stall: ctrl.exStallReq, ...};
```

因此一个 MEM 局部返回冲突会冻结 IS/RR/EX，并进一步反压 PF/IF/ID/RN/DS。

这解释了当前统计：

```text
load_return_block_cycles = ex_stall_cycles = is/rr_stall_cycles = 98297
```

也解释了 IPC 接近 0.5：load-heavy 阶段变成“发起/推进一拍，返回冲突停一拍”的节奏。

### 2. 第二瓶颈：ROB full 主要是后端停顿的放大结果

对应 RTL：

- `rtl/core/DispatchStage/DispatchStage.sv`
- `rtl/core/DispatchStage/ROB.sv`
- `rtl/core/CommitStage/CommitStage.sv`

Dispatch 使用 ROB free count 判断资源：

```systemverilog
ctrl.robFull = packetValid && (int'(rob.RobFreeCount) < validCount);
resourceReady = !ctrl.robFull && ...
ctrl.dsStallReq = packetValid && !ctrl.dsPipe.flush && !resourceReady;
```

Commit 遇到 ROB head 未完成时停止：

```systemverilog
if (!entry.done) begin
    stopCommit = 1'b1;
end
```

当前 `rob_full_cycles=148405` 很高，但它不是孤立原因。结合 `load_return_block_cycles=98297` 看，更合理的链路是：

```text
MEM 返回冲突频繁冻结后端
  -> ROB 中的 load/MEM 相关 uop 完成节奏慢
  -> head 或近 head entry 不能持续 pop
  -> ROB free count 不足
  -> Dispatch 停
  -> frontend 几乎全程 stall
```

当前还缺一类关键计数：ROB head 未提交的具体原因。仅有 `robFullCycles` 只能说明窗口满，不能说明 head 在等 load、MUL/DIV、store commit、serial，还是 branch recovery。

### 3. 当前不是分支预测主导

当前短窗口：

```text
branch_count = 236
branch_miss_count = 130
recovery_cycles = 131
```

分支 miss rate 看起来高，但总量太小。即便每次 miss 损失 10 cycle，也只有约 1300 cycle，远小于 `load_return_block_cycles=98297`。

因此针对当前 `srcWithMext` 阶段，BPU/RAS 不是第一优先级。

注意：`srcSmoke` 不同，它的短窗口中 `branch_miss_count=5144`，branch/recovery 是更重要的问题。后续优化需要按 workload 分阶段判断，不应把 `srcSmoke` 的分支结论直接套到 `srcWithMext`。

### 4. StoreBuffer/DRAM 读优先不是当前短窗口主因，但仍是后续风险

`rtl/core/DramAccessIF.sv` 当前读优先：

```systemverilog
readEn = exReadEn;
writeEn = !exReadEn && storeWriteEn;
storeWriteReady = accessReady && !exReadEn;
```

若持续 load，StoreBuffer head store 可能被压住。当前短窗口：

```text
store_commit_blocked_by_load_cycles = 15
store_buffer_full_cycles = 12
```

说明在这个 200k 周期样本中，store commit 被读优先压住不是主因。但如果后续重新放开 load 返回合并或提高 load 发起连续性，该问题可能变成新的瓶颈。因此 MEM 优化不能只看 load，还要考虑 store 提交公平性。

### 5. IssueQueue 不是当前直接瓶颈，但存在中长期频率/扩展风险

当前 `issue_queue_full_cycles=3`，说明短窗口不是 IQ 满主导。

但 IssueQueue 选择逻辑有明显频率风险：

1. 每周期全队列扫描选择 older entry。
2. MEM 保序用 `memBlockedByOlder` 做全队列 older MEM 检查。
3. `has_same_cycle_raw()` 再扫 selected mask。
4. 若简单扩大 IQ 深度，组合路径会明显变长。

因此短期不建议靠“直接扩大 IQ”解决 IPC。先解决 MEM 返回/ROB head，再决定是否扩容。

## 优化计划

### 阶段 0：先补观测，不改控制

目标：确认 ROB full 的精确来源，避免盲改。

建议新增计数：

| 计数 | 定义 |
| --- | --- |
| `robHeadNotDoneCycles` | ROB head valid 但 `done=0`。 |
| `robHeadLoadWaitCycles` | head 未 done 且 entry 来源为 MEM load。当前 ROB entry 未保存 tube/subtype，需要扩展 ROB entry 或额外 trace。 |
| `robHeadMulWaitCycles` | head 未 done 且来源为 MUL/DIV。 |
| `robHeadStoreCommitWaitCycles` | head 是 store，done 但 `StoreBufferCommitReady=0`。 |
| `robHeadBranchMissCycles` | head branch done 且 miss，触发恢复。 |
| `robHeadSerialWaitCycles` | head serial 未完成或 serial block。 |
| `memLoadReturnWithCurrentMemCycles` | 现有 `load_return_block_cycles`，保留。 |
| `memCurrentValidWhenLoadReturnByLane` | load 返回时当前 MEM lane0/lane1 有效分布。 |
| `memLoadReturnCouldMergeOneCycles` | load 返回且当前 MEM pipe 只有 1 条 uop，可用于评估 result buffer/merge 收益上限。 |

如果不想扩展 ROB entry，可先在 CommitStage 输出 coarse reason：

```text
head valid && !done
head valid && done && isStore && !StoreBufferCommitReady
head valid && done && isBranch && isMiss
head valid && done && exception
```

更细的 load/MUL 区分需要 ROB entry 增加 `tubeType/subType` 或调试影子表。

优先级：最高。频率风险：低。因为只加寄存计数和 debug 输出，不进控制关键路径。

### 阶段 1：修 MEM load 返回阻塞，采用 result buffer 而不是简单合并

目标：解除 `loadMetaPipe1.valid && currentMemValid` 对全后端的 0.5 IPC 限制。

不建议直接恢复 031 的简单合并版本，因为它把“返回 load 和当前 MEM uop”硬塞到同一个组合输出选择里，容易和 StoreBuffer/DRAM 读优先产生新冲突。

推荐方案：给 MEM stage 增加一个很小的 load return result buffer。

概念：

```text
T2 load 返回
  -> 若 WB lane 可直接输出，则输出
  -> 否则写入 memResultBuf

后续周期
  -> memResultBuf 优先占用 MEM->WB 输出 lane
  -> 当前 MEM pipe 可以继续推进或只在 buffer 满时阻塞
```

最小版本：

1. `memResultBuf` 1 entry，保存 `ExMemToWbPath`。
2. load 返回优先进入 buffer 或输出。
3. `loadReturnBlocked` 改为 `load return && buffer full && no output slot`。
4. 当前 MEM pipe 不再因为“任意 currentMemValid”被阻塞。

收益估计：

当前 `load_return_block_cycles=98297`。如果 result buffer 能消掉其中一半以上，理论 IPC 可能从约 0.50 提升到：

```text
有效周期减少约 50k
IPC ~= 99534 / (200000 - 50000) = 0.66
```

如果大部分都能消掉，并且 ROB/commit 不产生新瓶颈：

```text
IPC ~= 99534 / (200000 - 90000) = 0.90
```

实际不会线性达到 0.9，因为 ROB head、load-use 依赖、单 MEM issue、commit 保守策略会接手成为瓶颈。但这仍是当前最值得做的优化。

频率风险：中等。需要谨慎设计输出 mux 和 valid 优先级，避免把 MEM 组合路径拉长。建议 buffer 控制寄存化，优先保证 150MHz。

验证重点：

1. `rv32ui-p-lw/sw/lb/lh/lbu/lhu/sb/sh`。
2. store-to-load forwarding partial byte。
3. `srcWithMext` 短窗口 `load_return_block_cycles` 是否下降。
4. `store_commit_blocked_by_load_cycles` 是否上升。

### 阶段 2：给 DRAM load/store 仲裁加公平性或 store aging

目标：避免阶段 1 提高 load 连续性后，store commit 被长期压住。

当前 `DramAccessIF` 读优先：

```text
load read > store write
```

建议策略：

1. 当 StoreBuffer head store 已请求提交并连续被 load 抢占 N 次后，下一次优先 store。
2. 或者当 StoreBuffer 水位达到阈值，store 优先。
3. 保持 MMIO/DRAM 读延迟 metadata 对齐：load 被仲裁拒绝时，不能推进 `loadMetaPipe0`。

优先级：阶段 1 后。频率风险：低到中等。主要是仲裁条件，不应影响大数据路径。

### 阶段 3：校准并逐类放开预计唤醒

目标：减少 load-use、mul-use、div-use 依赖链等待 WB wakeup 的额外空泡。

当前 IssueQueue 只对 `delay==1` 启用预计唤醒。全类型启用曾导致 `rv32um-p-mul/div` 失败，说明当前 `delay_for()` 和真实结果可用相位不匹配。

建议顺序：

1. 增加定向微测试：
   - ALU-use
   - load-use
   - mul-use
   - div-use
2. 对每类画波形：
   - producer issue 周期
   - producer WB forward 周期
   - consumer issue/RR/EX 周期
   - consumer EX 输入是否拿到正确 bypass
3. 校准 `delay_for()`：
   - ALU 当前保守可用。
   - MEM load 需要结合 result buffer 后重新定义。
   - MUL/DIV 需要按 IP latency 和 `mulMetaPipe/divMetaPipe` 输出相位重新定。

频率风险：低到中等。预计唤醒本身只在 IQ 寄存更新路径；但如果同时加 EX-to-EX bypass，频率风险会变高。

### 阶段 4：再评估 commit 和窗口大小

阶段 1/2/3 后再看：

```text
rob_full_cycles
commit w0/w1/w2
issue w0/w1/w2
rob head reason
```

若仍然 ROB full 且 head 多数是长延迟 M/DIV/load，则考虑：

1. ROB 从 16 增到 24/32。
2. 但 IQ 不建议同步简单扩大，除非先优化选择逻辑。

若 commit w2 仍极低但 head done 足够多，则再考虑放开更多 lane1 commit 情况：

1. lane1 branch update 双端口或延迟 update queue。
2. lane1 store commit queue。
3. 更宽 checkpoint free。

这些都比阶段 1 更复杂，且频率/验证风险更高。

## 不建议优先做的方向

### 1. 直接扩大 IssueQueue

当前 IQ full 几乎没有出现。扩大 IQ 会加重选择逻辑和 MEM older scan 的组合路径，未必提升当前短窗口 IPC。

### 2. 先大改 BPU/RAS

`srcWithMext` 当前短窗口 recovery 很少。BPU 对 `srcSmoke` 重要，但不是当前 `srcWithMext` 这个瓶颈的第一解。

### 3. 直接恢复 031 简单合并

031 能降低一类局部 stall，但容易和读优先 DRAM/StoreBuffer 提交机会冲突。更推荐 result buffer + 仲裁计数，而不是硬合并输出 lane。

### 4. 立即做 EX-to-EX 全旁路

EX-to-EX bypass 可能提升依赖链，但会增加执行输入 mux 和比较网络，频率风险高。当前先把 MEM 返回全局 stall 解除，收益更确定。

## 推荐执行顺序

1. 新增 ROB head reason 与 MEM return merge opportunity 计数。
2. 短跑 `srcWithMext` 200k/1M，确认 head reason 分布。
3. 实现 1-entry MEM load return result buffer。
4. 回归 rv32ui load/store 与 rv32um。
5. 短跑 `srcWithMext`，比较：
   - IPC
   - `load_return_block_cycles`
   - `rob_full_cycles`
   - `store_commit_blocked_by_load_cycles`
   - `issue/commit width`
6. 若 store 被压住，增加 DRAM store aging/fairness。
7. 再做 load-use/MUL/DIV 预计唤醒校准。

## 预期阶段收益

| 阶段 | 乐观收益 | 风险 |
| --- | --- | --- |
| 阶段 0 计数 | 不直接提升 IPC | 低 |
| 阶段 1 MEM result buffer | `srcWithMext` IPC 0.50 -> 0.65~0.85 | 中 |
| 阶段 2 store fairness | 防止阶段 1 引入 store 饥饿 | 低到中 |
| 阶段 3 预计唤醒校准 | 对 load-use/MUL-use 阶段提升明显 | 中 |
| 阶段 4 ROB/commit 扩展 | 取决于前面解除后剩余瓶颈 | 中到高 |

当前最应避免的是在没有 ROB head reason 的情况下直接大改窗口或预测器；这会把频率风险和验证风险提前，而不一定命中 `srcWithMext` 当前 0.5 IPC 的真实瓶颈。
