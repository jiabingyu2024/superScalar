# srcSmoke SEG/counter 显示与 IPC 统计审查

> 后续更新：本文记录的是修复前的审查结论。`archive/2026-07-04/022_srcSmoke_seg_fix_and_ipc_breakdown.md` 已定位并修复 `perip_bridge` MMIO/counter 读返回相位问题，修复后 `srcSmoke` 最终 SEG 为 `0x37001456`。

## 背景

本次审查回应两个问题：

1. `srcSmoke` 最终八位 SEG 是否保持 `0x37xxxxxx`，低六位 `x` 是否对应 counter 的 ms 数。
2. 当前 `srcSmoke` IPC 约 0.42，对二路乱序 CPU 来说偏低，是否可能是 TB 统计问题。

## SEG/counter 结论

当前完整 `srcSmoke` 运行结果不是 `0x37001456` 形式。

已观测运行：

```text
make sim-src TEST=srcSmoke NO_BUILD=1
```

结果概要：

```text
status         = PASS
checker        = src_ledonly
cycles         = 72813551
counter_ms     = 1456
expected SEG   = 0x37001456
last SEG       = 0x00000000
last nonzero   = 0x37000000
SEG at LED     = 0x00000000
last LED       = 0x01221c08
```

这不是 JSON 截断问题。运行日志显示：

```text
cycle 2496      write SEG = 0x37000000
cycle 2569..    write counter start
cycle 72813116  write counter stop
cycle 72813424  write SEG = 0x00000000
cycle 72813551  write LED = 0x01221c08
```

也就是说，TB 没有观察到 `SEG=0x37001456`。`srcSmoke` 当前只是按旧 LED PASS signature 判定通过，不能等价说明完整 SEG/counter 显示协议通过。

## dump 侧核对

`data/srcSmoke/src_test.dump` 中可以看到三类相关函数：

```text
0x80200020  SEG 写：先写高两位测试条数，再可能读 SEG 后 OR 低位
0x80200040  LED 写：写旧 PASS/FAIL 图案
0x80200050  counter start/stop/read
```

实际轨迹表明当前程序运行路径没有在 counter stop/read 之后再写出 `0x37 + ms` 的最终 SEG 值，反而在 LED PASS 前写了 `SEG=0`。这更像程序路径/协议版本与“最终保持显示值”的期待不一致，或者 CPU 在收尾路径上跑到了不符合预期的显示清零路径；目前没有证据表明是 TB 把 `0x37001456` 截断成了 `0x37000000`。

## 本次 TB 输出增强

结果 JSON 新增：

```text
correctness.seg.expected_counter_value
correctness.seg.current_matches_counter_ms
correctness.seg.pass_display_matches_counter_ms
correctness.seg.value_at_last_led_matches_counter_ms
perf.branch_miss_rate
```

编码规则：

```text
expected_counter_value = 0x37000000 | bcd6(counter_ms)
```

例如 `counter_ms=1456` 时，期望值为 `0x37001456`。

三个 match 字段分别对应：

| 字段 | 用途 |
| --- | --- |
| `current_matches_counter_ms` | 最终 SEG 是否还保持期望显示值。 |
| `pass_display_matches_counter_ms` | 最后一次非零 SEG 是否曾经写过期望显示值。 |
| `value_at_last_led_matches_counter_ms` | 最后一次 LED 写入时 SEG 是否为期望显示值。 |

后续若要把 `srcSmoke` 也纳入严格 SEG/counter 协议，可以将 profile 从 `ledonly` 切到更严格 checker，或新增 `ledseg_counter_final` checker。但当前本次修改不改变既有 `srcSmoke` PASS 门槛，只把事实显式暴露出来。

## IPC 统计结论

当前 IPC 低不是 TB 用错 wall-clock 或 MMIO 周期导致的。`perf.ipc` 的来源是：

```text
perf.ipc = core PerfIF commitCnt / sim cycles
```

`PerfIF` 位于 `rtl/core/core.sv`：

- `cycle` 每个 core 时钟周期加一。
- `commitCnt` 按两路 `cmStageIF.commitValid[i]` 累加。
- `branchCnt` 按 commit 阶段分支更新累加。
- `branchMissCnt` 按 commit 阶段 branch miss 累加。

`student_top` 只在 `VERILATOR_TB` 下把这些信号透出，TB 不重新推断提交数。因此当前 IPC 应理解为 core 实际提交密度。

当前 `srcSmoke` 已观测性能概要：

```text
cycles             = 72813551
commit_count       = 30758260
ipc                = 0.422425
branch_count       = 12854992
branch_miss_count  = 3317701
branch_hit_rate    = 0.741913
branch_miss_rate   = 0.258087
```

对二路乱序核来说，0.42 IPC 明显偏低，但首要线索是分支密度和 miss 率都很高：约 41.8% 的提交指令是分支，分支 miss 率约 25.8%。结合当前 RTL，低 IPC 有几个合理来源：

1. `CommitStage` 中分支提交后会 `stopCommit=1`，同周期不继续提交后续 ROB 项。
2. branch miss 走 `REC_BRANCH_MISS`，会 frontend/backend flush，代价较高。
3. BPU 只在 commit 阶段更新，遇到短循环/频繁跳转时学习滞后明显。
4. store 提交需要等待 StoreBuffer commit ready，store 在 commit 阶段也会停止继续提交。
5. 当前 fetch/issue/mem 路径虽然是二路框架，但资源冲突、load-use、单 memory path、ROB/IssueQueue 容量都会让平均提交宽度远低于 2。

因此，当前“IPC 低”更像真实微架构性能问题或 workload 分支特性问题，不是 TB 结果统计错。后续优化应先分解：

```text
IPC = commit_count / cycles
branch miss penalty = branch_miss_count 对 cycles 的贡献
commit 宽度利用率 = commit_count / (2 * cycles)
```

再增加更细的 RTL perf counter，例如：

- `fetch_valid_count`
- `dispatch_count`
- `issue_count`
- `rob_head_not_done_cycles`
- `store_commit_stall_cycles`
- `branch_recovery_cycles`
- `mem_wait_cycles`

这些计数能判断低 IPC 是前端供给不足、分支恢复过重、访存阻塞，还是 commit 保守策略导致。
