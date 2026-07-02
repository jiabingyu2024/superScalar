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

仿真 memory model 必须匹配 RTL 和 SoC/IP 行为模型预期的有效时序。除非 RTL 明确改成零延迟取指模式，否则不要用过度理想化的零延迟模型掩盖问题。

## DRAM/MMIO 契约

`DramAccessIF` 明确区分“访问被接受”和“读数据有效”：

```text
accessReady: 本周期地址/命令被接受
readData: 固定延迟后的读返回数据
```

`ExecuteMemStage` 使用 `loadMetaPipe0/loadMetaPipe1` 对齐 load 元信息和 `readData`。后续 Verilator memory model 必须保留这个延迟关系，否则可能出现仿真通过但 FPGA 失败。

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

