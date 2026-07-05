# srcSmoke IPC 偏低的 RTL 深度分析

## 问题

当前 `srcSmoke` 在二路乱序核上的 IPC 约 `0.422`。用户对比顺序单发流水线约 `0.75` IPC，认为二发乱序不应更低，并提出重点怀疑：

- 分支预测处理是否代价过大。
- serial 要求、提交规则是否过保守。
- 如果分支预测率提升到 90% 以上，IPC 是否会大幅提升，是否能到 1 以上。

## 当前实测数据

来自 `build/result/src/srcSmoke.json`：

```text
cycles             = 72,814,875
commit_count       = 30,758,700
ipc                = 0.422423
branch_count       = 12,855,156
branch_miss_count  = 3,317,770
branch_hit_rate    = 0.741911
branch_miss_rate   = 0.258089
```

分支分类：

| 类型 | count | miss_count | miss_rate |
| --- | --- | --- | --- |
| conditional | 12,055,013 | 3,117,626 | 0.258617 |
| JAL | 400,076 | 80 | 0.000199962 |
| JALR | 400,067 | 200,064 | 0.500076 |

动态分支比例：

```text
branch_count / commit_count = 41.8%
```

这说明当前 workload 极端分支密集，不能按普通顺序算术循环预期二发 IPC。

## RTL 中导致 IPC 低的关键机制

### 1. Branch miss 是全后端恢复

`CommitStage.request_branch_recovery()`：

```text
frontendFlush = 1
backendFlush  = 1
rob.RobFlush  = 1
storeBuffer.flush = 1
```

也就是说每次 miss 不只是修正 PC，而是清掉前端和后端投机窗口。二路乱序靠窗口吸收延迟，但高 miss 率会反复清空窗口，使后端持续重新热身。

### 2. 恢复基于 commit，且 RecoveryManager 再打一拍

路径：

```text
BRC 执行 -> WB 回填 ROB -> branch 到 ROB head -> Commit 发现 miss
          -> RecoveryManager 下一拍 emit recoveryInfo -> Ctrl flush/redirect
```

恢复不是在 branch execute 当拍完成。分支执行后还要等它到 ROB head，Commit 发请求后 RecoveryManager 再打一拍。因此 miss penalty 至少是 10 拍量级，并包含窗口清空后的重新填管。

### 3. Commit 对 branch/store 非常保守

`CommitStage` 遇到 branch 后无论预测对错都会：

```text
stopCommit = 1
```

遇到 store 也会停止继续提交。对一个动态分支比例 41.8% 的程序，这会显著降低平均 commit width。即使预测全对，commit 端也不容易接近每周期 2 条。

### 4. Decode/Rename 会把分支密集 packet 拆窄

`DecodeStage` 对以下情况拆包 replay：

```text
同包多 branch
同包多 store
serial + 其他指令
```

`RenameStage` 对 branch/serial 创建 checkpoint，并且 `chkptCount > 1` 会 stall。分支密集代码会让前端实际注入宽度低于 2。

### 5. Issue/MEM 路径限制二路利用

`IssueQueue`：

- MEM uop 保序。
- 每周期最多选择一个 MEM uop。

`ExecuteMemStage`：

- 一次只发一个 load。
- load 返回时如果当前 MEM pipeReg 有有效 uop，会拉 `exStallReq`。

虽然 `srcSmoke` 当前 DRAM 访问数不是最大瓶颈，但这类结构会进一步削弱二发利用率。

### 6. 无 RAS 导致 JALR return miss 很高

当前没有 return address stack。`JALR` 统一走普通 BTB/BHB，实测：

```text
JALR miss_rate ~= 50%
```

这类 miss 约 20 万次，不是最大项，但属于明确可修的微架构问题。

### 7. 最大 miss 来源是软件除法 helper 中的数据相关条件分支

`srcSmoke` dump 显示性能循环调用：

```text
0x800004dc -> 0x800013ac
0x800004f4 -> 0x80001328
```

最终进入 `0x80001330` 附近的软件除法/取模 helper。该 helper 是移位减法循环，包含多条数据相关条件分支：

```text
beq / bgeu / bge / bltu / bne
```

这解释了为什么条件分支 miss 达到 311 万次，是总 miss 的主要来源。

## 分支命中率提升到 90% 的理论估算

当前：

```text
branch_count = 12,855,156
miss_count   = 3,317,770
```

若命中率提升到 90%：

```text
new_miss = 12,855,156 * 10% ~= 1,285,516
miss_reduction ~= 2,032,254
```

用顺序单发 `IPC=0.75` 做反推：

```text
30,758,700 / 0.75 = 41,011,600 cycles
72,814,875 - 41,011,600 = 31,803,275 extra cycles
31,803,275 / 3,317,770 ~= 9.6 cycles/miss
```

因此当前实际等效 miss 代价约 10 cycle/miss。按不同 penalty 估算：

| 假设 miss penalty | 90% hit 后 cycles | 估算 IPC |
| --- | --- | --- |
| 8 cycles | 56.56M | 0.544 |
| 10 cycles | 52.49M | 0.586 |
| 12 cycles | 48.43M | 0.635 |
| 15 cycles | 42.33M | 0.727 |

结论：

- 分支命中率到 90% 会明显提升性能，但大概率只能到 `0.58~0.65 IPC`。
- 极乐观按 15 cycle/miss，也约 `0.73 IPC`。
- 仅靠 90% 分支命中率，不足以让 IPC > 1。

如果假设 10~12 cycle/miss，即使所有 branch miss 都消除，受 commit/dispatch/MEM/Decode 限制，IPC 也大约在 `0.78~0.93` 区间。这说明“分支预测”是第一大问题，但不是唯一问题。

## 为什么二发乱序不自然超过 IPC 1

二发乱序要 IPC > 1，需要：

```text
前端持续双取/双发
预测稳定，少 flush
ROB/IQ 有足够窗口
执行单元能并行消化
commit 能经常双退
```

当前正好相反：

1. 分支占比 41.8%，且 miss 率 25.8%。
2. miss 全后端 flush，窗口经常清空。
3. branch/store 提交停止后续 commit。
4. Decode/Rename 对多 branch、多 store、serial 有拆包/停顿。
5. MEM 单发且 load 返回会阻塞当前 MEM uop。
6. 软件除法 helper 把算术工作变成大量数据相关分支。

所以当前表现为：二发乱序的硬件框架存在，但 workload 和控制策略让它长期退化成“频繁清空、保守提交、前端窄注入”的状态。

## 优化优先级

建议不要一开始就大改乱序主体。优先级：

1. 跑 `srcWithMext` 并观察 `branch_breakdown`，确认硬件 M 扩展是否消掉软件除法 helper。如果条件分支数量显著下降，这是最大收益点。
2. 增加 RAS，专门优化 `JALR x0, 0(x1)` return，目标是把 20 万次 JALR miss 大幅降下来。
3. 加 PC 级 branch miss hotspot 计数，确认 `0x80001330` helper 中最差的条件分支，再决定 BPU 是扩 PHT、加 history，还是加 loop/biased predictor。
4. 评估正确预测 branch 提交时是否可以继续提交 lane1。这个风险低于早恢复，但能改善高 branch 密度程序的 commit width。
5. 评估 branch execute/WB 早恢复。收益可能大，但会改变精确恢复边界，需要非常谨慎。
6. 后续再补 `fetch_valid/dispatch/issue/commit_width/recovery_cycles/rob_head_not_done/store_commit_stall` 计数，把 IPC 损失拆成可量化 buckets。

## 当前结论

当前 IPC 低是 RTL 微架构和 workload 共同导致的真实问题，不是 TB 统计问题。第一大瓶颈是条件分支 miss，第二类明确问题是无 RAS 导致 return miss，第三类是 commit/Decode/Rename/MEM 的保守策略限制了二发宽度。分支预测率提升到 90% 会提升 IPC，但按当前 RTL 和实测数据估计，不能单独把 IPC 拉到 1 以上。
