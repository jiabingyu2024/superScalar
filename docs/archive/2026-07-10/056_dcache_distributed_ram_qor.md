# DCache distributed RAM QoR 优化

日期：2026-07-10

## 1. 背景

旧 Vivado 综合层次报告中：

| 模块 | LUT | FF | LUTRAM |
| --- | ---: | ---: | ---: |
| `CoreDCache` | 49,520 | 71,570 | 0 |

当前 DCache 为 2 way、128 set、每 line 8 word，data payload 为：

```text
2 * 128 * 8 * 32 = 65,536 bits
```

旧三维数组通过动态 way/set/word 直接访问，Vivado 将其展开为 FF 和大 mux，没有识别为 FPGA RAM。

## 2. 优化目标

保持现有组合 hit lookup 和 ready/valid 周期不变，把 data/tag 存储改写为 Vivado 可识别的 distributed RAM 模板。相比直接改 BRAM，该方案不增加同步读拍数，不需要修改 ExecuteCluster 的 load pipeline。

## 3. RTL 修改

文件：`rtl/core/memory/DCache.sv`

### 3.1 Data array

原结构：

```systemverilog
DataPath data_q [WAYS-1:0][SET_COUNT-1:0][WORDS_PER_LINE-1:0];
```

改为每 way 一块扁平存储：

```systemverilog
(* ram_style = "distributed" *) logic [31:0] data_way0_q [0:DATA_DEPTH-1];
(* ram_style = "distributed" *) logic [31:0] data_way1_q [0:DATA_DEPTH-1];
```

接口模板为：

- 一个异步组合读地址；
- 每 way 一个同步写 enable；
- data array 无 reset；
- way0/way1 独立存储；
- set/word 扁平地址为 `{index, word}`。

读地址按状态选择：

| 状态 | 读地址用途 |
| --- | --- |
| `DC_IDLE` | hit lookup / store-hit merge |
| `DC_WRITEBACK_REQ` | victim writeback word |
| `DC_FINISH` | miss 返回 word / miss 后 store merge |

写端口覆盖三个互斥来源：

1. cacheable store hit；
2. refill response；
3. refill 完成后的原始 store merge。

### 3.2 Tag array

tag 同样改为每 way 一块异步读、同步写的 distributed RAM：

```systemverilog
(* ram_style = "distributed" *) logic [TAG_BITS-1:0] tag_way0_q [0:SET_COUNT-1];
(* ram_style = "distributed" *) logic [TAG_BITS-1:0] tag_way1_q [0:SET_COUNT-1];
```

tag 只在 refill 最后一拍写入，compare 由 `valid_q[way][index]` 门控，因此不需要 reset。

### 3.3 参数修正

`OFFSET_BITS` 从固定 5 改为：

```systemverilog
OFFSET_BITS = $clog2(WORDS_PER_LINE) + 2
```

默认配置仍为 5，但参数关系不再隐含依赖 8 words/line。

## 4. 行为保持

本轮没有改变：

- cache hit 的组合 lookup latency；
- `cpu_req_ready/cpu_resp_valid` 时序；
- store byte merge；
- dirty/valid/LRU 状态；
- critical-word refill 顺序；
- victim writeback 顺序；
- uncached 请求路径；
- cache 容量、ways、sets 和 line size。

## 5. Verilator 回归

### RV32

| Suite | 结果 |
| --- | ---: |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |

### `srcSmoke`

- 状态：PASS
- cycles：33,798,107
- IPC：0.910069
- DCache miss：7
- LED：`0x01221c08`
- SEG：`0x37000675`

上述结果与重构前一致。

### `srcWithMext` 小窗口 difftest

- 窗口：200,000 cycles
- 状态：TIMEOUT，符合小窗口预期
- difftest commits：130,742
- last PC：`0x80000e14`
- RV32I count：37
- M extension count：8
- RV32I fail count：0

未运行全量 `srcWithMext`。

## 6. Vivado 综合验收

本轮没有启动 Vivado。用户生成新工程并完成 synthesis 后，必须确认：

1. synthesis log 没有 `ram_style` 被忽略或 RAM inference 失败的警告。
2. 顶层 `LUT as Memory` 从旧基线 0 变为非零。
3. `CoreDCache` FF 从旧基线 71,570 大幅下降。
4. `CoreDCache` LUT 从旧基线 49,520 明显下降。
5. RAM 层次或 primitive 名称能对应 `data_way0_q/data_way1_q/tag_way0_q/tag_way1_q`。
6. 没有新增 multi-driven net、combinational loop 或时序未约束路径。

若 `LUT as Memory` 仍为 0，不继续 BPU/ROB/IQ 优化；先根据 synthesis log 调整 RAM 模板。

## 7. 预期与限制

data+tag 共约 70,656 bits 进入 distributed RAM 候选。该数字不是最终 LUTRAM primitive 数量，也不能在没有综合报告时换算为确定的 LUT/FF 节省。

异步读 distributed RAM 保持了 IPC，但最大频率仍可能受 1024-depth read mux、tag compare、load align 和 writeback mux 影响。如果资源显著改善但 timing 不满足，下一阶段应评估同步 BRAM lookup pipeline，而不是恢复 FF array。
