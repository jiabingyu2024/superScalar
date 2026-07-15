# Iteration28：提前执行分支与两拍乘法

## 结论

在 iteration23 的三项 oldest-ready IssueQueue 基础上，本轮接受了两项架构改动：

1. branch 在操作数就绪后即可提前执行，结果按 transaction ID 暂存；只有到达顺序提交头时才进行 redirect/full flush。
2. 33×33 乘法 IP 从三拍改为两拍，Verilator 行为模型、乘除单元 valid pipeline 与 Vivado IP 配置保持一致。

同时增加了一个窄化的时序切分：如果 fixed completion 本身由 load-return bypass 驱动，则依赖它的访存基址晚一拍变为 `mem_addr_ready`。普通 ALU 唤醒和 load 到普通消费者的同拍旁路不受影响。

最终 20M `srcWithMext` IPC 为 `0.856137`。在重新生成并核对 `PipeStages=2` 的 XCI/OOC DCP 后，真实两拍实现的 routed WNS 为 `-1.065885 ns`，等效 Fmax 为 `164.86 MHz`，`IPC × Fmax = 141.14`。相对 iteration23 的 routed 乘积 `137.65`，提升约 `2.5%`。

审计时发现，最初 iteration28 的工程复用了旧 `MUL_0.dcp`，其中乘法 IP 实际仍为三拍；因此原先 `-1.051 ns / 141.49` 只能视为无效的缓存结果，不能证明两拍硬件 QoR。本文下面的最终数据均来自重新生成的 `PipeStages=2` XCI、OOC DCP 和完整布局布线。

## 性能瓶颈证据

对 `srcWithMext.dump` 的热 PC 和提交前空泡进行临时 Verilator 采样后，探针已完全删除。主要结论：

- `0x800009b8..0x80000a3c` 的 34 条指令热循环占约 96.6% 动态提交和 96.1% 空泡。
- `lw` 占约 32.1% 提交、42.0% 空泡。
- `mul` 占约 3.0% 提交、34.1% 空泡，原设计每次稳定产生约三拍空泡。
- 循环末尾 `bge` 占约 23.3% 空泡，原设计必须等到提交头才允许 branch 执行。

这说明继续扩展通用 ALU 宽度或镜像 DCache 不是当前最高价值方向。提前 branch 和缩短乘法 latency 分别直接覆盖两个最大的非 load 瓶颈。

## 接受的 RTL 改动

### 提前 branch、提交时精确恢复

- `inorder_issue_queue.sv` 不再要求 branch 的 transaction ID 等于提交指针才可发射。
- 每个 scoreboard transaction 对应一个紧凑的 `{miss, actual_next}` 结果槽。
- branch 提前执行后仍只标记 scoreboard done；到达提交头后才驱动 recovery。
- younger store 仍只进入 StoreBuffer，不能越过 branch 提交；uncached/MMIO load 仍要求提交头，因而保持精确副作用。
- mispredict 或更老异常继续 full-flush 所有年轻 scoreboard/IQ/execute/store 状态。

### 两拍乘法

- `muldiv_unit.sv` 的 MUL valid pipeline 从三位缩为两位。
- `rtl/ip/MUL_0.sv` 的行为模型改成两级寄存。
- `fpga/create_vivado_project.tcl` 与 `fpga/test_prj/create_project.tcl` 的 `PipeStages` 改为 2。
- 真实两拍 routed 的 2588 个负 setup endpoint 中，乘法 IP endpoint 共 75 个，最差 slack 约 `-0.496 ns`；DSP 不是 Fmax 主导路径。

### load→ALU→访存链切分

- 若 fixed completion 的 ALU 操作数来自 load-return bypass，只延后一拍设置依赖 memory uop 的 `mem_addr_ready`。
- 该切分去除了 iteration25 的 18 级 `load data → ALU → completion → IQ wakeup → AGU` 最差链。
- 20M IPC 从切分前 `0.835341` 到切分后 `0.835347`，没有可测损失。

## 正确性与性能

| 测试 | 窗口 | 结果 | IPC |
|---|---:|---|---:|
| RV32I/M | 52 项 | 52/52 PASS | - |
| srcSmoke | 500k | I=37, fail=0 | 0.685762 |
| srcWithMext | 500k | I=37, M=8, fail=0 | 0.869596 |
| srcWithMext | 20M | I=37, M=8, fail=0 | 0.856137 |

20M 主要计数：

- commit `17,122,749`
- branch `519,021`，miss `6,503`，hit rate `98.7471%`
- load `5,502,573`，store `1,024,612`
- DCache access `6,527,394`，hit rate `99.7491%`

相对 iteration23 的 20M IPC `0.795558`，提升约 `7.61%`。

## Vivado QoR

200 MHz 约束：

| 版本/阶段 | IPC | WNS | TNS | 等效 Fmax | IPC × Fmax |
|---|---:|---:|---:|---:|---:|
| iteration23 routed | 0.795558 | -0.779584 ns | -590.332 ns | 173.02 MHz | 137.65 |
| 真实两拍 synthesis | 0.856137 | -1.093 ns | -616.015 ns | 164.12 MHz | 140.51 |
| 真实两拍 routed | 0.856137 | -1.065885 ns | -798.428 ns | 164.86 MHz | 141.14 |

最终 routed 状态：

- setup failing endpoints：`2588`
- hold WNS：`+0.037 ns`，hold failing endpoints：`0`
- routed checkpoint：`fpga/build/digital_twin_srcWithMext/digital_twin.runs/impl_1/top_routed.dcp`
- 全量 setup 违例：`fpga/build/digital_twin_srcWithMext/reports/iteration33_true_two_cycle_final_routed_all_violating_setup_paths.{rpt,csv}`

最差 routed 路径为 load bypass 标志经 branch compare 到 `branch_outcome_q.miss`，WNS `-1.065885 ns`；第二簇为 execute/IQ 到 `exec_mem_addr_q`，最差约 `-0.971 ns`。其余主要簇为 DCache tag 到 IQ/execute、scoreboard 到 IQ/execute 和 queue payload 更新。两拍乘法没有成为 Fmax 限制。

## 被拒绝的实验

- hits-under-miss 镜像 DCache：busy 时到达的 load 仅约 `0.019%`，无实际收益。
- 完整双 load 镜像 DCache：理想上限约 `+0.0226 IPC`，但第二套 enqueue/completion/wakeup 无法满足现有频率预算。
- 提交时精确 predictor 训练：`srcSmoke` 提升到 `0.701028`，但 `srcWithMext` 几乎无收益，综合 WNS 恶化到 `-1.328 ns`，乘积下降，已回退。
- 完全结构化延迟 load-dependent fixed wakeup：形成新的 21 级 defer 控制链，综合 WNS `-1.184 ns`，已回退到轻量切分。
- 一拍乘法：Verilator 20M IPC 提升到 `0.878594`，但真实 `PipeStages=1` 综合 WNS 恶化到 `-2.273 ns`，乘积约 `120.8`，已回退。
- IQ 双候选/独立 memory-base 组合视图：可减少 DCache tag 路径和 TNS，但 WNS 分别恶化到 `-1.182/-1.163 ns`；wake-only 变体恶化到 `-2.346 ns`，均已回退。
- 分支 miss 并行比较因式分解：功能与 IPC 不变，但综合 WNS 恶化到 `-1.564 ns`，已回退。

后续若继续提升频率，应针对 memory address 预计算或将 AGU 选择从通用 IQ 组合锥中拆出；不应增加第二套 load completion 或扩大 IssueQueue 深度，除非先消除当前 load wakeup/AGU 扇出。
