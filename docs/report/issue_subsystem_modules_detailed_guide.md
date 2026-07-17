# `rtl/core/issue/` 模块深度讲解

> 设计依据：当前分支 [`rtl/core/issue/`](../../rtl/core/issue/) 下的 SystemVerilog。
> 目标：不仅看懂每段代码，还能理解它们如何共同实现“顺序发射、乱序完成、顺序提交”的 Issue 子系统。

## 0. Issue 子系统总览

当前目录包含四个模块：

| 文件 | 角色 | 是否有状态 |
|---|---|---|
| [`regfile.sv`](../../rtl/core/issue/regfile.sv) | 保存已提交的 32 个架构整数寄存器 | 有 |
| [`scoreboard.sv`](../../rtl/core/issue/scoreboard.sv) | 保存 8 条在途指令、结果、完成状态和 youngest producer map | 有 |
| [`operand_resolver.sv`](../../rtl/core/issue/operand_resolver.sv) | 从 RF、Scoreboard、WB 和 completion 中选择最终操作数 | 无，纯组合 |
| [`issue_control.sv`](../../rtl/core/issue/issue_control.sv) | 汇总源 ready、FU ready、队列 credit、serialize 和恢复条件 | 无，纯组合 |

### 0.1 它们在流水线中的位置

```text
Fetch Queue -> Decode -> id_uop_q
                         |
                         +-> RegFile asynchronous read -----------+
                         +-> Scoreboard producer/result query ----+-> Operand Resolver
                                                                  |
Fixed / Load / Slow completion ----------------------------------+
Commit-WB --------------------------------------------------------+
                                                                  |
                                                                  v
                                                          src value / ready
                                                                  |
Queue counts / FU busy / branch / redirect ----------------> Issue Control
                                                                  |
                                                            issue_fire
                                                              /       \
                                              Scoreboard allocate     exec_q capture
```

### 0.2 一个 Issue 周期内发生什么

假设 `id_uop_q` 已经保存一条有效指令：

1. `id_uop_q.rs1/rs2` 同时送给 RegFile 和 Scoreboard query。
2. RegFile 给出已提交架构值。
3. Scoreboard producer map 判断每个源是否有更年轻的在途写者。
4. Operand Resolver 决定应该使用 RF、Commit-WB、Scoreboard result，还是本周期 completion。
5. Issue Control 检查操作数 ready、目标资源、Scoreboard credit、serialize、branch/redirect。
6. `issue_fire=1` 时，本周期末：
   - Scoreboard 在 `allocate_ptr` 创建新 entry。
   - `exec_q` 捕获 transaction ID、uop 和最终操作数。
   - ID 可以清空或同拍换入下一条指令。

### 0.3 关键组合路径

```text
id_uop_q
-> RegFile read / producer map lookup
-> Scoreboard entry result/done mux
-> completion transaction ID compare + data mux
-> Issue Control gates
-> exec_q D / Scoreboard allocate enable
```

这个路径决定 Issue 阶段 Fmax。设计中的 Load-to-address 旁路隔离、CSR 独立源路径和 producer direct map 都是在控制这条路径的复杂度。

### 0.4 为什么这里不是通用 Issue Queue

当前只有一个 `id_uop_q` 等待发射。它如果 RAW、FU busy 或队列满，就保持在 ID；年轻指令不能绕过。

Scoreboard 允许已经发射的年轻独立指令比老 DIV/Load 更早 completion，但它不从多个 ready uop 中选择。因此：

```text
in-order issue != in-order completion
Scoreboard != age-scheduled Issue Queue
```

---

# 1. `regfile.sv`

## 1.1 模块定位

`regfile` 保存已经 Commit 的 RV32 架构整数寄存器状态，是 Issue 阶段操作数的最基础来源。它位于 `id_uop_q` 之后、Operand Resolver 之前，提供两个组合读端口和一个时序写端口。x1–x31 不做复位，x0 每周期物理写零。尚未提交的结果不进入 RegFile，而是保存在 Scoreboard 或经 completion bypass 使用。

前级：ID holding register 提供 rs1/rs2 地址，Commit-WB bridge 提供写端口。
后级：Operand Resolver 把 RF 值与 Scoreboard/WB/completion 合并。

## 1.2 接口速查表

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `clk` | input | 写端口时钟 | posedge 写入 |
| `rst` | input | 仅用于仿真 assertion 使能 | 不复位 x1–x31 数据阵列 |
| `rs1_addr_i[4:0]` | input | rs1 架构寄存器号 | 整个 Issue 周期稳定，来自 `id_uop_q.rs1` |
| `rs2_addr_i[4:0]` | input | rs2 架构寄存器号 | 整个 Issue 周期稳定，来自 `id_uop_q.rs2` |
| `rs1_data_o[31:0]` | output | rs1 组合读值 | 地址变化后组合变化；x0 恒为 0 |
| `rs2_data_o[31:0]` | output | rs2 组合读值 | 地址变化后组合变化；x0 恒为 0 |
| `write_valid_i` | input | 架构 RF 写使能 | 来自前一拍 Commit-WB register |
| `write_addr_i[4:0]` | input | 写回 rd | `write_addr=0` 时禁止写 |
| `write_data_i[31:0]` | input | 写回数据 | 普通 result 或 CSR old value |

依赖关系：

```text
write_valid_i = wb_valid_q
write_addr_i  = wb_rd_q
write_data_i  = wb_data_q
```

`wb_*_q` 由 Commit 在前一个上升沿生成，因此真正 RF 写入比架构 Commit 边界晚一个上升沿；这个间隙由 Operand Resolver 的 Commit-WB bypass 覆盖。

## 1.3 主数据流

### 读路径

```text
id_uop_q.rs1 -> x0 check -> regs_q[rs1] -> rf_rs1_data -> Operand Resolver
id_uop_q.rs2 -> x0 check -> regs_q[rs2] -> rf_rs2_data -> Operand Resolver
```

读端口是组合读取，没有单独 RR 流水寄存器。最终操作数只在 `issue_fire` 时写入 `exec_q.op1/op2`。

### 写路径

```text
Scoreboard head Commit
-> wb_valid_q / wb_rd_q / wb_data_q
-> 下一上升沿 regs_q[rd]
```

RegFile 只接收顺序提交结果，不接 fixed/load/slow completion。这是精确状态边界。

## 1.4 控制流与优先级

写端口优先级很简单：

```text
write_valid && write_addr != 0 -> 写 x1..x31
每个周期无条件 regs_q[0] <= 0
```

没有 flush 输入：

- Branch miss 不应回滚已提交 RF。
- Exception full flush 也只清在途状态，不清已提交 RF。
- Reset 不要求把 x1–x31 置为 0，因为 RISC-V 不定义它们的复位值。

如果给整个 `regs_q` 加 reset，会增加 1024-bit reset fanout，可能阻碍 FPGA RAM/LUTRAM 推断，并不增加架构正确性。

## 1.5 关键代码块精讲

### 代码块 A：x0 在读端口强制为零

```systemverilog
assign rs1_data_o = (rs1_addr_i == 0) ? 32'd0 : regs_q[rs1_addr_i];
assign rs2_data_o = (rs2_addr_i == 0) ? 32'd0 : regs_q[rs2_addr_i];
```

为什么这样写：即使 `regs_q[0]` 因仿真初态或意外写入短暂异常，架构读值仍被组合钳位为 0。

如果删掉/改错：任何对 x0 的读取可能获得非零值，几乎所有地址计算、立即数伪操作和 ABI 代码都会出现系统性错误。

### 代码块 B：写 x0 被禁止，同时物理维持零

```systemverilog
always_ff @(posedge clk) begin
    if (write_valid_i && write_addr_i != 0)
        regs_q[write_addr_i] <= write_data_i;
    regs_q[0] <= 32'd0;
end
```

为什么双重保护：

- `write_addr_i != 0` 阻止架构写。
- `regs_q[0] <= 0` 保证物理存储和仿真 assertion 均稳定。

如果只保留无条件 x0 写零、却允许同一个 always_ff 前面写 x0，当前文本顺序仍由最后的 x0 写零覆盖；但显式禁止写能减少无意义的写使能译码并让意图清晰。

### 代码块 C：不复位 x1–x31

```systemverilog
// No reset branch for regs_q[1:31]
```

为什么这样写：软件在使用寄存器前必须先定义其值；异常恢复保留已提交 RF，而不是复位 RF。

如果测试程序直接读取未初始化寄存器，仿真可能出现 X。这不是 RegFile bug，而是软件/测试违反了架构使用前定义的前提。

## 1.6 时序示例

### 正常路径：Commit 后紧接消费者

```asm
I0: add x5, x1, x2   # 本周期 Commit
I1: xor x6, x5, x3   # 已在 ID
```

| 周期 | RegFile | Commit-WB | Operand Resolver |
|---|---|---|---|
| T0 | x5 仍是旧值 | T0 末尾捕获 I0 result | I1 还可能由 Scoreboard producer 约束 |
| T1 | 上升沿前仍是旧值 | `wb_valid_q=1, wb_rd_q=5` | WB bypass 给 I1 新 x5，允许 issue |
| T1 末尾 | 写入新 x5 | WB bridge 前进 | 后续读取可直接来自 RF |

### 特殊路径：异常 full flush

异常提交会 flush Scoreboard/Execute/LoadQueue，但不会清 RegFile。异常前已提交值必须保留，异常后的年轻 completion从未写入 RF。

### 特殊路径：Reset 后读取 x0 与 x1

- x0：组合输出确定为 0。
- x1：直到软件写入前可能是 X/任意值，这是允许的。

## 1.7 可以直接复用的设计模式

1. 架构 RF 只接受 Commit 结果，completion 进入独立在途结构。
2. x0 同时做读端口钳位和写端口屏蔽。
3. 不为架构未定义的 RAM 数据添加大规模 reset。
4. Commit 与 RF 写有寄存间隔时，显式增加 WB bypass。
5. 两读一写的小 RF 可先用组合读数组实现，再根据 Fmax/资源决定是否改同步 RAM。

## 1.8 常见坑与自检清单

- [ ] `write_addr=0` 是否永远不改变架构值？
- [ ] x0 读值是否组合恒零？
- [ ] RF 是否只接 Commit，而不是 completion？
- [ ] full flush 是否错误地清了已提交 RF？
- [ ] 是否误以为 `rst` 会把 x1–x31 清零？
- [ ] Commit-WB 到 RF 写入间隙是否有旁路？
- [ ] 组合读路径是否成为 ID -> exec_q 的关键路径？
- [ ] 仿真 X 是否来自软件读取未初始化寄存器？

---
# 2. `scoreboard.sv`

## 2.1 模块定位

`scoreboard` 是当前 Core 的在途指令窗口和顺序提交队列。它同时承担部分 ROB、结果缓冲和寄存器依赖跟踪职责：Issue 时分配 entry，各执行单元按 transaction ID 写 completion，Commit 只读取 head。它允许结果乱序完成，但不负责从多个等待指令中乱序选择发射。

前级：Issue/ID 分配 uop；Fixed/Load/Slow 三类执行路径返回 completion。
后级：Operand Resolver 查询 producer/result；Core Commit 读取 head 并产生架构副作用。

## 2.2 接口速查表

### 时钟、恢复和分配

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `clk` | input | Scoreboard 状态时钟 | posedge 更新 |
| `rst` | input | 清窗口和 producer map | 最高优先级 |
| `flush_i` | input | exception/mret/fence.i 全清在途状态 | 次高优先级；覆盖 completion/commit/allocate |
| `allocate_i` | input | 分配一条新 uop | 等于 `issue_fire` |
| `allocate_uop_i` | input | 新 entry 的完整 uop metadata | `allocate_i=1` 时采样 |
| `allocate_csr_src_i` | input | CSR 非立即数源值 | CSR allocate 时采样 |
| `allocate_trans_id_o` | output | 当前 allocation transaction ID | 组合等于 `allocate_ptr_q`，同时送 `exec_q.trans_id` |

### Completion

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `fixed_complete_i` | input | Fixed completion valid | ALU/Branch/Store/对齐异常完成周期 |
| `fixed_completion_i` | input | tid、result、exception、Store slot | valid 时写对应 entry |
| `load_complete_i` | input | Load result valid | DCache/forwarding completion 周期 |
| `load_trans_id_i` | input | Load 对应 tid | active/queued metadata 提供 |
| `load_result_i` | input | 格式化后的 Load result | 写 entry.result |
| `load_complete_accepted_o` | output | Load completion 命中 occupied entry | 同时通知 LoadQueue 可以清 active |
| `slow_complete_i` | input | MDU/Bitmanip completion valid | long-latency response 周期 |
| `slow_trans_id_i` | input | Slow completion tid | valid 时必须命中 occupied entry |
| `slow_result_i` | input | Slow result | 写 entry.result |

### Commit 和窗口状态

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `commit_i` | input | 当前 head 被 Core 判定可提交 | 每周期最多 1 条 |
| `commit_trans_id_o` | output | 当前 head transaction ID | 组合等于 `commit_ptr_q` |
| `commit_entry_o` | output | 当前 head 全部 metadata/result | Core 组合计算 commit ready/CSR/Store/recovery |
| `count_o` | output | occupied entry 数 | Issue credit、serialize、性能观察 |
| `serial_pending_o` | output | 是否有未退休 serialize 指令 | 阻止后续普通 issue |

### Source query

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `query_uop_i` | input | 当前 ID uop 的 rs/use 信息 | 整个 Issue 周期 |
| `query_rs1_found_o` | output | rs1 是否有在途 youngest producer | `uses_rs1 && rs1!=0 && producer_valid` |
| `query_rs1_ready_o` | output | 无 producer 或 producer.done | Issue gate 输入 |
| `query_rs1_trans_id_o` | output | rs1 youngest producer tid | completion bypass compare |
| `query_rs1_data_o` | output | producer entry.result | producer 已 done 时使用 |
| `query_rs2_found_o` | output | rs2 是否有在途 youngest producer | 同 rs1 |
| `query_rs2_ready_o` | output | rs2 producer ready | Issue gate 输入 |
| `query_rs2_trans_id_o` | output | rs2 producer tid | completion bypass compare |
| `query_rs2_data_o` | output | rs2 producer result | producer 已 done 时使用 |

## 2.3 主数据流

### Allocate

```text
issue_fire
-> allocate_ptr 作为 transaction ID
-> uop metadata 写 entries[allocate_ptr]
-> occupied=1
-> done = decode exception OR FU_SYSTEM
-> 若 writes rd：producer[rd] = allocate_ptr
-> allocate_ptr++
```

System/Decode exception 不进入 `exec_q`，因此在 allocate 时直接 done，等待顺序 Commit 执行 CSR/trap/fence 动作。

### Query

```text
uop.rs
-> producer_valid[rs]
-> producer_tid[rs]
-> entries[tid].done/result
-> found/ready/data/tid
```

这里没有从 Scoreboard 尾部向前做 CAM 扫描。producer map 直接指向每个架构寄存器的 youngest writer，减少 8-entry 反向比较网络。

### Complete

```text
completion.tid
-> entries[tid]
-> done=1
-> result/exception/store slot update
```

Fixed、Load、Slow 可以同周期完成不同 entry，所以 Scoreboard 支持多 completion、单 commit。

### Commit

```text
entries[commit_ptr] -> commit_entry_o -> Core commit decision
commit_i
-> occupied=0
-> 条件清 producer map
-> commit_ptr++
```

Scoreboard 自身不决定 Store 是否可提交、Fence 是否 quiescent，也不直接写 RF/CSR。这些架构副作用由 `core_top` 在 Commit 边界集中处理。

## 2.4 控制流与优先级

### 全局优先级

```text
rst
> flush
> normal completion/commit/allocate
```

flush 必须覆盖 normal path，否则异常 full flush 周期可能又分配新 entry 或接受 late completion。

### Normal path 文本/NBA 优先级

```text
fixed/load/slow completion
-> commit clear
-> allocate new entry
```

同一寄存器字段被多次 nonblocking assignment 时，后面的 allocation 最终生效。这个顺序专门支持 Scoreboard 满时同拍 commit + issue，allocate pointer 与 commit pointer 可能指向同一物理 slot。

### Count 更新

```text
allocate=1, commit=0 -> count + 1
allocate=0, commit=1 -> count - 1
allocate=1, commit=1 -> count hold
```

当前指针直接执行 `ptr + 1'b1`，并使用全局 `TRANS_ID_W=$clog2(SCOREBOARD_DEPTH)`。因此实际参数化前提是 `DEPTH` 与全局 `SCOREBOARD_DEPTH` 一致且为 2 的幂；若要支持任意深度，必须显式写 `ptr == DEPTH-1 ? 0 : ptr+1`，并同步修正 transaction ID 位宽。

如果只把 `DEPTH` 改成 6：3-bit 指针会走到 6/7 并越界索引 `entries_q`，仿真出现 X，综合后的行为也不再可靠。

### Producer map 清除规则

老写者 Commit 时，只有满足以下条件才清：

```text
commit entry writes rd
AND rd != x0
AND producer_valid[rd]
AND producer_tid[rd] == commit_ptr
```

如果 producer map 已被年轻 WAW 指令覆盖，老 Commit 不能把它清掉。

### Serialize

- allocate serialize uop：`serial_pending=1`。
- Commit System 或 exception：`serial_pending=0`。
- flush/reset：强制清零。

## 2.5 关键代码块精讲

### 代码块 A：youngest producer direct map

```systemverilog
query_rs1_found_o = query_uop_i.uses_rs1 && query_uop_i.rs1 != 0 &&
                    producer_valid_q[query_uop_i.rs1];
query_rs1_trans_id_o = query_rs1_found_o ?
                       producer_tid_q[query_uop_i.rs1] : '0;
query_rs1_ready_o = !query_rs1_found_o ||
                    entries_q[query_rs1_trans_id_o].done;
```

为什么这样写：顺序发射保证 producer map 可在 allocate 时直接覆盖成 youngest writer，consumer 只需一次索引。

如果删掉 `uses_rs1`：不使用 rs1 的 LUI/JAL 等指令也可能被 instruction bits 中的伪 rs1 阻塞。
如果删掉 `rs1!=0`：x0 可能错误依赖某条写 rd=0 的在途指令。
如果 query 不取 youngest：WAW 后 consumer 可能读取老版本。

### 代码块 B：Load completion accepted

```systemverilog
load_complete_accepted_o = load_complete_i &&
                           entries_q[load_trans_id_i].occupied;
```

为什么存在：LoadQueue 只有在 Scoreboard 确认目标 entry 仍有效时才清 active。full flush 或 late response 后，旧 transaction ID 可能已经无效或即将重用。

如果 LoadQueue 只看原始 `load_complete_i`：late response 可能清除一条新 active Load 的状态，或把旧结果写入已回收 tid。

### 代码块 C：WAW-safe commit clear

```systemverilog
if (commit_entry_o.writes_rd && commit_entry_o.rd != 0 &&
    producer_valid_q[commit_entry_o.rd] &&
    producer_tid_q[commit_entry_o.rd] == commit_ptr_q)
    producer_valid_q[commit_entry_o.rd] <= 1'b0;
```

为什么比较 tid：producer map 可能指向更年轻的同 rd writer。

如果无条件清 producer_valid：老写者一提交，依赖年轻写者的后续 consumer 会误读 RF 中的老值。

### 代码块 D：Allocation 放在 Commit 后

```systemverilog
if (commit_i) begin
    entries_q[commit_ptr_q].occupied <= 1'b0;
    ...
end

if (allocate_i) begin
    entries_q[allocate_ptr_q].occupied <= 1'b1;
    ...
end
```

为什么这样写：窗口满时 `allocate_ptr==commit_ptr`，同一 slot 先清老 entry，再由年轻 allocation 覆盖。

如果交换顺序：同拍分配的新 uop 可能在时钟沿被 Commit clear 掉，随后 completion assertion 或提交顺序出错。

### 代码块 E：只 reset occupied，不 reset payload

```systemverilog
for (i = 0; i < DEPTH; i = i + 1)
    entries_q[i].occupied <= 1'b0;
```

为什么不清 result/PC/instr：payload 只有在 occupied/producer valid 条件下才有语义。少 reset 大幅降低 reset fanout。

如果下游不检查 occupied 就使用 stale payload，则是下游协议错误，不应靠 reset 整个数组掩盖。

## 2.6 时序示例

### 正常路径：ALU producer/consumer

```asm
I0: add x5, x1, x2
I1: xor x6, x5, x3
```

| 周期 | Scoreboard 状态 | Query/Completion |
|---|---|---|
| T0 | allocate I0 tid0；producer[x5]=tid0，done=0 | I0 issue |
| T1 | edge 前 tid0.done=0 | I1 query found tid0；fixed completion tid0 由 Operand Resolver 旁路 |
| T1 末尾 | tid0.done=1/result 写入；allocate I1 tid1 | I1 issue |
| T2 | head tid0 ready，可 Commit | tid1 fixed completion |

### WAW 路径：老 Commit 不能清年轻 producer

```asm
I0: div x5, ...   # tid0
I1: add x5, ...   # tid1
I2: xor x6, x5, ...
```

I1 allocate 后 producer[x5]=tid1。I0 Commit 时比较失败，不清 producer valid。I2 始终依赖 tid1。

### 满窗口同拍 Commit + Allocate

8 个 entry 全满时，若 head done：

```text
commit_i=1
issue_control 因 commit credit 允许 allocate_i=1
allocate_ptr == commit_ptr
count 保持 8
new allocation 最终覆盖旧 head slot
```

### 异常/Flush 路径

异常到 Commit 触发 `flush_i`：

- 所有 occupied 清零。
- producer map 清零。
- ptr/count 回到 0。
- serial pending 清零。
- 同周期 completion/commit/allocate 不执行 normal update。

## 2.7 可以直接复用的设计模式

1. 用 ring pointer + count 实现小型顺序提交窗口。
2. 顺序发射架构可用 architectural register -> youngest transaction direct map。
3. Completion 用 transaction ID 定位，不用 rd 定位。
4. Commit 清 producer 时必须比较版本/tid，保证 WAW 正确。
5. 满队列允许 same-cycle pop/push，并明确 NBA 覆盖顺序。
6. 只 reset valid/occupied，不 reset 无效 payload。
7. 将 commit eligibility 留给拥有架构副作用上下文的顶层，而 Scoreboard 只保存状态。
8. late response 必须经过 occupied/epoch 类有效性检查。

## 2.8 常见坑与自检清单

- [ ] `allocate_ptr/commit_ptr/count` 是否在 wrap 时保持一致？
- [ ] `DEPTH` 是否保持 2 的幂并与全局 transaction ID 位宽一致？
- [ ] full window 下 commit+allocate 是否保留新 entry？
- [ ] producer map 是否始终指向 youngest writer？
- [ ] 老 WAW writer Commit 是否错误清掉年轻 producer？
- [ ] x0 和 `uses_rs*` 是否被正确排除？
- [ ] completion tid 是否必须命中 occupied entry？
- [ ] flush 是否覆盖 normal completion/allocate？
- [ ] payload 未 reset 时，所有消费者是否由 occupied/valid gate？
- [ ] System/exception 是否在 allocate 时直接 done？
- [ ] serial pending 是否在正确的 Commit/flush 时清除？
- [ ] count 是否只由 allocate/commit 二元事件更新一次？
- [ ] Scoreboard 是否被误当成可跳过 ID 阻塞的 Issue Queue？

---


# 3. `operand_resolver.sv`

## 3.1 模块定位

`operand_resolver` 是 Issue 阶段的操作数版本选择器和 completion bypass 网络。它不保存状态，只根据当前 ID uop、RegFile、Commit-WB、Scoreboard query 和三类 completion，输出最终 rs1/rs2 value 与 ready。它还提供独立的 memory-address rs1 路径，用于禁止 Load completion 直达下一条 AGU。

前级：RegFile、Scoreboard、Fixed Execute、Load data path、MDU/Bitmanip、Commit-WB。
后级：Issue Control 使用 ready；`core_top` 在 `issue_fire` 时把 value 捕获进 `exec_q`。

## 3.2 接口速查表

### 当前 uop 与基础架构值

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `uop_i` | input | 当前 ID uop 的 rs/use/FU 信息 | 整个 Issue 周期 |
| `rf_rs1_data_i` | input | RegFile rs1 组合读值 | baseline value |
| `rf_rs2_data_i` | input | RegFile rs2 组合读值 | baseline value |
| `wb_valid_i` | input | Commit-WB bypass valid | Commit 后、RF 真写前的一周期 |
| `wb_rd_i` | input | Commit-WB rd | 与 uop rs 比较 |
| `wb_data_i` | input | Commit-WB data | 普通 result 或 CSR read old value |

### Scoreboard query

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `rs1_found_i` | input | rs1 有在途 youngest producer | 为 1 时 Scoreboard 版本覆盖 RF/WB |
| `rs1_scoreboard_ready_i` | input | producer entry.done | completion 未旁路时的 ready |
| `rs1_trans_id_i` | input | youngest producer tid | completion 精确匹配 |
| `rs1_scoreboard_data_i` | input | producer entry.result | done 后稳定使用 |
| `rs2_found_i` | input | rs2 有在途 youngest producer | 同 rs1 |
| `rs2_scoreboard_ready_i` | input | rs2 producer done | 同 rs1 |
| `rs2_trans_id_i` | input | rs2 producer tid | 同 rs1 |
| `rs2_scoreboard_data_i` | input | rs2 producer result | 同 rs1 |

### Completion bypass

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `fixed_completion_valid_i` | input | Fixed completion valid | ALU/Branch/Store completion 周期 |
| `fixed_completion_i` | input | Fixed tid/result | 优先级最高 completion bypass |
| `load_completion_valid_i` | input | Load completion valid | Cache/forwarding result 周期 |
| `load_completion_meta_i` | input | Load tid/metadata | 取 trans_id 比较 |
| `load_result_i` | input | 已 merge/extend 的 Load value | 只进入普通 operand |
| `slow_completion_valid_i` | input | MDU/BM response valid | 长延迟完成周期 |
| `slow_completion_trans_id_i` | input | Slow tid | 与 producer tid 比较 |
| `slow_completion_result_i` | input | Slow result | 普通和 memory rs1 均可使用 |

### 输出

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `src1_value_o` | output | 普通 rs1 最终值 | ALU/Branch/MULDIV/BM 使用 |
| `src2_value_o` | output | 普通 rs2 最终值 | 所有 uses_rs2，包括 Store data |
| `src1_memory_value_o` | output | Load/Store 地址 rs1 最终值 | `exec_mem_addr_q` 捕获 |
| `src1_ready_o` | output | 普通 rs1 ready | 非 memory FU issue gate |
| `src2_ready_o` | output | rs2 ready | 所有双源/Store data issue gate |
| `src1_memory_ready_o` | output | 地址 rs1 ready | Load/Store issue gate |
| `src1_found_o` | output | rs1 producer found 透传 | 当前顶层未使用，便于模块合同/调试 |
| `src2_found_o` | output | rs2 producer found 透传 | 同上 |

## 3.3 主数据流

### 普通 rs1/rs2

```text
RF / x0
-> Commit-WB match
-> Scoreboard youngest producer result/ready
-> same-cycle Fixed completion match
-> same-cycle Load completion match
-> same-cycle Slow completion match
-> src value / ready
```

这里的“优先级”分两类：

1. 版本优先级：Scoreboard youngest producer 必须覆盖 RF/Commit-WB 的老架构版本。
2. 完成时机优先级：如果 youngest producer 本周期 completion，直接用 completion 覆盖尚未更新的 Scoreboard done/result。

### Memory-address rs1

```text
先复制普通 Scoreboard/RF/WB 路径
-> Fixed completion 可以覆盖
-> Load completion不覆盖
-> Slow completion可以覆盖
```

Store data 使用 `src2_value_o`，因此 Load completion 可以前递给 Store data；限制只针对 Load/Store 的地址基址 rs1。

## 3.4 控制流与优先级

`operand_resolver` 没有 stall/flush 寄存器。它只产生 ready/value，真正是否发射由 `issue_control` 决定。

### 基础选择优先级

```text
x0 clamp
WB bypass
Scoreboard producer override
```

如果没有 producer，ready 默认 1，使用 RF/WB。
如果有 producer，ready 取 entry.done，value 取 entry.result。

### Completion 优先级

```text
fixed > load > slow
```

用 `if / else if` 形成确定优先级。正常协议下，同一个 youngest transaction ID 不应同时从多个 completion port 返回；顶层 assertion 也防止 MDU/BM 同拍共享 slow port冲突。

### Flush/Redirect

Resolver 本身不会清输出。安全性来自：

- full flush 清 Scoreboard producer/occupied。
- redirect/full flush 阻止 `issue_fire`。
- MDU/DCache/Bitmanip kill 抑制 late completion。

如果只清 Scoreboard 而不阻止 Issue，同周期 stale组合值仍可能进入 `exec_q`。

## 3.5 关键代码块精讲

### 代码块 A：RF 与 Commit-WB baseline

```systemverilog
src1_value_o = rf_rs1_data_i;
src2_value_o = rf_rs2_data_i;
if (uop_i.rs1 == 0) src1_value_o = 32'd0;
if (uop_i.rs2 == 0) src2_value_o = 32'd0;

if (wb_valid_i && uop_i.rs1 == wb_rd_i && uop_i.rs1 != 0)
    src1_value_o = wb_data_i;
```

为什么 WB 在 RF 后：WB 是更新版本，覆盖尚未物理写入的 RF。

如果删掉 WB：producer 已 Commit 并从 Scoreboard 清除、RF 又尚未写入的单周期内，consumer 会读取旧值。

### 代码块 B：Scoreboard youngest 覆盖 WB

```systemverilog
if (rs1_found_i) begin
    src1_ready_o = rs1_scoreboard_ready_i;
    src1_value_o = rs1_scoreboard_data_i;
end
```

为什么在 WB 后：同一个架构寄存器可能有一个老值正在 Commit-WB，同时有一个年轻写者仍在 Scoreboard。consumer 必须依赖年轻 writer。

如果把 WB 放最后：WAW 场景会错误选择老 Commit 值。

### 代码块 C：Completion 必须匹配 transaction ID

```systemverilog
if (fixed_completion_valid_i &&
    fixed_completion_i.trans_id == rs1_trans_id_i) begin
    src1_ready_o = 1'b1;
    src1_value_o = fixed_completion_i.result;
end
```

为什么不用 rd 比较：completion 的精确版本身份是 transaction ID；WAW 时多个 entry 可以写同一个 rd。

如果只看 valid 不看 tid：任何 ALU completion 都可能错误唤醒当前 ID 指令。

### 代码块 D：Load completion 不更新 memory path

```systemverilog
end else if (load_completion_valid_i &&
             load_completion_meta_i.trans_id == rs1_trans_id_i) begin
    src1_ready_o = 1'b1;
    src1_value_o = load_result_i;
    // Intentionally no src1_memory_ready/value assignment.
end
```

为什么这样写：Load result 可以给 ALU/Branch/JALR 使用，但不能在同周期经过 AGU、Store forwarding、Memory Arbiter 再形成新 DCache request。

如果补上 memory assignment：Load-to-address 少一拍 stall，但可能形成 DCache BRAM output -> load merge -> bypass mux -> AGU -> DCache request 的长路径，影响 FPGA Fmax。

### 代码块 E：Fixed/Slow 可以进入 memory path

```systemverilog
src1_memory_ready_o = 1'b1;
src1_memory_value_o = fixed_or_slow_result;
```

为什么允许：Fixed/Slow result 在本周期进入 exec register，AGU 在时钟沿捕获后才驱动下一周期 memory request，不包含 DCache response/formatting 的同类长链。

如果禁止：ALU->Load address 和 DIV->Load address都会额外多停一拍。

## 3.6 时序示例

### 正常路径：ALU completion 前递到 Load 地址

```asm
I0: add x5, x1, x2
I1: lw  x6, 0(x5)
```

I0 fixed completion 周期：

```text
rs1_found=1, rs1_tid=I0.tid
fixed.tid matches
src1_value = fixed.result
src1_memory_value = fixed.result
src1_memory_ready = 1
```

I1 可以背靠背 issue，周期末有效地址写入 `exec_mem_addr_q`。

### 普通 Load-use

```asm
lw  x5, 0(x1)
add x6, x5, x2
```

Cache hit completion 周期，Load tid 匹配 x5 producer：`src1_ready=1`，I1 当周期 issue。

### 特殊路径：Load-to-address

```asm
lw x5, 0(x1)
lw x6, 0(x5)
```

Load completion 周期：普通 `src1_ready=1`，但 `src1_memory_ready=0`，I1 仍 stall。下一周期 Scoreboard done/result 稳定后，memory path ready，I1 issue。

### WAW + WB 同时存在

```asm
I0: add x5, ...  # Commit-WB
I1: div x5, ...  # younger Scoreboard producer, not done
I2: xor x6, x5, ...
```

虽然 WB match x5，Scoreboard found 会覆盖为 I1 的 ready/result。I2 必须等 I1，不能使用 I0。

### Flush 周期

Resolver 可能仍组合显示某些 input 值，但 `issue_control.redirect_i=1` 或 Scoreboard flush 使它们不能被捕获进新执行状态。

## 3.7 可以直接复用的设计模式

1. 把“版本选择”和“本周期完成旁路”分成两层优先级。
2. Completion 用 transaction/tag 精确匹配，不用架构 rd 模糊匹配。
3. 为高风险 consumer 建独立 ready/value 路径，例如 memory-address source。
4. Commit-WB bridge 覆盖 Commit 与 RF 写入的相位差。
5. 组合 resolver 不拥有 flush 状态，flush 应在状态拥有者和 capture enable 处生效。
6. Store address 与 Store data 使用不同语义路径：rs1 memory path、rs2 ordinary path。
7. 串行指令的简化源路径可以隔离全局 completion 大 mux。

## 3.8 常见坑与自检清单

- [ ] Scoreboard producer 是否覆盖 RF/WB 老版本？
- [ ] Completion 是否只在 tid 匹配时前递？
- [ ] x0 是否始终为 0？
- [ ] `uses_rs*` 是否由 Scoreboard query 正确 gate？
- [ ] Load completion 是否错误进入 memory-address path？
- [ ] Store data rs2 是否仍允许 Load completion？
- [ ] Fixed/Slow result 是否同步更新普通和 memory rs1？
- [ ] WB bypass 是否位于 RF 后、Scoreboard 前？
- [ ] Flush/redirect 周期是否禁止 capture resolver 输出？
- [ ] 是否错误地让 completion 直接写 RegFile？
- [ ] 组合 mux 扇入是否造成 Issue 关键路径？
- [ ] CSR 是否错误接入不可能使用的通用 completion 网络？

---


# 4. `issue_control.sv`

## 4.1 模块定位

`issue_control` 是 Issue 阶段最后一级组合门控。它不选择多条候选指令，也不保存状态；它只判断当前 `id_uop_q` 能否在本周期原子地完成“Scoreboard 分配 + `exec_q` 捕获”。

前级：Operand Resolver 提供源操作数 ready，Scoreboard/LoadQueue/StoreBuffer 提供容量，MDU/Bitmanip 提供握手和 busy，分支恢复逻辑提供阻断条件。
后级：`issue_o` 同时驱动 Scoreboard allocate、ID 消费和 `exec_q` capture，因此所有条件必须在一个组合表达式中保持一致。

它存在的核心原因是：**源数据可用不等于指令可安全发射**。还必须保证目标资源有 credit、串行化约束成立，并且当前周期没有恢复动作。

## 4.2 接口速查表

| 信号 | 方向 | 作用 | 关键时机 |
|---|---|---|---|
| `id_valid_i` | input | 当前 ID holding register 有有效 uop | `issue_o` 的总 valid |
| `uop_i` | input | 当前 uop 的 FU、serialize 等属性 | 组合选择资源与源路径 |
| `src1_ready_i` | input | 普通 rs1 路径 ready | ALU/Branch/JALR/MDU 等使用 |
| `src1_memory_ready_i` | input | 访存地址 rs1 路径 ready | Load/Store 专用；不接受 Load completion 直达 AGU |
| `src2_ready_i` | input | rs2 普通路径 ready | 所有声明使用 rs2 的 uop；Store data 也走此路径 |
| `scoreboard_count_i` | input | 当前在途 entry 数 | 检查 ROB/Scoreboard allocation credit |
| `store_count_i` | input | StoreBuffer 已占用数 | Store 资源 credit |
| `load_count_i` | input | LoadQueue 已占用数 | Load 资源 credit |
| `exec_i` | input | 当前执行寄存器内容 | 预留尚未计入 LoadQueue/StoreBuffer 的本拍执行项 |
| `serial_pending_i` | input | 已有串行指令在途 | 阻止任何更年轻指令发射 |
| `mdu_req_ready_i` | input | MDU 请求口可接收 | `FU_MULDIV` 发射条件之一 |
| `mdu_busy_i` | input | MDU 占用共享慢执行资源 | 阻止 Bitmanip 发射 |
| `bitmanip_req_ready_i` | input | Bitmanip 请求口可接收 | `FU_BITMANIP` 发射条件之一 |
| `bitmanip_busy_i` | input | Bitmanip 占用共享慢执行资源 | 阻止 MDU 发射 |
| `bitmanip_clmul_start_i` | input | 本周期正在启动 CLMUL | 防止与 MDU/Bitmanip 请求冲突 |
| `commit_i` | input | 本周期 Scoreboard head 将提交 | Scoreboard 满时提供同拍释放 credit |
| `branch_resolve_i` | input | 本周期有分支解析 | 无论预测对错都阻断新 issue |
| `redirect_i` | input | 本周期发生重定向/全恢复 | 禁止错误路径 uop 被捕获 |
| `issue_o` | output | 当前 uop 本周期真正发射 | 同时作为 allocate、ID pop 和 exec capture 使能 |

隐含前提：`commit_i` 必须已经包含“head valid、done、提交副作用可接受”等完整提交条件，不能只是 `commit_entry.done`。

## 4.3 主数据流

### 第一步：选择 rs1 ready 域

```text
Load/Store -> src1_memory_ready_i
其他 FU    -> src1_ready_i
所有 uop   -> src2_ready_i
```

这里不是重复检查同一个 rs1。普通路径允许 Load completion 前递；memory-address 路径有意屏蔽它，从而把 DCache return 到下一条 AGU 的长组合路径切断。

### 第二步：计算目标 FU credit

```text
Load     -> LoadQueue count + exec 中待入队 Load < depth
Store    -> StoreBuffer count + exec 中待入队 Store < depth
MULDIV   -> request ready + Bitmanip 不 busy + 无共享启动冲突
BITMANIP -> request ready + MDU 不 busy + 无共享启动冲突
其他     -> ready
```

`exec_i` 是重要的 reservation。当前 `exec_q` 中的 Load/Store 要到 Fixed Execute 产生 enqueue 后才进入队列；如果只看队列的已登记 count，可能连续多发一条而超过深度。

### 第三步：加入 serialize 屏障

```text
uop.serialize = 1:
    既有 Scoreboard 必须为空，并且没有 serial pending

uop.serialize = 0:
    只要求没有 serial pending
```

串行指令必须等所有老指令提交后再发射；一旦串行指令已分配，`serial_pending_i` 会阻断其后的所有年轻 uop，直到该指令提交或 flush。

### 第四步：检查 Scoreboard allocation credit

```text
scoreboard_count < SCOREBOARD_DEPTH
    或
本周期 commit_i = 1
```

满窗口时，Commit 和 Allocate 可以在同一上升沿复用 head slot，避免无意义空泡。

### 第五步：恢复门控并形成 issue

```text
ID valid
-> 正确的 rs1 ready
-> rs2 ready
-> FU/serialize ready
-> Scoreboard credit
-> 无 branch resolve
-> 无 redirect
-> issue_o
```

`issue_o=1` 后，`core_top` 在同一个上升沿使用相同 transaction ID 分配 Scoreboard entry 并捕获 `exec_q`，因此不会出现“执行了却没进 Scoreboard”或“分配了却没执行”的半事务状态。

## 4.4 控制流与优先级

`issue_control` 没有顺序状态，最终语义是所有条件的 AND。为了阅读和验证，可以按下列优先层次理解：

1. `redirect_i` / `branch_resolve_i`：最高安全优先级，强制 `issue_o=0`。
2. `id_valid_i`：无有效 uop 时禁止任何副作用。
3. 源 ready：Load/Store 的 rs1 必须使用 memory-ready 域。
4. FU credit：队列、MDU、Bitmanip 资源必须可接收。
5. Serialize：串行指令等待 drain；已有串行指令阻塞年轻指令。
6. Scoreboard credit：空闲 entry 或同拍 Commit credit。

### Branch resolve 为什么预测正确也阻断

`branch_resolve_i` 只要为 1 就停发一拍，即使 `redirect_i=0`。这是保守的恢复边界：当前分支解析与 predictor/update/redirect 状态在同一周期收敛，不让新 issue 与该边界交叠。

代价是每个已解析分支至少损失这个 issue 机会；收益是不用证明“预测正确分支解析拍的新发射”与各种 redirect 组合完全无冲突。

### Serialize 为什么不使用最后一次 Commit credit

串行条件直接检查 `scoreboard_count_i == 0`，不会把 `commit_i` 视为“本拍已经为空”。因此当窗口只剩一条老指令并在本拍提交时，serialize uop 要等下一周期才发射。

这是一个保守空泡。如果改为接受 `scoreboard_count_i == 1 && commit_i`，必须证明老指令所有架构副作用在同一边沿后对串行操作可见，尤其是 CSR、Store、Fence 和异常边界。

### ID holding 行为

当任一条件不满足，`issue_o=0`，`core_top` 中 `id_valid_q/id_uop_q` 保持不变。它不是 replay：指令从未离开 ID，也没有产生需要撤销的 Scoreboard 或执行副作用。

## 4.5 关键代码块精讲

### 代码块 A：Load/Store credit 包含执行级 reservation

```systemverilog
FU_LOAD: fu_ready =
    (load_count_i + LD_CNT_W'(exec_i.valid && exec_i.uop.fu == FU_LOAD)) <
    LD_CNT_W'(LOAD_QUEUE_DEPTH);
FU_STORE: fu_ready =
    (store_count_i + ST_CNT_W'(exec_i.valid && exec_i.uop.fu == FU_STORE)) <
    ST_CNT_W'(STORE_BUFFER_DEPTH);
```

为什么这样写：`load_count_i/store_count_i` 只统计已进入相应队列的项，`exec_i` 中还有一个即将 enqueue 的一拍在途项，必须提前占 credit。

如果删掉 reservation：当队列只剩一个空位且 `exec_q` 已保存一条同类访存时，ID 仍可能再发一条，下一周期出现两条需求争一个 slot，导致覆盖、丢请求或 count 越界。

### 代码块 B：共享慢执行资源互斥

```systemverilog
FU_MULDIV: fu_ready = mdu_req_ready_i && !bitmanip_busy_i &&
                          !(exec_i.valid && exec_i.uop.fu == FU_MULDIV) &&
                          !bitmanip_clmul_start_i;
FU_BITMANIP: fu_ready = bitmanip_req_ready_i && !mdu_busy_i &&
                             !(exec_i.valid && exec_i.uop.fu == FU_MULDIV) &&
                             !bitmanip_clmul_start_i;
```

为什么这样写：M Extension 与某些 Bitmanip/CLMUL 操作共享慢路径请求和结果返回边界。ready 只表示端口局部可接收，busy/start/exec reservation 则保证全局互斥。

如果删掉任一互斥项：两个操作可能在同一资源生命周期重叠，表现为 transaction ID 与 result 错配、响应丢失或错误完成另一个 Scoreboard entry。

注意：`FU_BITMANIP` 对 `exec_i` 检查的是 `FU_MULDIV`，这是当前共享路径协议的实现事实，不要未经下游接口核对就“对称化”修改。

### 代码块 C：串行化前后双向封锁

```systemverilog
if (uop_i.serialize)
    fu_ready = fu_ready && scoreboard_count_i == 0 && !serial_pending_i;
else
    fu_ready = fu_ready && !serial_pending_i;
```

为什么这样写：第一行保证串行指令之前没有老指令；第二类条件保证串行指令之后没有年轻指令。这两半共同构成完整的序列化边界。

如果只检查 `scoreboard_count_i==0`：串行指令分配后的下一周期，年轻普通指令又能继续进入窗口，破坏 CSR/Fence/System 的全序语义。

如果只检查 `serial_pending_i`：串行指令可能越过尚未提交的老 Store、异常或 CSR 副作用。

### 代码块 D：满 Scoreboard 的同拍 Commit credit

```systemverilog
(scoreboard_count_i < SB_CNT_W'(SCOREBOARD_DEPTH) || commit_i)
```

为什么这样写：Scoreboard 的时序块支持同拍 commit+allocate，并通过赋值顺序让新 allocation 保留在复用 slot 中。

如果删掉 `|| commit_i`：窗口满时即使 head 每拍都提交，也会固定插入一拍 issue 空泡，持续高占用场景吞吐下降。

如果 Scoreboard 本身不支持同 slot pop/push 却保留此条件：会覆盖新 entry 或错误清空 occupied，因此 control 与 storage 的 credit 契约必须成对验证。

### 代码块 E：Load/Store 使用独立 memory-ready

```systemverilog
((uop_i.fu == FU_LOAD || uop_i.fu == FU_STORE) ?
 src1_memory_ready_i : src1_ready_i)
```

为什么这样写：访存地址计算处于容易形成 DCache 数据回返长路径的位置。普通 rs1 已 ready 不代表它满足 AGU 的时序隔离规则。

如果统一改为 `src1_ready_i`：Load completion 可在同周期穿过 resolver、地址加法和 cache 控制，可能功能仿真正确但 implementation 出现严重 setup violation。

如果统一改为 `src1_memory_ready_i`：普通 ALU 消费 Load completion 也会被多停一拍，降低无必要的 load-use 性能。

### 代码块 F：恢复周期禁止 issue

```systemverilog
!branch_resolve_i && !redirect_i
```

为什么这样写：分支解析或 redirect 周期，ID uop 可能属于即将作废的取指流，不能在边沿创建不可撤销的新执行事务。

如果删掉：错误路径 uop 可能与 flush 同拍进入 Scoreboard/执行级；依赖 always_ff 文本顺序“碰巧清掉”会形成脆弱的跨模块语义。

## 4.6 时序示例

### 正常路径：独立 ALU 连续发射

```asm
I0: add x5, x1, x2
I1: xor x6, x3, x4
```

| 周期 | ID | 源/FU/credit | `issue_o` | 周期末动作 |
|---|---|---|---:|---|
| T0 | I0 | 全 ready | 1 | 分配 tid0，I0 进入 `exec_q` |
| T1 | I1 | 与 I0 无 RAW，Fixed FU ready | 1 | I0 completion；分配 tid1，I1 进入 `exec_q` |

如果 ID 上游可持续供给，Fixed 指令可达到每周期一条的 issue 吞吐；当前不是 2-wide issue。

### 正常路径：Scoreboard 满但同拍 Commit

假设 `scoreboard_count_i==SCOREBOARD_DEPTH`，head 已 done 且 `commit_i=1`：

```text
组合期：scoreboard credit = full || commit = true
边沿：  老 head commit，同时当前 ID uop allocate 到释放的 slot
边沿后：count 保持满，窗口没有气泡
```

### 特殊路径：Load result 可供 ALU，但不能直供下一条地址

```asm
I0: lw  x5, 0(x1)
I1: lw  x6, 0(x5)
```

在 I0 Load completion 周期：

- Resolver 的 `src1_ready_i=1`，因为普通路径接收 Load completion。
- `src1_memory_ready_i=0`，因为 memory path 有意不接收 Load completion。
- I1 是 `FU_LOAD`，Issue Control 选择 memory-ready，因此 `issue_o=0`。
- 下一周期 I0 result 已写入 Scoreboard entry，memory path ready，I1 才能发射。

这是一拍有意的 Load-to-address stall，不是遗漏旁路。

### 特殊路径：LoadQueue 最后一个空位已被 exec 预留

假设 `load_count_i=DEPTH-1`，同时 `exec_i` 中有一条 Load：

```text
effective occupancy = DEPTH-1 + 1 = DEPTH
fu_ready = 0
当前 ID Load 保持，不再超发
```

等 `exec_i` 的 Load 入队且队列释放 credit 后再继续。

### 特殊路径：Serialize 等待 drain

```asm
I0: div  x5, x1, x2
I1: csrrw x6, mstatus, x7  # serialize
I2: add  x8, x9, x10
```

| 状态 | I1 | I2 |
|---|---|---|
| I0 尚在 Scoreboard | `count!=0`，I1 不发射 | 尚未进入当前 issue 位置 |
| I0 最后一拍 Commit | 仍看到旧 `count=1`，I1 不发射 | 阻塞 |
| 下一周期窗口为空 | I1 发射并设置 `serial_pending` | 阻塞 |
| I1 在途 | 已离开 ID | `serial_pending=1`，I2 不发射 |
| I1 Commit 后 | 串行边界结束 | I2 可继续 |

### 异常路径：Branch resolve / redirect

- 预测正确：`branch_resolve_i=1`，本拍保守停发；下一拍按顺序继续。
- 预测错误：`branch_resolve_i=1` 且随后/同时 `redirect_i=1`，本拍不发射，ID 被清空，前端从正确 PC 重取。
- 异常/full flush：`redirect_i=1`，即使源和资源全部 ready，也不能产生新 allocation。

## 4.7 可以直接复用的设计模式

1. 用单一 `issue_fire` 原子驱动“消费者离开 ID、在途表分配、执行寄存器捕获”。
2. Queue credit 必须包含尚未写入 count 的流水 reservation。
3. 满队列允许 pop+push 时，将同拍释放 credit 显式纳入 ready。
4. 普通操作数 ready 与关键 consumer ready 可以分域建模。
5. Serialize 要同时约束“等待老指令 drain”和“阻止年轻指令进入”。
6. Shared FU 的 ready、busy、start 和前级 reservation 要统一检查。
7. 恢复边界在 capture enable 处集中阻断，不依赖下游再清理非法事务。
8. 纯组合 issue gate 不保存 replay 状态；未发射 uop 应由 ID holding register 保持。

## 4.8 常见坑与自检清单

- [ ] `issue_o` 是否同时控制 ID 消费、Scoreboard allocate 和 exec capture？
- [ ] Load/Store rs1 是否使用 `src1_memory_ready_i`？
- [ ] Store data rs2 是否仍使用允许 Load bypass 的普通路径？
- [ ] LoadQueue/StoreBuffer credit 是否计入 `exec_i` reservation？
- [ ] 满 Scoreboard 同拍 Commit 是否可安全 Allocate？
- [ ] `commit_i` 是否是真正可提交握手，而不是仅 done？
- [ ] Serial 指令是否等待所有老 entry 清空？
- [ ] `serial_pending_i` 是否阻止所有年轻普通指令？
- [ ] Branch resolve 和 redirect 周期是否都禁止 issue？
- [ ] MDU/Bitmanip 共享资源是否检查 ready、busy、start 与前级占用？
- [ ] count 位宽 cast 是否能表示 `DEPTH`，避免比较截断？
- [ ] ID stall 时 uop 与 valid 是否保持稳定？

---

# 5. 四模块联动：典型指令流

这一节不再按文件拆分，而是从一条指令进入 ID 到最终 Commit，检查四个模块如何形成闭环。

## 5.1 ALU RAW：completion 同周期唤醒

```asm
I0: add x5, x1, x2
I1: xor x6, x5, x3
```

```text
T0:
  RegFile 提供 I0 的 x1/x2
  Scoreboard 未发现 producer
  Resolver 输出 ready/value
  Issue Control 放行
  边沿分配 I0 tid0，并捕获 exec_q

T1:
  I1 查询 x5 -> Scoreboard producer map 命中 tid0，但 entry.done 仍为 0
  Fixed Execute 同周期产生 tid0 completion
  Resolver 通过 tid 精确匹配，把 completion.result 前递给 I1
  Issue Control 看到 src ready，I1 无需等待 Scoreboard 下一拍写 done
  边沿完成 tid0，同时分配 I1 tid1
```

关键点：Scoreboard query 决定“应等待哪个版本”，completion bypass 决定“这个版本是否正在本拍产生”。二者缺一不可。

## 5.2 Load-use：普通消费与地址消费不同

```asm
I0: lw  x5, 0(x1)
I1: add x6, x5, x2   # 普通消费
I2: lw  x7, 0(x5)    # 地址消费
```

- I1 在 I0 Load completion 周期可通过 ordinary rs1 path 发射。
- I2 即使排在同样的 completion 边界，也必须等下一周期 Scoreboard `done/result` 可见后发射。
- Store 的地址 rs1 与 I2 相同；Store 的数据 rs2 与 I1 相同。

这不是 ISA 语义差异，而是微架构时序取舍：只隔离会把 Load data 再送入 AGU/DCache control 的路径。

## 5.3 WAW + RAW：必须锁定 youngest producer

```asm
I0: add x5, x1, x2
I1: div x5, x3, x4
I2: xor x6, x5, x7
```

1. I0 allocate：`producer[x5]=tid0`。
2. I1 allocate：覆盖为 `producer[x5]=tid1`。
3. I0 先完成并 Commit：RF/WB 出现 I0 的 x5，但 Commit 清表时发现 map 已不再指向 tid0，因此不能清 `producer[x5]`。
4. I2 query 仍锁定 tid1；Resolver 中 Scoreboard found 覆盖 RF/WB 老版本。
5. 只有 tid1 completion 或 entry.done 才能让 I2 ready。

如果 producer map 只保存 busy bit，无法区分 I0/I1 两个版本，WAW 后的 RAW 很容易误读老值。

## 5.4 满窗口持续流：Commit 与 Issue 同拍

```text
Scoreboard count = depth
head.done = 1 -> commit_fire = 1
ID uop 所有源和 FU ready
```

Issue Control 用 `commit_fire` 获得 allocation credit；Scoreboard 在同一个 always_ff 中先处理 Commit、后处理 Allocate；`count` 在 `{allocate, commit}=2'b11` 时保持不变。三个规则必须一致，任何一处漏改都会造成气泡或 entry 损坏。

## 5.5 异常与恢复：状态拥有者各自清理

```text
异常/系统提交
-> full_flush / redirect
-> Scoreboard 清 occupied、count、producer、serial
-> exec_q 清 valid
-> ID 清 valid
-> Issue Control 在恢复拍禁止新 capture
-> RegFile 保留此前已提交架构状态
```

Resolver 是纯组合逻辑，不需要也不应该保存 flush 状态。恢复正确性由“状态模块清 valid + issue capture 阻断”共同保证。

## 5.6 组合环路与关键路径自检

当前主要组合方向是：

```text
Scoreboard/RegFile/completion
-> Operand Resolver
-> Issue Control
-> issue_fire
-> Scoreboard allocate enable / exec_q D
```

`issue_fire` 只能影响下一边沿后的 Scoreboard 状态，不能组合反向改变当前 query/count，否则会形成环路。`commit_fire` 可以作为 credit 输入，但它也必须由当前稳定的 head 和下游 ready 产生，不能依赖 `issue_fire`。

综合/implementation 重点观察：

- producer map 到 entry result 的动态索引 mux；
- 三路 completion 的 tid compare 与 32-bit data mux；
- LoadQueue/StoreBuffer count 加 reservation 后的深度比较；
- Resolver value 到 `exec_mem_addr_q` 加法器；
- `issue_o` 的高扇出 allocate/capture/ID 控制网络。

---

# 6. 联动查看的定义与文件

| 文件 | 为什么必须一起看 |
|---|---|
| [`core_top.sv`](../../rtl/core/core_top.sv) | 四模块的真实连接、`issue_fire` 的三处副作用、Commit/flush 与 `exec_q` 时序 |
| [`core_types_pkg.sv`](../../rtl/core/pkg/core_types_pkg.sv) | `uop_t`、`exec_req_t`、Scoreboard entry、completion metadata 的字段语义 |
| [`core_config_pkg.sv`](../../rtl/core/pkg/core_config_pkg.sv) | Scoreboard、LoadQueue、StoreBuffer 深度和 transaction ID 位宽 |
| [`fixed_execute.sv`](../../rtl/core/execute/fixed_execute.sv) | Fixed completion、branch resolve、Load/Store enqueue 的产生时机 |
| [`load_queue.sv`](../../rtl/core/memory/load_queue.sv) | Load completion 生命周期以及 accepted 回握 |
| [`store_buffer.sv`](../../rtl/core/memory/store_buffer.sv) | Store 分配、提交和队列 count 语义 |

若实际路径与表中名称有调整，应以 `core_top.sv` 实例化和 filelist 为准；不要仅凭模块名推断时序契约。

---

# 7. 最小实践任务

目标：手写一个可仿真的简化 Issue 子系统，理解“版本跟踪 + 同拍旁路 + 原子发射”，不实现完整 CPU。

## 7.1 功能边界

- 32x32 RegFile，2 个组合读口、1 个 Commit 写口，x0 恒零。
- 4-entry Scoreboard，单发射、单提交，支持 ALU completion。
- 每个 entry 只保存 `occupied/done/rd/writes_rd/result`。
- `producer_valid[32] + producer_tid[32]` 跟踪 youngest writer。
- Resolver 支持 RF、WB、Scoreboard、同拍 ALU completion 四层来源。
- Issue Control 只检查 ID valid、两个源 ready、Scoreboard credit 和 flush。
- 不实现 Load/Store、异常、CSR、分支预测和多执行单元。

## 7.2 实现步骤

1. 先写 RegFile，并用断言验证 x0 永远为零。
2. 写 4-entry ring Scoreboard，只实现 allocate/complete/commit/count。
3. 加 producer map，并构造两条连续写同一 rd 的 WAW 测试。
4. 写纯组合 Resolver，先完成 RF/WB/Scoreboard，再加入 completion tid bypass。
5. 写 `issue_fire`，保证它同拍驱动 Scoreboard allocate 与执行请求寄存器。
6. 最后加入满窗口 `commit + allocate`，验证 count 保持为 4 且新 entry 未被清掉。

## 7.3 必测指令/事务序列

1. `add x5,...` 后紧跟读 x5：同拍 completion bypass，无额外等待。
2. 两条连续写 x5，第三条读 x5：只能等待第二条 producer。
3. 老 x5 Commit 与年轻 x5 在途重叠：Commit 不得清年轻 map。
4. Scoreboard 满，head Commit 与新指令 Issue 同拍：count 不变，新 entry 有效。
5. Flush 与 completion/allocate 同拍：flush 覆盖全部年轻状态，RegFile 已提交值不变。
6. completion tid 指向非 occupied entry：必须忽略或触发 assertion，不能写结果。

## 7.4 完成标准

- 随机生成 RAW/WAW 序列，与一个顺序软件模型逐次比较 Commit 的 `rd/wdata`。
- 断言 `count<=4`、x0 恒零、Commit head 必须 occupied/done。
- 断言 `issue_fire` 时一定同时发生 allocate 与 exec capture。
- 断言 producer map 有效时对应 entry 必须 occupied 且写同一个 rd。
- 通过后再扩展 Load completion 和独立 memory-address ready；不要一开始就加入全部真实 Core 复杂度。

完成这个练习后，你应能独立搭建“顺序 Issue、乱序 Completion、顺序 Commit”的最小骨架，并知道升级到真正多候选 Issue Queue 时，哪些状态仍可复用，哪些选择逻辑必须重写。
