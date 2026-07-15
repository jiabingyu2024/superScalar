# Iteration23 IssueQueue、routed QoR 与双镜像 DCache 评估

## 结论

当前最佳版本是 3 项、单发射、oldest-ready 的 `inorder_issue_queue`。它在保持顺序提交、memory 保序和 branch 提交头发射约束的同时，允许已准备好的年轻非 memory 指令绕过未准备好的老指令。

该版本已完成 RV32IM、src 短窗、20M 稳态窗口、synthesis-only 和完整 place/route。20M `srcWithMext` 的 IPC 为 `0.795558`；routed WNS 为 `-0.779584 ns`，等效 Fmax 为 `173.02 MHz`，`IPC x Fmax` 为 `137.65`。

双镜像 DCache 暂不实现。精确动态计数表明它的双 load 理想上限约为 `+0.0226 IPC`，但 routed 最佳点要求双 load 版本仍达到约 `168.2 MHz`，只允许约 `2.8%` 的频率损失或约 `0.16 ns` 的额外关键路径。当前全部 routed 违例已集中在 load/execute/scoreboard/load-queue 路径，加入第二套 load 选择、完成和唤醒链超过该预算的风险很高。

## IssueQueue 结构

- 深度固定为 3，payload 不做逐拍移位压缩。
- 用 `trans_id - commit_ptr` 比较年龄，从所有 ready 项中选择最老者。
- load/store 之间严格 memory 保序；branch 只有位于提交头时才能发射。
- fixed、load 和 slow completion 均可唤醒驻留项。
- load completion 同拍只向选择端传递 ready/tag；32-bit 数据先写入 `load_issue_bypass_data_q`，下一拍在执行端恢复 operand。
- memory 地址使用独立的 `mem_addr_ready` 与 oldest-memory 选择，避免 DCache 数据/tag 驱动 AGU 选择。
- branch mispredict 在提交头退休时 full flush，清除所有年轻 scoreboard/IQ/execute 状态。

主要 RTL：

- `rtl/core/issue/inorder_issue_queue.sv`
- `rtl/core/core_top.sv`
- `rtl/core/control/recovery_ctrl.sv`
- `rtl/core/issue/scoreboard.sv`

## 正确性与性能

| 测试 | 窗口 | 结果 | IPC |
|---|---:|---|---:|
| RV32IM | 全套 52 项 | 52/52 PASS | - |
| srcSmoke | 500k cycles | RV32I pass=37, fail=0 | 0.455600 |
| srcWithMext | 500k cycles | RV32I=37, M=8, fail=0 | 0.829388 |
| srcWithMext | 20M cycles | RV32I=37, M=8, fail=0 | 0.795558 |

20M 主要计数：

- commit `15,911,169`
- load `5,111,075`，store `952,216`
- DCache access `6,056,501`，hit rate `99.7331%`
- branch `482,369`，miss `6,083`，hit rate `98.7389%`
- load return block `4,063,802` cycles

## Vivado QoR

200 MHz 约束下：

| 阶段 | WNS | TNS | 等效 Fmax | IPC x Fmax |
|---|---:|---:|---:|---:|
| synthesis-only iteration23 | -1.044 ns | - | 165.45 MHz | 131.61 |
| post-route signoff | -0.779584 ns | -590.332 ns | 173.02 MHz | 137.65 |

完整 route：

- 0 failed nets，0 unrouted nets，0 overlaps。
- hold WNS `+0.037 ns`，无 hold failing endpoint。
- setup failing endpoints `2203`。
- 全量路径导出：`fpga/build/digital_twin_srcWithMext/reports/iteration23_final_routed_all_violating_setup_paths.{rpt,csv}`。

按模块聚类的主要 setup 违例：

| 起点 -> 终点 | 路径数 | 最差 slack |
|---|---:|---:|
| Execute -> Execute | 59 | -0.780 ns |
| DCache -> Execute | 209 | -0.720 ns |
| LoadQueue -> LoadQueue | 290 | -0.703 ns |
| DCache -> Scoreboard | 304 | -0.649 ns |
| DCache -> IssueQueue | 33 | -0.605 ns |
| Frontend -> IssueQueue | 304 | -0.471 ns |
| Execute -> Scoreboard | 218 | -0.433 ns |

这些路径说明 load completion/result fanout、load queue forwarding metadata 和 execute operand 选择仍是频率主压力。第二个 load completion port 会直接复制或扩大现有热点，而不是利用一条空闲的独立路径。

## 双镜像 DCache 动态评估

临时 Verilator 探针已在评估后完全移除，当前 RTL 与探针前备份一致。

20M 运行到约 19.5M cycles 时：

- load enqueue `4,986,879`
- DCache busy 时到达的 load 仅 `940`，占 `0.019%`
- busy 且 IQ 中有 queued load 的 cycles 为 `316,504`
- IQ 中至少两条 ready load 的 cycles 为 `440,278`
- 两条最老 memory 都是 ready load，且 LoadQueue 有两个空槽的精确可双发 cycles 为 `440,102`

因此：

1. 只做 hits-under-miss 的镜像无收益，理想 IPC 增量小于 `0.00005`。
2. 真正双 load 后端的理想上限约为 `440,102 / 19.5M = +0.0226 IPC`，约 `+2.8%`。
3. 以 routed 最佳点 `137.65` 为基准，双 load 版本必须保持约 `168.2 MHz` 以上才可能获胜。
4. 完整方案还需要双 load 分配、双 LoadQueue enqueue、双 completion、双 scoreboard/IQ wakeup，以及镜像 tag/data 的一致写入；它们正好压在当前最差路径族上。

决策：保留单 DCache 和单 load backend，优先继续减少 load-return 阻塞或切断 load completion/wakeup 的组合深度。只有后续能先设计出寄存化、无第二条同拍 completion fanout 的双 load 数据流，才重新打开镜像 DCache 实现。
