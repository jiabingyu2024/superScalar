# SoC 边界职责修复记录

## 1. 本次目标

按用户确认的职责划分检查并修复当前实现：

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

## 2. 检查结论

| 项 | 当前状态 |
| --- | --- |
| IROM 地址/时序 | 符合职责划分：byte PC -> `[13:2]` word index，一拍地址寄存、组合读。 |
| DRAM store | 符合职责划分：`ExecuteMemStage` 输出 raw data/raw mask，`dram_driver` 和 TB memory model 左移。 |
| DRAM load | 符合职责划分：`dram_driver` 和 TB memory model 右移，`ExecuteMemStage` 只扩展。 |
| StoreBuffer forwarding | 已按外部返回格式处理：内部临时对齐，命中后按 load 地址右移输出。 |
| MMIO 写 mask | 符合职责划分：LED/SEG/CNT 写忽略 mask。 |
| DRAM 地址范围 | 原先排他上界写成 `0x8013_ffff`，已修复。 |

## 3. 代码修改

### 3.1 DRAM 排他上界

修改：

```text
P_DRAM_ADDR_END: 0x8013_ffff -> 0x8014_0000
```

涉及文件：

1. `rtl/soc/student_top.sv`
2. `rtl/soc/perip_bridge.sv`

原因：`perip_bridge` 使用 `< P_DRAM_ADDR_END` 判断。`0x8014_0000` 才能完整覆盖 `0x8010_0000..0x8013_ffff` 的 256 KiB DRAM 空间。

### 3.2 对齐职责注释

在以下文件补充注释：

1. `rtl/core/ExecuteStage/ExecuteMemStage.sv`
2. `rtl/soc/dram_driver.sv`

明确 core 输出 raw store data/mask，SoC 边界拥有地址 offset 对齐职责。

## 4. 当前仍需后续验证的问题

1. `perip_bridge.dram_read_sel_d2` 与真实 `DRAM_0.douta` 的有效相位需要 `student_top` 定向波形确认。
2. misaligned half/word 没有完整支持，也没有 trap；测试应避免或后续补异常。
3. IROM 仍为 16 KiB，脚本应检查 `irom.hex` 深度不超过 4096 words。
4. StoreBuffer forwarding 需要 directed 测试覆盖 partial byte、多 store 合并和 block。

## 5. 已验证命令

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
scripts/run_verilator.py rv32 --test rv32ui-p-simple --max-cycles 20000 --no-build
scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
```

结果：

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| `rv32ui-p-simple` | FAIL，`tohost=0xffffffc4` | 主 Verilator 链路正常运行，DUT 仍未通过。 |
| `srcWithMext` | TIMEOUT，`checker_kind=src_lampseg` | src checker/TB 仍能正常运行。 |

本次验证证明边界修复没有破坏主仿真编译和运行入口，不代表 RTL 功能已经正确。
