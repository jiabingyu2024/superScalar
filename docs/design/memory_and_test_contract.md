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

IROM 地址映射由 `student_top` 完成：

```text
inst_addrA = irom_addrA[13:2]
inst_addrB = irom_addrB[13:2]
```

当前 IROM 容量是 4096 words = 16 KiB。程序应位于 `0x8000_0000..0x8000_3fff`，超过后会因只取 `[13:2]` 发生回绕。后续运行脚本应检查 irom hex 不超过 4096 words。

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
| T2 | `readData` 有效，`ExecuteMemStage` 用 `loadMetaPipe1` 的 metadata 做符号/零扩展后生成 WB 结果。 |

store 写入同样在命令被接受的周期生效。当前约定为“core 发 raw data/raw mask，外部 memory model 负责按地址 offset 对齐”：

| 访问 | `myCPU`/core 输出 | `dram_driver`/TB memory model 行为 |
| --- | --- | --- |
| `SB` | `perip_wdata[7:0]` 有效，`perip_mask=4'b0001` | `data << addr[1:0]*8`，`mask << addr[1:0]`。 |
| `SH` | `perip_wdata[15:0]` 有效，`perip_mask=4'b0011` | `data << addr[1:0]*8`，`mask << addr[1:0]`。 |
| `SW` | `perip_wdata[31:0]` 有效，`perip_mask=4'b1111` | word 写入。 |
| load | `readData` 已由外部按 `addr[1:0]` 右移 | `ExecuteMemStage` 只按 load subtype 做符号/零扩展。 |

这样 `myCPU` Verilator TB 和 `student_top/perip_bridge/dram_driver` 的对齐点一致。后续 Verilator memory model 必须保留两拍 load 返回关系，并复刻 `dram_driver` 的读右移、写左移行为，否则可能出现仿真通过但 FPGA 失败。

### SoC 地址划分

`perip_bridge` 当前地址表：

| 地址/范围 | 目标 | 说明 |
| --- | --- | --- |
| `0x8010_0000 <= addr < 0x8014_0000` | DRAM | 256 KiB，排他上界为 `0x8014_0000`。 |
| `0x8020_0000` | SW0 | 读 `virtual_sw[31:0]`。 |
| `0x8020_0004` | SW1 | 读 `virtual_sw[63:32]`。 |
| `0x8020_0010` | KEY | 读 `{24'd0, virtual_key}`。 |
| `0x8020_0020` | SEG | 读/写 `seg_wdata`；写忽略 mask。 |
| `0x8020_0040` | LED | 写 LED；写忽略 mask。 |
| `0x8020_0050` | counter | 写 start/stop，读 counter。 |
| 其他地址 | 无映射 | 读返回 0，写无效果。 |

注意：`myCPU` 没有单独 read enable 端口，`perip_bridge` 通过 `~perip_wen` 和地址选择推断读；因此 `myCPU` 无访问时必须把 `perip_addr` 置 0。当前 `myCPU.sv` 已满足这一点。

### Mask 和 offset 职责

当前唯一对齐点在 SoC/TB memory model：

```text
dram_data = perip_wdata << {addr[1:0], 3'b000}
dram_we   = perip_mask  << addr[1:0]
readData  = rawWord >> {addr[1:0], 3'b000}
```

core 内部不再对 load data 二次右移，也不对 store data/mask 左移。StoreBuffer 只在内部 forwarding 时临时对齐，用来判断和拼接同 word 的字节覆盖；对外提交仍保持 raw data/raw mask。

当前不完整支持 misaligned half/word。`SH addr+1/3`、`SW addr+1/2/3` 没有 trap，也不能跨 word 正确写入；测试应避免这些访问，或后续补 misaligned exception。

### 延迟风险

`perip_bridge` 用 `dram_read_sel_d2` 选择 DRAM 返回，`dram_driver` 用 `offset_d2` 对读数据右移。需要后续用 `student_top` 定向 smoke 确认该相位与真实 Vivado `DRAM_0`/当前行为模型完全一致。若发现 `DRAM_0.douta` 比 `dram_read_sel_d2` 晚一拍，应统一调整 `DRAM_0` 行为模型或 `perip_bridge` select 延迟，并同步 core load metadata。

## CSR 和无 cache 约束

当前 core 不实现 I/D cache。`FENCE/FENCE.I` 在项目内定义为 serial NOP：它们需要走 serial 路径保证顺序边界，但不产生 cache flush、取指失效或额外内存副作用。

CSR 当前只承诺测试子集：

| CSR | 地址 | 当前行为 |
| --- | --- | --- |
| `mstatus` | `0x300` | 支持有限 MIE/MPIE 位读写。 |
| `mtvec` | `0x305` | 写入时低两位清零；ECALL 跳转使用它。 |
| `mscratch` | `0x340` | 普通可读写 scratch CSR，用于当前 `rv32mi-p-csr`。 |
| `mepc` | `0x341` | ECALL/EBREAK 写入 trap PC，MRET 使用它返回。 |
| `mcause` | `0x342` | ECALL 写入 machine ecall cause 11，EBREAK 写入 breakpoint cause 3。 |

非白名单 CSR 当前读 0、写忽略；`misa` 当前读 0，不声明未实现的 U/S/F 等能力。这不是完整 RISC-V privileged 行为。rv32/src 测试选择必须和这个子集一致，除非后续明确扩展 CSR 实现。

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
