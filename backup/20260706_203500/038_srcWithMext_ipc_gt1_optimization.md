# srcWithMext IPC>1 优化记录

> 日期：2026-07-06  
> 目标：`srcWithMext` 小量/窗口内 IPC 至少超过 1，同时保持 RTL 可综合，避免不可控的长组合路径。

## 基线

最近一次 `srcWithMext` 结果：

| 指标 | 数值 |
| --- | ---: |
| cycles | 20,000,000 |
| commit_count | 10,563,639 |
| IPC | 0.528182 |
| issue_queue_full_cycles | 14,571,499 |
| frontend/id stall cycles | 14,584,060 |
| rn stall cycles | 14,568,553 |
| ds stall cycles | 14,567,782 |
| branch miss cycles | 8,066 |
| mem load return block | 0 |
| mem load access block | 0 |
| store commit blocked by load | 604,459 |

结论：当前 IPC 低的第一主因不是 EX/WB stall，也不是分支恢复；最大项是 IQ 资源反压导致 frontend/RN/DS 长期停住。`issue_queue_full_cycles` 占总周期约 72.9%，必须先拆分 Int/Mem/Mul 队列贡献。

## 观测增强

本轮新增 Verilator perf 字段：

1. `resources.issue_queue_full_breakdown.int_cycles`
2. `resources.issue_queue_full_breakdown.mem_cycles`
3. `resources.issue_queue_full_breakdown.mul_cycles`
4. `width.issue_mix.int_uops`
5. `width.issue_mix.mem_uops`
6. `width.issue_mix.mul_uops`

实现方式：`DispatchStage` 生成 per-queue full 标志，经 `CtrlIF` 传给 `core` 计数；`IssueStage` 输出按 `tubeType` 统计实际发射 uop 数。该观测只增加计数器和 `VERILATOR_TB` debug 端口，不改变核心调度行为。

## 假设队列

| 假设 | 判据 | 后续修复方向 |
| --- | --- | --- |
| MemIssueQueue 太浅/单发导致 backpressure | `mem_cycles` 占主导，`mem_uops` 接近 1/cycle 上限或 head 常等待 | 加深 MEM FIFO、允许同拍 pop+push、必要时做 load/store 分流或更宽 MEM issue。 |
| IntIssueQueue 被依赖链/选择策略填满 | `int_cycles` 占主导，`int_uops` 低于期望 | 优化预计唤醒、选择补选、增加 INT depth 或减少全局 age 仲裁损失。 |
| MulIssueQueue 长延迟堵塞 | `mul_cycles` 占主导，`mul_uops` 很低且 M 类密度高 | MUL/DIV 分队列或增加保守 reservation，避免 DIV/REM 堵住 MUL。 |
| Dispatch 整包阻塞放大局部 full | 单队列 full 时 w0 很高，另两个队列还有空间 | 考虑 partial dispatch 或 lane replay，但要评估复杂度和时序。 |

## 迭代记录

### 1. 观测增强

状态：已实现，并完成 `srcWithMext` 500,000-cycle 窗口测试。

命令：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果：

| 指标 | 数值 |
| --- | ---: |
| IPC | 0.789444 |
| issue_queue_full_cycles | 295,695 |
| int full cycles | 0 |
| mem full cycles | 295,695 |
| mul full cycles | 0 |
| int issued uops | 236,577 |
| mem issued uops | 124,942 |
| mul issued uops | 36,917 |

结论：低 IPC 第一主因已定位为 `MemIssueQueue` 反压。MEM 实际 issue 只有约 0.25 uop/cycle，不是 MEM 执行端口满载，而是 4 项严格 FIFO 在队头未 ready 或访存依赖等待时很快填满，随后 Dispatch 整包阻塞，把 Int/Mul 可执行工作也挡在 RN/DS 前面。

### 2. MemIssueQueue 低风险扩容

执行：

1. `MEM_ISSUE_QUEUE_DEPTH` 从 4 提高到 16。
2. 暂未引入同周期 pop->push freeCount 反馈，避免在同一轮增加跨 issue/dispatch 的组合反馈路径。
3. 不改变 MEM 严格 FIFO/head-ready 语义，不增加 MEM 发射宽度。

结果：

| 指标 | MEM depth=4 | MEM depth=16 |
| --- | ---: | ---: |
| IPC | 0.789444 | 0.789446 |
| issue_queue_full_cycles | 295,695 | 30 |
| mem full cycles | 295,695 | 30 |
| rob_full_cycles | 138 | 293,111 |
| free_list_empty_cycles | 0 | 121,711 |
| issue w2 cycles | 50,684 | 63,329 |

结论：MEM 队列深度 4 是明显表层瓶颈，但不是最终 IPC 根因。加深后 dispatch 不再主要被 MEM IQ full 阻塞，ROB 和 FreeList 很快被占满，说明退休端被 ROB head 未完成或 store commit 顺序卡住。下一步需要按 ROB head 类型拆分。

### 3. ROB head 阻塞观测

新增字段：

1. `resources.rob_head_block.not_done_cycles`
2. `resources.rob_head_block.not_done_int_cycles`
3. `resources.rob_head_block.not_done_mem_cycles`
4. `resources.rob_head_block.not_done_mul_cycles`
5. `resources.rob_head_block.not_done_other_cycles`
6. `resources.rob_head_block.store_commit_wait_cycles`

实现方式：ROB entry 增加 `tubeType` 字段，由 Dispatch 写入；`core` 在 perf 计数阶段观察 `robIF.RobPopRes[0]`，统计 head valid 但未 done 的类型，以及 head store 已 done 但 StoreBuffer 尚不能 commit 的周期。
