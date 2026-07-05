# ExecuteMem load 返回合并优化记录

> 2026-07-05 更新：该优化已在 `033_issuequeue_wakeup_and_perf_buckets.md` 中回退。短 src 观测显示该改动没有带来稳定收益，且可能加重持续 load 对 StoreBuffer store commit 的挤压。当前 RTL 恢复为旧的保守策略：`loadMetaPipe1.valid && currentMemValid` 时阻塞当前 MEM pipe。

## 背景

旧版 `ExecuteMemStage` 在 load 返回时使用如下条件拉全局 EX stall：

```systemverilog
loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
ctrl.exStallReq = loadReturnBlocked || loadAccessBlocked;
```

`Ctrl.sv` 会把 `exStallReq` 扩散到 `IS/RR/EX`，并通过 `backendBlock` 反压前端。结果是：上一条 load 返回时，只要当前 MEM pipe 还有任意有效 uop，就冻结后端/前端。

对 load-heavy 片段，这容易退化成：

```text
发起 load
等待/返回并 stall 一拍
再发起下一条 load
```

理论节奏接近 0.5 IPC。

## 修改内容

`rtl/core/ExecuteStage/ExecuteMemStage.sv`：

1. 将 `currentMemValid` 改为 `currentMemCount`。
2. `loadReturnBlocked` 从“load 返回 + 任意当前 MEM uop”改为：

```systemverilog
loadReturnBlocked = loadMetaPipe1.valid &&
                    (currentMemCount >= WAY_NUM) &&
                    !ctrl.exPipe.flush;
```

3. 当 load 返回存在时：
   - 返回 load 固定写入 `nextMemToStage[0]`。
   - 当前单个 store、StoreBuffer forward-hit load、或新发起 DRAM load 的即时完成/元信息路径使用 `nextMemToStage[1]`。
4. 当 load 返回且当前 MEM pipe 已经有两个有效 uop 时，仍然保守 stall，避免两个 WB lane 不够用。

## 行为边界

该优化不改变以下事实：

1. MEM issue 仍保序。
2. 每周期仍最多发起一个真实 DRAM load。
3. StoreBuffer 仍只有当前协议下的一组 push/match 输出。
4. DRAM read 延迟仍按 `loadMetaPipe0/1` 两级 metadata 对齐。

该优化只解除“load 返回结果”和“当前单个 MEM uop”之间不必要的全局 stall。

## 预期影响

对连续 load 或 load-heavy 片段，旧设计会在 load 返回拍阻止下一条 MEM uop 进入有效工作；新设计允许返回 load 和下一条 MEM uop 同周期共存，应降低 MEM 路径对 IPC 的 0.5 限幅。

如果程序瓶颈主要来自 branch miss 全后端恢复、JALR return miss、decode/rename checkpoint 限制，该优化不会单独把 IPC 推到大于 1，但应减少访存段的结构性空泡。

## 验证

已执行：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1
make sim-rv32 TEST=rv32ui-p-lw NO_BUILD=1
make sim-rv32 TEST=rv32ui-p-sw NO_BUILD=1
```

结果均通过。

按用户要求，停止默认大上限 `srcSmoke` 长跑后，仅做小周期 smoke：

```bash
make sim-src TEST=srcSmoke MAX_CYCLES=200000 NO_BUILD=1
```

结果为预期 TIMEOUT，已能输出部分统计：

| 项 | 值 |
| --- | --- |
| cycles | 200000 |
| commit_count | 83762 |
| ipc | 0.41881 |
| branch_hit_rate | 0.725519 |
| dram_read_count | 3040 |
| dram_write_count | 1059 |

该结果只用于确认短上限 src harness 能正常运行和输出统计，不作为完整性能结论。后续若要评估本优化收益，应使用同一 `MAX_CYCLES` 或完整 PASS 条件对比优化前后的 `cycle/ipc/memory` 数据。
