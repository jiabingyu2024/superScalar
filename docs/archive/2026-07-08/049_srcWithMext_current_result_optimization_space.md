# 049 srcWithMext 当前结果与优化空间分析

日期：2026-07-08

## 1. 结论摘要

当前 `srcWithMext` 已经功能 PASS，正确性信号完整：

```text
final_symbol_cn       = 对号
right_8_lamps_all_on  = true
right_8_lamps_value   = 0x03030303
rv32i_count_from_seg  = 37
mext_count_from_seg   = 8
rv32i_fail_counter    = 0
last_nonzero_seg      = 0x37814682
```

性能上，当前完整运行结果是：

```text
cycles       = 734,122,286
commit       = 380,344,389
IPC          = 0.518094
elapsed      = 14,682 ms @ 50 MHz
```

当前低 IPC 的主因不是分支预测。分支误预测只占总周期约 `0.036%`。真正的优化空间集中在：

1. DCache miss/fill 和 load/store 访存阻塞。
2. 当前单发射状态机对 load/mul/div 的全核阻塞。
3. MulDivUnit 尤其 divider 的长延迟等待。
4. DCache store 直写并 invalidate 导致后续 read locality 被破坏。

## 2. 数据来源

分析基于当前已有文件：

```text
build/result/src/srcWithMext.json
rtl/core/riscv_cpu.sv
rtl/core/memory/DCache.sv
rtl/core/execute/MulDivUnit.sv
tb/verilator/perf_stats.cpp
```

本次没有重新跑长仿真。注意：当前 RTL 主路径是 `riscv_cpu.sv` 的单发射阻塞式核心，不是之前归档里讨论过的乱序/超标量核心。因此 JSON 中 `ROB/IssueQueue/dispatch/issue/commit width` 等字段不要按乱序核心解释。当前有效字段主要是：

```text
core_cycle
commit_count
branch_count / branch_miss_count
load_count / store_count
dcache access / miss
stall_front
stall_mem
stall_muldiv
LED / SEG / counter
```

## 3. 正确性结果

`srcWithMext` 使用 `src_lampseg` checker，PASS 条件不是单一 LED hex，而是多条件同时满足：

| 条件 | 当前结果 | 结论 |
|---|---:|---|
| 最终对号 marker | `final_symbol_cn=对号` | 通过 |
| 右侧 8 灯 | `0x03030303` | 全亮 |
| RV32I 计数 | `37` | 通过 |
| M 扩展计数 | `8` | 通过 |
| RV32I fail counter | `0` | 通过 |
| SEG 高位 | `0x378xxxxx` | 通过 |

`last_raw LED = 0x078b7323` 看起来不是固定 pass marker，是因为右侧测试灯位会叠加到最终 LED 值里。checker 判断 marker 时使用 mask：

```text
test_lamp_mask = 0x03030303
pass_marker    = 0x04887020
fail_marker    = 0x90606090
```

所以不要直接拿完整 LED hex 和 `pass_marker` 做全等比较。

## 4. 性能指标拆解

### 4.1 总体指标

| 指标 | 数值 |
|---|---:|
| cycles | 734,122,286 |
| commit | 380,344,389 |
| IPC | 0.518094 |
| branch_count | 10,958,983 |
| branch_miss_count | 266,018 |
| branch_miss_rate | 2.4274% |
| load_count | 110,606,986 |
| store_count | 21,450,261 |
| DCache access | 132,057,232 |
| DCache miss | 50,080,018 |
| DCache hit rate | 62.0770% |
| DCache miss rate | 37.9230% |

访存密度很高：

```text
load / commit      = 29.08%
store / commit     = 5.64%
mem op / commit    = 34.72%
branch / commit    = 2.88%
```

这说明当前程序更像 memory/M-extension heavy workload，而不是 branch-heavy workload。继续优化 BTB 的收益很小。

### 4.2 stall 占比

| stall 来源 | 周期 | 占总周期 |
|---|---:|---:|
| memory stall (`stall_mem`) | 200,408,392 | 27.299% |
| mul/div wait (`stall_muldiv`) | 42,496,500 | 5.789% |
| frontend/redirect (`stall_front`) | 266,019 | 0.036% |

`stall_mem` 是第一大瓶颈，约等于 `DCache miss * 4`：

```text
avg stall per DCache miss = 200,408,392 / 50,080,018 = 4.00 cycles
```

这与当前 DCache miss 处理一致：每次 miss 固定填 4 个 word。当前架构每次 load miss 会全核停住等 line fill 结束。

## 5. 当前 RTL 造成瓶颈的机制

### 5.1 DCache miss 必须 4-word fill

`DCache.sv` miss 后从 line base 开始读 4 个 word：

```text
DC_IDLE -> DC_MISS_WAIT word0
        -> DC_MISS_REQ  word1
        -> DC_MISS_WAIT word1
        -> DC_MISS_REQ  word2
        -> DC_MISS_WAIT word2
        -> DC_MISS_REQ  word3
        -> DC_MISS_WAIT word3 -> CPU resp
```

当前 `SocMemBridge/DramBramAdapter` 下游 `req_ready=1`，BRAM 读约 1 拍返回，所以 miss 平均代价统计为 4 cycles。这个代价本身不算大，但 miss 数量高达 50M，累计成本变成最大瓶颈。

如果把每次 miss 只取请求 word，单次 miss 代价可降，但后续顺序/局部访问命中率会变差。当前数据说明 line fill 的命中收益还不够，miss rate 仍有 37.9%，需要看访问模式决定是加容量/改映射，还是改 refill 策略。

### 5.2 Store 直写并 invalidate

当前 store 路径：

```systemverilog
if (cpu_req_write) begin
    mem_req_valid = 1'b1;
    mem_req_write = 1'b1;
    ...
end
```

并且 cacheable store 会：

```systemverilog
valid_q[req_index_c] <= 1'b0;
perf_dcache_miss <= perf_dcache_miss + 64'd1;
```

这是正确性优先的保守策略，但它会破坏 store 后同 line load 的局部性。`srcWithMext` 有 21.45M store，占 commit 的 5.64%。如果这些 store 与后续 load 存在同 line 复用，invalidate 会制造额外 miss。

### 5.3 Load hit 仍然需要阻塞式写回

在 `riscv_cpu.sv` 中，load 指令即使 cache ready，也进入 `ST_WAIT_MEM`：

```text
ST_EXEC load -> ST_WAIT_MEM
ST_WAIT_MEM cache_resp_valid -> write_gpr -> ST_EXEC
```

DCache hit 会很快给 `cpu_resp_valid`，但当前 CPU 是全核阻塞状态机，没有独立 execute/writeback 流水级，也没有 load-use forwarding。因此 load 密集程序的 IPC 天然受限。

### 5.4 MulDivUnit 全核阻塞

M 扩展指令会进入：

```text
ST_EXEC M -> ST_WAIT_MULDIV -> done -> writeback
```

当前 `MulDivUnit`：

```text
MUL/MULH/MULHSU/MULHU: 等 3 拍左右
DIV/DIVU/REM/REMU: 等 DIV_0，大约 34 拍
特殊除 0 / overflow: 1 拍 special path
```

`stall_muldiv = 42,496,500`，占总周期 5.789%。这不是第一大瓶颈，但它是第二类明确可优化来源。

### 5.5 分支已经不是主要问题

当前：

```text
branch_count      = 10,958,983
branch_miss_count = 266,018
branch_miss_rate  = 2.4274%
stall_front       = 266,019 cycles
```

分支误预测代价约 1 cycle/次，总占比只有 0.036%。继续做更复杂分支预测器，对总运行时间几乎没有价值，除非目标程序或核心结构发生变化。

## 6. 理论收益估算

按当前计数做粗略上限估算：

| 假设优化 | 新 cycles 估计 | IPC 估计 | speedup |
|---|---:|---:|---:|
| 消除全部 frontend stall | 733,856,267 | 0.518282 | 1.000x |
| 消除一半 memory stall | 633,918,090 | 0.599990 | 1.158x |
| 消除全部 memory stall | 533,713,894 | 0.712637 | 1.375x |
| 消除一半 mul/div wait | 712,874,036 | 0.533537 | 1.030x |
| 消除全部 mul/div wait | 691,625,786 | 0.549928 | 1.061x |
| 消除 memory stall + mul/div wait | 491,217,394 | 0.774289 | 1.494x |

这个表说明：

1. 优化分支没有意义。
2. 优先压低 memory stall。
3. MulDiv 优化有收益，但单独做最多约 6.1% 上限。
4. 想显著超过 IPC 0.7，必须处理 load/memory 阻塞。

## 7. 优化优先级

### P0：先保证当前综合通过和时序

当前已经出现过 Vivado IP wrapper 与行为模型参数不一致的问题。继续做性能优化前，先把当前版本稳定综合更重要：

1. 保持 `DRAM_0/IROM_0/MUL_0/DIV_0` 无参数实例化。
2. 补 XDC `create_clock`。
3. 跑 `synth_1` 后确认 blackbox 和 utilization。

否则性能优化可能建立在不可上板结构上。

### P1：优化 DCache miss 率或 miss 暴露代价

可选方向：

1. 增大 `LINE_COUNT`，例如 128 -> 256/512，降低 conflict miss。
2. 做 2-way set associative，降低冲突 miss，但会增加 hit path mux/tag 比较，可能伤 Fmax。
3. 引入 critical-word-first：先取请求 word 并尽快返回 CPU，后续 word 后台填充。
4. 加 next-line/stride prefetch，但要非常保守，避免单端口 DRAM 被预取占满。
5. 针对 store 后 load 的热点，考虑 store update cache line 或 store buffer forwarding，而不是简单 invalidate。

当前最推荐的第一步不是上 2-way，而是加更细的性能计数：

```text
load_hit_count
load_miss_count
store_count_causing_invalidate
miss_by_load
miss_by_store_invalidate
same_line_store_then_load_miss
```

没有这些计数时，无法判断 miss 是容量/冲突、line fill 策略、还是 store invalidate 引起。

### P2：减少 load hit 的结构性阻塞

当前 load 即使 hit，也要进入 `ST_WAIT_MEM` 等一拍。可做：

1. 将 DCache hit load 的返回和写回合并到 `ST_EXEC` 下一拍，并减少状态机额外空转。
2. 拆出 execute/writeback 两级，让非 load 指令在 load 等待时有机会继续推进。
3. 最小代价版本：只优化 load hit path，不动 miss path 和 store path。

风险：这会触碰 CPU 状态机、寄存器写回和 load-use hazard。必须回归 `LB/LH/LBU/LHU/LW`、`srcSmoke`、`srcWithMext`。

### P3：MulDiv 优化

当前 MulDiv 占 5.789%，可做但优先级低于 memory。

可选方向：

1. 对乘法结果做更准确 latency 计数，确认 `MUL_0` 实际 pipeline stage 与 `mul_count_q` 是否多等了一拍。
2. 若 Vivado Fmax 允许，把乘法 pipeline 从 3 降到 2 或 1。
3. 对 divider 增加早出路径，例如 divisor 为 1、-1、power-of-two 的 quotient/remainder。
4. 如果资源允许，保留一个 divider，但允许非 M 指令在 divider busy 时继续执行；这需要从单状态机升级到至少小型流水线/scoreboard。

不建议现在直接增加多个 divider。`srcWithMext` 的主瓶颈不是 divider 数量，而是单发射全核等待和访存阻塞。

### P4：清理无效性能字段

当前 JSON 仍输出：

```text
ROB
IssueQueue
dispatch_width
issue_width
commit_width
```

这些字段来自历史乱序实现，不适合当前 `riscv_cpu`。建议在当前单发射版本中：

1. JSON 增加 `core_type = "single_issue_blocking"`。
2. 对无效字段标记 `available=false`，或者移入 `legacy_perf_fields`。
3. 增加当前核心真正有意义的字段：`state_fetch_cycles/state_exec_cycles/state_wait_mem_cycles/state_wait_muldiv_cycles`。

否则后续很容易再次拿 `issue_queue_full_breakdown.mul_cycles` 这类字段误解为真实 IssueQueue 阻塞。当前它实际来自 `stall_muldiv` 映射。

## 8. 不建议的优化

1. 不建议继续优化 BTB。收益上限约 0.04%，不值得。
2. 不建议直接做复杂 2-way/write-back DCache。验证复杂度高，当前更缺少 miss 分类计数。
3. 不建议把 `StoreWriteBuffer` 直接接回默认路径。之前已经有一致性风险，必须先设计 forwarding 和 line fill 冲突规则。
4. 不建议为了 IPC 牺牲当前 Vivado 可综合性。当前版本应先证明上板时序，再决定是否增加结构复杂度。

## 9. 推荐执行顺序

1. 修工程稳定性：Vivado IP 契约、XDC `create_clock`、Tcl source 边界。
2. 给 DCache/CPU 状态机加更准的性能计数。
3. 用完整 `srcWithMext` 重新跑一次，确认 miss 来源。
4. 先做低风险 DCache 参数试验：`LINE_COUNT=256/512`，比较 miss rate、cycles 和 Vivado Fmax。
5. 如果 miss 主要来自 store invalidate，再设计 store update/forwarding。
6. 如果 miss 主要来自冲突，再考虑 2-way。
7. 如果 memory stall 降下去后 `stall_muldiv` 成为主瓶颈，再做 MulDiv early-out 或非阻塞化。

## 10. 当前判断

当前 `srcWithMext` 的功能已经达标，性能仍有明显空间，但优化方向已经从“分支/前端”转向“访存与阻塞式执行模型”。

最有价值的短期目标不是直接重构成超标量，而是把当前单发射核心的 memory stall 从 27.3% 降下来。只要能消除一半 memory stall，IPC 估计可从 `0.518` 提升到约 `0.600`；如果同时减少部分 MulDiv wait，才有机会稳定接近 `0.65`。要超过 `0.75`，需要更大的结构变化：非阻塞 load/muldiv、流水化写回，甚至重新走模块化流水线设计。
