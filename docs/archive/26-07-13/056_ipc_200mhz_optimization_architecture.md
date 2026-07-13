# 顺序单发射 Core：IPC 0.8 与 200 MHz 优化架构

> 参考：052 CVA6 微架构分析、053 superScalar 适配架构、055 当前实现结果。  
> 目标：`srcWithMext` 接近 IPC 0.8，并在 xc7k325tffg900-2 上实现 200 MHz routed timing；中间只使用短窗口，优化收敛后才跑全量。

## 1. 目标换算与边界

当前全量结果：

```text
cycle       = 604,195,675
commit      = 380,344,388
IPC         = 0.629505
50 MHz time = 12.0839 s
```

若 commit 数保持不变：

```text
IPC 0.80 → 475,430,485 cycles → 2.377 s @ 200 MHz
IPC 0.90 → 422,604,876 cycles → 2.113 s @ 200 MHz
IPC 0.95 → 400,362,514 cycles → 2.002 s @ 200 MHz
```

因此“IPC 约 0.8”和“约 2 秒”并非完全同一个门槛：0.8 对应约 2.38 秒；严格 2 秒需要约 0.95 IPC。第一阶段以 IPC≥0.8、200 MHz timing closure 为硬目标，以 2.0~2.4 秒为现实区间。

## 2. 定量瓶颈

20M `srcWithMext` 基线窗口：

| 指标 | 数值 |
|---|---:|
| commit / IPC | 11,934,008 / 0.596700 |
| Load / Store | 3,825,933 / 714,576 |
| load-return stall | 8,047,426 cycles |
| frontend stall | 13,758 cycles |
| branch miss | 4,581，miss rate 1.265% |
| DCache access | 4,183,128 |
| DCache miss | 113,680，miss rate 2.718% |
| DRAM read | 454,720，恰为 miss 的 4 倍 |

结论：

1. 前端和 branch predictor 不是第一瓶颈；即使 branch miss 全消失，也不足以接近目标。
2. 主要损失是 load 返回/依赖等待。当前 DCache hit 和 refill 都存在可消除的串行拍。
3. 每个 miss 固定等待完整 4-word refill 后才返回 critical word；这对 load-use 链极不利。
4. DCache `DC_RESP` 占用独立状态，加上 Core 的 `load_active` 单 outstanding gate，使连续 hit 不能做到 1 load/cycle。
5. 当前 8 KiB direct-mapped 在矩阵热点中 miss rate 稳定约 2.6~2.7%；容量/冲突优化有价值，但不能以拉长 200 MHz lookup path 为代价。

## 3. 第一轮优化：不改变 ISA/精确状态

### 3.1 DCache hit 流水化

- 删除专用 `DC_RESP` bubble，改为 1-cycle `resp_valid_q` pulse。
- hit 接受后 Cache 保持可接收状态；上一 load response 与下一 load lookup 可以同拍发生。
- Core 将 `dc_resp_valid` 视为“当前 active load 本拍释放”，允许同拍从 Load Queue 启动下一项。
- sequential update 中先完成旧 load，再安装新 `load_active_meta`，保证同拍替换不丢 transaction ID。

目标：连续 cache hit 从“每两拍一个”提升到“填管后每拍一个”。

### 3.2 Critical-word-first + early restart

- miss refill 首地址改为请求 word，而不是固定 word0。
- 第一个 DRAM response 立即完成 load；其余 3 word 在 DCache 内继续 refill。
- line 只有 4 word 全部返回后才置 valid，early response 不等于 partial line valid。
- early response 后 Core 可执行依赖 ALU；新的 memory request仍等 DCache refill 完成，保持单外部 read ownership。
- flush 在 early response 前后都能 kill 未完成 refill；已握手 response 继续 drain，不能污染新 ID。

目标：miss 的 load-use 可见延迟减少约三个 word refill 相位。

### 3.3 Cache 容量策略

先保持 16B line 和 direct-mapped，使用短窗口比较 8/16/32 KiB：

- line size 不增大，避免 DRAM 无 burst 合同时一次 miss 读 8/16 word。
- 先尝试 32 KiB direct-mapped；容量只由 `DCACHE_LINES` 统一传播。
- 暂不采用 2-way，因为双 tag/data lookup mux 更可能破坏 5 ns 路径；只有 direct-mapped 容量扩展仍存在明显 conflict 时才考虑。

### 3.4 200 MHz 存储实现方向

- 最终 DCache data bank 改为同步读、byte-write 的 bank 结构，并明确 `ram_style="block"`，以推断 BRAM，而不是让大容量 async array 形成深 MUX/LUTRAM。
- tag/valid 保持较小独立阵列；请求地址、tag compare、data select、response 各自不跨越多个逻辑层级。
- 不在拿到 routed timing 前盲目给 Issue 增拍；Issue 增拍会直接损害单发射 IPC。

## 4. 暂缓的优化

| 方案 | 暂缓原因 |
|---|---|
| 扩大 Scoreboard 到 16 | RAW age scan 更长，可能直接破坏 200 MHz；先解决已量化的 load latency |
| 多 outstanding miss/MSHR | 外部 dmem 无 response ID，需重构桥和恢复合同，风险远高于第一轮收益 |
| 非阻塞 DCache | 同上；当前目标可先靠 early restart 达成大部分收益 |
| 双发射 | 超出顺序单发射知识目标，且提交/RF/LSU 带宽均需翻倍 |
| 更大 cache line | DRAM 无 burst，miss traffic 和单 miss 延迟会明显增加 |
| 分支更复杂预测器 | branch miss 只占小比例，不是当前主瓶颈 |

## 5. 验证顺序与停止条件

中间阶段：

1. 每次 RTL 改动先双 DUT build + RV32 base 52。
2. `srcSmoke/srcWithMext` 先跑 500k，确认基础计数、无 assertion/FAIL。
3. 性能 A/B 使用固定 20M `srcWithMext` 窗口；比较 commit、IPC、load stall、miss/access，不能比较不同窗口。
4. 只有 20M 指标明确提升且功能稳定，才进入下一项优化。

最终阶段：

1. 优化收敛后只跑一次 `srcSmoke` 大窗口和一次 `srcWithMext` 1.2B 上限。
2. 最终 RTL 只调用一次 200 MHz implementation；加上优化前基线，本任务 Vivado implementation 总计不超过两次。
3. timing 以 routed WNS/TNS 为准，不用 synthesis estimate 代替。

## 6. 风险与必须保持的不变量

- response 与新 request 同拍时，旧 transaction completion 和新 active metadata 必须同时保留。
- early restart 后 full flush 不能让 refill 后续 response 再次 completion。
- line 未填满前不得 valid；否则另一个 word 会命中未初始化数据。
- store hit byte update 与 refill write 不能同拍写同一 bank；blocking FSM/请求仲裁必须保证单 owner。
- DCache idle 必须包含“无 refill outstanding”，FENCE 不能在 background refill 中提前通过。
- request backpressure payload 稳定、committed Store 才可 external write、uncached load 仍在 commit head 发出。

## 7. 预期收益判断

在 20M 基线中，要达到 IPC 0.8，需要把相同 11,934,008 commits 的周期降到约 14,917,510，即节省约 5.08M cycles。连续 hit 去 bubble 的理论上限接近 load 数 3.83M；critical-word-first 对 113,680 misses 再减少多个 refill 相位，两者组合具备达到目标的数量级。若短窗仍低于 0.75，再评估 cache capacity 和 Store/Load 仲裁，而不是直接扩大窗口。
