# 五级流水顺序预取 IPC 优化记录

日期：2026-07-08

## 目标

在功能基线通过后，先做低风险 IPC 优化：让执行当前指令时同时发起下一条顺序指令取指。普通非跳转指令不再回到 `FETCH` 状态，而是直接留在 `EXEC` 状态执行下一拍返回的指令。

## 修改

`rtl/core/riscv_cpu.sv`：

1. `ST_EXEC/ST_WAIT_MEM` 时 `irom_addr = pc_q + 4`，提前取下一条顺序指令。
2. 普通指令提交后 `state_q <= ST_EXEC`。
3. taken branch、JAL/JALR、trap、mret 等 redirect 事件仍回到 `ST_FETCH`，重新取目标 PC。
4. load 等待期间继续预取 `pc+4`；load 返回后直接进入下一条执行。
5. `dmem` 请求组合逻辑改为使用当前执行指令 `exec_inst_c`。

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

| 版本 | cycles | commit | IPC |
| --- | --- | --- | --- |
| 功能基线 | 92,976,339 | 30,758,720 | 0.330823 |
| 顺序预取优化后 | 39,101,279 | 30,758,601 | 0.786639 |

收益来自普通顺序路径接近每拍执行一条；剩余损失主要来自 taken branch redirect、load 等待和未做 BPU/D-cache。

## 后续

1. 将当前 streaming 顺序执行结构继续拆成显式 IF/ID/EX/MA/WB pipeline 寄存器。
2. 增加 BPU，降低 taken branch 的取指泡。
3. 接入 D-cache/write buffer，降低真实访存 stall。
4. 将 M 扩展替换为 Vivado 友好的多周期 `MulDivUnit`。
