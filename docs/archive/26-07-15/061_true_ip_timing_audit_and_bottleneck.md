# 真实 IP 时序审计与后续瓶颈

## 结论

当前最好 RTL 仍为提交 `e9330e2`：三项 oldest-ready IssueQueue、提前执行但顺序恢复的 branch、两拍乘法以及窄化的 load→ALU→memory 地址延迟。所有后续试验均已精确回退，当前 RTL 与该提交一致。

重新生成并核对 `MUL_0.xci`、`MUL_0.dcp` 与 `pll.dcp` 后，200 MHz 完整布局布线结果为：

- 20M `srcWithMext` IPC：`0.856137`
- routed WNS/TNS：`-1.065885 ns / -798.428284 ns`
- 等效 Fmax：`164.86 MHz`
- `IPC × Fmax`：`141.14`
- setup 负 endpoint：`2588`
- hold WNS：`+0.037 ns`，hold 负 endpoint：`0`

最初 iteration28 的 routed 工程实际复用了三拍乘法 OOC DCP，旧的 `-1.051 ns / 141.49` 结果不能作为两拍硬件证据。现在 synthesis/implementation Tcl 会校验 PLL 频率、MUL stage 和 DCP 时间戳，发现缓存不一致时直接失败。

## 全部 routed 违例分组

| endpoint 簇 | 数量 | 最差 slack | slack 总和 |
|---|---:|---:|---:|
| branch outcome | 16 | -1.066 ns | -8.293 ns |
| exec memory address | 32 | -0.971 ns | -22.108 ns |
| exec payload | 209 | -0.909 ns | -113.915 ns |
| queue entry payload | 1642 | -0.883 ns | -491.717 ns |
| DCache | 200 | -0.670 ns | -57.219 ns |
| MUL IP | 75 | -0.496 ns | -15.786 ns |

最差路径是 load-bypass 标志经 branch compare 到 `branch_outcome_q.miss`。第二簇是 execute/IQ 到 AGU 和 `exec_mem_addr_q`。MUL IP 已不是频率主导路径，继续增加乘法流水级会损失 IPC 而没有足够时序回报。

## IPC 是否还容易提升

不容易。20M 热区 `0x800009b8..0x80000a3c` 占约 96.6% 提交，主要是 load、地址计算、mul 和循环 branch。DCache hit rate 约 99.75%，frontend stall 极少；因此 loop buffer、更大 fetch queue 或 hits-under-miss DCache 都没有足够收益。

本轮测试了 dispatch-time trivial completion：让 `LUI` 和 `ADDI rd,x0,imm` 不占 IQ/execute 槽。500k IPC 提升明显，但 20M 只从 `0.856137` 到 `0.856695`（+0.065%），同时综合 TNS 从约 `-616 ns` 恶化到 `-664 ns`，负 endpoint 从 1569 增到 1666，故已回退。这说明单独消除常量指令不足以改变稳态瓶颈。

仍可能有价值、但需要更大架构投入的方向：

1. move elimination / dependency alias：把热循环中的 `addi rd,rs,0` 作为依赖重命名而非执行指令；必须保留独立顺序提交项和精确异常语义。
2. 针对地址链的专用 address-generation queue：base/imm 和 memory age 选择必须与通用 IQ payload 分离，不能再把预计算值复制进每个槽；此前朴素预计算使 WNS 恶化到 `-1.783 ns`。
3. 小范围 macro-op fusion：例如 loop index 更新与边界 branch 的内部融合，但仍生成两个架构提交事件。收益可能高于常量 fast-complete，验证复杂度也显著更高。
4. load-value prediction/replay：理论上可覆盖 load→branch/ALU，但需要可靠 replay、store 冲突检测和错误恢复，不适合当前时序余量。

双镜像 DCache 仍不建议：hits-under-miss 的实际 load 到达率只有约 0.019%；双 load 理想上限约 +0.0226 IPC，却需要第二套 load enqueue/completion/wakeup，极可能超过当前约 1 ns 的时序预算。

## 本轮拒绝的时序试验

- 一拍 MUL：20M IPC `0.878594`，真实综合 WNS `-2.273 ns`，乘积约 `120.8`。
- IQ 双候选：DCache tag 路径改善，但 WNS `-1.182 ns`。
- 双候选加独立 memory-base：TNS/endpoint 改善，WNS 仍为 `-1.163 ns`。
- wake-only 候选：WNS `-2.346 ns`。
- branch miss 并行比较：WNS `-1.564 ns`。
- synthesis retiming：WNS 仍为 `-1.093 ns`，无收益。

因此当前最合理的冻结点是 `e9330e2`。若继续迭代，优先级应是“足够大收益的 move/fusion 架构”或“局部、可物理隔离的 branch/AGU 时序切分”，不再做通用 IQ 组合锥的细碎扩张。
