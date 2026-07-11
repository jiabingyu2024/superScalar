# MUL/DIV 2/16、INT cold parking 与 store address/data split 实现记录

## 1. 结论

本轮三项优化已经进入当前 RTL：

1. `MUL_0` 延迟从 3 级改成 2 级；`DIV_0` manual latency 从 34 改成 16。
2. INT IQ 保持 8-entry hot select window，并增加 4-entry cold parking queue。
3. store 地址和数据解耦：地址 ready 即可建立 StoreBuffer shell，data 通过 PRD 后填。

最终 Verilator 回归通过；`srcWithMext` 50M 窗口 IPC 为 `1.215790`，相对 R1 的 `0.976866` 提升 `24.46%`。

当前没有用旧提交的 Vivado routed report 宣称新设计 Fmax。旧 `061_vivado_100mhz_timing_baseline` 只属于旧 checkpoint；本轮只用 AMD 官方文档和 fresh IP Catalog generation 判断参数合法性。当前提交仍需重新 clean synth/place/route 才能给出全设计频率结论。

## 2. AMD 官方 IP 支持性

### 2.1 MUL 33x33 signed、PipeStages=2

官方依据：

- [AMD Multiplier v12.0 Product Guide, PG108](https://docs.amd.com/v/u/en-US/pg108-mult-gen)
- [AMD Multiplier performance/resource tables](https://download.amd.com/docnav/documents/ip_attachments/mult-gen.html)

PG108 给出的边界：

- parallel multiplier 支持 signed/unsigned；
- 输入宽度支持 1 到 64 bit，输出支持 1 到 128 bit；
- `Pipeline Stages=0` 是组合，`=1` 只有 output register，`>1` 会在 input/output 之间插入寄存器；
- pipeline stage 可由设计者选择，减少 stage 合法，但会降低最高频率；
- parallel multiplier 可以选择 LUT 或 dedicated multiplier primitive；33x33 位于 DSP48E1 speed/area 可选的 `<=47x47` 范围内。

因此 `33x33 signed -> 66 bit, PipeStages=2` 是合法配置。

原 Tcl 没有显式设置 `Multiplier_Construction`，PG108 的默认值是 `Use_LUTs`。这对两级 33x33 宽乘法不合适，本轮已明确冻结：

```tcl
Multiplier_Construction = Use_Mults
OptGoal                  = Speed
PipeStages               = 2
```

官方 Kintex-7 表中最接近的 `35x35 signed, Use_Mults, Speed` 样例使用 6 stages，OOC Fmax 为 544 MHz（xc7k70t-1）。它证明 DSP 构造适用，但不能外推本项目两级 MUL 或全 core Fmax。

### 2.2 DIV 32x32、integer remainder、Radix-2、Latency=16

官方依据：

- [AMD Divider Generator v5.1 Product Guide, PG151](https://docs.amd.com/v/u/en-US/pg151-div-gen)
- [AMD Divider Generator performance/resource tables](https://download.amd.com/docnav/documents/ip_attachments/div-gen.html)

PG151 给出的边界：

- Radix-2 支持 2 到 64 bit dividend/divisor；
- Radix-2 支持 integer remainder；
- `clocks_per_division=1` 时，manual latency 可在 0 到 fully-pipelined latency 之间选择；
- 降低 latency 会减少寄存器，但 LUT 数基本不变，并降低最高频率；
- High Radix 推荐给大于约 16 bit 的 operand，但只支持 fractional output，不能直接提供 RV32 `REM/REMU` 所需 integer remainder；
- LUTMult 的宽度范围也不足以覆盖 32x32。

因此当前 `DIV/REM` 共用一颗 IP 时，`Radix2 + 32x32 + Remainder + clocks_per_division=1 + Manual Latency=16` 是合法且保持接口语义的配置。不能直接换 High Radix，除非另加 `remainder = dividend - quotient * divisor` 数据通路和对应验证。

PG151 还指出 Blocking AXI4-Stream 的运行时 latency 可能受 FIFO/握手影响。当前 `CoreMulDivPipe` 不用固定倒计数完成 DIV，而是一直等待 `m_axis_dout_tvalid`，所以真实 IP latency 波动不会写错 owner。Verilator 行为模型的固定 16 拍只模拟无反压单事务路径。

官方 Kintex-7 表中的 `32x32 signed, Radix2, Remainder, clocks_per_division=1, NonBlocking, Automatic` 样例为 450 MHz、1280 LUT、3334 FF。它不是本项目的 `Blocking + Manual 16` 配置，不能用 450 MHz 代替当前配置的实测 Fmax。

### 2.3 Fresh IP 参数复核

Vivado 2023.2 fresh IP generation 接受以下 XCI 值：

```text
MUL_0: Multiplier_Construction=Use_Mults
       OptGoal=Speed
       PipeStages=2

DIV_0: algorithm_type=Radix2
       dividend_and_quotient_width=32
       divisor_width=32
       remainder_type=Remainder
       FlowControl=Blocking
       latency_configuration=Manual
       latency=16
```

这只证明 IP Catalog 参数合法并能生成 target，不是当前 RTL 的 synth/route sign-off。

## 3. MUL/DIV RTL 对齐

涉及文件：

- `rtl/core/execute/MulDivPipe.sv`
- `rtl/ip/MUL_0.sv`
- `rtl/ip/DIV_0.sv`
- `fpga/create_vivado_project.tcl`

### 3.1 MUL owner 对齐

```text
issue accept
  -> MUL_0 pipe0
  -> MUL_0 P
  -> mul_valid_q[1] + mul_uop_q[1] 同拍完成
```

`MUL_LATENCY=2` 同时控制 metadata valid 和 owner payload 深度。若只改 IP、不改 metadata，结果会写到前一条或后一条 ROB/PRD owner。

### 3.2 DIV owner 与 flush

normal DIV：

```text
MD_IDLE -> MD_DIV_WAIT -> 等 m_axis_dout_tvalid -> complete
```

special DIV：

```text
除 0 或 INT_MIN/-1 -> MD_SPECIAL -> 本地结果 -> complete
```

flush 时 `div_drain_q` 会吸收已经启动 IP 的迟到 valid，禁止新 DIV 在旧 transaction 返回前复用 active owner。删掉 drain 会让恢复后的新 uop 收到旧 quotient/remainder。

## 4. INT IQ cold parking queue

结构：

```text
dispatch
  -> 8-entry active CoreCompressedQueue
  -> 4-entry cold CoreCompressedQueue

cold oldest-ready
  -> 每拍最多 reinject 1 条
  -> 下一拍进入 active hot select window
```

关键规则：

1. 只有 active 8 entries 参加 ALU oldest-ready select，hot window 没扩大。
2. cold queue 只保存 overflow owner，不直接 issue。
3. cold 非空时，active 永远保留一个 escape slot。
4. cold entry 只有在 active push 接管成功时才从 cold 删除。
5. `clear_i/recover_i` 同时清 active/cold valid owner。

保留 escape slot 是必要条件。若 active 8 entries 全等待某 PRD，而该 PRD 的 producer 被停在 cold，只有空位后才 reinject 会形成闭环死锁。

已加入断言：

- dispatch uop 不得同时获得 active/cold 两个 owner；
- accepted dispatch 必须至少有一个 owner；
- cold entry 删除时 active push 必须已经接管同一 ROB owner。

## 5. Store address/data split

### 5.1 主数据流

```text
MEM IQ store
  -> src1/address ready 即可 issue
  -> registered 2-entry MEM request queue
  -> StoreBuffer shell {rob_idx, addr, mask, data_prd}
  -> completion bus 按 PRD 填 data
  -> StoreBuffer registered state 发 store_complete 到 ROB
  -> ROB done 后有序 retire
  -> retired StoreBuffer head 写 DRAM
```

MEM IQ 仍不允许 load 越过 store/fence/device。优化只消除“地址已经知道，但 store data 未 ready”对后续 no-alias load 的全 MEM barrier。

### 5.2 completion owner 窗口

data producer 可能在以下任一阶段完成：

1. store 仍在 MEM IQ；
2. store 已进入 2-entry request queue；
3. shell 已进入 StoreBuffer。

因此 request entry 和 StoreBuffer shell 都监听 registered completion bus。若只让 StoreBuffer 监听，producer 恰在 request-to-shell 转移拍完成时会丢掉单拍 wakeup，store 永远不能 done。

### 5.3 load forwarding

StoreBuffer 按老到年轻扫描同 word store：

- data-ready entry 合并其 byte mask；
- data-pending entry 清除它覆盖 byte 上更老 entry 已贡献的 mask；
- 更年轻 data-ready entry 可以再次覆盖这些 byte；
- 只有 load 所需 byte 全部有效时才 full-forward；
- pending store 和 load byte 不重叠时不构成 barrier。

若 pending younger store 不清除更老 forwarding mask，load 会读到已被覆盖的旧 store 值。

### 5.4 ROB completion

data-ready store 仍走 Execute normal completion。data-pending store 在 shell 填好后，通过独立 `store_complete_valid/rob_idx/addr` 写 ROB。

该通路来自 StoreBuffer 寄存状态，不把 StoreBuffer CAM 组合接到 Commit ready。ROB 断言要求 completion 目标：

- entry 仍 valid；
- entry 是 store；
- entry 尚未 done。

这会抓住 flush 后迟到 completion、ROB index 回绕和重复完成。

## 6. 最终验证

### 6.1 静态与 ISA

| 项目 | 结果 |
| --- | ---: |
| Verilator lint | 通过；无 error、LATCH、UNOPTFLAT、MULTIDRIVEN |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |
| `git diff --check` | PASS |

### 6.2 srcSmoke

| 项目 | 结果 |
| --- | ---: |
| status | PASS |
| cycles | 33,087,618 |
| commits | 30,758,594 |
| IPC | 0.929610 |
| RV32I SEG count | 37 |
| final marker | 对号 |

### 6.3 srcWithMext 500k

500k 是性能窗口，TIMEOUT 是预期状态：

| 项目 | 结果 |
| --- | ---: |
| commits | 593,643 |
| IPC | 1.187290 |
| RV32I pass/fail | 37 / 0 |
| M count | 8 |

### 6.4 srcWithMext 50M

50M 仍是性能窗口，尚未到最终 workload marker：

| 项目 | R1 baseline | 当前 | 变化 |
| --- | ---: | ---: | ---: |
| IPC | 0.976866 | 1.215790 | +24.46% |
| ROB head wait MEM | 12,649,994 | 6,948,807 | -45.07% |
| ROB head wait MUL | 4,109,116 | 2,268,648 | -44.79% |
| MEM IQ head-not-ready | 35,066,233 | 23,930,588 | -31.76% |

当前窗口 `60,789,745` commits，RV32I pass/fail 为 `37/0`，M count 为 `8`。整个 50M 窗口没有 owner/assertion 失败。

## 7. 尚未完成的物理结论

以下结论不能从旧工程或官方相近样例推出：

1. 当前全 core 在 100 MHz 下的 WNS/TNS。
2. 2-stage MUL 是否出现在全设计 top path。
3. manual-latency-16 DIV 的当前器件 OOC Fmax。
4. cold reinject mux、StoreBuffer completion 和新增 payload 对 placement/routing 的实际影响。

下一次 clean route 应冻结：

- 当前 Git/worktree fingerprint；
- fresh XCI 的 2/16 和 `Use_Mults` 属性；
- CPU clock 10 ns 的 WNS/TNS/failing endpoints；
- top path family；
- DSP/LUT/FF 利用率；
- 同一份 `srcWithMext` IPC。

只有这组数据齐全后，才能评价 `IPC x Fmax`，不能复用 `061` 的旧 checkpoint。
