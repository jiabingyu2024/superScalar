# srcWithMext 低 IPC 微架构分析

## 背景

用户反馈：按 `031_execute_mem_load_return_merge.md` 放开 `ExecuteMemStage` 的 load 返回冲突后，`srcWithMext` 上没有性能提升，甚至可能更差。当前测试集已固定为 `data/srcWithMext/srcWithMext.dump`，不再把软件乘除法 helper 作为主要因素。

本文只分析当前 RTL 的微架构限制和优化方向，不修改 RTL。

## 已有结果

当前已有 `build/result/src/srcWithMext.json`：

| 项 | 值 |
| --- | --- |
| cycles | 100000000 |
| commit_count | 36045338 |
| IPC | 0.360453 |
| branch_count | 1034616 |
| branch_miss_count | 25565 |
| branch_hit_rate | 97.529% |
| conditional miss_rate | 2.471% |
| JAL miss_rate | 1.930% |
| JALR miss_rate | 98.507%，但只有 67 次 |
| dram_read_count | 8571572 |
| dram_write_count | 2042912 |

关键判断：

1. `srcWithMext` 的分支命中率已经很高，且动态分支数只占 `commit_count` 的约 `2.87%`。
2. 即使每次 branch miss 损失 20 cycle，`25565 * 20 = 511300 cycle`，只占 100M cycle 的约 0.5%。
3. 因此当前 0.36 IPC 不能主要归因于“分支命中率不够”。更大的问题是依赖链延迟、访存/StoreBuffer/DRAM 仲裁、全局 stall 耦合、commit/store 边界和窗口太小。

## dump 静态结构

对 `data/srcWithMext/srcWithMext.dump` 的静态统计：

| 类别 | 条数 | 比例 |
| --- | ---: | ---: |
| other | 1118 | 50.45% |
| load | 341 | 15.39% |
| store | 301 | 13.58% |
| conditional branch | 147 | 6.63% |
| JAL | 131 | 5.91% |
| JALR | 118 | 5.33% |
| M extension | 39 | 1.76% |
| serial/CSR/trap | 21 | 0.95% |

2-wide 静态 packet：

| packet 特征 | 数量 | 比例 |
| --- | ---: | ---: |
| has_branch | 363 | 32.76% |
| has_load | 306 | 27.62% |
| has_store | 257 | 23.20% |
| multi_store | 44 | 3.97% |
| multi_branch | 33 | 2.98% |
| serial_with_other | 19 | 1.72% |

静态 basic block：

| 项 | 值 |
| --- | ---: |
| block 数 | 418 |
| 平均长度 | 5.30 inst |
| 中位数 | 5 inst |
| 最大长度 | 57 inst |

静态看，branch/store/serial split 会损失一些前端宽度，但从动态 `branch_count` 看，`srcWithMext` 的长时间运行阶段不是高分支密度路径，因此 decode split 不是当前 0.36 IPC 的第一主因。

## 为什么 031 没提升

`031` 只优化了这一种情况：

```text
loadMetaPipe1.valid = 1
当前 MEM pipe 中恰好有 1 条有效 uop
  -> load 返回占 MEM WB lane0
  -> 当前 uop 占 MEM WB lane1 或发起下一次 load
```

它没有解决以下更常见的瓶颈。

### 1. 真实瓶颈不是 load 返回端口冲突

`srcWithMext` 100M cycle 内：

```text
dram_read_count  = 8,571,572
dram_write_count = 2,042,912
memory request   = 10,614,484
commit_count     = 36,045,338
```

访存约占提交指令的 29.45%，确实不低，但 031 只减少“load 返回拍和当前 MEM uop 抢 WB lane”的冲突。如果当前 MEM pipe 在 load 返回拍经常是空的，或者冲突主要来自 store commit/StoreBuffer/依赖链，那么 031 触发次数就少。

### 2. 031 可能让 store commit 更难抢到 DRAM

`DramAccessIF.sv` 当前读优先：

```systemverilog
readEn  = exReadEn;
writeEn = !exReadEn && storeWriteEn;
storeWriteReady = accessReady && !exReadEn;
```

也就是说：只要 ExecuteMem 发起 load，StoreBuffer head store 就不能提交到 DRAM。

031 允许 load 返回拍同时发起下一条 load，这可能提高 load 连续性，但也可能进一步压缩 store commit 的机会。若 StoreBuffer 因 store 无法提交而接近满，Dispatch 会因为 `storeBuffer.allocRdy=0` 停住，反而使 IPC 变差。

这解释了“局部看 load 更顺，整体 IPC 可能更差”的现象。需要加计数器确认：

1. `storeBufferFullStallCycles`
2. `storeCommitReadyButReadPriorityBlockedCycles`
3. `loadReturnMergeFireCycles`
4. `loadReturnStillBlockedCycles`

## 当前更大的 IPC 限制

### 1. IssueQueue 的延迟唤醒机制没有真正提前唤醒

`DispatchStage.delay_for()` 已经给 uop 设置预计延迟：

```systemverilog
TUBE_TYPE_MUL: div/rem 34, mul 3
TUBE_TYPE_MEM: 3
default:       1
```

`IssueQueue` 也有 `srcAMatched/srcAShift/srcBRdy` 机制。但当前代码只做移位：

```systemverilog
if (entries[i].srcAMatched && !entries[i].srcARdy) begin
    if (entries[i].srcAShift != '0) begin
        entries[i].srcAShift <= {1'b0, entries[i].srcAShift[SHIFT_WIDTH-1:1]};
    end
end
```

没有在 `srcShift == 1` 时把 `srcRdy` 置 1。因此依赖指令大概率要等生产者真正 WB 后，通过 `IssueWakeup` 才 ready。

后果：

```text
ALU producer issue
  -> RR
  -> EX
  -> WB wakeup
dependent consumer 才能 issue
```

这相当于依赖链每步付出多拍延迟。对 `addi/lw/add/sw` 这类地址更新、循环计数、load-use 链，二发乱序会退化为“等 WB 再发射”，IPC 很容易落到 0.3~0.5。

这个问题比 031 更像当前主因，因为 `srcWithMext` 分支 miss 已经很少，但仍然 IPC 只有 0.36。

优化方向：

1. 在 `srcShift == 1` 时把源标 ready，使 dependent 提前 issue。
2. 保证它到达 EX 时，生产者刚好处于 WB，可由现有 `BypassIF` 前递。
3. 这是低频率风险优化，因为移位逻辑已经存在，只是补一个比较和置 ready。

频率影响：小到中等。IssueQueue 已经有 16 entry 扫描和 wakeup 比较，增加 `shift == 1` 判断不会成为主要新关键路径。收益可能很大。

### 2. 当前只有 WB-only bypass，没有 EX-to-EX 早前递

执行级只在 EX 前查询 `BypassIF`，而 `BypassIF` 来源是 WriteBackStage 当前周期的 `wbForward`。没有 ALU/MEM/MUL/BRC 直接到下一条 EX 的旁路。

这意味着即使 ALU 结果在 Execute 当拍已算出，依赖者也不能在下一拍 EX 使用它，除非时序被安排到生产者 WB 的同周期。

优化方向：

1. 先修 IssueQueue 预测唤醒，让现有 WB bypass 被充分利用。
2. 再考虑 EX-to-EX forwarding。

频率影响：EX-to-EX 旁路会给执行输入 mux 增加更多比较和数据选择，频率风险高于补 `srcShift == 1`。

### 3. StoreBuffer/DRAM 单端口读优先可能造成 store 提交饥饿

当前 store 只有到 commit 才对外写，正确性上合理；但 DRAM 单端口仲裁读优先，会导致：

```text
load 流持续发起
  -> StoreBuffer head store 提交被推迟
  -> StoreBuffer count 升高
  -> Dispatch store 分配失败
  -> dsStallReq / frontendBlock
```

031 增加 load 连续发起机会后，这个问题可能更明显。

优化方向：

1. 加 store-buffer 水位优先级：当 StoreBuffer 接近满，DRAM 仲裁优先提交 store。
2. 或按简单 round-robin 在 load/store commit 间公平仲裁。
3. 保持 load metadata 对齐：若 load 因仲裁被拒绝，必须继续 `loadAccessBlocked` 并保持 EX pipe。

频率影响：小。主要是 `DramAccessIF` 或上游仲裁加几个条件。收益取决于 store buffer stall 计数。

### 4. 全局 stall 耦合过强

`Ctrl.sv`：

```systemverilog
backendBlock = isStallReq | rrStallReq | exStallReq | wbStallReq;
frontendBlock = serialBlock | backendBlock | robFull | issueQueueFull |
                freeListEmpty | idStallReq | rnStallReq | dsStallReq;
```

任何 EX 局部资源冲突都会冻结：

```text
IS/RR/EX
并进一步冻结 PF/IF/ID
```

这使 MEM 的局部 stall、load access blocked、StoreBuffer blocked 等事件放大成整机空泡。

优化方向：

1. 短期：减少 `exStallReq` 产生源，例如 031、store 仲裁、load buffer。
2. 中期：拆分每个执行单元的 ready/valid，让 MEM stall 不冻结 ALU/BRC/MUL。

频率影响：局部 ready/valid 会显著增加控制复杂度和验证成本，不建议在没有 stall 计数前贸然改。

### 5. ROB/IQ 窗口太小，且 IssueQueue 选择逻辑频率风险已经较高

当前：

```text
ROB_DEPTH = 16
ISSUE_QUEUE_DEPTH = 16
```

对于无 cache、load 多、依赖多的程序，16-entry 窗口容易被未 ready 的 load-use 链、store、long latency M uop 占满。

但直接扩大窗口有明显频率风险：

1. `IssueQueue` 有多处 16-entry 全扫描。
2. `memBlockedByOlder` 是 MEM uop 的 O(N^2) 年龄比较。
3. `has_same_cycle_raw()` 也扫描 selected mask。

优化方向：

1. 先修 IssueQueue 预测唤醒和 store 仲裁。
2. 再用计数确认 `robFull/issueQueueFull` 是否频繁。
3. 如果确实频繁，再考虑 ROB=24/32；IQ 扩容需要同时优化选择逻辑，不宜简单翻倍。

### 6. Commit 仍然保守，但不是 srcWithMext 当前第一主因

已有 027 优化：

1. lane0 正确 branch 后允许 lane1 安全普通指令提交。
2. lane0 commit-ready store 后允许 lane1 安全普通指令提交。

仍未支持：

1. 双 branch 同周期提交。
2. lane1 branch 提交。
3. 双 store commit。
4. lane1 store commit。

`srcWithMext` 动态 branch 占比只有约 2.87%，因此继续扩 branch commit 对当前结果收益有限。store 写有 204 万次，占提交约 5.67%，store commit 优化可能有收益，但更应先看 `StoreBufferCommitReady` 和 store buffer full stall。

频率影响：双 branch update、双 checkpoint free 会明显拉高 commit 控制复杂度；不建议作为当前第一步。

### 7. Decode split 不是当前第一主因

`srcWithMext.dump` 静态上：

1. `multi_branch` packet 约 2.98%。
2. `multi_store` packet 约 3.97%。
3. `serial_with_other` packet 约 1.72%。

这些会降低前端供应宽度。但动态 `srcWithMext` 分支数很低，说明长时间运行段不是频繁执行静态高 branch 区域。Decode split 值得后续优化，但不应排在 IssueQueue 唤醒和 StoreBuffer/DRAM 仲裁之前。

频率影响：放开 multi-store 需要 StoreBuffer 双分配/双 push 或更复杂的 replay；放开 multi-branch 需要双 checkpoint create/BPU 预测/恢复边界，频率和验证风险都更高。

### 8. Branch miss recovery 代价大，但当前不是主导

当前 branch miss 仍是 commit-based 全后端恢复：

```text
BRC execute
  -> WB 回填 ROB
  -> branch 到 ROB head
  -> Commit 发 recovery
  -> RecoveryManager 下一拍 emit
  -> frontend/backend flush
```

这是高代价设计。但在 `srcWithMext` 当前结果中只有 25,565 次 miss。即使按 20 cycle/miss 估算，也远不足以解释 100M cycle。

优化方向：

1. 对 `srcSmoke` 这类 miss 多的程序，RAS/早恢复仍重要。
2. 对 `srcWithMext` 当前长跑，优先级低于 IssueQueue 唤醒和 StoreBuffer 仲裁。

频率影响：早恢复会改变精确状态边界和 flush 范围，验证风险高；建议后置。

## 建议优化顺序

### 第一优先级：补 IssueQueue 预测唤醒

目标：让已被同周期 RAW 标记的 consumer 在预计延迟结束时变 ready，而不是等 WB wakeup。

预期收益：高。它直接降低 ALU/load-use 依赖链 CPI。

频率风险：低到中。逻辑基本已存在，只补 `srcShift == 1` 时置 ready。

### 第二优先级：补 stall bucket 计数

在 `PerfIF` 或 debug 口加以下计数：

1. `frontend_stall_cycles`
2. `id_split_cycles`
3. `rn_resource_stall_cycles`
4. `rn_chkpt_stall_cycles`
5. `ds_rob_full_cycles`
6. `ds_iq_full_cycles`
7. `ds_storebuffer_full_cycles`
8. `ex_load_return_block_cycles`
9. `ex_load_access_block_cycles`
10. `store_commit_blocked_by_load_cycles`
11. `rob_head_not_done_cycles`
12. `commit_width0/1/2_cycles`
13. `issue_width0/1/2_cycles`
14. `dispatch_width0/1/2_cycles`

预期收益：不直接提升 IPC，但能避免继续做 031 这种“局部看合理、整体不命中”的优化。

频率风险：低。计数器在时钟边沿采样已有控制信号即可。

### 第三优先级：DRAM load/store 公平仲裁

目标：避免 load 连续流饿死 StoreBuffer commit。

策略：

1. StoreBuffer 水位高时优先 store commit。
2. 或简单 load/store round-robin。

频率风险：低。

### 第四优先级：确认是否需要扩大 ROB/IQ

只有当计数显示 `robFull/issueQueueFull` 很频繁时再扩。

频率风险：中到高，尤其是 IssueQueue。

### 第五优先级：前端/Decode/Commit 更激进双发

包括：

1. multi-store 不拆包。
2. lane1 branch commit。
3. 双 checkpoint create/free。
4. 更早 branch recovery。

这些收益可能存在，但频率和验证风险明显更高，应在依赖唤醒、store 仲裁和计数器之后处理。

## 对 031 的结论

031 不是错误方向，但它只解决一个很窄的端口冲突。`srcWithMext` 当前 IPC 低的主要嫌疑不是 load 返回端口，而是：

1. IssueQueue 未使用 `delay/srcShift` 做提前唤醒，依赖链等 WB。
2. DRAM 读优先可能导致 StoreBuffer commit 饥饿。
3. 全局 stall 把局部资源冲突放大成整机冻结。
4. ROB/IQ 小窗口难以覆盖无 cache load 和长依赖链。

后续不要再优先做大而复杂的分支预测或早恢复。对 `srcWithMext`，更实际的第一步是修 IssueQueue 预测唤醒，并加 stall bucket 计数来验证主瓶颈。
