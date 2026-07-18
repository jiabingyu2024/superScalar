# RV32 Zb 扩展配置与实现

## 1. 功能边界

当前 core 支持 `data/rv32uzb*` 中六个 RV32 位操作子扩展，共 39 个独立回归项。指令编码和语义按 RISC-V Bit-Manipulation 1.0.0 实现；配置是编译期常量，修改后必须重新编译 RTL/Verilator/Vivado 工程。

配置位置：`rtl/core/CoreConfigPkg.sv`。

| 配置 | 默认值 | 独立指令覆盖 |
| --- | ---: | --- |
| `SUPPORT_ZBA` | 1 | `sh1add sh2add sh3add` |
| `SUPPORT_ZBB` | 1 | `andn orn xnor clz ctz cpop max maxu min minu orc.b rev8 rol ror rori sext.b sext.h zext.h` |
| `SUPPORT_ZBC` | 1 | `clmul clmulh clmulr` |
| `SUPPORT_ZBKB` | 1 | `brev8 pack packh zip unzip`，以及下述共享指令 |
| `SUPPORT_ZBKX` | 1 | `xperm4 xperm8` |
| `SUPPORT_ZBS` | 1 | `bclr bclri bext bexti binv binvi bset bseti` |

`andn/orn/xnor/rol/ror/rori/rev8` 同时属于 Zbb 和 Zbkb，因此任一对应配置为 1 时均可译码。配置为 0 且没有其他扩展共享该指令时，译码器产生 illegal-instruction；不是把指令当作基础 ALU 操作继续执行。

## 2. 数据流与时序取舍

Zb 指令在 `CoreRv32Decoder` 中被标为 `TUBE_TYPE_MUL/FU_TYPE_MULDIV`，经现有 MULDIV Issue Queue 进入 `CoreMulDivPipe`。这样没有扩展普通双发射 INT ALU 的 PRF→ALU→writeback 组合锥，RV32I 的两条 INT 发射通路、ready 和旁路结构保持不变。

- 轻量操作：在复杂整数管线中组合计算，结果由现有 writeback 边界寄存；`MD_SPECIAL` 使该 1-wide 管线的接收间隔为 2 拍。
- `clmul/clmulh/clmulr`：共享一套 64-bit 累计器，每拍执行一次条件 XOR、被乘数左移和乘数右移，共 32 步；避免推导 32×32 carry-less multiplier 长组合路径。
- flush/recovery：`clear_i` 清除状态和有效位，错误路径 Zb 结果不会写 PRF；CLMUL 没有外部不可取消响应，因此不需要 DIV 的 drain 流程。
- M 扩展：原 MUL 流水和 DIV/REM 状态机保持不变；只有操作枚举从 4-bit 扩为 6-bit。

该选择保护基础 workload 的 IPC/Fmax，但 Zb 密集 workload 会受 1-wide 复杂整数队列、轻量操作 II=2 和 CLMUL 32 步延迟限制。如果后续编译器 workload 大量使用 Zba/Zbb/Zbs，可把轻量子集迁回独立的流水化 Bitmanip FU，而不是直接塞入普通 ALU 关键路径。

## 3. 配置方法

全开配置：

```systemverilog
localparam logic SUPPORT_ZBA  = 1'b1;
localparam logic SUPPORT_ZBB  = 1'b1;
localparam logic SUPPORT_ZBC  = 1'b1;
localparam logic SUPPORT_ZBKB = 1'b1;
localparam logic SUPPORT_ZBKX = 1'b1;
localparam logic SUPPORT_ZBS  = 1'b1;
```

只需把不需要的扩展改为 `1'b0`，然后重新生成仿真模型和 FPGA 工程。配置是综合常量，关闭的译码分支和只被该扩展使用的执行选择可由综合器裁剪。

## 4. 回归结果（2026-07-18）

| 回归 | 结果 |
| --- | ---: |
| RV32UZba | 3/3 PASS |
| RV32UZbb | 18/18 PASS |
| RV32UZbc | 3/3 PASS |
| RV32UZbkb | 5/5 PASS |
| RV32UZbkx | 2/2 PASS |
| RV32UZbs | 8/8 PASS |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |

`srcSmoke` 完整 PASS：42,504,434 cycles、30,758,614 commits、IPC 0.723657，与修改前同版本记录一致。该 workload 的 `mul_uops/muldiv_busy_cycles` 均为 0，说明 Zb 逻辑没有改变基础指令工作负载的动态执行路径。

Verilator 编译没有新增 `LATCH`、`MULTIDRIVEN` 或 `UNOPTFLAT`；日志中仍有仓库既存的 timescale、ROB/Backend 索引宽度和 Execute/Backend `UNOPTFLAT` 告警。

## 5. 物理实现验收

当前证据只能证明功能与仿真 IPC。Fmax 必须以当前 worktree 的 Vivado 综合/实现报告为准，重点检查：

1. `CoreMulDivPipe` 的 Zb 单周期结果到 `special_result_q` 路径，尤其 `clz/ctz/cpop/xperm*`。
2. 扩为 6-bit 的 `muldiv_op` 在 issue queue、metadata pipeline 和状态译码中的扇出。
3. CLMUL 64-bit XOR/移位到累计寄存器的单拍路径。
4. 关闭不用的扩展后，相关逻辑是否被综合裁剪。

规范参考：[RISC-V Bit-Manipulation Extensions, Version 1.0.0](https://docs.riscv.org/reference/isa/unpriv/b-st-ext.html)。
