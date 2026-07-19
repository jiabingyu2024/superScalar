# Dispatch 与预测器时序优化

## 输入报告

本轮以 2026-07-19 20:05 生成的 routed 报告为当前实现基线：

- WNS：`-0.752 ns`
- TNS：`-871.708 ns`
- setup 负 endpoint：`3993`
- hold WNS：正 slack，无 hold 违例

routed 最差十条路径分成三族：

1. `Scoreboard commit/full_flush -> IssueQueue select -> exec payload`
2. `BranchPredictor collision/result -> next request -> BTB/PHT read register`
3. `exec branch compare -> Scoreboard exception_tval`

上一轮同版本 synthesis 的全量 CSV 还有一个规模更大的公共锥。`FetchQueue -> Scoreboard` 有 2224 条负路径，`FetchQueue -> IssueQueue` 有 566 条；二者合计贡献约 `-1746.468 ns` TNS。只处理 routed 前十条不会改善综合阶段的 TNS 主体。

## RTL 修改

### 注册 dispatch payload

`core_top.sv` 在 FetchQueue 与 Scoreboard/IssueQueue 之间增加一项 dispatch 寄存器。该寄存器允许当前 uop dispatch 的同拍接收下一条 uop，稳态吞吐仍为每拍一条。macro-move 的 valid 和第二条指令也随主 uop 一起寄存。

代价是 reset、redirect 或前端重新启动后增加一拍 dispatch 填充延迟。它不会降低无停顿直线代码的发射带宽，IPC 影响只与恢复/重新填充频率有关。

同一文件把 branch alignment fault 的 `exception_tval` 改为直接取 `branch_target_c`。异常有效时，taken branch 的故障地址必然等于该 target，因此无需让 branch taken 选择器进入 32 位 tval payload。

### IssueQueue payload 预选

`inorder_issue_queue.sv` 先完成 oldest-ready payload 选择，再用 `issue_block_i` 屏蔽最终 `issue_valid_o`。被 redirect 或 serial 阻塞时不会 pop entry，但 exec payload 不再受 commit/full_flush 组合锥控制。

该修改不增加发射等待周期，也不改变 memory 保序和 oldest-ready 规则。

### Predictor collision 前移

`branch_predictor.sv` 将 BTB/PHT 同地址读写 forwarding 移到 `read_entry_q` 和 `read_pht_counter_q` 的寄存器入口，删除结果寄存器后的 collision mux。功能仍为 write-first；预测读取和更新同拍命中同一项时，下一拍使用更新值。

综合后 BTB 继续实现为 LUTRAM，没有退化为宽寄存器阵列。

## 唯一一次 Vivado synthesis-only

命令：

```text
vivado.bat -mode batch -source fpga/run_synthesis.tcl -tclargs srcWithMext 8 200 1 v42_dispatch_collision_preselect 100000 0 0
```

Vivado 2023.2 完成 RTL elaboration 和 synthesis，结果为 0 error。没有新增 latch、多驱动或组合环告警。

| 指标 | 修改前 synthesis | 修改后 synthesis | 变化 |
|---|---:|---:|---:|
| WNS | -1.236 ns | -1.400 ns | -0.164 ns |
| timing-summary TNS | -2041.110 ns | -260.038 ns | 改善 87.3% |
| 负 setup endpoint | 3665 | 1006 | 减少 72.6% |
| Total LUT | 11835 | 11592 | -243 |
| FF | 10204 | 10331 | +127 |

全量 CSV 的 slack 合计为 `-259.823 ns`，与 timing summary 的 `-260.038 ns` 有 `0.215 ns` 差异，来自报告接口对 endpoint/path 的取值方式；判断收敛程度时使用 timing summary。

原来的两类主要路径已清零：

- `FetchQueue -> Scoreboard`：2224 条降为 0
- `FetchQueue -> IssueQueue`：566 条降为 0

修改后的 1006 条负路径主要为：

| 路径族 | 条数 | WNS | CSV TNS |
|---|---:|---:|---:|
| DCache -> Scoreboard | 416 | -0.455 ns | -82.729 ns |
| DCache -> LoadQueue | 182 | -0.430 ns | -16.700 ns |
| Scoreboard -> DCache | 120 | -0.437 ns | -24.180 ns |
| Predictor -> 其他前端状态 | 124 | -0.643 ns | -61.108 ns |
| Predictor 内部反馈 | 60 | -1.400 ns | -64.471 ns |
| 其他 | 104 | -0.436 ns | -10.635 ns |

## 结论与边界

本轮消除了 TNS 主体和 2659 个负 endpoint，面积也略有下降。WNS 没有改善；新 WNS 是 `read_pc_q -> macro-move/next-PC feedback -> BTB read_entry_q`，综合估算为 13 级逻辑、`-1.400 ns`。200 MHz 仍未收敛，不能把本轮结果写成 timing closure。

继续处理 WNS 需要修改 frontend 的 next-PC 反馈或 macro-move 判断。直接给预测反馈增加流水拍会把取指吞吐降到接近每两拍一条，不符合本轮 IPC 约束；较合理的后续方向是证明并删除 macro-move 中冗余的 `predicted_next_pc == pending_pc + 4` 比较，或把 sequential/non-sequential 元数据在预测器内单独生成。该改动需要新的功能回归和下一次独立 Vivado 迭代，本轮不继续试跑。

按用户要求，本轮没有运行全量仿真，也没有调用 place/route。IPC 判断基于结构：dispatch 稳态仍支持每拍 consume/refill；实测 IPC 尚未更新。

## 产物

- `fpga/build/digital_twin_srcWithMext/reports/v42_dispatch_collision_preselect_timing_summary.rpt`
- `fpga/build/digital_twin_srcWithMext/reports/v42_dispatch_collision_preselect_all_violating_setup_paths.csv`
- `fpga/build/digital_twin_srcWithMext/reports/v42_dispatch_collision_preselect_utilization_hier.rpt`
- `backup/20260719_203500/`
