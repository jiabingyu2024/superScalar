# 100 MHz 全时序收敛优化实施方案

> 基线：`c24d8588372f7b5b68c68b4138bc3842c7a0276d` routed DCP
>
> 目标：CPU setup/hold/recovery 全部无违例，并完成约束、CDC、DRC 审计
>
> 原则：每个阶段独立提交、功能回归、clean Vivado route；不累计未验证的大重构

## 1. 完成标准

“消除所有时序违例”必须同时满足：

| 项目 | 完成门槛 |
| --- | --- |
| CPU setup | WNS ≥ 0，TNS = 0，failing endpoints = 0 |
| CPU hold | WHS ≥ 0，THS = 0 |
| Recovery/removal | WNS ≥ 0，TNS = 0 |
| Pulse width | 0 violation |
| Routing | 0 unrouted / routing error |
| Timing coverage | no-clock=0，unconstrained internal endpoint=0 |
| CDC | Critical=0；warning 均有结构性解释或修复 |
| Clock groups | 同 PLL 时钟关系有明确、正确的同步/异步合同 |
| DRC | `REQP-1839=0`；DSP pipeline warning 已处理或有性能证据解释 |
| 功能 | RV32I/M/MI、短窗口与长窗口 difftest、reset/recovery/cache directed tests 通过 |
| 性能 | 相同 workload 记录 IPC；最终比较 `IPC × Fmax`，不能只看 WNS |

建议工程目标不是刚好 `WNS=0.000`，而是 routed CPU setup 至少留 `+0.2 ns` 裕量，
防止 seed、温度和微小 RTL 变化立即回归。

## 2. 不可采用的“捷径”

1. 不对真实 CPU 同周期路径设置 false path；
2. 不为当前单周期微架构路径设置 multicycle，除非协议本身被改成多周期并有验证；
3. 不把 100 MHz 约束放宽后宣称通过；
4. 不只修 top-1 WNS；每轮必须重新导出全部失败 endpoint；
5. 不在同一轮同时重构 recovery、LSU、rename 和 IQ，避免功能失败无法归因；
6. 不用大范围 `dont_touch` 或 Pblock 冻结坏结构；
7. 不通过关闭 recovery/CDC/DRC 检查隐藏问题。

## 3. 阶段 P0：reset 树同步化

### 3.1 目标

- 消除 11 个 recovery endpoint；
- 消除 `cpu_rst_sync` 对普通 setup 的污染；
- 使 `REQP-1839` 归零；
- 降低 4042 fanout 异步 control routing。

### 3.2 修改范围

- `rtl/soc/student_top.sv`
- `rtl/core/**/*.sv` 中所有 `always_ff @(posedge clk or posedge rst)`
- 必要时新增小型 `ResetSynchronizer`/`ResetBridge`，但异步 reset 只能存在于该模块。

### 3.3 推荐结构

1. 板级 reset/PLL lock 进入两级或三级 synchronizer：异步 assert、同步 deassert；
2. synchronizer 输出作为 core 的**同步 reset 条件**；
3. core 内统一使用：

```systemverilog
always_ff @(posedge clk) begin
    if (rst) begin
        valid_q <= '0;
    end else begin
        ...
    end
end
```

4. 宽 payload 仍不 reset，只 reset valid/count/head/tail/epoch；
5. IROM/DRAM 地址和控制来源寄存器必须是同步 reset 或无 reset。

该原则同时是低功耗/状态保持约束：不为了 reset 或 recovery 切换数千位无效 payload，
减少无效动态翻转和 control-set 扇出；真正的时钟门控如后续引入，必须使用 FPGA
专用 BUFGCE，不得用普通逻辑门控时钟。

### 3.4 隐含前提

- PLL 输出时钟在 reset 期间必须运行；
- reset 至少保持若干 CPU 时钟周期；
- 若 PLL unlock，reset bridge 必须重新进入 reset 并重新同步释放。

### 3.5 功能验证

- reset 在任意相位断言/释放；
- reset 中无 commit、memory request、PRF write；
- reset 后 PC、RAT、ROB/IQ valid、DCache valid 状态正确；
- 连续短 reset、PLL lock 抖动测试；
- Verilator 与 Vivado xsim 的 reset 可见周期一致。

### 3.6 Routed 验收

- async_default recovery failing endpoints 从 11 降为 0；
- `cpu_rst_sync` 不再出现在 top negative-slack setup nets；
- `REQP-1839=0`；
- setup WNS 不允许恶化超过 0.1 ns。

如果同步 reset 使大面积 D mux 恶化，说明 reset 仍错误地覆盖宽 payload；回到“只 reset
ownership/valid”的原则，而不是恢复深层异步 reset。

## 4. 阶段 P1：recovery 与数据路径解耦

### 4.1 目标

直接处理 25,794 个 `retire_stage` 源 endpoint，并切断当前 `-2.868 ns` 最差路径。

### 4.2 关键原则

将 recovery 信号分成两类语义：

- `redirect_now`：立即选择 recovery PC，服务前端重定向；
- `kill/ownership`：在 recovery 边沿撤销后端 speculative owner，只作用于窄 valid、
  count、head/tail、epoch/killed bit。

`redirect_now` 不应参与 IQ payload、PRF address、execute result、WB exception cause、
DCache data/write mux。

### 4.3 P1A：移除 recovery 对 registered completion 的组合门控

重点审计：

- `ExecuteCluster.sv:340-354` 的 `complete_valid_o`、`complete_csr_write_o`、`prf_we`；
- `CoreBackend.sv:458-513` 的 issue-ready；
- Dispatch/IQ/ROB/StoreBuffer 中所有 `!clear_i`、`!recover_i` 组合条件。

推荐做法：

1. registered `wb_valid_q` 是 completion ownership 的唯一来源；
2. recovery 在时钟沿清 `wb_valid_q`，而不是用 `clear_i` 组合修改 payload/PRF mux；
3. 对 recovery 边沿仍到达的 PRF speculative write，证明其不可通过恢复后的 RAT 被观察；
4. ROB completion 写若与 ROB clear 同边沿发生，clear 必须拥有优先级；payload 可写但
   valid/count 清零后不可见；
5. scheduler 不把 recovery 当作 wakeup/payload select 输入；IQ valid 在边沿清零。

不能机械删除所有门控。以下外部副作用仍需 `redirect_now` 或本地 kill 保护：

- 未被 DCache 接收的 uncached/MMIO request；
- StoreBuffer 对外 drain；
- CSR architectural write；
- commit/free-list/ARAT 更新。

### 4.4 P1B：局部 ownership 清理

按模块建立窄状态所有权：

| 模块 | recovery 只应更新 |
| --- | --- |
| ROB | valid/done/count/head/tail/retire-stage-valid |
| Dispatch buffer | head/tail/count 或 epoch |
| INT/MEM/MUL IQ | valid/count/age/probe-valid |
| Issue elastic stage | valid_q |
| Execute/WB | wb_valid、mem request valid、killed metadata |
| StoreBuffer | 删除未退休 entry；保留已退休 side-effect owner |
| Rename/Busy/FreeList | sRAT/Busy/free ownership 从 ARAT 恢复 |

宽 uop/result/exception/address/data payload 不进入 recovery control set。

若一个模块清 valid 仍产生高 fanout，可以使用模块本地 epoch：recovery 翻转 epoch，
entry 的 epoch 不匹配即不可见。epoch 方案仅在 valid-vector clear 仍是关键路径时采用，
不要一开始全核引入。

### 4.5 P1C：Commit recovery action 稳定化（条件阶段）

先实施 P1A/P1B 并 route。只有 `retire_stage→recover` 本身仍超时，才增加 recovery
action register/sequencer。不能直接把 `recover_valid_o` 延后一拍；必须同时：

1. 在检测 recovery 的边沿消费且只消费一次对应 retire entry；
2. 锁存 `{valid, pc, cause/type}`；
3. 阻止下一周期重复 retire/CSR/free；
4. 阻止额外 uncached/MMIO request 和 store side effect；
5. 对已接收 load 设置 killed，并继续 drain response；
6. 下一周期执行 redirect 与 ownership clear。

### 4.6 必须增加的断言

- recovery 后不存在旧 epoch/旧 valid 的 commit；
- recovery entry 只 commit/free 一次；
- wrong-path store 永不 drain；
- killed load response 永不写 PRF/ROB；
- recovery 与 completion 同边沿时，clear ownership 优先；
- lane1 retire 不能越过 lane0 recovery/trap；
- branch miss、exception、mret 的 recovery PC 正确。

### 4.7 Routed 验收

- `ROB retire` 源 endpoint 从 25,794 降到接近 0；
- `recover_valid_o` 不再出现在 PRF address、IQ payload、WB data top paths；
- WNS 至少优于 `-1.5 ns`；
- TNS 至少下降 50%；
- IPC 损失目标 <2%；若引入 recovery sequencer，只允许影响 mispredict/trap 周期。

## 5. 阶段 P2：LSU→DCache request 注册边界

### 5.1 目标

切断 `mem_req_count_q → DCache LUTRAM WE`，处理 5,648 个 mem_req 源 endpoint 和
大量 retire→DCache 残余路径。

### 5.2 推荐接口

在 Execute/LSU 与 DCache 之间引入一项 request skid register：

```text
LSU request queue head
→ req_valid/ready handshake
→ dcache_req_q {valid, write, addr, wdata, wstrb, uncached, owner metadata}
→ DCache lookup/write FSM
```

完整 payload 必须原子锁存，不能只打一拍 valid。

### 5.3 实施要点

1. `mem_req_count_q` 只决定 LSU 本地 request-register enqueue；
2. DCache 的 `active_req_*` 只能来自 registered request 或内部 hold register；
3. request register 在 `valid && ready` 后释放，支持 same-cycle replace；
4. store hit、load hit、uncached、miss/refill 使用同一 request owner 合同；
5. 对已接收 load，保留 response metadata；recovery 只设 killed；
6. uncached/MMIO request 一旦下游接受不得 replay；未接受的 wrong-path request 可丢弃；
7. 重新核对 `cpu_resp_valid` 与 owner metadata 的拍数；
8. DCache LUTRAM 写口只由 DCache 本地 registered state/refill response 驱动。

### 5.4 DCache 内部收尾

若注册 request 后 LUTRAM WE 仍超时：

- 将 store-hit merge 结果先写入 `data_write_*_q`，下一拍写 LUTRAM；
- 将 refill response `{way, addr, data, valid}` 注册后写 RAM；
- bypass 使用 `data_write_*_q` 保持 read-after-write 行为；
- 不要把 data array 改成 BRAM，除非同时接受 lookup latency 增加并修改整个 load pipeline。

### 5.5 Directed tests

- load/store hit、miss、dirty writeback、critical-word-first；
- refill request/response 连续与气泡；
- same-address read/write、byte/halfword mask；
- request backpressure、same-cycle pop+push；
- recovery 与 request accept 同边沿；
- recovery 与 load response 同边沿；
- uncached/MMIO request 不丢失、不重复；
- StoreBuffer partial/full forwarding。

### 5.6 Routed 验收

- `Execute mem_req` 源 endpoint 从 5,648 降到接近 0；
- top path 不再从 LSU count/head 到 RAMD64E WE；
- DCache 目的 endpoint 数显著下降；
- load-hit latency/IPC 变化必须记录；目标优先保持 throughput，每拍可接收一个命中请求。

## 6. 阶段 P3：缩短 sRAT→dispatch-buffer capture

### 6.1 目标

处理 3,211 个 sRAT 源 endpoint，尤其 2,699 个 dispatch-buffer payload endpoint。

### 6.2 第一选择：ready 状态延迟解析

保留 dispatch buffer 作为已分配 uop owner，但简化入队数据：

1. Rename 当拍只完成：sRAT map、older-lane bypass、PRD/old-PRD、uop metadata；
2. 不在入队数据上叠加 `scheduler_wakeup_valid`；
3. 不要求 BusyTable query 结果进入同一条 payload capture path；
4. 下一周期 buffer head/entry 根据 registered BusyTable 状态和 wakeup 更新
   `src1_ready/src2_ready`；
5. completion 与入队同边沿时，BusyTable 在边沿标 ready，下一周期查询必须看到 ready，
   从而不会丢失 wakeup。

建议把 readiness 与宽 payload 分离存储：

```text
payload_q[slot] = {uop, prs1, prs2, prd, old_prd, ...}
ready_q[slot]   = {src1_ready, src2_ready}
```

这样 wakeup 只写 2-bit ready state，不重写完整 `CoreRenamedUop`。

### 6.3 第二选择：buffer 写 bank 化

若 dynamic tail 仍是 top path，把 4-entry buffer 改成 2 个 two-wide bundle slot 或
even/odd bank：

- lane0/lane1 写固定 bank；
- bundle valid mask 保持 lane prefix；
- head 以 bundle 为单位，允许部分消费时保留 lane1 survivor；
- ROB allocation 仍在 buffer pop 时发生，保持当前原子合同。

不要退回每拍压缩宽 payload；上一轮报告已证明 wide compaction 对 FPGA 时序不友好。

### 6.4 必须保持的不变量

- lane1 不能在 lane0 未接收时独立分配；
- same-cycle lane0→lane1 RAW/WAW 映射正确；
- PRD 分配、sRAT 更新、buffer enqueue 原子；
- buffer pop、ROB allocation、IQ dispatch 原子；
- recovery 清除所有 speculative buffer owner；
- completion 与入队同边沿不丢 ready；
- x0 永远映射到 PRF 0 且 ready。

### 6.5 Routed 验收

- sRAT 源 endpoint 从 3,211 降到接近 0；
- QoR 不再报告 sRAT→dispatch payload 27～32 levels；
- dispatch buffer 不成为新的 high-fanout/拥塞中心；
- steady-state 2-wide rename/dispatch throughput 保持。

## 7. 阶段 P4：ROB/IQ/PRF 残余路径治理

P0～P3 后重新聚类，不预判新的 top path。仅按新报告选择以下措施。

### 7.1 ROB

当前 ROB 已拆分 allocation payload 与 completion payload，并有 retire stage；保留该结构。
若 ROB 仍有大量 endpoint：

- valid/done 使用窄 bank 或 epoch；
- retire-stage refill 只读固定两个 candidate，并避免 survivor+fill 宽动态索引；
- completion decode 分 bank，避免 4 completion port 扇入所有 entry；
- 不给 wide retire payload增加 reset/clear CE。

### 7.2 INT IQ

当前 active queue 仍使用 `CompressedQueue`，每拍重写宽 payload。若它成为 top path：

- active queue 改 stable-slot `{valid, age/tag, ready bits, payload}`；
- selector 输出 index，issue register 下一拍读 payload；
- wakeup 只更新 ready bits；
- cold queue 保留容量，但 reinject 使用注册 grant；
- 不让 ready 反馈进 valid 组合环。

### 7.3 PRF

PRF 为 64×32、8R4W FF/mux 结构，QoR congestion 仍位于该区域。若 PRF 回到 top path：

- 比较 read-port 分组和本地 operand register；
- 将 MEM/MULDIV 读口与 INT 读口分区放置或复制只读 shadow 不现实，优先减少同拍活跃端口；
- 保留 WB bypass，避免消费者读到旧值；
- 检查同 PRD 多写口优先级并增加冲突断言。

## 8. 阶段 P5：DSP、约束与实现策略收尾

### 8.1 DSP pipeline

DRC 报告 `DPIP-1=2`、`DPOP-1=2`、`DPOP-2=3`。检查 `MUL_0` 的 A/B input、MREG、
PREG 配置与 RTL `MUL_LATENCY` 合同：

- 若增加 DSP pipeline，必须同步修改行为模型、MulDivPipe latency 和 valid shift；
- 验证 MUL/MULH/MULHU/MULHSU 的 bit packing 与符号扩展；
- 以实际 DSP path 和 IPC 决定，不因 DRC 建议盲目加拍。

### 8.2 Clock/CDC

- 重新确认 `clk_out1_pll` 与 `clk_out2_pll` 的真实相位/频率关系；
- 若为同步派生时钟，不得整域 `set_clock_groups -asynchronous`；使用 generated clock
  关系并对真实 CDC 加同步器；
- 修复 counter Gray 值同步器前组合逻辑：先在源域注册 Gray，再同步；
- 多 bit 控制/数据使用 handshake、Gray 或 async FIFO，不能只打 ASYNC_REG；
- 补齐 UART 输入 delay 和板级输出 delay，或在文档中明确 virtual-clock 假设。

### 8.3 QoR 对照 run

结构优化完成后，建立同一 RTL 的独立实现 run 比较：

1. 默认 strategy；
2. 应用 `RQS_CONG-2_1` 的 MUXF remap；
3. 应用关键 net replication / `FORCE_MAX_FANOUT`；
4. Performance_Explore / AggressiveExplore 类 directive；
5. 不同 seed（至少 3 个）确认裕量稳定性。

只保留能在多个 seed 上稳定改善 WNS/TNS、且不恶化 hold/DRC 的策略。不要直接把
QoR suggestion 写成全局永久属性。

## 9. 每阶段验证矩阵

| 类别 | 最低要求 |
| --- | --- |
| 静态 | lint/elaboration；无 latch、multiple driver、width warning 新增 |
| 单元 | 修改模块 directed tests + assertion |
| ISA | RV32I、RV32M、RV32MI |
| 差分 | srcSmoke；srcWithMext 短窗口，再跑约定长窗口 |
| Recovery | branch miss、exception、mret、同拍 completion/load/store 场景 |
| Memory | cache hit/miss/writeback/refill/MMIO/backpressure |
| FPGA | clean synth/impl；重新导出本目录全部报告 |
| 性能 | 相同 binary/max cycles，记录 IPC、mispredict penalty、load latency |

每次修改后先跑最小 directed test，再扩大到 ISA/difftest，最后才启动 Vivado。功能
失败时不得用旧 routed 数值继续推断时序收益。

## 10. 每轮报告比较模板

```text
commit:
Vivado strategy / seed:
CPU WNS / TNS / failing endpoints:
recovery WNS / endpoints:
hold WHS / endpoints:
top-5 source families:
top-5 destination modules:
top-5 source→destination families:
worst path logic levels / route%:
level-5 congestion regions:
top negative-slack fanout nets:
LUT / FF / LUTRAM / BRAM / DSP:
CDC critical / DRC count:
IPC / workload / max cycles:
functional regression:
```

必须重新运行 `export_all_setup_endpoints.tcl`；不能让全量 CSV再次滞后于 routed DCP。

## 11. 推荐提交顺序

| 提交 | 内容 | 预期主要收益 |
| --- | --- | --- |
| T0 | reset 同步化 | recovery/REQP-1839 归零 |
| T1 | completion/issue/queue 去 recovery 组合门控 | 切断当前 WNS，覆盖 retire 大族 |
| T2 | backend 局部 ownership/valid clear | 清理 ROB/IQ/StoreBuffer 残余 |
| T3 | LSU→DCache request register | 清理 mem_req→DCache 大族 |
| T4 | rename readiness 延迟解析 | 清理 sRAT→dispatch 大族 |
| T5 | 按新报告做 ROB/IQ/PRF 收尾 | WNS/TNS 归零 |
| T6 | DSP/CDC/clock constraints/QoR runs | 完成全设计 sign-off |

## 12. 停止与回退条件

- 某阶段 IPC 下降 >5% 且 `IPC × Fmax` 无净收益：回退或改为参数化；
- recovery/memory directed test 出现一次 ownership 错误：停止 Vivado，先修协议；
- WNS 改善但 TNS/失败 endpoint 大幅增加：视为路径搬家，不接受；
- setup 通过但 hold 失败：不得以 setup 成功结束；
- 使用 implementation directive 才勉强 `WNS≈0` 且 seed 不稳定：继续 RTL 优化；
- clock group/CDC 未完成：只能宣称 CPU 域 timing clean，不能宣称全设计 sign-off。

最终目标不是生成一份“绿色 timing summary”，而是在精确恢复、内存副作用、乱序
ownership 和 IPC 均保持正确的前提下，让 100 MHz 成为可重复的 routed 结果。
