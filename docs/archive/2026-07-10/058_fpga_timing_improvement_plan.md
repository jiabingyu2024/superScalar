# FPGA 时序改善计划

日期：2026-07-10

## 1. 当前基线

对象：`digital_twin_srcWithMext` routed design，CPU/系统时钟均为 50 MHz。

| 指标 | 当前值 |
| --- | ---: |
| CPU setup WNS | +0.923 ns |
| CPU setup TNS | 0 ns |
| CPU hold WHS | +0.026 ns |
| CPU hold THS | 0 ns |
| system setup WNS | +16.164 ns |
| Slice LUT | 81,080 (39.78%) |
| Slice FF | 44,804 (10.99%) |
| LUTRAM | 1,520 |
| BRAM36 | 68 |

50 MHz 已收敛，但 CPU setup 只剩 0.923 ns；hold 余量 0.026 ns 也要求每轮 route 重新检查。

## 2. 最差路径

```text
MemIssueQueue entry.prs1
 -> issue select/ready
 -> PRF combinational read
 -> load/store address adder
 -> StoreBuffer forwarding CAM/full mask
 -> MEM completion gating
 -> DCache request/decode
 -> SocMemBridge DRAM select
 -> DRAM BRAM WEA
```

报告值：data path `18.935 ns`，logic `2.673 ns`，route `16.262 ns (85.9%)`，35 级逻辑。它跨越 Issue Queue、PRF、Execute、StoreBuffer、DCache、SoC bridge 和 BRAM，主要问题是模块跨度与扇出，不是单个慢运算器。

## 3. P0：可信基线

提频前完成：

1. `implfix_p1` 上板确认 37+8 和最终 PASS；
2. ROB/BPU/MultiPushFifo 的 `Synth 8-7137` 归零；
3. 使用 interface modport 清理 203 条 `HPDR-2` INOUT inconsistency；
4. 复核 PLL 两输出关系，删除整域 blanket async clock group，或只 false-path 同步器第一级；
5. 保持 `no_clock=0`、`unconstrained_internal_endpoints=0`；
6. 归档 timing、methodology、control sets、层次利用率和板测结果。

`TIMING-47` 已警告两个 PLL 派生时钟本来同步，却被整域切为 asynchronous clock group；该约束可能隐藏真实 CDC 路径，不能当作时序优化。

## 4. P1：切断 MEM issue 到 DRAM WEA 长路径

优先在 MEM issue/execute 与 DCache 之间增加单项 registered request buffer：

1. issue 时锁存 uop、源操作数或最终地址/写数据；
2. 下一拍执行 StoreBuffer forwarding 查询与 DCache 请求；
3. `mem_issue_ready` 只依赖 buffer 空闲，不再组合依赖 forwarding、DCache 和 DRAM ready；
4. load 按 ready/valid 返回，store 继续由 StoreBuffer 顺序提交；
5. 为 forwarding、flush、recovery 添加断言。

目标是切断当前 35 级跨层次路径。代价是 load issue 增加一拍；若 `srcWithMext` IPC 下降超过 3%，再设计 skid/bypass，不恢复长组合路径。

## 5. P2：缩短 StoreBuffer CAM

1. 先寄存 load 地址；
2. forwarding CAM 仅在 request buffer 有效时工作；
3. 分层计算 address match 与 byte merge，必要时增加一拍；
4. 保持年轻 store 覆盖老 store；
5. 覆盖 SB/SH/SW 与 LB/LBU/LH/LHU/LW 组合测试。

验收目标：最差路径不再经过 `load_forward_full_o`。

## 6. P3：PRF 与 Issue Queue

若 P1/P2 后仍不足：

1. PRF 组合多读口改为 bank/replica 或 registered read；
2. Issue Queue 从每拍全表压缩改为 valid bitmap + age/select；
3. wakeup/select 先产生 index，下一拍读 payload；
4. INT/MEM/MUL queue 分别优化，不一次重写整个 backend。

该阶段会改变流水与旁路时机，风险高于 P1/P2，必须逐项提交回归。

## 7. P4：DCache 后续路线

当前 LUTRAM 异步读仍可能形成深 mux。只有 timing report 进入 data/tag read 路径时再选择：

- 保守：保持 LUTRAM，注册 request/tag compare 并保留同址写旁路；
- 提频：data array 改同步 BRAM，增加 lookup pipeline 和 miss/refill bypass。

当前最差路径主要是 request/ready 控制，不应先重写 cache data array。

## 8. 目标与门槛

`FPGA_ENABLE_POWER_OPT` 继续为 `false`。每阶段先使用同 seed/strategy，再尝试 `Performance_Explore` 或额外 phys_opt。

| 阶段 | 频率 | setup 目标 | hold 目标 |
| --- | ---: | ---: | ---: |
| P0 正确性 | 50 MHz | WNS >= +0.5 ns | WHS >= 0 ns |
| P1/P2 | 55 MHz | WNS >= +0.3 ns | WHS >= 0 ns |
| P1/P2 收敛 | 60 MHz | WNS >= 0, TNS=0 | WHS >= 0, THS=0 |

每阶段必须满足：RV32UI 40/40、RV32UM 8/8、RV32MI 4/4、`srcWithMext` 早期 37+8、完整测试 PASS、内部端点全约束、setup/hold/DRC 无 blocker，并记录 IPC/资源/WNS/WHS。禁止靠扩大 false path 或伪造 multicycle 获得正 WNS。
