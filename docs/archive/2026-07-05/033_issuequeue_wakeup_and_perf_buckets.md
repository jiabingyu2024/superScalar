# IssueQueue 保守预计唤醒与性能分桶计数

## 背景

用户要求先执行 `032_srcWithMext_low_ipc_microarch_analysis.md` 中第一、第二优先级：

1. 修复 IssueQueue 预计唤醒只移位、不置 ready 的问题。
2. 增加 stall/resource/width 性能分桶计数，帮助后续定位低 IPC。
3. 由于 `031_execute_mem_load_return_merge.md` 的 MEM/load 返回合并在短 src 观测中没有稳定收益，且可能加重 load 对 StoreBuffer store commit 的挤压，本轮先回退该优化。

## RTL 修改

### 1. 回退 ExecuteMem load 返回合并

`rtl/core/ExecuteStage/ExecuteMemStage.sv` 恢复为保守策略：

```systemverilog
loadReturnBlocked = loadMetaPipe1.valid && currentMemValid && !ctrl.exPipe.flush;
```

即只要上一条 load 返回且当前 MEM pipe 中存在任意有效 uop，就拉 `ctrl.exStallReq`。这会保留旧的 0.5 IPC 风险，但避免当前单端口 DRAM 读优先下进一步压缩 StoreBuffer head store 的提交机会。

### 2. IssueQueue 预计唤醒

`rtl/core/DispatchStage/IssueQueue.sv` 修复了 `srcAShift/srcBShift` 移到 1 后不置 ready 的问题：

```text
srcMatched && !srcRdy && srcShift == 1
  -> srcRdy = 1
  -> srcMatched = 0
  -> srcShift = 0
```

但实际启用范围做了保守限制：只有生产者 `delay == 1` 时，IssueQueue 才给消费者写入 `srcMatched/srcShift`。MUL/MEM/DIV 等 `delay > 1` 的生产者仍等待 `WriteBackStage` 的真实 `IssueWakeup`。

这样做的原因是：第一次按所有 `delay` 启用预计唤醒后，`rv32um-p-mul` 和 `rv32um-p-div` 失败，说明长延迟 IP/MEM 的结果可用相位和当前 `delay_for()` 估计不完全一致。保守版本先获得 ALU 依赖链收益，并保持 RV32M 正确性。

## 性能分桶

新增 `PerfIF` 字段，并通过 `myCPU/student_top` 的 `VERILATOR_TB` debug 端口导出到 C++ JSON：

| JSON 字段 | 来源 | 语义 |
| --- | --- | --- |
| `perf.stalls.frontend_cycles` | `ctrlIF.pfPipe.stall` | 前端被全局阻塞周期。 |
| `perf.stalls.id/rn/ds/is/rr/ex/wb_cycles` | 各级 `PipeCtrlPath.stall` | 各级 stall 周期，非互斥。 |
| `perf.stalls.recovery_cycles` | `recoveryInfo.valid` | recovery 事件周期。 |
| `perf.resources.rob_full_cycles` | `ctrlIF.robFull` | ROB 满相关阻塞。 |
| `perf.resources.issue_queue_full_cycles` | `ctrlIF.issueQueueFull` | IQ 满相关阻塞。 |
| `perf.resources.free_list_empty_cycles` | `ctrlIF.freeListEmpty` | FreeList 空相关阻塞。 |
| `perf.resources.store_buffer_full_cycles` | `dsStallReq && !storeBuffer.allocRdy` | StoreBuffer 分配不可用相关阻塞。 |
| `perf.resources.serial_block_cycles` | `ctrlIF.serialBlock` | serial/system 顺序化阻塞。 |
| `perf.mem_stalls.load_return_block_cycles` | `ExecuteMemStage.loadReturnBlocked` | load 返回和当前 MEM pipe 冲突造成的 EX stall。 |
| `perf.mem_stalls.load_access_block_cycles` | `ExecuteMemStage.loadAccessBlocked` | load 发起被访问通道阻塞。 |
| `perf.mem_stalls.store_commit_blocked_by_load_cycles` | StoreBuffer commit req + `dromAccess.exReadEn` | store 提交被 DRAM 读优先压住。 |
| `perf.width.dispatch/issue/commit.*` | core 内部各阶段 valid 数 | 每周期 0/1/2 宽度分布。 |

这些计数只用于观测，不参与控制和数据通路。

## 验证结果

已重新 build：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

基础回归：

| 命令 | 结果 |
| --- | --- |
| `make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 OBJCACHE=` | PASS |
| `make sim-rv32 TEST=rv32ui-p-lw NO_BUILD=1 OBJCACHE=` | PASS |
| `make sim-rv32 TEST=rv32ui-p-sw NO_BUILD=1 OBJCACHE=` | PASS |
| `make sim-rv32 TEST=rv32um-p-mul NO_BUILD=1 OBJCACHE=` | PASS |
| `make sim-rv32 TEST=rv32um-p-div NO_BUILD=1 OBJCACHE=` | PASS |

短 src 抽样：

| 命令 | 结果 | 关键观测 |
| --- | --- | --- |
| `make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=` | TIMEOUT | IPC 0.49767，`load_return_block_cycles=98297`，`rob_full_cycles=148405`，issue 双发仅 555 周期。 |
| `make sim-src TEST=srcSmoke MAX_CYCLES=100000 NO_BUILD=1 OBJCACHE=` | TIMEOUT | IPC 0.4528，`recovery_cycles=5144`，`rob_full_cycles=8361`，`load_return_block_cycles=304`。 |

短 src 结果只用于确认 TB/JSON 和局部性能现象，不代表完整 PASS 性能。

## 当前结论

1. `IssueQueue` 的 `srcShift == 1` 不置 ready 是确定问题，已修复为保守版本。
2. 长延迟生产者不能直接使用当前 `delay_for()` 全量预计唤醒，否则会破坏 RV32M 正确性；后续若要放开 MUL/MEM/DIV，需要逐类重校 `delay_for()` 与 WB bypass/RegFile 写回相位。
3. 当前短 `srcWithMext` 抽样显示 `load_return_block_cycles` 很高，说明回退 031 后 MEM load 返回冲突确实是明显瓶颈；但 031 的直接合并策略可能和 StoreBuffer/DRAM 读优先冲突，后续更稳妥方向应是先改 DRAM load/store 仲裁或引入更明确的 MEM 返回队列。
4. `rob_full_cycles` 很高，说明 ROB head/commit/长延迟完成也在压住前端。下一步优化不应只盯单个 load 返回冲突，需要结合 `width.commit`、`serial_block`、M 单元完成相位和 StoreBuffer 提交机会共同判断。

## 后续建议

1. 在波形中抽样 `srcWithMext` 的 `robFull` 时段，确认 ROB head 是等待 load、MUL/DIV、branch recovery 还是 store commit。
2. 若继续做 MEM 优化，优先设计带公平性的 load/store 仲裁或 store commit aging，而不是简单让 load 连续发起。
3. 对预计唤醒逐类放开时，建议新增 `alu-use/mul-use/div-use/load-use` 定向微测试，并用波形校准消费者 EX 读操作数的准确周期。
