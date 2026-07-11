# superScalar IPC 与 FPGA 频率联合优化空间分析

日期：2026-07-11

整合输入：

- `docs/archive/2026-07-10/vs/NOP-Core_vs_superScalar_current_microarchitecture_timing_review.md`
- `docs/archive/2026-07-10/058_fpga_timing_improvement_plan.md`
- `docs/archive/2026-07-10/059_ipc_optimization_plan.md`
- `docs/archive/2026-07-10/060_nopcore_lsu_muldiv_ipc_timing_optimization.md`

## 1. 执行摘要

上一轮已经完成最有把握的 LSU 和乘法优化：registered LSU request stage 切断旧 MEM 长 ready 路径，cacheable load 支持 StoreBuffer no-alias 放行，pending load 与 INT issue 解耦，`MUL_0` 改为 II=1。`srcWithMext` 200k IPC 从 `0.640525` 提高到 `0.836345`。

优化后的主矛盾已经变化：

1. **IPC 主空间在 memory latency/ordering，不再是 INT 全局封锁或 MulDiv busy。**
2. **频率主空间需要新的 routed timing report 才能排序。** 旧的 18.935 ns 路径已被寄存边界切断，不能继续拿旧报告决定 PRF、IQ 或 DCache 重构。
3. **优先目标仍应是 `IPC × routed Fmax`。** 当前 500k 快速基线 IPC `0.831074`，50 MHz 对应 `41.554 MIPS`；55 MHz 即使 IPC 降到 `0.755522` 仍与当前吞吐打平，60 MHz 的打平 IPC 是 `0.692562`。
4. 下一步最合理顺序是：新 Vivado 基线 -> 2-entry LSU request skid/FIFO -> 根据新关键路径选择一次 stage 切分 -> 再评估 bounded MEM lookahead。不能直接开放 `HEAD_ONLY=0`，也不应先扩大 ROB、PRF、IQ 或 fetch width。

## 2. 新的快速性能基线

### 2.1 为什么不再用 200k 作为唯一基线

200k 已能越过启动和 37+8 早期检查，但固定启动、CSR/MMIO 和 M 扩展测试占比仍偏高。另一方面，窗口太大又会进入后续大矩阵/内存密集阶段，使一次小改的回归成本和 workload 构成都发生变化。

本次用完全相同 binary 和参数采样：

| max cycles | commit | IPC | load pending | INT IQ backpressure | ROB wait MEM | 判断 |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 200k | 167,269 | 0.836345 | 35.9% | 40.8% | 33.8% | 超快速 sanity，启动占比稍高 |
| 500k | 415,537 | 0.831074 | 36.3% | 42.2% | 34.6% | 统计已稳定，尚未被后段主导 |
| 600k | 480,061 | 0.800102 | 38.4% | 46.0% | 35.7% | workload 构成开始变化 |
| 750k | 575,730 | 0.767640 | 40.5% | 49.9% | 36.9% | 后续 memory phase 权重明显增大 |
| 900k | 673,974 | 0.748860 | 41.7% | 52.4% | 37.5% | 不适合作为日常快速门槛 |
| 1M | 738,628 | 0.738628 | 42.4% | 53.7% | 37.8% | 已明显混入后续阶段 |

500k 与 200k 的 IPC 只差 `0.63%`，主要压力比例也接近；从 600k 开始 IPC 和 memory/INT-IQ 压力发生连续偏移。由此推断阶段变化发生在约 500k 之后，精确程序 phase 边界仍需显式 PC/progress marker 才能证明。

### 2.2 建议的三级回归窗口

| 层级 | 用途 | 建议命令/上限 | 门槛 |
| --- | --- | --- | --- |
| A | 极快功能和计数 sanity | `srcWithMext`, 200k | 37/37、M 8/8、无提前 FAIL；IPC 仅参考 |
| B | 日常 IPC 基线 | `srcWithMext`, 500k | 固定 binary/参数；基线 IPC `0.831074` |
| C | workload 变化诊断 | 600k/750k/1M 按需 | 不作为每次合入门槛，只观察优化跨 phase 是否仍成立 |
| D | 收口正确性 | `srcSmoke` full + 小量 difftest | `srcSmoke` PASS；difftest 正常推进 |

不建议把完整 `srcWithMext` 或大矩阵阶段作为日常性能基线。若以后要专门优化矩阵，应增加明确的 `perf_start/perf_stop` 或 PC 区间采样，而不是继续扩大从 reset 累积的 `max_cycles`。

## 3. 当前微架构事实与工程推断

### 3.1 已确认事实

500k 窗口的关键现象：

- IROM wait 为 0，前端存储带宽不是瓶颈。
- ROB full 仍极低，FreeList empty 为 0，窗口/PRF 容量不是优先项。
- INT 被 pending load 直接封锁已接近 0。
- request stage 约 47.7% 周期有效，MEM issue 约 `0.261 uop/cycle`。
- load pending 约 36.3%，ROB head wait MEM 约 34.6%。
- `younger_ready_behind_head` 约 26.3%，MEM IQ head-of-line 现象真实存在。
- DCache miss rate 约 1.46%，但 DCache stall 约 13.5%；stall 不能仅用 miss 数解释。
- partial store alias 极少，200k 只有 3 cycles；实现 partial-forward + memory merge 没有收益证据。
- MUL/DIV/REM 中 MUL 占绝对多数，MUL II=1 后 MulDiv busy 已接近消失。

### 3.2 工程推断

`INT IQ backpressure` 排名第一，但 ROB head wait INT 很低，因此它更像 memory latency 造成 consumer 长时间等待后向 INT IQ/dispatch 传播，而不是 ALU 数量不足。直接扩大 INT IQ 会增加压缩、选择和布线成本，只能延迟堵塞传播。

`load_pending`、`MEM issue block`、`ROB wait MEM` 和 `MEM IQ backpressure` 高度重叠，不能相加估算损失。共同根因主要包括：

1. 单 outstanding load；
2. blocking DCache/memory response；
3. MEM IQ head source 未 ready；
4. 单项 request stage 对短 burst 的吸收有限；
5. 保守的严格 memory issue 顺序。

## 4. IPC 优化空间

### P0：先补 phase-aware 计数，不改架构

建议增加 simulation-only 观测：

- `mem_req_q` accept/consume/empty/full 分桶；
- load hit、miss/refill、uncached、共享 store 通道等待的互斥原因；
- MEM IQ head 类型以及 `younger_ready` 类型组合；
- PC 区间或软件 progress marker 控制的 perf window。

目的不是继续增加总计数，而是回答两个决策问题：request stage 的容量是否限制吞吐，以及 MEM lookahead 能合法越过的动态比例是多少。

### P1：1-entry request stage 扩为 2-entry skid/FIFO

这是当前最安全的下一项 IPC 优化，也符合 NOP-Core 的 elastic stage 思路。

建议 contract：

```text
MEM IQ -> request FIFO(depth=2) -> SB CAM/DCache

mem_issue_ready = !clear && (count_q < 2)
```

要求：

- ready 只看 registered count，不能用同拍 CAM/DCache consume 形成回传；
- payload 只在 push fire 时写，stall 时稳定；
- clear 只清 ownership，已接受但错误路径的外部 response 用 pending/epoch 丢弃；
- 保持单 outstanding load，先只吸收 store/load burst，不同时引入 response ID。

预期收益是减少 request slot 周转气泡和 MEM IQ 瞬时 backpressure，保守目标为 500k IPC 提升至少 2%。若收益低于 2%，不要继续扩大到 4 项。

风险：若 FIFO 中 younger store 参与了比它更老 load 的 forwarding，年龄语义会错误。因此 FIFO 仍必须按序 drain，StoreBuffer 查询只能由 FIFO head 发起。

### P2：两项 bounded MEM lookahead

该项潜在收益比 request FIFO 大，但验证风险显著更高。进入条件建议改为：

- 500k `younger_ready_behind_head > 10%`；当前满足；
- 新计数证明候选之前没有 unresolved store 的合法周期占比 > 5%；当前尚未测得；
- ROB wait MEM 仍在前四瓶颈；当前满足。

只做两项 lookahead，选择结果先寄存再进入 request FIFO。必须增加 memory sequence/ROB age，使 StoreBuffer forwarding 只匹配比 load 更老的 store。MMIO、fence、异常和地址未知的老 store 继续严格 head-only。

验收：500k IPC 至少提升 3%，且 memory-order scoreboard、recover/exception 定向测试和 assertion 全过。否则回退到 head-only。

### P3：多 outstanding load / non-blocking DCache

这是中长期最大的 IPC 空间，也是最高风险项。单纯把 `mem_load_pending_q` 改成计数器不够，还需要：

- request ID/ROB/PRD/epoch；
- 至少 2 项 load metadata queue；
- DCache 支持多个 hit 或 hit-under-miss/MSHR；
- response 与 completion slot 仲裁；
- flush 后迟到 response 隔离；
- store/load、uncached/MMIO 顺序证明。

当前 DCache miss rate低但 load pending高，先区分 hit latency、miss/refill和共享端口等待，再决定做“两项顺序 outstanding”还是完整 non-blocking cache。没有这组分解计数前不建议实施。

### 暂不建议的 IPC 项

| 项目 | 原因 |
| --- | --- |
| partial forwarding merge | 动态 partial alias 极少，收益不足 |
| 扩 ROB/PRF | ROB full/FreeList empty 几乎为 0 |
| 扩 INT IQ | 更可能掩盖 memory consumer 堵塞，且恶化选择/布线 |
| 放松 serial/unique-retire | serial block 极低 |
| 扩 fetch width/I-cache | IROM wait 为 0，前端压力来自后端反压 |
| 缩短 MUL DSP latency | MulDiv busy 已消失；减少 pipeline stage 会伤害 Fmax |

## 5. 频率优化空间

### P0：必须先获得新 routed baseline

旧 routed 最差路径从 MEM IQ 穿过 PRF、AGU、StoreBuffer、DCache 到 DRAM WEA；060 已在 MEM IQ 后增加寄存边界。旧 `WNS=+0.923 ns @ 50 MHz` 和 18.935 ns 路径只能作为历史数据，不能证明新版本的 WNS，也不能说明新最差路径在哪里。

下一次 Vivado 只需做一次可信基线，不必先尝试大量 strategy：

1. 相同 part、seed、strategy、约束生成 50 MHz routed design；
2. 归档 setup/hold top 20、hierarchical utilization、high-fanout、control sets、DRC/CDC/methodology；
3. 确认旧跨模块路径已消失；
4. 修复/解释 `TIMING-47`、HPDR-2、unconstrained endpoint 和 Synth 8-7137，不能用 blanket async/false path 隐藏；
5. 同一版本再试 55 MHz，只有 55 MHz 有余量才评估 60 MHz。

### 新关键路径的条件化处理

| 新 timing report 落点 | 优先动作 | IPC 代价 | 风险 |
| --- | --- | ---: | --- |
| request_q -> SB CAM -> DCache/bridge | SB address match/byte merge 分层，必要时 CAM result 再寄存 | 约 1 个 load cycle | 中 |
| INT IQ select -> PRF -> ALU/BRU | 增加 issue-to-RRD elastic register，保留 raw valid/ready/flush contract | dependent ALU/branch 多 1 cycle | 高 |
| decode -> rename -> dispatch | decode 后或 rename 后加 2-wide elastic stage | steady-state 小，recovery penalty +1 | 中 |
| FreeList priority scan | bitmap 分组编码/小队列 free list | 近乎 0 | 中 |
| INT IQ 压缩/宽 payload 搬移 | valid/age 与 payload 分离，只移动 index | 近乎 0 | 高 |
| DCache LUTRAM read mux | 先注册 request/tag compare；只有报告明确指向 array 才考虑 BRAM | load latency +1 | 高 |

### NOP-Core stage 对齐的取舍

NOP-Core 的 ID/RN/DS、ISS/RRD/EXE 分段能提高 Fmax，但直接照搬会增加当前核的 branch resolution、load-use 和 dependent ALU latency。应由 timing report 决定切哪一刀，而不是一次加入全部 stage。

若必须优先选择一个无报告候选，`decode/rename/dispatch` elastic boundary 通常比 `issue/RRD/EXE` 更稳妥：它主要增加恢复重填延迟，不直接增加所有依赖 ALU 链的 latency。但最终仍应以 top path 为准。

## 6. IPC × Fmax 决策门槛

新的日常基线采用 500k IPC `0.831074`：

| 频率 | 保持当前 IPC 的吞吐 | 与当前 50 MHz 打平所需 IPC | 可容忍 IPC 回退 |
| ---: | ---: | ---: | ---: |
| 50 MHz | 41.554 MIPS | 0.831074 | 0% |
| 55 MHz | 45.709 MIPS | 0.755522 | 9.09% |
| 60 MHz | 49.864 MIPS | 0.692562 | 16.67% |

因此，增加一个 stage 即使让 IPC 从 0.831 降到 0.80，只要 routed Fmax 达到 55 MHz，吞吐仍是 `44.0 MIPS`，比当前提高约 5.9%；若达到 60 MHz，则是 `48.0 MIPS`，提高约 15.5%。

阶段接受条件应写成：

```text
new_IPC × new_routed_Fmax > 0.831074 × 50 MHz
```

同时必须满足 RV32/src 正确性、hold、DRC/CDC、资源和无伪约束条件；不能只用乘积掩盖功能或时序风险。

## 7. 推荐实施路线

```text
Stage A：冻结 500k 基线 + 新 Vivado 50/55 MHz routed report
  -> Stage B：2-entry ordered request skid/FIFO
     -> 500k IPC、RV32、srcSmoke、50k difftest
  -> Stage C：依据新 top path 只切一个 stage
     -> 比较 IPC × routed Fmax
  -> Stage D：补合法 lookahead 比例计数
     -> 条件进入 2-entry MEM bounded lookahead
  -> Stage E：只有 load latency 仍占主导时评估 2 outstanding/MSHR
```

每个 Stage 单独归档，不同时修改 LSU ordering、INT pipeline 和 rename recovery。

## 8. 验证敏感点与低功耗/QoR约束

- request FIFO、RRD stage、rename stage 的所有 side effect 只能绑定 fire；stall 时 payload 必须稳定。
- recovery 必须清所有 speculative valid/token；外部不可取消 response 用 epoch/drop 状态隔离。
- bounded lookahead 不允许 load 越过地址未知的老 store，forward 只能来自 younger load 之前的 store。
- StoreBuffer flush 继续保留 retired store，丢弃 speculative store。
- MUL/DIV metadata 与 IP latency必须严格对齐，不能为降 cycle latency减少 DSP pipeline。
- 宽 payload 不做异步 reset，只 reset valid/count/state；性能计数继续只存在于 `VERILATOR_TB`。
- `FPGA_ENABLE_POWER_OPT` 在 QoR 对比阶段保持 `false`，避免实现策略变化污染架构优化归因。
- 任何新 buffer/FIFO 的 FF/LUT 增量应单独记录；单阶段顶层资源增幅原则上不超过 5%。

## 9. 最终判断

短期最有性价比的 IPC 项是 **2-entry ordered LSU request skid/FIFO**，而不是扩大窗口或直接开放 memory OoO；最大的中期 IPC 空间是 **合法的 bounded MEM lookahead 和多 outstanding load**。最大的频率空间仍是 NOP-Core 式 stage boundary，但必须先用新 routed report确定是切 rename、INT issue/RRD，还是 request/SB/DCache。

当前版本已经把 50 MHz 估算吞吐提升到约 41.55 MIPS。下一目标建议设为：

- 保守：500k IPC >= 0.84，routed 55 MHz，吞吐 >= 46.2 MIPS；
- 进取：500k IPC >= 0.85，routed 60 MHz，吞吐 >= 51.0 MIPS。

这两个目标都要求先完成新的 Vivado可信基线；在新 timing report 出来前继续大改 PRF/IQ/DCache，无法判断是在提高实际吞吐还是只移动瓶颈。

