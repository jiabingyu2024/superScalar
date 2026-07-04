# 020 结果 JSON、分支统计与中断落盘

日期：2026-07-03

## 目标

修正 src/rv32 仿真结果 JSON 过于杂乱的问题，并补充性能统计：

1. 精简 JSON 顶层字段，按 `correctness` 和 `perf` 分组。
2. 保留最后 LED 值、SEG 当前值和最后一次非零 SEG 显示值。
3. 记录 counter ms，避免只看最后清零后的 SEG 而丢失计时信息。
4. 记录分支预测命中率相关数据。
5. TIMEOUT 或键盘中断时也输出当前已经累计的部分结果。

## JSON 新结构

顶层只保留：

```text
test
mode
checker
status
reason
cycles
max_cycles
correctness
perf
```

src 的 `correctness` 重点：

```text
correctness.led.last_value
correctness.led.pass_seen
correctness.led.pass_cycle
correctness.seg.current_value
correctness.seg.pass_display_value
correctness.seg.pass_display_cycle
correctness.seg.value_at_last_led_write
correctness.counter.ms
correctness.counter.start_cycle
correctness.counter.stop_cycle
```

其中 `pass_display_value` 是最后一次非零 SEG 写值，用于保留 `0x37......` 这类通过条数/计时显示。`srcSmoke` 最终会把 SEG 清零，因此 `current_value` 可能为 0，但 `pass_display_value` 仍保留早期 `0x37000000`。

## 分支预测统计

通过 `VERILATOR_TB` 条件编译暴露 core `PerfIF`：

```text
dbg_perf_cycle
dbg_perf_commit
dbg_perf_branch
dbg_perf_branch_miss
```

rv32/myCPU 和 src/student_top harness 都会读取这些信号，并输出：

```text
perf.commit_count
perf.ipc
perf.branch_count
perf.branch_hit_count
perf.branch_miss_count
perf.branch_hit_rate
```

`branch_hit_rate = (branch_count - branch_miss_count) / branch_count`，无分支时为 0。

这些 debug 口只在 Verilator 构建中打开，不进入 FPGA 正式接口。

## TIMEOUT 与中断

主循环现在安装 `SIGINT/SIGTERM` handler。

退出行为：

| 场景 | JSON status | 说明 |
| --- | --- | --- |
| checker PASS | `PASS` | 正常通过。 |
| checker FAIL | `FAIL` | 正常失败。 |
| 达到 `MAX_CYCLES` | `TIMEOUT` | 输出已累计统计。 |
| Ctrl+C / SIGTERM | `INTERRUPTED` | 输出已累计统计，方便查看部分 branch hit rate、counter 和 MMIO 进展。 |

验证过 `SIGINT` 路径：

```text
status: INTERRUPTED
reason: interrupted by SIGINT
cycles: 623603
perf.branch_hit_rate: 0.745304
correctness.counter.ms: 12
```

## 修改文件

```text
rtl/core/myCPU.sv
rtl/soc/student_top.sv
scripts/run_verilator.py
tb/verilator/sim_common.h
tb/verilator/perf_stats.h
tb/verilator/perf_stats.cpp
tb/verilator/sim_result.cpp
tb/verilator/sim_control.h
tb/verilator/sim_control.cpp
tb/verilator/main_mycpu.cpp
tb/verilator/main_student_top.cpp
tb/verilator/dut_mycpu_io.h
tb/verilator/dut_mycpu_io.cpp
tb/verilator/dut_student_top_io.h
tb/verilator/dut_student_top_io.cpp
docs/sim/verilator_plan.md
docs/archive/2026-07-03/020_result_json_perf_and_interrupt.md
```
