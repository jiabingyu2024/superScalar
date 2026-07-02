# 存储与测试契约

## 主仿真 DUT

主 Verilator DUT 使用 `myCPU`，不是 `core`，也不是 `student_top`。

原因：

1. `core` 外部是 SystemVerilog interface，C++ testbench 直接驱动不如扁平端口稳定，并且会绕过真实赛事 CPU 适配层。
2. `student_top` 包含 SoC 壳、外设桥、IP 行为模型、显示/counter/按键开关同步等逻辑，早期 debug 范围过大。
3. `myCPU` 端口扁平，同时覆盖 core 到赛事接口的关键适配行为。

## DUT 分层

| 层级 | DUT | 用途 |
| --- | --- | --- |
| L1 | `myCPU` | rv32 正确性和 src 性能仿真的主入口。 |
| L2 | `student_top` | L1 稳定后的 SoC 壳集成 smoke。 |
| L3 | `top` | FPGA/Vivado 上板入口。 |

## IROM 契约

`myCPU` 暴露两个取指端口：

```text
irom_addrA = 当前取指地址
irom_addrB = 当前取指地址 + 4
irom_enaA/B = 取指使能
irom_dataA/B = 返回的两条指令
```

取指时序固定为 BRAM 风格的一拍地址寄存、寄存地址组合读：

| 周期 | 行为 |
| --- | --- |
| T0 上升沿前 | `myCPU` 给出 `irom_addrA/B` 和 `irom_enaA/B`。 |
| T0 上升沿 | IROM 行为模型寄存 `addrA/B`；`FetchStage` 同时寄存 PF 阶段 PC/预测 payload。 |
| T0 上升沿后 | `irom_dataA/B = mem[addr_q]` 组合有效，并和 `FetchStage` 保存的 payload 同拍绑定。 |

因此主 Verilator TB 不允许把 IROM 简化成“当前地址组合读当前指令”的零延迟模型，也不应额外增加到两拍同步读。否则 IF 阶段 PC 和指令会错位。

## DRAM/MMIO 契约

`DramAccessIF` 明确区分“访问被接受”和“读数据有效”：

```text
accessReady: 本周期地址/命令被接受
readData: 固定延迟后的读返回数据
```

`myCPU` 当前固定 `accessReady=1'b1`，语义是“本周期命令被接收”，不是“读数据本周期有效”。DRAM 读返回固定两拍：

| 周期 | 行为 |
| --- | --- |
| T0 | `ExecuteMemStage` 发起 load，`readEn=1`，地址被 DRAM 接收；load 的 ROB/Rd/addr/subtype 进入 `loadMetaPipe0`。 |
| T1 | load metadata 从 `loadMetaPipe0` 推进到 `loadMetaPipe1`，DRAM 内部读地址/valid 继续推进。 |
| T2 | `readData` 有效，`ExecuteMemStage` 用 `loadMetaPipe1` 的 metadata 对齐生成 WB 结果。 |

store 写入同样在命令被接受的周期生效；byte mask 和非对齐字节移位由 `ExecuteMemStage` 与 `dram_driver` 配合完成。后续 Verilator memory model 必须保留这个两拍 load 返回关系，否则可能出现仿真通过但 FPGA 失败。

## CSR 和无 cache 约束

当前 core 不实现 I/D cache。`FENCE/FENCE.I` 在项目内定义为 serial NOP：它们需要走 serial 路径保证顺序边界，但不产生 cache flush、取指失效或额外内存副作用。

CSR 当前只承诺测试子集：

| CSR | 地址 | 当前行为 |
| --- | --- | --- |
| `mstatus` | `0x300` | 支持有限 MIE/MPIE 位读写。 |
| `mtvec` | `0x305` | 写入时低两位清零；ECALL 跳转使用它。 |
| `mepc` | `0x341` | ECALL/EBREAK 写入 trap PC，MRET 使用它返回。 |
| `mcause` | `0x342` | ECALL 写入 machine ecall cause 11，EBREAK 写入 breakpoint cause 3。 |

非白名单 CSR 当前读 0、写忽略；这不是完整 RISC-V privileged 行为。rv32/src 测试选择必须和这个子集一致，除非后续明确扩展 CSR 实现。

## rv32 通过标准

采用严格 `tohost` 判定：

| 条件 | 结果 |
| --- | --- |
| 写 `tohost == 1` | PASS |
| 写 `tohost != 0 && tohost != 1` | FAIL，并记录失败码 |
| 超时 | TIMEOUT，失败 |
| 无法定位 `tohost` | UNSUPPORTED，不能算通过 |

当前 riscv-tests 示例中 `tohost` 通常在 `0x80001000`，但 testbench 应优先从 ELF symbol 中解析地址，不应全局硬编码。

## src 测试契约

src 测试有独立通过逻辑，后续由用户补充。框架需要预留：

1. 用户提供的 src pass/fail 规则。
2. 赛事 counter/MMIO 行为。
3. 在不修改 `myCPU.sv` 端口的前提下，尽量保留内部性能指标观测能力。
