# 单页 CPU Core 架构图 PPT 绘制指南

> 适用 RTL：当前 [`rtl/core/core_top.sv`](../../rtl/core/core_top.sv)。
>
> 目标：只用一页 16:9 幻灯片，准确体现流水阶段、关键模块、主数据流、Completion/旁路和恢复路径。图中不展开端口级信号。

## 1. 这一页要表达的结论

标题直接使用：

> **RV32 单发射 Scoreboard Core 微架构**

副标题使用：

> **In-order Issue · Out-of-order Completion · In-order Commit**

右上角放三行小字，不要做成大卡片：

```text
1-wide Issue / 1-wide Commit
8-entry Scoreboard
GShare + DCache + Store Buffer
```

这页不能写成“2-way 超标量 OoO Core”。当前 RTL 没有 Rename、PRF、多候选 Issue Queue 或多发射选择器；它的乱序能力仅体现在不同功能单元可以乱序完成，最终仍由 Scoreboard head 顺序提交。

## 2. 流水阶段划分

在图的最上方画七个等高阶段标题。它们是便于汇报的**逻辑阶段**，不是所有指令都固定逐级经过的七级等延迟流水。

| 阶段 | PPT 标题 | 主要内容 | 关键寄存边界 |
|---|---|---|---|
| S0 | `IF / PRED` | PC、GShare、IROM、Fetch Queue | Frontend 内部请求/返回状态 |
| S1 | `ID` | Decoder、单条 ID holding register | `id_uop_q` |
| S2 | `IS / RD` | RegFile、Scoreboard query、Operand Resolver、Issue Control | Issue 后进入 `exec_q` |
| S3 | `EX` | Fixed Execute、Branch、AGU、MDU/Zb 启动 | `exec_q`、`exec_mem_addr_q` |
| S4 | `MEM / LONG` | Load/Store、DCache、MDU、Bitmanip 可变延迟执行 | 各队列和 FU 内部状态 |
| S5 | `COMPLETE` | 按 transaction ID 写 Scoreboard result/done | Scoreboard entry |
| S6 | `COMMIT / WB` | Head Commit、CSR、Store commit、GPR WB、Recovery | `wb_*_q` 与架构状态 |

主图上在 `MEM / LONG` 和 `COMPLETE` 标题下方加一行灰色小字：

```text
variable latency
```

这样可避免观众误以为 ALU、DIV 和 Cache miss 都是相同固定拍数。

## 3. 推荐页面布局

页面使用 PowerPoint `宽屏 16:9`。推荐尺寸按 13.33 × 7.5 英寸理解，四周至少留 0.5 英寸边距。

### 3.1 垂直分层

```text
0.3  ┌──────────────── 标题 / 副标题 ────────────────┐
1.0  ├──────────────── 七个阶段标题 ────────────────┤
1.4  │              主指令数据流和执行模块           │
4.4  │              Scoreboard 状态主干              │
5.6  │       旁路 / Commit-WB / 外部 Memory 连线      │
6.8  └──────────────── 图例与一句结论 ───────────────┘
```

### 3.2 水平模块布局

按从左到右的程序生命周期摆放：

```text
┌────────────┐  ┌──────────┐  ┌────────────────┐  ┌────────────────┐
│ IF / PRED  │->│    ID    │->│    IS / RD     │->│       EX       │
│            │  │          │  │                │  │                │
│ PC         │  │ Decoder  │  │ RegFile        │  │ exec_q         │
│ GShare     │  │ id_uop_q │  │ Operand Resolve│  │ Fixed EX       │
│ Fetch Queue│  │          │  │ Issue Control  │  │ Branch / AGU   │
└────────────┘  └──────────┘  └────────────────┘  │ MDU / Zb       │
                                                  └───────┬────────┘
                                                          │
                               ┌───────────────────────────┴──────────┐
                               │             MEM / LONG              │
                               │ Store Buffer | Store Fwd | Load Q   │
                               │ Memory Arbiter -> DCache -> Regslice│
                               └───────────────────┬──────────────────┘
                                                   │ load completion
                 ┌─────────────────────────────────▼──────────────┐
                 │                 SCOREBOARD                     │
                 │ 8 entries | producer map | result/done | head │
                 └───────────────┬───────────────────────┬────────┘
                                 │ query / bypass        │ oldest done
                                 └──────> IS / RD        ▼
                                                  ┌───────────────┐
                                                  │ COMMIT / WB   │
                                                  │ Commit Gate   │
                                                  │ CSR / Trap    │
                                                  │ GPR WB        │
                                                  └───────────────┘
```

实际 PPT 中不要让 `MEM / LONG` 挡住主流程。建议把它放在 `EX` 右下方，把 Scoreboard 画成从 `IS / RD` 下方延伸到 `COMMIT / WB` 左侧的横向长条。

## 4. 每个方框写什么

每个框只保留模块名和 2～4 个关键词。不要写 SystemVerilog 端口。

### `IF / PRED`

```text
Frontend
PC + GShare
IROM / Fetch Queue
```

### `ID`

```text
Decoder
ID Holding Reg
```

在框底用小字标 `id_uop_q`，体现 ID stall 时指令保持在这里。

### `IS / RD`

```text
RegFile
Operand Resolver
Issue Control
```

框右下角用小字标：

```text
RAW + FU credit + serialize
```

Scoreboard 本体不要再放进这个框；这里只写 `Scoreboard query` 的输入箭头。

### `EX`

```text
exec_q
Fixed EX: ALU / Branch / AGU
MDU / Bitmanip
```

`Fixed EX` 与 `MDU / Bitmanip` 用框内的一条细分隔线分开，表示一拍固定执行和可变延迟执行是不同 completion 路径。

### `MEM / LONG`

内部只画两行子模块：

```text
Store Buffer | Store Forwarding | Load Queue
Memory Arbiter -> DCache -> DMEM Regslice
```

不要在总图中展开 Cache tag/data RAM、refill FSM、byte merge 或每个 ready/valid 信号。

### `SCOREBOARD`

```text
8-entry Scoreboard
producer map | result / done | commit head
```

在框上沿放三个小入口标签：

```text
fixed complete    load complete    slow complete
```

Scoreboard 是整页最重要的状态模块，边框应比普通模块粗一级。

### `COMMIT / WB`

```text
In-order Commit
CSR / Trap / MRET
GPR WB + Store Commit
```

在框旁边放一个较小的 `Recovery Control` 红色边框框，接收 Branch miss 和 Commit exception/mret。

## 5. 必须画出的连线

一页图建议限制在以下 11 组连接。超过这些通常会开始遮挡模块文字。

| 编号 | 起点 -> 终点 | 在线上标什么 | 线型 |
|---:|---|---|---|
| 1 | Frontend -> ID | `fetch entry` | 黑色粗实线 |
| 2 | ID -> IS/RD | `uop` | 黑色粗实线 |
| 3 | IS/RD -> EX | `issue: tid + operands` | 黑色粗实线 |
| 4 | IS/RD -> Scoreboard | `allocate` | 灰色虚线 |
| 5 | Fixed EX -> Scoreboard | `fixed complete` | 绿色实线 |
| 6 | MDU/Bitmanip -> Scoreboard | `slow complete` | 绿色实线 |
| 7 | EX/AGU -> MEM/LONG -> Scoreboard | `load/store · load complete` | 橙色实线 |
| 8 | Scoreboard -> IS/RD | `producer query + result bypass` | 蓝色回折线 |
| 9 | Scoreboard -> Commit/WB | `oldest done entry` | 黑色粗实线 |
| 10 | Commit/WB -> RegFile / StoreBuffer | `GPR WB / store commit` | 蓝色回折线 |
| 11 | EX + Commit -> Recovery -> Frontend | `branch miss / trap / mret · redirect` | 红色回折线 |

另外从 `MEM / LONG` 的 DCache 画一条向下的双向橙色箭头：

```text
External DMEM
```

这条线不算 Core 内部流水连接，但能说明 Cache 与外部系统的边界。

## 6. 连线如何避免混乱

采用四条固定“走线通道”：

1. **主数据流**沿模块中线从左向右，不折返。
2. **Completion**统一从执行模块向下进入 Scoreboard 上沿。
3. **旁路/WB**统一走 Scoreboard 下方，再向上回到 `IS/RD` 或 RegFile。
4. **Redirect/Flush**统一走所有模块上方，从 Recovery 向左回 Frontend。

具体规则：

- 箭头必须使用 PowerPoint 的肘形连接符，不使用普通直线。
- 一条线最多两个直角弯。
- 不让任何连接线穿过方框文字。
- 多个 Completion 不画成一根总线后再分叉；直接各自进入 Scoreboard 的三个入口。
- `full flush` 不分别连到十几个寄存器，只在红色返回线上写：

```text
redirect + flush speculative state
```

- Scoreboard 的 query、result 和同拍 completion bypass 合并成一条蓝线，标签写全即可，不展开 rs1/rs2 两套网络。
- Store forwarding 不画回 RegFile；它只在 `MEM / LONG` 框内表示 StoreBuffer 到 Load data path 的局部路径。

## 7. 颜色与线型

背景使用 `#F7F8FA`，模块填充保持白色，主要用边框颜色区分功能，避免整页被一种蓝色占满。

| 类别 | 颜色 | 用途 |
|---|---|---|
| 文字/主数据流 | `#20242A` | 标题、模块名、左到右 uop 流 |
| Frontend | `#007C83` | IF/PRED 阶段边框和阶段标题 |
| Issue/Scoreboard | `#3A7D44` | IS/RD 和 Scoreboard 边框 |
| Execute | `#B26A00` | EX、MDU、Bitmanip |
| Memory | `#8A5A00` | LSU、DCache、外部 DMEM |
| Completion | `#2E7D32` | FU 返回 Scoreboard |
| Bypass/WB | `#2563EB` | Scoreboard query、结果旁路、GPR WB |
| Recovery | `#B3261E` | branch miss、trap、redirect、flush |
| 次要控制 | `#73777F` | allocate、credit、说明文字 |

线宽建议：

- 主数据流：`2.25 pt`
- Completion / Memory / Recovery：`1.75 pt`
- Bypass：`1.5 pt`
- 次要控制虚线：`1.25 pt`

模块使用直角矩形或 4 pt 以内轻微圆角；不要使用阴影、渐变、发光效果和装饰性图标。

## 8. 字号与方框层级

| 元素 | 字号 |
|---|---:|
| 页面标题 | 30～34 pt，粗体 |
| 副标题 | 14～16 pt |
| 阶段标题 | 14～16 pt，粗体 |
| 模块主名称 | 13～15 pt，粗体 |
| 模块内部关键词 | 10～12 pt |
| 箭头标签 | 9～10 pt |
| 图例/注释 | 9～10 pt |

推荐字体：中文使用`等线`或`微软雅黑`，英文和信号名使用 `Aptos` 或 `Consolas`。同一个文本框不要混用超过两种字体。

## 9. PowerPoint 实际绘制顺序

1. 新建 16:9 空白页，设置浅灰背景和 0.5 英寸安全边距。
2. 放标题、副标题和右上角三行参数。
3. 先放七个阶段标题，确认水平空间分配。
4. 放六个主框：Frontend、ID、IS/RD、EX、MEM/LONG、Commit/WB。
5. 放 Scoreboard 横向长框和较小的 Recovery Control 框。
6. 先连接三条黑色主数据流，再连接三个绿色 Completion。
7. 补蓝色 query/bypass/WB 回路、橙色 Memory 路径和红色 Recovery 路径。
8. 最后添加箭头标签；标签背景设为页面背景色，避免线穿过文字。
9. 使用“对齐 -> 垂直居中/横向分布”，统一方框高度和间距。
10. 全选连接线检查端点是否吸附到方框连接点，移动方框验证线会自动跟随。

## 10. 不要画进这一页的内容

- `perf_counters`、DiffTest、debug probe。
- 每个模块的 valid/ready、count、pointer 和 transaction ID 位宽。
- DCache tag/data RAM、miss/refill FSM 的内部细节。
- LoadQueue active meta 和 StoreBuffer sequence 的字段级结构。
- GShare 的 BTB/PHT/GHR 逐项更新逻辑。
- 所有 exception cause 和 CSR 地址。
- 不存在的 Rename、PRF、ROB、Reservation Station 或 2-wide Issue。

如果后续讲解需要这些内容，应口头说明或另做附页；不要继续往这一页添加小框。

## 11. 页脚一句话

在页面左下角放这一句，作为观众读图结论：

> **指令按序发射，各执行单元可按 transaction ID 乱序完成，Scoreboard 保证结果按程序顺序提交。**

右下角放四色小图例：

```text
黑：主数据流   绿：Completion   蓝：Bypass/WB   红：Recovery
```

## 12. 最终自检

- [ ] 七个逻辑阶段是否清楚可见？
- [ ] 是否明确标出 single issue、out-of-order completion、in-order commit？
- [ ] 主数据流能否从左到右一次读完？
- [ ] ALU、Load、MDU/Zb 三类 Completion 是否都进入 Scoreboard？
- [ ] Scoreboard 是否同时连接 Issue query 和 Commit head？
- [ ] Commit-WB 回 RegFile、Store commit 回 StoreBuffer 是否可见？
- [ ] Branch miss 与 trap/mret 是否通过 Recovery 返回 Frontend？
- [ ] Load/Store 路径是否包含 StoreBuffer、LoadQueue、Arbiter、DCache？
- [ ] 是否避免画出不存在的 Rename/ROB/IQ/PRF？
- [ ] 是否没有连接线穿过文字或出现三次以上折弯？
- [ ] 在投影模式下，最小箭头标签是否仍能看清？

通过以上检查后，这一页已经足以同时说明流水阶段、有限乱序机制、访存子系统和精确恢复，不需要再增加模块或信号。
