# Verilator TB 自审与优化提案（待审）

> 本文是待审文档，不代表继续执行代码修改。用户确认前，不应继续扩大 TB 实现改动。

## 1. 本次审查目标

目标不是让当前 RTL 测试通过，而是确认当前 FAIL/TIMEOUT 是否可能由 TB 侧建模、checker 或运行脚本错误导致。

审查重点：

1. `myCPU` Verilator DUT 边界是否和 TB memory/MMIO 模型一致。
2. IROM/DRAM 读延迟是否匹配当前设计事实。
3. store data/mask、load data shift、MMIO 地址和 counter 行为是否可能误判。
4. `srcWithMext/srcWithoutMext` 新 LED/SEG 协议是否被 checker 正确理解。
5. 结果 JSON 是否能提供足够证据区分“DUT 没跑到”和“TB 判错”。

## 2. 当前结论概览

当前 TB 主 DUT 是 `myCPU`，不是 `student_top`。这点非常关键：

| 边界 | 外部模型 |
| --- | --- |
| `myCPU` TB | C++ TB 直接模拟 IROM/DRAM/MMIO/counter。 |
| `student_top` | `perip_bridge + dram_driver + counter + IROM_0/DRAM_0`。 |

因此，TB 需要优先匹配 `myCPU` 端口语义，而不是盲目复制 `dram_driver` 的输入侧变换。后续 `student_top` smoke 再单独检查 SoC wrapper 与 `dram_driver` 一致性。

## 3. 已确认或高风险问题

### 3.1 store data/mask 对齐边界必须澄清

RTL 中 `ExecuteMemStage` 已经对 store 做了对齐：

```text
SB: data << (addr[1:0] * 8), mask = 0001 << addr[1:0]
SH: data << (addr[1] * 16),  mask = 0011 or 1100
SW: data 原样,               mask = 1111
```

也就是说，从 `myCPU.perip_wdata/perip_mask` 看到的数据已经是按字节 lane 对齐后的形式。

但 `rtl/soc/dram_driver.sv` 内部又执行：

```text
dram_data = perip_wdata << {offset, 3'b000}
dram_we   = perip_mask << offset
```

这意味着：

1. 对 `myCPU` C++ TB 来说，memory model 不应再次按 `addr[1:0]` 左移，否则会把已对齐 store 再移一次。
2. 对 `student_top` 上板/SoC 路径来说，`ExecuteMemStage` 与 `dram_driver` 的双移位关系需要单独作为 RTL 集成风险审查。
3. 当前 `sim_memory.cpp::write_word_masked()` 按 `perip_mask` 直接写对应 byte lane，这更接近 `myCPU` 端口语义。

建议：不要把 `myCPU` TB 改成复制 `dram_driver` 的左移逻辑。相反，应在文档中明确“`myCPU` TB 接收的是 core 已对齐 data/mask”，并给 memory model 增加自测覆盖 SB/SH/SW。

### 3.2 TB 当前把所有非 MMIO 非 0 读都当作普通内存读

当前模型逻辑近似为：

```text
!write && addr != 0 && addr 不属于 SW/KEY/SEG/CNT => normal memory read
```

这对 `myCPU` 裸核测试是方便的，但它不等价于 `perip_bridge`：

```text
perip_bridge 只把 0x8010_0000 <= addr < 0x8013_FFFF 视为 DRAM
```

影响：

1. rv32 `tohost` 地址可能在 `0x80001000`，TB 会捕获写入并判定；这属于 rv32 harness 特判，不是 SoC 行为。
2. 性能统计里当前 `dram_read_count/dram_write_count` 可能包含 `tohost` 或其他非 DRAM 普通地址访问，字段名略有误导。

建议：

1. 保留 rv32 `tohost` 特判。
2. 将统计字段或内部命名区分为 `normal_mem_*` 与 `dram_region_*`。
3. src 模式普通内存最好限制在 `0x8010_0000..0x8013_FFFF`，其他地址写入单独记录为 `unexpected_mem_access`，但是否严格 FAIL 需要你确认。

### 3.3 reset 期间 memory model 仍会 tick 请求

当前 reset 预热周期中，TB 也会：

```text
capture_request(top)
mem.tick_posedge(req)
```

理论上如果 DUT reset 期间外部输出不是全 0，TB 可能错误写 memory/MMIO。当前 smoke 未观察到明显问题，但这是 TB 鲁棒性风险。

建议：

1. reset 周期只更新 IROM 地址寄存或完全忽略 perip 写。
2. 或给 `tick_posedge(req, ..., in_reset)` 增加 reset 参数，reset 时清除 read pipeline/mmio select/counter，不执行写入。

### 3.4 `srcWithMext/srcWithoutMext` checker 应使用新 `lampseg` 语义

dump 反推结论：

| 项 | 值 |
| --- | --- |
| 8 个测试灯总 mask | `0x03030303` |
| PASS/✅ marker | `0x04887020` |
| FAIL/❎ marker | `0x90606090` |
| PASS 最终 LED | `0x04887020 | test_lamps` |
| `srcWithMext` 额外期望 | RV32I 条数 37，M/Z 类条数 8 |
| `srcWithoutMext` 期望 | RV32I 条数 37 |

checker 匹配 marker 时建议使用更严格的形式：

```text
(led_value & ~test_lamp_mask) == marker
```

而不是只检查：

```text
(led_value & marker) == marker
```

这样可以避免其他非测试灯 bit 被错误接受。

### 3.5 结果区观测应读 memory model 的最终值

当前 checker 记录 pass/fail counter 时，如果只保存 `req.perip_wdata`，在以下场景可能不等于最终内存值：

1. byte/halfword masked store。
2. 后续同一 word 其他 byte lane 更新。
3. unaligned 地址写。

建议在 `mem.tick_posedge()` 之后，从 memory model 读：

```text
mem.read_aligned_word(pass_counter_addr)
mem.read_aligned_word(fail_counter_addr)
```

作为 JSON 中的 `last_pass_counter/last_fail_counter`。

## 4. 建议的最小修复顺序（待批准）

不建议一次性大改，建议按下面顺序做：

1. 增加 memory model 单元自测，不改仿真行为。
2. 明确并测试 `myCPU` 端口 store data/mask 已对齐语义。
3. 修正 result counter 观测为 memory tick 后读最终内存值。
4. 将 `lampseg` marker 匹配改为 `led & ~test_mask == marker`。
5. reset 阶段禁止 memory/MMIO 写副作用。
6. 拆分统计字段：`normal_mem_*` 与 `dram_region_*`，避免误读。
7. 重新跑短 smoke，比较修复前后结果是否只改变 JSON 观测字段，不改变 DUT FAIL/TIMEOUT 原因。

## 5. 推荐增加的 TB 自测

建议新增一个不依赖 Verilator 的 C++ selftest，只编译：

```text
sim_common.cpp
sim_memory.cpp
selftest_memory.cpp
```

覆盖点：

1. word 写：`mask=1111`。
2. aligned byte 写：`addr=base+1, data=0x0000aa00, mask=0010`。
3. aligned half 写：`addr=base+2, data=0xbbbb0000, mask=1100`。
4. shifted read：`read_shifted_word(base+1)`。
5. counter start/stop。
6. hex 文件解析。

这个 selftest 的目的不是替代 Verilator，而是防止 TB memory model 本身成为错误来源。

## 6. 需要用户确认的问题

1. `myCPU` TB 是否明确按“core 已对齐 data/mask”建模？我建议是。
2. src 模式下，非 `0x8010_0000..0x8013_FFFF` 且非 MMIO 的访问，是否应直接判 FAIL，还是只记录 warning？
3. reset 期间如果 DUT 输出 perip 写，TB 是否应忽略？我建议忽略。
4. `srcWithMext` 的 M/Z 类条数是否确定就是 `0x80100030 == 8` 并映射到 SEG bit `[23:20]`？dump 显示如此，但最终仍建议你确认赛方源码。
5. 是否允许先加入 TB selftest，再调整 checker 细节？

## 7. 当前建议

在你审查并确认前，不继续改 TB 代码。优先确认第 6 节的几个策略问题；确认后再按第 4 节顺序做小步修复和验证。
