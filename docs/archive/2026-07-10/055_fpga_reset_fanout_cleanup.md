# FPGA reset fanout 清理与 GUI 文档整理

日期：2026-07-10

## 1. 用户侧流程调整

按 Windows Vivado GUI Tcl Console 使用习惯完成以下调整：

1. 删除额外的 `fpga/run_vivado_stage.tcl`。
2. 重写 `docs/fpga/vivado_project.md`，只保留 GUI Tcl Console 建工程、检查属性、分阶段 `launch_runs` 和生成报告的命令。
3. 新增 `docs/fpga/README.md`，明确当前操作手册与 IP 时序契约的职责边界。
4. 单次运行结果继续归档到 `docs/archive/`，不写入当前操作手册。

## 2. RTL 优化原则

FPGA 中大范围异步 reset 会增加高扇出网络和 control set，限制寄存器打包、复制、重定时和 RAM inference。对于 ready/valid 结构，payload 在 valid 为 0 时没有协议意义，因此只复位 ownership/state 位通常更合适。

本轮仅修改可以由 `valid/count/state` 严格证明安全的 payload，没有删除架构状态或影响有效事务的数据初始化。

## 3. 修改内容

### 3.1 Completion bundle

`CoreBackend.sv` 的 completion payload 不再 reset/clear，只清 `complete_valid`。ROB 和 BusyTable 仅在 `complete_valid` 有效时消费 payload，下一活动周期会覆盖全部 completion 字段。

### 3.2 ROB

`ROB.sv` reset/clear 只清 `head_q/tail_q/count_q`。当 count 为 0 时 entry 不会进入 retire；新 allocation 会覆盖 entry 的全部字段，因此无需复位 32 项宽 payload。

### 3.3 Issue Queue

`CompressedQueue.sv` reset/clear 只清 `valid_q/count_q`。issue 和 compaction 均由 `valid_q` 门控，push 会覆盖完整 uop。

### 3.4 Branch Predictor

`BranchPredictor.sv` 保留 PHT/local history 的确定性初始化和 `btb_valid_q/ras_count_q` reset；移除 BTB tag/target/type payload 和 RAS payload reset。预测输出分别由 BTB valid 和 RAS count 门控。

### 3.5 DCache

`DCache.sv` 保留 valid/dirty/LRU 和状态机 reset，移除 tag array reset。tag compare 由对应 valid bit 门控。

这不会解决当前 DCache data array 以 FF/LUT 实现的问题。DCache RAM 化需要单独修改同步读 latency 和 hit pipeline，必须等待新的 routed 基线后实施。

### 3.6 StoreBuffer 与通用缓冲器

- `StoreBuffer.sv` reset 只清每项 valid/retired，不复位地址、数据、mask 和 ROB index。
- `PipeReg.sv` 只复位 valid，不复位 invalid data。
- `SkidBuffer.sv` 只复位 full；empty 时输出直接旁路输入，不选择缓存 payload。

## 4. 预期 FPGA 收益

根据当前结构尺寸和旧综合层次报告，本轮从异步 reset 网络中移除的 payload 约为数万寄存器，主要来自：

- ROB：约 8.8k FF 层次中的绝大部分 payload；
- 三类 Issue Queue：约 4.1k FF 层次中的 entry payload；
- BTB/RAS：约 14.6k payload bits；
- DCache tag：约 5.1k bits；
- StoreBuffer 与 completion bundle：约 1k 量级 payload bits。

这些数字表示 reset load/control-set 缩减估算，不表示 FF 总数一定等量下降。最终收益必须通过新的 `report_control_sets`、high-fanout 和 placed utilization 报告确认。

## 5. Verilator 回归

### RV32

| Suite | 结果 |
| --- | ---: |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |

### `srcSmoke`

- 状态：PASS
- cycles：33,798,107
- LED：`0x01221c08`
- SEG：`0x37000675`
- IPC：0.910069

cycles 和最终签名与优化前一致。

### `srcWithMext` 小窗口 difftest

- 窗口：200,000 cycles
- 状态：TIMEOUT，符合小窗口预期
- difftest commits：130,742
- last PC：`0x80000e14`
- RV32I count：37
- M extension count：8
- RV32I fail count：0
- 未出现 crash、fail marker 或 early execution error

未运行全量 `srcWithMext`。

## 6. Vivado 待确认项

本轮没有启动 Vivado。用户在 GUI Tcl Console 运行后需要重点比较：

1. `Synth 8-5413` 是否归零。
2. `cpu_rst_sync` fanout 和 BUFG 自动插入是否改善。
3. FDCE/FDPE 数量和 control set 数量是否下降。
4. ROB、Issue Queue、BPU、DCache 层次 LUT/FF 是否变化。
5. DCache tag 是否开始推断为更合适的存储结构。
6. setup/hold、CDC、DRC 和 methodology 是否无 blocker。

在新报告返回前，不能声明 FPGA QoR 已改善，只能确认 RTL 行为回归通过且 reset 结构更适合 FPGA 综合。

## 7. 已确认但本轮不直接修改的热点

以下问题明确存在，但会改变 latency、端口或调度结构，必须由新的综合/route 报告驱动后续工作：

1. `CoreDCache` data array 仍为组合读、多点写结构，旧报告中约 49.5k LUT/71.6k FF；真正 RAM 化需要增加同步 lookup pipeline。
2. `CoreBranchPredictor` 的 PHT/local-history 需要确定初值且双 lane 组合读取；改为 LUTRAM/BRAM 需要处理初始化和预测返回拍数。
3. `CoreROB` 有多 allocation、completion、retire 端口，`CoreCompressedQueue` 每周期全表 wakeup、选择和压缩；两者仍会形成大 mux/全表组合网络。
4. `CorePhysRegFile` 多组合读口和多写口仍是约 9.3k LUT 热点；RAM 化需要 bank/复制、写冲突与 bypass 设计。

这些项目不能仅靠 `ram_style`、`dont_touch` 或 false path 解决。
