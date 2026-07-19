# 局部 BTB 与取指反馈优化

## 结论

本轮处理上一版 synthesis 的最差路径：`read_pc_q -> macro-move/next-PC ->
BTB/PHT read register`。最终保留两项 RTL 修改：BTB 只保存 IROM 局部地址，前端删除
macro-move 判断中冗余的 `predicted_next_pc == pc + 4` 比较。

`srcWithMext` 20M IPC 从 `0.944961` 变为 `0.944644`，下降 `0.0335%`；
分支 miss 从 `7179` 变为 `7177`。唯一一次 Vivado synthesis-only 的 WNS 从
`-1.400 ns` 改善到 `-0.837 ns`，但 TNS 从 `-260.038 ns` 回退到
`-472.339 ns`，负 setup endpoint 从 `1006` 增至 `1401`。因此这版改善了最差
路径和面积，没有完成 200 MHz timing closure，也不能视为整体时序已收敛。

## 输入报告

上一版报告标签为 `v42_dispatch_collision_preselect`：

| 指标 | 数值 |
|---|---:|
| WNS | -1.400 ns |
| TNS | -260.038 ns |
| 负 setup endpoint | 1006 |
| Total LUT | 11592 |
| FF | 10331 |
| LUTRAM | 564 |

全量 CSV 中，predictor 内部反馈有 60 条负路径，最差 `-1.400 ns`。DCache tag
BRAM 到 Scoreboard/LoadQueue 是主要 TNS 来源。历史实验还表明，2048 项 tag bank
强制使用 LUTRAM 会形成深层地址级联，曾得到约 `-4.721 ns` WNS。因此本轮没有把
2K DCache tag 阵列改为 distributed RAM，也没有缩减当前 32 KiB DCache 容量。

## RTL 修改

### BTB 改为 IROM 局部地址

文件：`rtl/core/frontend/branch_predictor.sv`

IROM 字节地址宽度为 14 bit，BTB 有 128 项。BTB tag 由原来的 23 bit 缩为 5 bit，
target 只保存低 14 bit，预测时用当前 PC 的高位恢复完整地址。每项宽度由 58 bit
降为 22 bit，表项数、GShare history、PHT 和 RAS 深度不变。

同拍预测读与更新写命中同一项时，不再在 `read_entry_q/read_pht_counter_q` 输入端
强制前递。读到旧值或新值都属于合法的推测状态；错误预测仍由原有 branch recovery
精确恢复。该修改不改变体系结构状态，代价最多是同地址训练冲突时多一次误预测。

BTB 明确使用 distributed RAM。综合日志确认实现为 `128 x 22`、`RAM64M x 48`，
没有原先 block-RAM inference infeasible 的警告。

### 删除 macro-move 冗余比较

文件：`rtl/core/frontend/frontend.sv`

`writes_rd_noncontrol()` 已排除 branch、JAL、JALR 等所有控制流 opcode。IROM 在运行
期间不可修改，所以满足该条件的 PC 不可能拥有合法 BTB redirect。原来的
`predicted_next_pc == pending_pc + 4` 不提供额外正确性保证，却在同步预测反馈上增加
32 bit 加法和比较。删除后 macro-move 的识别条件、双指令跳步和提交语义不变。

## 被否决的 DCache 方案

曾尝试只在 `dcache.sv` 内把 cache-hit response 注册一拍，以切断 tag BRAM 到
LoadQueue/Scoreboard 的组合路径。`src2` 500k 在约 800 条提交后停住，
`load_return_block_cycles=498381`，说明这一改法破坏了当前 DCache response 与
LoadQueue active metadata 的拍对齐。该修改在最终 RTL 中已完全撤回。

如果后续要给 load-hit 增加流水级，必须把 response valid/data、LoadQueue active
metadata 和 completion handshake 一起重定时，不能只延迟 DCache 输出。

## 仿真回归

两套 Verilator 模型均从最终 RTL 重建。

| 测试 | 窗口/结果 | 关键结果 |
|---|---|---|
| RV32I/MI/M | 52/52 PASS | 40 + 4 + 8 全部通过 |
| `src2` | 500k TIMEOUT | 提交 314488，RV32I 37/0，SEG `0x37000000` |
| `srcWithMext` | 500k TIMEOUT | RV32I 37/0，M=8，IPC `0.895602` |
| `srcWithMext` | 20M TIMEOUT | RV32I 37/0，M=8，IPC `0.944644` |
| `srcSmoke` | 500k TIMEOUT | RV32I 37/0，SEG `0x37000000`，IPC `0.627926` |

这些 src 短/中窗口按进度计数器和 SEG 判断；未到程序最终结束时，TIMEOUT 是预期
状态。目标程序 20M IPC 相对上一版下降 `0.0335%`，低于 2% 限制。

`srcSmoke` 相对 063 文档中的 `0.668484` 下降约 6.1%，该跨度同时包含上一轮新增的
dispatch register，不能全部归因于本轮 BTB 修改。目标 `srcWithMext` 的同窗口对比
和 branch miss 计数没有显示明显预测性能回退。

## 唯一一次 Vivado 综合

命令：

```text
vivado.bat -mode batch -source fpga/run_synthesis.tcl -tclargs srcWithMext 8 200 1 v42_local_btb_macro_fast 100000 0 0
```

Vivado 2023.2 完成综合，0 error。4 条 `set_clock_groups` critical warning 与上一版
相同，来自 generated clock 建立前的早期 XDC 解析；最终表内使用的是
`clk_out2_pll` 同时钟域结果。

| 指标 | 修改前 | 修改后 | 变化 |
|---|---:|---:|---:|
| WNS | -1.400 ns | -0.837 ns | +0.563 ns |
| TNS | -260.038 ns | -472.339 ns | -212.301 ns |
| 负 setup endpoint | 1006 | 1401 | +395 |
| synthesis 等效 Fmax | 156.25 MHz | 171.32 MHz | +15.07 MHz |
| Total LUT | 11592 | 11089 | -503 |
| LUTRAM | 564 | 276 | -288 |
| FF | 10331 | 10254 | -77 |

最终全量负路径的主要分布：

| 路径族 | 条数 | WNS | CSV TNS |
|---|---:|---:|---:|
| DCache tag -> Scoreboard | 456 | -0.787 ns | -154.115 ns |
| load issue bypass -> Scoreboard | 284 | -0.527 ns | -141.388 ns |
| DCache tag -> exec payload | 187 | -0.562 ns | -84.912 ns |
| StoreBuffer -> LoadQueue | 182 | -0.490 ns | -25.352 ns |
| StoreBuffer -> DCache | 120 | -0.519 ns | -25.278 ns |
| IROM -> Predictor | 24 | -0.837 ns | -11.310 ns |

上一版 60 条 predictor 内部反馈负路径已归零。新的 WNS 起点变为 IROM BRAM，经过
macro-move 指令字段判断和 request-PC 选择，终点是 PHT 读寄存器。这是当前“同拍识别
双指令融合并立即选择下一取指地址”的结构边界。

## 下一步

若继续保留 macro-move 的 IPC 收益，下一轮应给 IROM 生成窄 predecode sidecar，直接
提供“本 PC 是否形成 move pair”元数据，减少 IROM 数据后的 opcode/寄存器字段比较。
直接关闭 macro fusion 或给 predictor 反馈加一拍都会明显影响分支密集代码，不宜先做。

TNS 优先项是 `load_issue_bypass_data_q -> Scoreboard exception_tval/result`。这条链可从
异常 payload 的真实需求入手，避免普通 load completion 数据驱动 32-bit exception
字段。DCache 路径若要流水化，需要与 LoadQueue metadata 联合设计，并先用
`srcWithMext` 20M 检查额外 load latency。

## 产物

- `fpga/build/digital_twin_srcWithMext/reports/v42_local_btb_macro_fast_timing_summary.rpt`
- `fpga/build/digital_twin_srcWithMext/reports/v42_local_btb_macro_fast_all_violating_setup_paths.csv`
- `fpga/build/digital_twin_srcWithMext/reports/v42_local_btb_macro_fast_utilization_hier.rpt`
- `backup/20260719_212824/`
