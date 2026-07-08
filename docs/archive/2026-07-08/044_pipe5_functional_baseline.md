# 五级流水功能基线记录

日期：2026-07-08

## 目标

在 Phase 0 工程骨架基础上，先建立可运行的正确性基线。当前 `riscv_cpu` 采用顺序单发射、多周期执行方式实现 RV32I/M/MI 目标子集，还不是最终高 IPC 五级流水。

## 已实现

`rtl/core/riscv_cpu.sv`：

1. 单端口 IROM 取指，reset PC=`0x8000_0000`。
2. RV32I 算术、逻辑、移位、比较、branch、JAL/JALR。
3. LB/LH/LW/LBU/LHU 和 SB/SH/SW。
4. RV32M：MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU。
5. CSR 子集：`mstatus/mtvec/mscratch/mepc/mcause/misa`。
6. `ecall/ebreak/mret`。
7. `fence/fence.i` 作为 serial NOP。
8. 基础 perf：cycle/commit/branch/branch_miss。

SoC 路径：

1. `student_top` 使用单端口 `IROM_0`。
2. `SocMemBridge` 连接 DRAM/MMIO/counter/display。
3. `DramBramAdapter` 提供 ready/valid 数据访问。

## 验证结果

已通过：

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
make sim-rv32 SUITE=rv32ui NO_BUILD=1 MAX_CYCLES=1000000
make sim-rv32 SUITE=rv32um NO_BUILD=1 MAX_CYCLES=2000000
make sim-rv32 SUITE=rv32mi NO_BUILD=1 MAX_CYCLES=2000000
make sim-src TEST=srcSmoke NO_BUILD=1 MAX_CYCLES=100000000 CPU_FREQ_MHZ=50
```

结果：

| 套件 | 结果 |
| --- | --- |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |
| `srcSmoke` | PASS |

`srcSmoke` 当前性能：

```text
cycles       = 92,976,339
commit_count = 30,758,720
IPC          = 0.330823
```

## 当前限制

1. 现在是顺序多周期功能核心，不是最终 pipeline。
2. IPC 约 0.33，主要因为每条普通指令仍经过取指/执行多周期。
3. D-cache/write buffer 尚未接入执行路径。
4. RV32M 目前在功能核心里直接计算，后续需要替换为 Vivado 友好的 `MulDivUnit`/IP 或多周期实现。
5. 没有运行 Vivado synthesis/implementation。

## 下一步

性能优化从这个正确性基线继续：

1. 把取指和执行重叠，先把普通指令从约 3 cycle/instr 降到约 2 cycle/instr。
2. 再拆成 IF/ID/EX/MA/WB pipeline。
3. 接入 forwarding/load-use stall。
4. 接入 D-cache/write buffer。
5. 替换 M 扩展为 Vivado 友好的多周期路径。
