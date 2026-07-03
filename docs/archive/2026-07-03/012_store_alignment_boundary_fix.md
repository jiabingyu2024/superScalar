# store/load 对齐边界修正

## 1. 背景

用户明确要求：store mask 问题应通过删除 RTL 内部对齐解决，只保留 SoC 处 `dram_driver` 的对齐逻辑。

修改前存在双对齐风险：

1. `ExecuteMemStage` 对 `SB/SH` 的 store data 和 mask 按 `addr[1:0]` 左移。
2. `dram_driver` 又对 `perip_wdata/perip_mask` 按 `offset=perip_addr[1:0]` 左移。
3. load 路径同理，`dram_driver` 已按 offset 右移，`ExecuteMemStage` 又再次按 load 地址右移。

因此非 word 对齐的 `lb/lh/sb/sh` 可能在 SoC 路径和 TB 路径出现不一致或双移位。

## 2. 新边界约定

统一边界为：

```text
core / myCPU:
  store 输出 raw data/raw mask
  load 输入已按地址 offset 右移后的 readData

dram_driver / Verilator memory model:
  store 写入时按 addr[1:0] 左移 data/mask
  load 返回时按 addr[1:0] 右移 readData
```

具体表：

| 访问 | core 输出 | 外部 memory model |
| --- | --- | --- |
| `SB` | `wdata[7:0]`，`mask=0001` | `wdata << offset*8`，`mask << offset` |
| `SH` | `wdata[15:0]`，`mask=0011` | `wdata << offset*8`，`mask << offset` |
| `SW` | `wdata[31:0]`，`mask=1111` | word 写入 |
| `LB/LBU/LH/LHU/LW` | core 不再二次右移 | 外部返回已右移数据，core 只做符号/零扩展 |

## 3. RTL 修改

### 3.1 `ExecuteMemStage`

修改：

1. 删除 `align_store_data()`。
2. `store_wstrb()` 不再依赖地址：
   - `SB -> 0001`
   - `SH -> 0011`
   - `SW -> 1111`
3. StoreBuffer entry 写入 raw `dataB` 和 raw `wstrb`。
4. 删除 load 返回的 `align_load_data()` 二次右移，`extend_load_data()` 直接处理 `dram.exReadData`。

### 3.2 `StoreBuffer`

StoreBuffer 对外提交 raw data/mask，交给外部 memory model 对齐。

但为了保持 store-to-load forwarding 正确，内部匹配时临时做对齐：

```text
entryMask = entry.wstrb << entry.addr[1:0]
entryData = entry.data  << entry.addr[1:0] * 8
```

若完全覆盖 load 需要的 `rstrb`，转发时再按 load 地址右移：

```text
forwardData = matchedData >> load_addr[1:0] * 8
```

这样 StoreBuffer forwarding 的输出格式和 `dram_driver` load 返回格式一致。

## 4. TB 修改

`tb/verilator/sim_memory.cpp::write_word_masked()` 改为复刻 `dram_driver` 写入语义：

```text
write_data = perip_wdata << addr[1:0] * 8
write_mask = perip_mask  << addr[1:0]
```

读路径原本已经按 `addr[1:0]` 右移，继续保留。

## 5. 已验证命令

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
scripts/run_verilator.py rv32 --test rv32ui-p-simple --max-cycles 20000 --no-build
scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
scripts/run_verilator.py src --test srcWithoutMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
```

结果：

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| `rv32ui-p-simple` | FAIL，`tohost=0xffffffc4` | Verilator/TB 链路可运行；当前 DUT 仍未通过。 |
| `srcWithMext` | TIMEOUT，`checker_kind=src_lampseg` | TB 正常等待新 LED/SEG 协议最终图案。 |
| `srcWithoutMext` | TIMEOUT，`checker_kind=src_lampseg` | TB 正常等待新 LED/SEG 协议最终图案。 |

这些结果不代表 RTL 正确，只说明本次对齐边界修改后 Verilator 编译和基础运行链路未破坏。

## 6. 后续注意

1. 需要重点回归 `lb/lbu/lh/lhu/lw/sb/sh/sw`，尤其是非 0 offset 地址。
2. StoreBuffer forwarding 需要用同 word 多 store、partial byte、store 后 load 的测试覆盖。
3. `student_top` smoke 后续应检查 `myCPU -> perip_bridge -> dram_driver` 的真实组合是否与 TB memory model 完全一致。
