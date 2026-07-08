# 五级流水小 BTB IPC 优化记录

日期：2026-07-08

## 目标

在顺序预取优化基础上加入小 BTB，减少循环 taken branch/JAL/JALR 的重定向泡。目标是提升目标程序运行速度，同时保持结构足够小，避免 Vivado Fmax 被复杂预测器拖垮。

## 修改

`rtl/core/riscv_cpu.sv`：

1. 新增 64-entry direct-mapped BTB。
2. BTB entry 包含：
   - `valid`
   - `tag = pc[31:8]`
   - `target`
3. `ST_EXEC/ST_WAIT_MEM` 预取地址从固定 `pc+4` 改为：

```text
btb_hit ? btb_target : pc + 4
```

4. JAL/JALR 和 taken branch 更新 BTB target。
5. conditional branch not-taken 且 BTB hit 时清除 entry。
6. 只有真实 next PC 与预测 next PC 不一致时才回 `ST_FETCH` 插 bubble。

## 验证

已通过：

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
make sim-rv32 SUITE=rv32ui NO_BUILD=1 MAX_CYCLES=1000000
make sim-rv32 SUITE=rv32um NO_BUILD=1 MAX_CYCLES=2000000
make sim-rv32 SUITE=rv32mi NO_BUILD=1 MAX_CYCLES=2000000
make sim-src TEST=srcSmoke NO_BUILD=1 MAX_CYCLES=40000000 CPU_FREQ_MHZ=50
```

结果：

| 测试 | 结果 |
| --- | --- |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |
| `srcSmoke` | PASS |

## 性能变化

`srcSmoke`：

| 版本 | cycles | commit | IPC | branch miss rate |
| --- | --- | --- | --- | --- |
| 功能基线 | 92,976,339 | 30,758,720 | 0.330823 | 59.45% |
| 顺序预取 | 39,101,279 | 30,758,601 | 0.786639 | 59.45% |
| 顺序预取 + BTB | 34,014,770 | 30,758,589 | 0.904272 | 19.88% |

BTB 对 `srcSmoke` 有实际收益，且结构小，适合作为当前默认前端策略。

## Vivado 注意

1. BTB reset 只清 valid。
2. target/tag payload 不需要 reset。
3. 若 Vivado critical path 出现在 BTB lookup -> PC mux，可将 entry 数降到 32 或打一拍预测输出。
4. 当前 BTB 不做全局历史、RAS、2-way，相比复杂预测器更利于 Fmax。
