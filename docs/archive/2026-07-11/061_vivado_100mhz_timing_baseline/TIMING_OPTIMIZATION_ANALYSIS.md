# `c24d858` 100 MHz routed 时序违例全量分析

> 分析对象：提交 `c24d8588372f7b5b68c68b4138bc3842c7a0276d` 的 routed DCP
>
> 器件 / 工具：`xc7k325tffg900-2` / Vivado 2023.2 build 4029153
>
> CPU 时钟：`clk_out2_pll`，10.000 ns / 100 MHz
>
> 数据来源：本目录的 routed timing、QoR、high-fanout、CDC、DRC 及全失败 endpoint CSV

## 0. 结论

当前版本距离 100 MHz 仍有结构性差距，但已经从上一轮 `-4.495 ns / -127382 ns`
改善到 `-2.868 ns / -40279 ns`。旧版本的 completion→IQ→PRF→execute→PRF-CE
最差组合环已经被 issue/WB 寄存边界消除，证明流水切分方向有效。

当前 36,724 个失败 endpoint 并非 36,724 个独立问题，而是四类主因：

1. `ROB retire_stage → Commit recover → 全后端 clear/valid/ready/data mux`：
   `25,794` 个 endpoint，占 `70.24%`；
2. `Execute mem_req_count/request queue → DCache LUTRAM 写口`：
   `5,648` 个 endpoint，占 `15.38%`；
3. `Rename sRAT → mapped uop/BusyTable/wakeup → dispatch buffer tail write`：
   `3,211` 个 endpoint，占 `8.74%`；
4. `cpu_rst_sync → 深层异步 reset`：既产生 `11` 个 recovery 违例，也成为
   `542` 个普通 setup endpoint 的源头。

前 3 类覆盖 `94.36%` 的失败 endpoint。因此，消除全部时序违例的正确路径是：

- 让 recovery 只改变窄 valid/ownership，不再参与当拍 payload 和 issue 数据选择；
- 在 LSU 与 DCache 之间建立真正的注册 request 边界；
- 缩短 sRAT 到 dispatch-buffer 写入路径，移除同拍 BusyTable/wakeup 叠加；
- 将 core 深层寄存器改为同步 reset，保留 reset synchronizer 的异步断言能力；
- 最后才使用 MUXF remap、局部复制和实现 directive 收尾。

不能用 false path 或 multicycle 掩盖上述 CPU 同步路径；这些路径代表真实的一周期
微架构合同。

## 1. 证据边界

### 1.1 全量 endpoint 的定义

`setup_violating_endpoints_all.csv` 已从当前 `c24d858` DCP 重新导出，共 36,724 条
数据行。导出使用：

```tcl
get_timing_paths -delay_type max -max_paths 100000 -nworst 1 \
    -slack_lesser_than 0 -sort_by slack
```

即每个失败 endpoint 保留一条最差路径。该数量与全设计 timing summary 一致：

- CPU 常规 setup：36,713 个；
- CPU async recovery：11 个；
- 合计：36,724 个。

它不是“同一 endpoint 的所有替代路径”。需要检查某 endpoint 的次差路径时，联动
`setup_violations_top1000.rpt`。

### 1.2 事实与推断

- 表格中的 slack、endpoint 数、logic levels、fanout 均为报告事实。
- “对应 RTL 组合锥”和“推荐切分点”是基于当前提交源码的工程推断。
- 任何优化收益都必须由新 clean routed DCP 验证；本文不宣称方案实施后一定一次
  达到 100 MHz。

## 2. 全局时序状态

| 检查项 | 当前值 | 判断 |
| --- | ---: | --- |
| CPU setup WNS | -2.868 ns | FAIL |
| CPU setup TNS | -40279.301 ns | FAIL |
| CPU setup failing endpoints | 36,713 / 69,510 | 52.82% CPU endpoint 失败 |
| 全设计 WNS / TNS | -2.868 ns / -40279.938 ns | FAIL |
| Recovery WNS / TNS | -0.454 ns / -0.638 ns | 11 个 endpoint FAIL |
| CPU hold WHS / THS | +0.055 ns / 0 | PASS |
| 50 MHz system setup WNS | +16.651 ns | PASS |
| Routed nets | 81,386 / 81,386 | PASS |
| QoR assessment | score 2 | Implementation completes; timing will not meet |
| Level ≥5 global congestion | 2 regions | FAIL / REVIEW |
| 超出 Net/LUT budget 的路径 | 64 | REVIEW |

当前 placement/routing 的单路径粗估频率为：

```text
1000 / (10.000 + 2.868) = 77.71 MHz
```

该数值不是 sign-off Fmax。TNS 和失败 endpoint 数说明设计不能靠修一条 WNS 路径
收敛。

## 3. Slack 分布

| Slack 区间 | endpoint 数 | 占失败 endpoint |
| --- | ---: | ---: |
| `< -2.5 ns` | 57 | 0.16% |
| `[-2.5, -2.0) ns` | 1,525 | 4.15% |
| `[-2.0, -1.5) ns` | 8,829 | 24.04% |
| `[-1.5, -1.0) ns` | 11,447 | 31.17% |
| `[-1.0, -0.5) ns` | 7,310 | 19.91% |
| `[-0.5, -0.2) ns` | 4,603 | 12.53% |
| `[-0.2, 0) ns` | 2,953 | 8.04% |

约 55.4% 的失败 endpoint 仍差 1 ns 以上。后 20.6% 的 endpoint 可能通过结构优化
带来的拥塞下降和物理优化一起收尾，但前 79.4% 不能依赖 route seed。

## 4. 按源寄存器族聚类

| 源寄存器族 | endpoint | 占比 | 最差 / 中位 slack | 平均 / 最大 levels |
| --- | ---: | ---: | ---: | ---: |
| ROB `retire_stage*` | 25,794 | 70.24% | -2.868 / -1.048 | 20.3 / 38 |
| Execute `mem_req*` | 5,648 | 15.38% | -2.429 / -1.498 | 19.9 / 21 |
| Rename `srat_q` | 3,211 | 8.74% | -2.832 / -1.798 | 26.0 / 32 |
| Execute 其他 completion/WB | 1,328 | 3.62% | -1.957 / -0.424 | 3.7 / 8 |
| `cpu_rst_sync` | 553 | 1.51% | -0.721 / -0.185 | 1.0 / 1 |
| 其他 | 190 | 0.52% | -1.942 / -0.528 | — |

注意：`cpu_rst_sync` 的 553 个 endpoint 中含 11 个 recovery endpoint；其他是 reset
信号进入 BPU、IQ、IROM 等控制锥形成的普通 setup 路径。

## 5. 按目的模块聚类

| 目的模块 | endpoint | 占比 | 最差 / 中位 slack | 最大 levels |
| --- | ---: | ---: | ---: | ---: |
| ROB | 11,908 | 32.43% | -2.259 / -0.599 | 25 |
| DCache | 11,354 | 30.92% | -2.429 / -1.499 | 21 |
| INT IQ active+cold | 5,328 | 14.51% | -2.093 / 约 -1.17 | 25 |
| Dispatch buffer | 2,818 | 7.67% | -2.832 / -1.859 | 32 |
| MEM IQ | 1,331 | 3.62% | -1.842 / -0.897 | 18 |
| Backend 其他 | 1,062 | 2.89% | -2.086 / -0.710 | 27 |
| PRF | 834 | 2.27% | -1.926 / -0.433 | 7 |
| Execute + WB | 702 | 1.91% | -2.868 / 约 -0.86 | 38 |
| BPU | 340 | 0.93% | -0.721 / -0.225 | 1 |
| Store Buffer | 328 | 0.89% | -1.957 / -0.518 | 11 |
| 其他 | 719 | 1.96% | — | — |

ROB 与 DCache 合计占 63.35%，但其源头并不相同：ROB 多数来自 retire/recovery，
DCache 同时被 retire/recovery 与 LSU request 两个锥驱动。优化时不能把它们合并为
一个“memory path”。

## 6. 主要源→目的路径族

| 路径族 | endpoint | 占比 | 最差 / 中位 slack | 工程含义 |
| --- | ---: | ---: | ---: | --- |
| ROB retire → ROB | 11,275 | 30.70% | -2.259 / -0.617 | recover/clear 回灌 ROB valid/done/next-state |
| ROB retire → DCache | 6,245 | 17.01% | -2.256 / -1.481 | recover 改变 LSU request，继续影响 cache lookup/write mux |
| Execute mem_req → DCache | 5,109 | 13.91% | -2.429 / -1.523 | request occupancy 到 LUTRAM WE 无注册边界 |
| ROB retire → INT IQ active | 3,367 | 9.17% | -2.093 / -1.219 | clear 参与 queue valid/ready/compaction |
| Rename sRAT → dispatch buffer | 2,699 | 7.35% | -2.832 / -1.896 | map+busy+wakeup+dynamic tail write同拍 |
| ROB retire → INT IQ cold | 1,767 | 4.81% | -1.819 / -1.133 | clear 参与 cold queue next-state |
| ROB retire → MEM IQ | 1,331 | 3.62% | -1.842 / -0.897 | clear 参与 stable-slot valid/age/update |
| Execute → PRF | 780 | 2.12% | -1.926 / -0.436 | WB 多写口译码；已不是主 WNS |
| ROB retire → Execute/WB | 702 | 1.91% | -2.868 / — | recover 进入 completion/issue/exception 数据路径 |

## 7. 路径族 A：retire/recovery 全局组合传播

### 7.1 最差路径事实

```text
u_rob/retire_stage_valid_q[1]
→ Commit recover 判定
→ recover_valid_o（fanout 1066）
→ Execute clear_i
→ complete_valid_o
→ MEM IQ wakeup/oldest-ready/payload select
→ PRF 组合读
→ MEM result / misalign / dynamic exception
→ wb_exception_cause_q[2]
```

| 属性 | 数值 |
| --- | ---: |
| Slack | -2.868 ns |
| Data path | 12.567 ns |
| Logic / route | 2.186 / 10.381 ns |
| Route 占比 | 82.61% |
| Logic levels | 35 |
| 关键 fanout | recover 1066、completion valid 836、PRF raddr 521 |

### 7.2 RTL 根因

- `ROB.sv:178-188` 从 registered retire stage 形成 retire valid/fire；
- `CommitUnit.sv:96-153` 同拍检查 exception/mret/branch_miss 并输出 recover；
- `CoreBackend.sv:602-772` 把 `recover_i` 直接送到 ROB、Dispatch、INT/MEM/MUL IQ、
  Execute、StoreBuffer；
- `CoreBackend.sv:458-513` 用 recover 组合门控 issue-ready；
- `ExecuteCluster.sv:340-354` 用 clear 组合门控 completion 与 PRF write enable；
- `ExecuteCluster.sv:392-398,465-516` 用 clear 参与 probe、memory send、issue-ready；
- IQ 的 clear 又影响 valid/next-state，导致 recover 不只是“清 valid”，而是继续参与
  payload selection 和执行数据锥。

问题不是 `recover_valid_o` 单根线延迟，而是它作为大量数据选择条件穿过多个模块。
如果只加 `MAX_FANOUT`，复制后的每个分支仍会进入 20～38 levels 的组合锥。

### 7.3 删除或改错会发生什么

- 直接删除 recovery 门控但不证明 ownership：错误路径可能写 ROB/PRF，甚至发出 MMIO
  请求；
- 直接把 recover 整体打一拍：额外一周期内可能 issue 新指令、接收 load 或重复 retire；
- 只清 payload 不清 valid：会出现幽灵 completion/issue；
- 只清 valid 而提前释放 store side effect：可能造成错误路径 store 对外可见。

因此正确目标是“允许无架构可见性的陈旧 payload 被覆盖，但在 recovery 边沿原子地
撤销所有 ownership/valid”，而不是简单删除 recover。

## 8. 路径族 B：LSU request queue → DCache LUTRAM 写口

### 8.1 代表路径事实

```text
Execute mem_req_count_q[1]
→ mem_req_valid / load-send / DramAccessIF request
→ DCache active_req / cacheability / tag hit
→ store/refill/finish write mux
→ data_write_addr / way WE
→ distributed RAM RAMD64E WE
```

| 属性 | 数值 |
| --- | ---: |
| Slack | -2.429 ns |
| Data path | 11.934 ns |
| Logic / route | 1.680 / 10.254 ns |
| Route 占比 | 85.92% |
| Logic levels | 21 |
| 该源覆盖 | 5,648 endpoints |

### 8.2 RTL 根因

- `ExecuteCluster.sv:375-485` 从 request count 和 head payload 组合形成 request；
- `ExecuteCluster.sv:553-570` 直接驱动 `DramAccessIF`；
- `DCache.sv:190-212` 把外部 request 与 held request 组合仲裁后立即查 tag/data；
- `DCache.sv:284-330` 同周期完成 hit/refill/finish 写数据和写地址 mux；
- `DCache.sv:332-340` 写入 LUTRAM。

Execute 已有 request queue，但它没有形成物理上的 LSU→DCache 注册边界：queue count、
head、cache lookup 和 LUTRAM WE 仍处在一个周期。

### 8.3 风险

- 只给 request valid 打拍但不保存完整 payload，会发生地址/数据错配；
- 改 ready 时序但不更新 metadata ownership，会丢请求或重复请求；
- refill response 和 critical-word-first 的计数必须保持一一对应；
- recovery 后已被 DCache 接收的 load 不能取消，只能保留 killed metadata 并 drain；
- uncached/MMIO 请求不得因 replay 重复产生副作用。

## 9. 路径族 C：sRAT → dispatch buffer

### 9.1 代表路径事实

```text
srat_q
→ map_with_older_lane
→ mapped_uop.prs/old_prd
→ BusyTable ready query
→ same-cycle scheduler wakeup overlay
→ dispatch-buffer tail offset/dynamic slot write
→ entry_q payload / src_ready D、S
```

| 属性 | 数值 |
| --- | ---: |
| Slack | -2.832 ns |
| QoR 代表 path | -2.522 ns，32 levels，route 87.1% |
| XDC budget path | -2.743 ns，27 levels，route 88.7% |
| 该源覆盖 | 3,211 endpoints |
| 到 dispatch buffer | 2,699 endpoints |

### 9.2 RTL 根因

- `RenameUnit.sv:46-63` lane1 做 older-lane map bypass；
- `RenameUnit.sv:89-115` 同拍读取 sRAT、构造完整 uop、查询 BusyTable；
- `CoreBackend.sv:382-401` 又把 completion wakeup 叠加到新入队 uop；
- `CoreBackend.sv:430-451` 动态 tail slot 写完整宽 payload。

dispatch buffer 已成功隔离 ROB/IQ，不应删除。剩余问题是“写入这个边界前做了太多事”。
尤其 `src1_ready/src2_ready` 同时由 BusyTable 和 scheduler wakeup 决定，但二者完全可以
在下一周期由注册 scoreboard 状态恢复，不必进入 sRAT→buffer 的当拍数据路径。

### 9.3 风险

- 若去掉 same-cycle wakeup 却不依赖下一拍 BusyTable 状态，可能永久丢失一次 wakeup；
- 两 lane 的 WAW/RAW older-lane bypass 必须保留；
- PRD、sRAT 更新和 buffer ownership 必须原子，不能“PRD 已分配但 uop 未入队”；
- recovery 必须使 buffer 中所有 speculative owner 不可见。

## 10. 路径族 D：异步 reset recovery

### 10.1 报告事实

最差路径：

```text
cpu_rst_sync_reg/Q（fanout 4042）
→ 9.782 ns route
→ CorePcGen pc_q_reg[0]/CLR
```

| 属性 | 数值 |
| --- | ---: |
| Recovery WNS / TNS | -0.454 / -0.638 ns |
| Recovery failing endpoints | 11 |
| Data path | 10.018 ns |
| Route 占比 | 97.64% |

### 10.2 根因

`student_top.sv` 已做异步断言、同步释放的 reset synchronizer，但最终
`cpu_rst_sync` 继续作为整个 core 的异步 reset，连接到大量 FDCE/FDPE 的 CLR/PRE。
这既产生 recovery check，也触发 DRC `REQP-1839=20`：带异步 reset 的 PC 地址寄存器
驱动 IROM BRAM 地址。

只做 reset net replication 可能改善 route，但无法消除 recovery sign-off 和
REQP-1839。根治是：异步 reset 只停在 synchronizer；core 内部状态使用同步 reset，
并保证 PLL/CPU clock 在 reset 期间持续运行。

## 11. 物理与资源背景

| 项目 | 当前值 |
| --- | ---: |
| Slice LUT | 79,323（38.92%） |
| Slice register | 27,586（6.77%） |
| LUTRAM | 2,151 |
| BRAM tile | 68 |
| DSP | 4 |
| `u_backend` LUT | 69,055 |
| `u_rob` LUT / FF | 20,956 / 9,396 |
| `u_int_iq` LUT / FF | 15,286 / 3,819 |
| `u_execute` LUT / FF | 15,233 / 5,143 |
| `u_prf` LUT / FF | 9,149 / 2,016 |

QoR 报告的 level-5 拥塞位于 PRF 区域，并给出：

- `RQS_CONG-2_1`：高 MUXF 使用，建议比较 `MUXF_REMAP=1`；
- `RQS_TIMING-3`：关键 net 负载物理距离过大，可比较 `FORCE_MAX_FANOUT`；
- `RQS_TIMING-56/59`：critical LUT remap/replication；
- `RQS_XDC-1`：64 条路径超出 Net/LUT budget，应减逻辑或加流水。

这些建议适合 RTL 切分后的实现收尾。当前 WNS 路径 82%～89% 为 route delay，说明
降低跨模块 fanout 和缩小物理作用域与减少 logic levels 同样重要。

## 12. 约束与 sign-off 风险

即使 CPU WNS/TNS 归零，也不能立即宣称全设计 sign-off：

1. 50 MHz 与 100 MHz 来自同一 PLL，却通过 asynchronous clock groups 整域切断；
   clock interaction 显示 50→100 有 104、100→50 有 65 个 ignored endpoint；
2. CDC 仍有 `CDC-10 Critical=31` 和 `CDC-6 Warning=4`；
3. DRC 除 `REQP-1839=20` 外，还有 DSP pipeline 建议：`DPIP-1=2`、
   `DPOP-1=2`、`DPOP-2=3`；
4. methodology 的 `TIMING-47` 指出同 PLL 同步时钟被异步分组；
5. UART/LED/SEG I/O delay 约束仍不完整。

这些问题不都导致当前 CPU setup WNS，但属于“消除所有时序/实现风险”的必要收尾项。

## 13. 优化优先级结论

| 优先级 | 工作项 | 预计直接覆盖 | 理由 |
| --- | --- | ---: | --- |
| P0 | 同步 reset 化 | 553 endpoint + 11 recovery | 独立、确定、同时修 DRC |
| P1 | recovery 只清 ownership/valid | 25,794 source endpoints | 覆盖 70.24%，当前 WNS 根因 |
| P2 | LSU→DCache 注册 request | 5,648 source endpoints | 当前第二独立结构路径 |
| P3 | 简化 rename→buffer capture | 3,211 source endpoints | 当前第三独立结构路径 |
| P4 | IQ/ROB stable-slot 与局部 clear 收尾 | P1 残余 | 防止 WNS 转移到 next-state/compaction |
| P5 | QoR directive / DSP / constraints | 尾部路径与 sign-off | 只能在结构优化后执行 |

具体实施顺序、功能不变量和验收门槛见
`TIMING_CLOSURE_OPTIMIZATION_PLAN.md`。
