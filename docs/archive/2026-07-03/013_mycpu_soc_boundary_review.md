# myCPU 与 SoC 边界审查：IROM/DRAM/MMIO 对齐契约

## 1. 审查目标

本文审查当前 `myCPU` 与 `rtl/soc` 边界，重点回答：

1. `myCPU` 到 `student_top/perip_bridge` 的信号语义是否清晰。
2. IROM 取指地址、延迟和容量边界是否匹配 core 前端假设。
3. DRAM load/store 的读写延迟、mask、offset 对齐职责由谁承担。
4. 当前 SoC 与 CPU 之间是否仍有对齐或时序风险。

本文只记录审查结论。后续 `014_soc_boundary_contract_fix.md` 已按本文部分结论修复 `P_DRAM_ADDR_END` 排他上界，并补充边界注释。

## 2. 模块边界总览

当前 SoC 集成路径：

```text
student_top
  -> myCPU
       -> core
  -> IROM_0
  -> perip_bridge
       -> dram_driver
            -> DRAM_0
       -> counter
       -> display_seg
       -> LED/SEG/SW/KEY MMIO
```

`myCPU` 是 CPU 裸核到赛事模板的扁平适配层：

| `myCPU` 端口 | 来源/去向 | 语义 |
| --- | --- | --- |
| `irom_addrA/B` | core 前端输出 | byte address，A 为当前取指 PC，B 为 `PC+4`。 |
| `irom_enaA/B` | core 前端输出 | IROM 取指使能，A/B 同源。 |
| `irom_dataA/B` | IROM 返回 | 两条 32-bit 指令。 |
| `perip_addr` | core 数据访问输出 | load/store 地址；无访问时为 0。 |
| `perip_wen` | core 数据访问输出 | store 写使能。无单独 read enable，SoC 侧通过 `~perip_wen` 和地址选择推断读。 |
| `perip_mask` | core store 输出 | store raw byte mask。 |
| `perip_wdata` | core store 输出 | store raw write data。 |
| `perip_rdata` | SoC/TB 返回 | load read data；按地址 offset 右移后的格式。 |

关键结论：`myCPU` 边界没有 ready/valid 握手，`accessReady` 在 `myCPU.sv` 中固定为 1。因此 SoC 侧必须是固定延迟、永远接收的 memory/MMIO 模型。

## 3. IROM 边界

### 3.1 地址映射

`myCPU` 输出 byte address：

```text
irom_addrA = iromAccess.iromAddr
irom_addrB = iromAccess.iromAddr + 4
```

`student_top` 将 byte address 转为 IROM word index：

```text
inst_addrA = irom_addrA[13:2]
inst_addrB = irom_addrB[13:2]
```

含义：

1. IROM 容量为 4096 words = 16 KiB。
2. 程序链接基址 `0x8000_0000` 的高位被截掉，只使用低 14 位。
3. 只要程序位于 `0x8000_0000..0x8000_3fff`，映射是正确的。
4. 超过 16 KiB 会按 `[13:2]` 截断/回绕，不会触发异常。

### 3.2 时序契约

`IROM_0` 行为：

```text
posedge clk:
  if (ena) addr_q <= addr

comb:
  dout = mem[addr_q]
```

也就是“地址打一拍，寄存地址组合读”。`FetchStage` 同样在 posedge 保存 PF payload，随后组合绑定 `iromAccess.inst[i]`。

正确时序：

| 时刻 | 行为 |
| --- | --- |
| T0 上升沿前 | PF 给出 PC 和 `irom_ena`。 |
| T0 上升沿 | IROM 锁存地址；FetchStage 锁存 PF payload。 |
| T0 上升沿后 | `irom_data` 由锁存地址组合读出；FetchStage 用保存的 payload 和返回指令组成 IF->ID。 |

该契约目前是闭合的。TB 必须复刻“一拍地址寄存 + 组合读”，不能改成零延迟组合 ROM，也不能额外变成两拍同步 ROM。

### 3.3 IROM 风险

| 风险 | 影响 | 建议 |
| --- | --- | --- |
| IROM 地址只取 `[13:2]` | 程序超过 16 KiB 会回绕。 | `scripts/prepare_test_data.py` 或运行脚本应检查 irom words <= 4096。 |
| `irom_addrB = A + 4` 跨 16 KiB 边界 | B 端口也会回绕。 | 大程序或边界取指前需检查。 |
| IROM 无 reset，初始 `addr_q` 未定义 | reset 后第一拍数据可能 X。 | FetchStage valid 应屏蔽 reset 后无效指令；仿真中不要用无效 lane 指令判错。 |

## 4. DRAM/MMIO 地址划分

`perip_bridge` 地址表：

| 地址/范围 | 目标 |
| --- | --- |
| `0x8010_0000 <= addr < 0x8014_0000` | DRAM |
| `0x8020_0000` | SW0 |
| `0x8020_0004` | SW1 |
| `0x8020_0010` | KEY |
| `0x8020_0020` | SEG |
| `0x8020_0040` | LED |
| `0x8020_0050` | counter |
| 其他地址 | 返回 0，写入无效果 |

注意：本文初次审查时发现 `P_DRAM_ADDR_END = 32'h8013_FFFF` 被作为排他上界使用：

```text
dram_sel = (perip_addr >= START && perip_addr < END)
```

该问题已在 `014_soc_boundary_contract_fix.md` 中修复为 `0x8014_0000`。修复后完整 256 KiB DRAM 地址范围为 `0x8010_0000..0x8013_ffff`，代码中继续使用 `< END` 的排他上界判断。

## 5. DRAM 写入职责：mask 与 offset

### 5.1 当前目标契约

根据最新决策，职责划分为：

```text
core / myCPU:
  输出 raw store data
  输出 raw store mask
  不按 addr[1:0] 左移

dram_driver / TB memory model:
  根据 perip_addr[1:0] 左移 data
  根据 perip_addr[1:0] 左移 mask
  写入 DRAM word lane
```

具体语义：

| store | core 输出 `perip_wdata` | core 输出 `perip_mask` | `dram_driver` 写入 |
| --- | --- | --- | --- |
| `SB addr+0` | `data[7:0]` | `0001` | lane0 |
| `SB addr+1` | `data[7:0]` | `0001` | lane1 |
| `SB addr+2` | `data[7:0]` | `0001` | lane2 |
| `SB addr+3` | `data[7:0]` | `0001` | lane3 |
| `SH addr+0` | `data[15:0]` | `0011` | lane0/1 |
| `SH addr+2` | `data[15:0]` | `0011` | lane2/3 |
| `SW addr+0` | `data[31:0]` | `1111` | lane0/1/2/3 |

`dram_driver` 当前实现符合这个目标：

```text
dram_data = perip_wdata << {offset, 3'b000}
dram_we   = dram_wen ? (perip_mask << offset) : 4'b0000
```

### 5.2 非自然对齐访问

当前设计不完整支持 misaligned half/word：

| 访问 | 当前结果 |
| --- | --- |
| `SH addr+1` | `mask << 1 = 0110`，会跨 lane1/2；这不是 RV32 自然对齐 half 访问。 |
| `SH addr+3` | `mask << 3 = 1000`，高 byte 溢出丢失。 |
| `SW addr+1/2/3` | `1111 << offset` 溢出，数据不完整。 |

当前 core 没看到 misaligned trap 路径。因此测试应避免 misaligned `LH/LHU/SH/LW/SW`，或者后续明确实现 misaligned exception。

## 6. DRAM 读取职责：offset 与扩展

目标契约：

```text
dram_driver:
  从 DRAM_0 读取 aligned word
  按原始地址 offset 右移
  输出给 myCPU 的 perip_rdata 已经右对齐

ExecuteMemStage:
  不再二次右移
  只根据 LB/LBU/LH/LHU/LW 做符号/零扩展
```

对应语义：

| load | `dram_driver` 输出给 CPU | core 后处理 |
| --- | --- | --- |
| `LB addr+N` | 目标 byte 位于 `readData[7:0]` | sign extend bit7 |
| `LBU addr+N` | 目标 byte 位于 `readData[7:0]` | zero extend |
| `LH addr+0/2` | 目标 half 位于 `readData[15:0]` | sign extend bit15 |
| `LHU addr+0/2` | 目标 half 位于 `readData[15:0]` | zero extend |
| `LW addr+0` | word 原样 | 原样 |

这要求 StoreBuffer forwarding 也输出同样格式：如果 load 被 store buffer 完全覆盖，forwarding 数据也应按 load 地址右移后送给 `ExecuteMemStage`。

## 7. DRAM 读延迟与潜在风险

### 7.1 当前代码时序

`perip_bridge` 对 DRAM read select 打两级：

```text
dram_read_sel_d1 <= dram_read_sel
dram_read_sel_d2 <= dram_read_sel_d1

if (dram_read_sel_d2) perip_rdata = dram_rdata
```

`dram_driver` 对 offset 也打两级：

```text
if (dram_ena && !dram_wen) offset_d1 <= offset
offset_d2 <= offset_d1
dout = dram_rdata_raw >> offset_d2*8
```

这表示 SoC 侧期望 `dram_rdata_raw` 在 `dram_read_sel_d2` 有效的同一拍可用。

### 7.2 与 `DRAM_0` 行为模型的风险

当前 `rtl/ip/DRAM_0.sv` 行为模型内部有：

```text
rd_valid_pipe0 <= ena
rd_valid_pipe1 <= rd_valid_pipe0
rd_addr_pipe0  <= addra
rd_addr_pipe1  <= rd_addr_pipe0
if (rd_valid_pipe1) douta <= mem[rd_addr_pipe1]
```

如果严格按非阻塞赋值理解，从 accepted read address 到 `douta` 更新可能需要比 `dram_read_sel_d2` 更晚一拍。也就是说：

```text
perip_bridge 的 read select 延迟
可能早于
DRAM_0 行为模型的 dout 更新
```

这是当前 SoC 边界里最需要波形确认的风险点。

建议用 `student_top` smoke 或一个小型定向 testbench 验证：

1. 在 T0 对 `0x8010_0000` 发起 load。
2. 观察 `dram_read_sel/d1/d2`。
3. 观察 `DRAM_0.douta`。
4. 观察 `perip_rdata` 被 core 采样的周期。

如果发现 `perip_rdata` 提前选择了旧值，有两种修复方向：

| 方向 | 修改 |
| --- | --- |
| 让 `DRAM_0` 行为模型变成 raw read 一拍返回 | 保持 `perip_bridge` 的 `d2`。 |
| 承认 `DRAM_0` raw read 两拍返回 | `perip_bridge` 需要把 `dram_read_sel` 再延后一拍，core load metadata 也要对应确认。 |

当前 `myCPU` Verilator TB 已按“读返回两级 pipeline 后给 CPU”建模，但 SoC wrapper 与 `DRAM_0` 的精确相位仍建议单独验证。

## 8. MMIO 与 counter 读写边界

MMIO 写：

| 地址 | 行为 |
| --- | --- |
| LED | `LED <= perip_wdata`，忽略 mask。 |
| SEG | `seg_wdata <= perip_wdata`，忽略 mask。 |
| CNT | `0x80000000` start，`0xffffffff` stop。 |

MMIO 读：

| 地址 | 返回 |
| --- | --- |
| SW0/SW1 | 两级同步后的 `virtual_sw`。 |
| KEY | 两级同步后的 `virtual_key`。 |
| SEG | 当前 `seg_wdata`。 |
| CNT | `counter.perip_rdata`。 |

风险：

1. `perip_bridge` 对 MMIO/counter read 只打一拍选择；core load metadata 的实际消费周期需要和这一拍返回对齐。
2. 如果 core 统一假设 DRAM/MMIO 都是同一固定延迟，应确认 MMIO/counter 的一拍返回是否会在消费周期保持稳定。
3. LED/SEG/CNT 写忽略 `perip_mask` 是合理的；软件应使用 word store。

## 9. StoreBuffer forwarding 与外部对齐的一致性

最新边界下，StoreBuffer entry 存 raw data/mask：

```text
entry.data  = raw store data
entry.wstrb = raw store mask
entry.addr  = byte address
```

对外提交时：

```text
dram.storeWriteData = entry.data
dram.storeWriteMask = entry.wstrb
dram.storeWriteAddr = entry.addr
```

由 `dram_driver` 负责最终左移。

内部 forwarding 不能直接用 raw mask 比较 load `rstrb`，必须临时转换成 word lane：

```text
entryMask = entry.wstrb << entry.addr[1:0]
entryData = entry.data  << entry.addr[1:0]*8
```

完全覆盖 load 需要的 lane 后，forwarding 输出应再按 load 地址右移：

```text
forwardData = matchedData >> load_addr[1:0]*8
```

这样 forwarding 输出和 `dram_driver` 的 load 返回格式一致。

需要重点回归：

1. `sb; lb/lbu` 同地址 forwarding。
2. `sh; lh/lhu` 自然对齐地址 forwarding。
3. 同 word 多个 `sb` 后 load word/half。
4. 部分覆盖时是否正确 block。

## 10. 当前问题清单

| 编号 | 问题 | 严重度 | 说明 |
| --- | --- | --- | --- |
| B1 | DRAM read select 与 `DRAM_0` 行为模型相位可能不一致 | 高 | 需要 `student_top` 波形确认。 |
| B2 | `P_DRAM_ADDR_END=0x8013ffff` 作为排他上界 | 已修复 | 已在 014 中改为 `0x8014_0000`。 |
| B3 | misaligned half/word 没有 trap，也不能完整写入 | 中 | 测试应避免，或后续实现 misaligned exception。 |
| B4 | `myCPU` 无 read enable 端口，SoC 通过 `~perip_wen && addr` 推断读 | 中 | 当前可用，但 idle 地址必须保持 0；无 unmapped access exception。 |
| B5 | MMIO/counter read latency 与 core load metadata 消费周期需确认 | 中 | 若软件频繁读 counter/SEG，需波形确认。 |
| B6 | IROM 只支持 16 KiB，超出后回绕 | 中 | 运行脚本应检查 irom size。 |

## 11. 建议的下一步

1. 做一个 `student_top` 级定向 smoke，只测 IROM 一拍、DRAM load 延迟、`sb/lb`、`sh/lh`、`sw/lw`。
2. 用 Verilator 波形确认 `dram_read_sel_d2` 与 `DRAM_0.douta` 的有效相位。
3. 将 `P_DRAM_ADDR_END` 调整为排他上界 `0x8014_0000`，或明确所有测试不会访问最后 byte。
4. 为 `scripts/run_verilator.py` 增加 irom depth 检查，超过 4096 words 直接报错。
5. 为 StoreBuffer forwarding 增加小型 directed 测试，重点覆盖 partial byte 和同 word 多 store。

## 12. 总结

当前最合理的职责划分是：

```text
IROM:
  myCPU 输出 byte PC
  student_top 截低位映射到 16 KiB IROM word index
  IROM 负责一拍地址寄存、组合读

DRAM store:
  core 输出 raw data/raw mask
  dram_driver/TB 按地址 offset 左移 data/mask

DRAM load:
  dram_driver/TB 按地址 offset 右移 read word
  core 只做符号/零扩展

MMIO:
  LED/SEG/CNT 写忽略 mask
  SW/KEY/SEG/CNT 读由 perip_bridge/counter 返回
```

对齐职责现在是清楚的；主要剩余风险不是 mask 归属，而是 `perip_bridge` 对 DRAM/MMIO 返回数据的选择相位是否与实际 `DRAM_0/counter` 行为完全一致。
