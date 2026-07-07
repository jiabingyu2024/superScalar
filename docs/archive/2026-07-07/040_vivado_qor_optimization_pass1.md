# Vivado QoR 优化第一轮修改记录

日期：2026-07-07

## 目标

根据 `039_vivado_synthesis_qor_review.md` 的审查结论，先做低风险、可快速验证的一轮 RTL/工程脚本优化。目标不是一次性重构整个后端，而是先减少 Vivado 最敏感的高扇出 reset/flush 控制网，并避免 implementation 继续卡在 power optimization。

## 本轮修改范围

### 1. 大数组 reset/flush 只清 valid/控制位

修改文件：

- `rtl/core/DispatchStage/IssueQueue.sv`
- `rtl/core/DispatchStage/Payload.sv`
- `rtl/core/DispatchStage/ROB.sv`
- `rtl/core/DispatchStage/StoreBuffer.sv`
- `rtl/core/PreFetchStage/BTB.sv`
- `rtl/core/RenameStage/SpecRAT.sv`
- `rtl/core/RenameStage/FreeList.sv`

修改原则：

- 队列 flush/reset 时，只清 `valid/head/tail/count/chkptValid` 这类控制状态。
- 不再清整条 entry/payload/checkpoint table。
- 新写入 entry 时仍然完整覆盖该 entry。
- 对可能读到无效 entry 的接口，组合输出显式清零，避免仿真中 X 扩散。

具体变化：

- `IssueQueue`：`IntIssueQueue` 和 `InOrderIssueQueue` reset/flush 不再清 `entries[]`，只清 `valid[]` 和 FIFO 控制指针。
- `Payload`：reset/flush 不再清 `entries[]`，只清 `valid[]`；`PayloadPopRes.entry` 在 `valid=0` 时输出 `'0`。
- `ROB`：reset/flush 不再清完整 `entries[]`，只清每项 `entries[i].valid`；`RobPopRes` 默认清零，只有 entry valid 时才输出 payload。
- `StoreBuffer`：reset/flush 不再清 `entries[]`，只清 `valid[]/head/tail/count`。
- `BTB`：reset 不再清 `tagTable[]/targetTable[]`，只清 `validTable[]`。
- `SpecRAT`：reset 不再初始化所有 `chkptRat[][]`，只清 `chkptValid[]`；checkpoint 创建时仍完整写入 checkpoint。
- `FreeList`：reset 不再清 `chkptMask[]`，只清 `chkptValid[]`；checkpoint 创建时仍完整写入 mask。

预期收益：

- 减少带异步 reset 的 FF 数量。
- 降低 reset/flush 高扇出控制网压力。
- 降低 `power_opt_design` 遇到巨大 TFI/TFO cone 的概率。
- 这是 RAM 化重构前的保守优化，不改变队列语义。

### 2. Vivado 工程脚本增加 QoR 开关

修改文件：

- `fpga/create_vivado_project.tcl`

新增环境变量：

```tcl
FPGA_KEEP_EQUIVALENT_REGISTERS=true
FPGA_ENABLE_POWER_OPT=false
```

实际设置：

```tcl
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS $keep_equivalent_registers [get_runs synth_1]
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED $enable_power_opt [get_runs impl_1]
set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED $enable_power_opt [get_runs impl_1]
```

本轮默认 `FPGA_ENABLE_POWER_OPT=false`，原因是当前 Vivado 2023.2 已经在 power optimization 阶段报：

```text
HACOOException: Too many TFIs and TFOs in design
EXCEPTION_ACCESS_VIOLATION
```

关闭 power optimization 是为了让 implementation 先继续完成 place/route/bitstream。

## 刻意没有修改的点

### RegFile 没有移除 reset

`RegFile` 仍保留 reset 清零，因为当前测试环境默认架构寄存器初值为 0。直接删除 PRF reset 可能导致 reset 后未写过的物理寄存器读出 X 或随机值，功能风险高。

后续若要优化 PRF，应改为更明确的 FPGA 友好结构，例如：

- 单边沿同步读写。
- 明确 banking/replication。
- rename 初始映射和 ready 状态保证启动时可见寄存器为 0。

### BHB/PHT 没有去 reset

`BHB` 的 PHT/chooser 若只删 reset 而不加初始化，第一次 update 会从 X 状态做 saturating update，仿真和硬件行为都不干净。本轮只处理 `BTB` 的 tag/target payload reset。

后续可以用 FPGA 支持的 init value 或同步 RAM 初始化方式重构 BHB。

### 没有把 IssueQueue/ROB/Payload 改成 RAM

本轮只是第一步减少 reset 负担。真正显著降低 LUT 的下一步仍然是：

- `Payload` 同步 RAM 化。
- `IntIssueQueue` 拆 CAM 状态和 payload RAM。
- `ROB` 拆 valid/done bit-vector 与 payload RAM。
- MEM/MUL in-order queue 改 RAM/FIFO + head shadow。

### DramAccessIF modport 本轮未改

`039` 中建议补齐 `DramAccessIF` modport。当前 `core` 端口使用裸 interface，是因为 `core` 内部还要把同一个 interface 继续传给 `ExecuteMemStage` 和 `StoreBuffer` 两个不同 modport。直接把 `core` 端口改成某一个 modport 有连接兼容性风险。本轮先不动该接口，后续应单独重构为：

- `core` 顶层端口只暴露 memory-side modport。
- core 内部另建 backend memory arbitration interface。
- `ExecuteMemStage`/`StoreBuffer` 只连接内部 backend interface。

## 验证结果

### 构建

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
```

结果：均通过，未发现语法或 elaboration 错误。

### 最小 RV32 用例

```text
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 MAX_CYCLES=200000
```

结果：`rv32ui-p-simple: PASS`

### RV32 全量快速回归

```text
make sim-rv32-all NO_BUILD=1 MAX_CYCLES=1000000
```

结果：

- `rv32mi/*`：通过。
- `rv32ui/*`：通过。
- `rv32um/*`：通过。
- `rv32uzb*`：失败。

说明：失败集中在 Zb 扩展测试，和本轮 Vivado QoR 优化无直接对应关系；基础 RV32I/M/MI 路径通过。

### srcSmoke

```text
make sim-src TEST=srcSmoke NO_BUILD=1 MAX_CYCLES=2000000
```

结果：超时。结果文件显示实际运行到 `20000000` cycles，仍在持续 commit：

```text
status = TIMEOUT
commit_count = 10736975
ipc = 0.536849
pass_marker_seen = false
```

判断：这不是早期死锁；本轮没有把它作为 pass/fail 依据。后续若要确认 src 程序完整通过，需要用默认更高 cycle 上限或专门的 src 回归配置。

## 下一轮建议

优先做 `Payload` RAM 化，因为它边界最清晰、风险低、资源也明显：

1. 将 `PayloadEntryPath entries[]` 改为同步读 RAM。
2. flush/reset 只清 `valid[]`。
3. `IssueStage` 发出 `payloadIndex` 后打一拍获得 payload。
4. 对 `ReadRegStage` 输入增加对应延迟或插入小型 payload-read stage。
5. 重新跑 RV32I/M/MI，并对比 Vivado `payload` 层级资源。

如果这一步收益明显，再按同样方法处理：

1. `BTB/BHB` 表 RAM 化。
2. `MEM InOrderIssueQueue` 改 FIFO/RAM + head shadow。
3. `ROB` 拆字段。
4. `IntIssueQueue` 分组 select。
