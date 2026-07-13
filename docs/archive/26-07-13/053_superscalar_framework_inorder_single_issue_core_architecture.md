# superScalar 框架下顺序单发射 Core 架构与微架构设计

> 文档性质：后续重写 `superScalar/rtl/core/` 的实现基线，不是当前 RTL 的描述。
> 参考输入：[`052_cva6_inorder_single_issue_core_microarchitecture.md`](./052_cva6_inorder_single_issue_core_microarchitecture.md)。
> 适配边界：保留现有 SoC、Verilator TB、FPGA 工程及 `rtl/core/myCPU.sv` 对外端口；后续删除旧 `rtl/core/` 其余实现和 `rtl/include/`。
> 核心目标：RV32 顺序单发射、顺序单提交、允许多功能单元乱序完成；做 DCache，不做 ICache。
> 日期：2026-07-13。

## 0. 结论先行

新 Core 采用六个逻辑流水阶段：

```text
S0 PC → S1 IF → S2 ID → S3 Issue/Read Operands → S4 EX/Complete → S5 Commit
```

它不是乱序发射核，也不是普通阻塞式五级流水线：每拍只检查并发射程序顺序上的第一条指令，但发射后的 load、mul/div 和整数指令可以以不同延迟完成，结果用 transaction ID 写回 8 项 scoreboard，最后只从最老项单条提交。这样不引入 rename、保留站和 wakeup/select，仍能在老 load/div 等待期间执行其后的无依赖 ALU 指令。

前端直接适配当前单口同步 IROM：不做 ICache、RVC 重对齐、ITLB 或取指 miss/replay。一个 4 项 Fetch Queue 吸收后端短暂停顿；64 项 BTB/BHT 和 8 项非投机 RAS 降低分支气泡。

数据侧采用 8 KiB、16 B line、直接映射、阻塞式 DCache。Load miss 分 4 个 32-bit word 顺序填充；store 采用 write-through、write-no-allocate。4 项 Store Buffer 把“store 已执行”与“store 已提交、允许写外部”分离，并提供按字节的 store-to-load forwarding。

所有不可回滚副作用都集中在 Commit：GPR 写入、CSR 修改、store 从 speculative 变为 committed、trap/mret redirect。外部 dmem 没有 response ID 和 cancel，因此被全流水 flush 的旧 load/miss 必须在 LSU/DCache 内部进入 kill-and-drain，迟到响应只能被丢弃，绝不能写到已复用的 scoreboard 槽位。

## 1. 设计事实、设计决定与明确假设

### 1.1 已从当前 superScalar 框架核实的事实

| 项目 | 当前事实 | 对新 Core 的约束 |
|---|---|---|
| CPU 封装 | `rtl/core/myCPU.sv` 是 `student_top` 和 rv32 Verilator DUT 的共同入口 | 保留模块名、端口名、方向和 `VERILATOR_TB` 调试端口 |
| 指令接口 | `irom_addr/irom_ena/irom_data`，无 ready、无 response valid | `irom_ena=1` 就表示请求在该上升沿被 IROM 接收；返回固定对应前一拍请求 |
| IROM | 4096×32 bit，`student_top` 使用 `irom_addr[13:2]` | 仅支持 32-bit 定长指令；复位 PC 为 `0x8000_0000`；有效窗口 16 KiB |
| 数据接口 | command `valid/ready`，read response 只有 `valid/data`，无 ID | Core 侧同一时刻最多保留一个无标签的外部 read transaction |
| DRAM | `0x8010_0000 <= addr < 0x8014_0000` | 只有该范围可缓存，排他上界不能写错 |
| MMIO | SW/KEY/SEG/LED/CNT 位于 `0x8020_xxxx` | MMIO load/store 必须不可投机、不可重复发出 |
| DRAM read | `DramBramAdapter` 的返回可能晚于 MMIO；统一由 `dmem_resp_valid` 标识 | LSU 不能假设固定一拍或固定两拍，只能等待 response valid |
| store | 外部 store 在 command handshake 当拍生效，不返回 response | store 只能在已提交后送出；完成条件是 request handshake |
| 数据对齐 | 外部桥对 store data/mask 左移，对 read data按请求地址 offset 右移 | 新 DCache 的 read 一律发 word-aligned 地址，内部统一做 offset/符号扩展；store 继续发原地址和低位对齐 raw data/mask |
| M 扩展 IP | `MUL_0` 为 33×33、3 拍；`DIV_0` 为 unsigned 32/32、34 拍，结果 `{quotient,remainder}` | 保持真实 Vivado IP 与 Verilator 行为模型的端口/延迟/打包合同 |
| 时钟复位 | Core、IROM、Dmem bridge 同属 `w_cpu_clk`；`student_top` 已做 reset 同步释放 | Core 内部只允许一个时钟域，不新增 CDC；统一使用高有效同步 `cpu_rst` |

### 1.2 本文冻结的设计决定

| 主题 | 决定 |
|---|---|
| 发射/提交宽度 | 单发射、单提交，长期退休 IPC 上界为 1 |
| 顺序性 | 顺序取指、顺序 Decode、顺序 Issue、可乱序完成、顺序 Commit |
| 在途窗口 | 8 项环形 scoreboard，允许多个相同 `rd` 在途 |
| 前端 | 4 项 Fetch Queue；64 项带 tag 的 BTB/BHT；8 项 commit-update RAS |
| ISA | RV32I + RV32M + 当前测试需要的 Zicsr/M-mode 子集；FENCE/FENCE.I |
| 不支持 | RVC、A/F/D、MMU、TLB、PMP、S/U mode、interrupt/debug、bitmanip Zb 系列 |
| DCache | 8 KiB，512 line，16 B/line，直接映射、阻塞式、load-allocate、write-through、write-no-allocate |
| Load 并发 | DCache/外部一次只处理一个 read；LSU 前放 2 项 load request queue |
| Store | 4 项 Store Buffer，执行时入队，提交后才可 drain；支持多 store 按字节合并转发 |
| 回写 | fixed completion 口 + variable completion 口；LSU 和 MDU 各自带结果保持寄存器后仲裁 |
| 精确状态 | GPR、CSR、store 批准和 trap 全部由 Commit 控制 |

### 1.3 有意不照搬 CVA6 的部分

| CVA6 机制 | 本 Core 的适配 |
|---|---|
| ICache、ITLB、取指 block、RVC realign/replay | 当前框架是单口固定一拍 IROM，删除这些层，只保留请求 metadata 和 Fetch Queue credit |
| 物理地址、DTLB、PMP | 当前没有相关端口，AGU 直接生成 32-bit 地址并做本地 cacheable/MMIO 判定 |
| 多 outstanding load + response ID | 当前 dmem response 无 ID，改为单 outstanding read + 2 项未发出 load queue |
| 复杂多端口 FU 集合 | 只保留 ALU/Branch、LSU、MUL/DIV、CSR/System |
| 可配置双提交 | 固定单提交，避免双 GPR 写口和特殊指令双副作用排序 |
| speculative RAS checkpoint | RAS 只在 Commit 更新；预测错误只影响性能，不需要恢复栈快照 |
| 多级 privilege/debug/interrupt | 仅实现当前 rv32mi/src 程序需要的 M-mode 同步异常 |

如果未来把上述 CVA6 机制直接复制进来，会增加与现有 SoC 无关的状态、端口和恢复路径，使第一版难以验证；本文只借鉴“顺序发射 + transaction-ID 完成 + 顺序提交”的架构原则。

## 2. 整机位置与模块职责

```text
Verilator rv32 harness ─────────────┐
                                    ├─ myCPU ─ core_top ─ frontend
student_top ─ IROM_0 ───────────────┤                    ├ decode/issue/scoreboard
student_top ─ SocMemBridge ─────────┘                    ├ execute/muldiv
                                                         ├ LSU/StoreBuffer/DCache
                                                         └ commit/CSR/recovery/perf
```

`myCPU` 是不可随意改变的适配壳，只负责：保持外部端口、连接 `core_top`、统一 reset 极性、导出性能计数。它不再保存流水策略或特殊 DCache index 端口。

`core_top` 只做结构化连接和少量顶层断言，不实现大段 decode、hazard、cache FSM。这样可以避免顶层成为综合关键路径和无法独立验证的“巨型模块”。

架构精确状态边界位于 Commit。Frontend、ID、Issue、执行单元中的 request、scoreboard 未提交项和 Store Buffer 未提交项都属于可撤销微架构状态。

## 3. `myCPU` 外部接口速查表

### 3.1 正式综合端口

| 信号 | 方向 | 作用 | 关键时机/依赖 |
|---|---|---|---|
| `cpu_clk` | input | Core 唯一时钟 | 所有内部状态只在其上升沿更新 |
| `cpu_rst` | input | 高有效 reset | `student_top` 已异步置位、同步释放；Core 内按同步 reset 使用 |
| `irom_addr[31:0]` | output | 当前取指 byte address | 在 `irom_ena=1` 的上升沿被 IROM 采样 |
| `irom_ena` | output | 取指请求有效 | 只有 Fetch Queue credit 足够且没有 redirect kill 时拉高 |
| `irom_data[31:0]` | input | 前一拍被接受地址的 32-bit 指令 | 必须与保存在 pending metadata 中的 PC/预测结果绑定 |
| `dmem_req_valid` | output | 数据命令有效 | 在 `valid && ready` 上升沿接受；stall 时 payload 必须稳定 |
| `dmem_req_ready` | input | 数据命令可接受 | 只表示 command 接受，不表示 load 数据已返回 |
| `dmem_req_write` | output | 1=store，0=load/refill | store handshake 即产生外部副作用 |
| `dmem_req_addr[31:0]` | output | byte address | read 使用 word-aligned 地址；store 使用原始地址 |
| `dmem_req_wdata[31:0]` | output | store 原始低位对齐数据 | SB/SH/SW 分别使用低 8/16/32 bit |
| `dmem_req_wstrb[3:0]` | output | store 原始 byte mask | SB=`0001`，SH=`0011`，SW=`1111`；由外部按地址 offset 移位 |
| `dmem_req_uncached` | output | 非缓存访问标识 | DRAM cacheable 窗口外为 1；当前 bridge 不依赖它完成译码，但保留合同 |
| `dmem_resp_valid` | input | read response 有效 | 没有 ready，DCache 必须在该拍接收或丢弃 killed response |
| `dmem_resp_rdata[31:0]` | input | read response 数据 | 因 read 地址对齐，Core 正常得到完整 aligned word |

### 3.2 Verilator 性能端口

| 端口 | 精确定义 |
|---|---|
| `dbg_perf_cycle` | reset 释放后累计的 CPU cycle |
| `dbg_perf_commit` | 成功退休的指令数；trap 的 faulting 指令不计普通 commit |
| `dbg_perf_branch` | 已执行且未被更老异常取消的 branch/JAL/JALR 数 |
| `dbg_perf_branch_miss` | EX 实际 next PC 与预测 next PC 不同的次数 |
| `dbg_perf_load/store` | 以 Commit 为准的 load/store 指令数 |
| `dbg_perf_dcache_access/miss` | cacheable DCache lookup 和 miss 次数；uncached 不计 miss |
| `dbg_perf_stall_front` | Issue 可工作但 ID/FQ 无有效指令的周期 |
| `dbg_perf_stall_mem` | 队首 memory uop 因 LSU/StoreBuffer/DCache 资源不可用而未发射的周期 |
| `dbg_perf_stall_muldiv` | 队首 M uop 因 MDU busy/回写缓冲占用而未发射的周期 |
| `dbg_perf_stall_load_use` | 队首源寄存器的最新生产者是未完成 load 时的 RAW stall 周期 |

若这些计数口继续常量 0，功能测试仍可能 PASS，但 IPC、miss 和瓶颈分析会失真，无法判断新微架构是否达到目的。

## 4. 六级流水线：一拍一个逻辑阶段

### 4.1 阶段划分

| 阶段 | 本拍组合工作 | 周期末保存的状态 | 主 stall 来源 |
|---|---|---|---|
| S0 PC | redirect 选择、BTB/BHT/RAS 查询、选择预测 next PC、生成 IROM 请求 | `fetch_pc_q`、pending fetch metadata | Fetch Queue 无 credit、redirect |
| S1 IF | 将前拍 IROM data 与 pending PC/预测信息绑定、压入 Fetch Queue | Fetch Queue entry | Queue 满；无 IROM miss |
| S2 ID | RV32 指令译码、立即数生成、非法/系统属性生成 | `id_uop_q` | Issue 不接受、flush |
| S3 Issue/RO | scoreboard 空间检查、最新 RAW 生产者选择、RF/旁路取数、FU ready 检查、分配 transaction ID | FU request、scoreboard allocation | RAW、SB full、LSU/MDU busy、serial gate |
| S4 EX/Complete | ALU/branch/AGU；变量延迟 FU 返回；结果按 ID 写 scoreboard | scoreboard done/result、LSU/MDU 状态 | variable FU 自身等待，不冻结独立 ALU |
| S5 Commit | 只观察最老 done entry；写 GPR/CSR；批准 store；处理 trap/mret/fence | 架构状态、commit pointer | 最老结果未完成、store commit/drain 条件 |

普通 ALU 的无 stall 时序：

```text
cycle       C0      C1      C2       C3           C4          C5
I0 ADD      PC  →   IF  →   ID   →   Issue/RO →   EX/WB   →   Commit
I1                  PC  →   IF   →   ID       →   Issue/RO →   EX/WB ...
```

相邻相关 ALU 不增加气泡：I0 在 C4 产生的 fixed completion 组合结果可在同一周期作为 I1 的 Issue operand bypass，并在 C4 上升沿同时完成“I0 写 scoreboard、I1 进入 EX”。

### 4.2 为什么不是旧 `PC-IF-ID-EX-MA-WB`

旧划分把 hazard、RF read、FU ready、长延迟等待和架构写回混在传统流水寄存器里，一旦 load miss 或 DIV busy，通常需要冻结一串级间寄存器。新设计把 Issue/RO 和 Commit 单独成级：

1. Issue 只负责“能否启动”和操作数快照，不承担长延迟等待。
2. scoreboard 接住不同完成时刻，年轻独立 ALU 无需跟随老 load 一起冻结。
3. Commit 成为唯一副作用边界，异常和 store 恢复不再散落在 EX/MA/WB。

若删掉独立 Commit 而让 FU 完成时直接写 GPR/store，年轻 ALU 或 store 可能越过老异常成为不可回滚状态，精确异常立即失效。

## 5. 跨级数据结构

所有结构定义在 `rtl/core/pkg/core_types_pkg.sv`，模块间用 packed struct + 独立 `valid/ready`，不依赖全局宏和隐式 interface。

### 5.1 `fetch_entry_t`

```systemverilog
typedef struct packed {
  logic [31:0] pc;
  logic [31:0] instr;
  logic        pred_taken;
  logic [31:0] pred_next_pc;
  branch_kind_e pred_kind;
} fetch_entry_t;
```

PC、指令和预测 next PC 必须作为一个整体 push/pop/flush。若只清指令 valid、未清对应预测 metadata，branch resolve 会拿另一条指令的预测目标比较，形成随机重定向。

### 5.2 `uop_t`

核心字段：

| 字段组 | 字段 | 用途 |
|---|---|---|
| 身份 | `pc/instr` | 异常 EPC、分支 link、debug |
| 寄存器 | `rs1/rs2/rd/uses_rs*/writes_rd` | RAW 和提交 |
| 操作 | `fu/op/imm/csr_addr/csr_op` | 功能单元控制 |
| memory | `mem_size/mem_unsigned/is_load/is_store` | LSU 对齐和扩展 |
| control | `pred_taken/pred_next_pc/branch_kind` | EX 预测验证 |
| system | `serialize/is_fence/is_fence_i/is_mret` | Issue/Commit 屏障 |
| early exception | `ex_valid/ex_cause/ex_tval` | 非法指令等精确异常 |

Decode 不携带动态操作数值；S3 才读取最新值。若在 ID 就锁存 RF，而没有覆盖所有后续 completion bypass，会把旧寄存器值送入 EX。

### 5.3 `scoreboard_entry_t`

```text
occupied, done
pc, instr, trans_id
fu/op, rd, writes_rd
result
exception {valid,cause,tval}
store_slot_valid/store_slot
CSR/system payload
```

`occupied` 表示槽属于一条在途指令，`done` 表示该指令已可提交，两者不能合并。Store 入 Store Buffer 后 scoreboard 可 done，但它还没有写外部；CSR entry 可已准备好但只能在 Commit 真正修改 CSR。

若把 `occupied` 和 `done` 合并，尚未完成的 load 会像空槽一样被复用，或已完成但未提交的结果会被覆盖。

### 5.4 `completion_t`

```systemverilog
typedef struct packed {
  logic                    valid;
  logic [TRANS_ID_W-1:0]   trans_id;
  logic [31:0]             result;
  exception_t              exception;
  logic                    store_slot_valid;
  logic [STORE_ID_W-1:0]   store_slot;
} completion_t;
```

所有数据、ID、异常和 store slot 必须同拍寄存。若只给 result 打一拍而 ID 没打拍，变量延迟返回会静默写错槽。

## 6. 前端微架构：无 ICache 的专用适配

### 6.1 PC 与 IROM 请求

`fetch_pc_q` 表示下一次待请求 PC。只有以下条件同时成立才拉高 `irom_ena`：

```text
!cpu_rst
&& !redirect_kill_this_cycle
&& (fetch_queue_count + fetch_pending_count < FETCH_QUEUE_DEPTH)
```

当前 IROM 不能被 backpressure，所以请求发出前必须预留一个 Queue credit。Core 同时寄存：

```text
pending_valid_q
pending_pc_q
pending_pred_taken_q
pending_pred_next_pc_q
pending_pred_kind_q
```

下一拍 `irom_data` 只与这组 pending metadata 配对。若只根据“当前 PC”给返回指令打标签，遇到 Queue stall 或 redirect 时 PC 已改变，指令与 PC 会错一拍。

### 6.2 Fetch Queue

Fetch Queue 深度固定 4，每项保存完整 `fetch_entry_t`。它的作用是：

1. 吸收 scoreboard/LSU/MDU 的短 stall，避免每个 stall 都关断 IROM。
2. 明确保存同步 IROM 返回和预测 metadata 的对应关系。
3. branch/trap redirect 时一次清除所有年轻指令。

Queue 使用 `push_valid/push_ready` 和 `pop_valid/pop_ready`。同拍 pop+push 时 count 不变；flush 优先级高于 push/pop。

### 6.3 分支预测器

第一版正式目标不是“无预测 bring-up”，而是以下小型预测器：

| 结构 | 参数 | 行为 |
|---|---|---|
| BTB/BHT | 64 项直接映射 | 保存 valid、PC tag、target、branch kind、2-bit counter |
| 条件分支 | BTB tag hit 且 counter[1]=1 时 taken | EX 按实际 taken 更新饱和计数器和 target |
| JAL | BTB hit 后无条件 taken | cold miss 顺序取，EX resolve 后建立 entry |
| JALR | BTB target；return 优先用 RAS top | EX resolve 后更新 target |
| RAS | 8 项 | call/return 只在 Commit 更新，不做投机 push/pop |

预测器只改变性能，不改变正确性。RAS 用 Commit 更新意味着在途 call 尚未提交时，紧随其后的 return 可能预测不准，但不会发生不可恢复的 speculative RAS 污染。

BTB 必须带 tag。若只有 index 没有 tag，地址别名可能把任意普通 PC 预测到别的函数，虽然 EX 最终可纠正，但会产生大量难以解释的 miss。

### 6.4 Redirect 处理

redirect 上升沿执行：

1. 清 Fetch Queue。
2. 清 `id_uop_q.valid`。
3. flush 分支中强制 `pending_valid_q<=0`，并让 flush 覆盖 response push，丢弃当前 pending IROM response。
4. `fetch_pc_q <= redirect_target`。
5. 该拍不再接受错误流新请求；下一拍从 target 请求。

IROM 请求不可取消，但它固定只有一拍延迟，所以一个 `pending_kill`/flush 优先级足够。若 redirect 时仍允许旧 response push，错误路径指令会在 Queue flush 后重新出现。

## 7. Decode 与序列化分类

Decoder 对每条 32-bit 指令输出完整 uop；不讲 SV 语法，只冻结实现责任：

| 类别 | Decode 输出重点 |
|---|---|
| OP/OP-IMM/LUI/AUIPC | ALU op、立即数、源/目的寄存器 |
| Branch/JAL/JALR | 比较类型、target 立即数、link 写回属性、预测 metadata |
| Load/Store | size、signed/unsigned、地址立即数、store data source |
| M extension | MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU |
| CSR | CSR address、write/set/clear、寄存器或 zimm source、是否真正写 CSR |
| System | ECALL、EBREAK、MRET、FENCE、FENCE.I |
| 非法 | `ex_valid=1,cause=2,tval=instr`，禁止任何功能单元副作用 |

以下指令设 `serialize=1`：CSR、ECALL、EBREAK、MRET、FENCE、FENCE.I。序列化规则是：只有 scoreboard 为空时才能分配；一旦分配，在它提交/陷入之前禁止后继 Issue。

CSR 的 `CSRRS/CSRRC` 在 source 为 x0、立即数变体 zimm=0 时不得产生 CSR write side effect，但仍要把旧值写 `rd`。若简单按 opcode 一律写 CSR，read-only CSR 探测和 rv32mi CSR 测试会出错。

## 8. Issue、RAW 和 Scoreboard

### 8.1 发射条件

ID 当前 uop 只有同时满足以下条件才在本拍 Issue：

```text
id_valid
&& scoreboard_has_free_slot
&& !global_recovery
&& !serialize_block
&& src1_ready && src2_ready
&& selected_fu_ready
&& !branch_mispredict_same_cycle
```

最后一项非常关键：branch 在 S4 resolve 的同一拍，S3 可能正准备分配预测路径下一条指令。mispredict 必须覆盖 allocation enable，保证年轻错误指令不进入 scoreboard。

### 8.2 环形槽位与 transaction ID

scoreboard 深度 8：

```text
issue_ptr_q  = 下一条分配槽
commit_ptr_q = 当前最老槽
count_q      = occupied 数量
trans_id     = issue_ptr_q
```

普通 ALU/branch/load/store/M 指令分配时 `done=0`，等待对应 completion。Decode 已确定的 illegal/ECALL/EBREAK exception，以及已经通过 serialize gate 的 CSR/MRET/FENCE 控制项，可以在分配时置 `done=1`；它们不启动普通 FU，真正 CSR、trap、redirect 或 fence 等待仍只在 Commit 发生。

若 early exception 仍向 ALU/LSU 发 request，即使最终 Commit 能 trap，也可能先产生错误 cache/MMIO/store 副作用。

允许在 scoreboard full 且本拍正常 commit 时同拍释放/分配，避免窗口满时额外气泡。next-state 更新顺序固定为：处理 commit clear → 处理 completion → 处理 allocation；若同一槽发生“老 entry commit + 新 entry allocate”，新 allocation 最终占槽。

FU request 一旦接受，必须保存 transaction ID 直到完成。若 MDU/LSU busy 时继续从变化的 Issue 总线读取 ID，结果会写到另一条指令。

### 8.3 多个相同 `rd` 与最新生产者

本设计允许：

```text
I0: x5 = ...
I1: x5 = ...
I2: x6 = x5 + 1
```

I2 必须依赖程序顺序更近的 I1。RAW 查询从 `issue_ptr-1` 开始按环形年龄向旧方向扫描，命中的第一个 occupied writer 是最新生产者，不能简单取数组最高/最低下标。

`x0` 永远不是生产者，任何 `rd=x0` 都不参与 RAW，也不在 Commit 写 RF。

### 8.4 操作数选择优先级

对已经选中的 producer ID，值来源优先级为：

```text
本拍 completion bypass
  > scoreboard[producer].done/result
  > architectural register file
```

若存在 producer 但它未 done 且本拍也无匹配 completion，则源操作数 not-ready，整条顺序 Issue stall。后面的独立指令不能越过，这正是“顺序发射”的严格定义。

### 8.5 Regfile

GPR 采用 32×32、2R1W，组合读、Commit 单写口；x0 读 0、写忽略。架构写口只来自 Commit，不允许 ALU/LSU/MDU 直接写。

允许多个 WAW 的依据是：每条消费者在 Issue 时按最新 in-flight producer 取值，最终 GPR 又按程序顺序提交。若改为 FU 完成即写 GPR，年轻写可能先覆盖，随后老写又回退最终值。

## 9. 执行与完成网络

### 9.1 ALU/Branch fixed pipe

S3 周期末锁存 `{operands,uop,trans_id}`，S4 完成：

```text
整数运算 / 比较 / shift
PC + imm 或 rs1 + imm
实际 taken 与 actual_next_pc
JAL/JALR link = pc + 4
prediction compare
```

JALR target 强制 bit0=0；由于不支持 RVC，target[1:0] 非 0 产生 instruction-address-misaligned exception。分支异常和正常结果都随同一个 transaction ID 回写。

branch resolve 在单拍 S4 完成是恢复模型的前提。若以后把 branch 拆成两拍，可能已有一条以上年轻指令进入 scoreboard，届时必须增加按年龄 squash，而不能继续使用“mispredict 只清未发射路径”的假设。

### 9.2 MDU

MDU 一次只允许一个操作在途：

- MUL 四种操作使用一个 `MUL_0` 实例，按 33-bit signed 扩展组合选择 high/low 结果，固定 3 拍。
- DIV/REM 使用一个 `DIV_0`，输入先做绝对值，34 拍后做符号恢复。
- 除零和 `INT_MIN/-1` 严格按 RISC-V 结果定义处理。
- MDU 保存 `{trans_id,op,sign,special_case,killed}`，输出进入 1 项 result hold register。

MDU busy 不冻结独立 ALU；只有下一条程序顺序指令也是 M op，或依赖未完成 M 结果时才 stall。

全流水 flush 时不能假设 Vivado DIV IP 真能取消。MDU 将当前请求标成 killed 并保持 drain 状态，等真实 `m_axis_dout_tvalid` 到达后内部丢弃，期间不接受新 M 请求。若 flush 后立刻复用旧 ID 接受新除法，34 拍后的旧结果可能污染新指令。

### 9.3 Completion 端口

scoreboard 提供两个逻辑 completion 写口：

1. `fixed_completion`：ALU/Branch，每拍最多一个，不可背压。
2. `variable_completion`：LSU result hold 与 MDU result hold 之间按最老 transaction age 仲裁，每拍最多一个。

LSU/MDU 的 hold register 允许 variable port 暂时被另一个结果占用。因为 MDU 限制单 outstanding、DCache 限制单 read outstanding，单项 hold 足以避免不可背压结果丢失。

若直接用固定优先级且没有 hold，LSU 与 DIV 同拍返回时低优先级结果会永久丢失；若永远优先 MDU，连续 M 返回还会饿死 load。

## 10. LSU、Store Buffer 与 DCache

### 10.1 总体路径

```text
Issue operands
  → S4 AGU / alignment check
  ├─ store → speculative Store Buffer → Commit mark → committed drain
  └─ load  → 2-entry Load Request Queue
              → older-store byte forwarding
              → DCache/uncached access
              → byte merge + load extend
              → LSU result hold → variable completion
```

### 10.2 对齐与异常

| 操作 | 合法条件 | 非法 cause |
|---|---|---|
| LB/LBU/SB | 任意 byte address | 无对齐异常 |
| LH/LHU/SH | `addr[0]==0` | load=4，store=6 |
| LW/SW | `addr[1:0]==0` | load=4，store=6 |

misaligned 操作只向 scoreboard 返回 exception，不进入 load queue/store buffer/DCache。若异常 store 仍分配 Store Buffer 项，Commit trap flush 时容易漏清并污染内存。

### 10.3 Store Buffer

4 项环形 Store Buffer entry：

```text
valid, committed
scoreboard trans_id
store_seq（单调模计数的 store 程序序号）
byte address
raw wdata, raw wstrb
aligned word address
aligned byte mask/data
uncached
```

生命周期：

```text
Store S4 完成
  → 分配 speculative entry，返回 store_slot 给 scoreboard，并标记指令 done
  → 指令到 Commit head，无异常
  → 对应 entry.committed=1，store 指令退休
  → buffer head 获得 DCache/外部 command handshake
  → entry 释放
```

全流水 flush 只删除 `committed=0` 的 suffix；已 committed store 必须继续排空。branch mispredict 按本架构不会有已发射的年轻 store，因此通常无需清 Store Buffer，但仍由统一 recovery 接口防御性检查 transaction age。

若 flush 清掉 committed store，会出现“指令已经退休但内存没写”；若保留 uncommitted store，错误路径或异常后的 store 会写外部。

### 10.4 Store-to-load forwarding

Load 在 AGU 入队时保存 `store_seq_cutoff=next_store_seq`。之后即使它在 Load Queue 等待、年轻 store 又进入 Store Buffer，也只扫描 `store_seq` 严格早于 cutoff 的 valid 项：

1. 将 store 规范化到 aligned word 的 4 个 byte lane。
2. 从最老到最年轻依次 overlay，保证同一 byte 最年轻 store 胜出。
3. 形成 `forward_mask[3:0]` 和 `forward_data[31:0]`。
4. 若 load 所需 byte 全覆盖，直接返回，不访问 DCache。
5. 若部分覆盖，读取 aligned word，再按 mask 合并。
6. 无覆盖则正常读 DCache。

`store_seq` 使用足够宽的模计数器，要求半个计数空间大于 Core 内可能同时跨越的全部 store 数；初值取 8 bit，最大在途远小于 128，所以 wrap 后年龄比较仍唯一。不能只在服务时扫描“当前所有 Store Buffer 项”：Load 等待期间可能已有年轻 store 入队，把年轻数据错误转发给老 load。

由于 Issue 顺序，当前 load 入队时所有更老 store 已完成 AGU 或正在其前方阻塞，故不存在“越过地址未知的老 store”。这是比乱序 LSU 简单的重要前提。

上述 forwarding 只用于 cacheable 普通内存。uncached/MMIO load 必须先等更老 store drain，再实际读取设备，不使用 Store Buffer 数据替代设备 read side effect。

若 byte merge 只取第一条匹配 store，两个 SB 分别覆盖同一 LW 的不同 byte 时会得到混合旧数据；若 youngest/oldest 覆盖顺序相反，会读到过时 store。

### 10.5 MMIO/uncached 规则

cacheable 判定：

```text
0x8010_0000 <= addr < 0x8014_0000
```

范围外均为 uncached。规则：

- uncached load 只有在其 transaction ID 等于 scoreboard commit head、所有更老 store 已 drain、DCache 无 outstanding read 时才能真正发出。
- uncached store 仍先进入 Store Buffer，只在 Commit 后 drain。
- FENCE 等待 Store Buffer empty、Load Queue empty、DCache idle。
- FENCE.I 满足上述条件后再 flush frontend；因为无 ICache，不做 cache invalidation。

这些规则会降低 MMIO IPC，但保证 LED/SEG/counter 不被重复读取或错误路径写入。若让 MMIO load 在投机阶段发出，随后更老异常 flush，它的读副作用无法撤销。

### 10.6 DCache 组织

| 参数 | 默认值 |
|---|---|
| 容量 | 8 KiB |
| line | 16 B = 4×32-bit word |
| line 数 | 512 |
| 相联度 | direct-mapped |
| index | address `[12:4]` |
| word select | address `[3:2]` |
| tag | address `[31:13]` |
| refill | critical word 不提前返回；四个 word 全填完再 replay |
| store policy | write-through、write-no-allocate；hit 时同步更新 cache byte lanes |
| outstanding | 一个 lookup/miss/uncached read/store service transaction |

采用阻塞、整 line 填完再 replay，是为了先把 request/response、flush 和 FPGA BRAM 时序做正确。critical-word-first、non-blocking miss 和多 MSHR 都留作后续，不进入第一版。

DCache FSM：

```text
DC_IDLE
  → DC_LOOKUP
      hit load  → DC_RESP
      hit/miss store → DC_STORE_REQ → IDLE
      load miss → DC_REFILL_REQ ↔ DC_REFILL_WAIT（4 words）→ DC_REPLAY
      uncached load → DC_UNC_REQ → DC_UNC_WAIT → DC_RESP
```

Tag/data array 内容不 reset，只 reset valid bits。若 reset 整个 8 KiB data array，FPGA 可能无法推断 RAM并产生大面积 reset mux；若 valid bits 不清，未初始化 tag/data 会被当成 hit。

### 10.7 DCache 与外部对齐合同

- load/refill command：`dmem_req_addr = {original_addr[31:2],2'b00}`，所以 response 是完整 aligned word；所有 offset 和符号扩展只在 LSU 做一次。
- store command：保留 original byte address、raw low-bit data 和 raw mask，让 `DramBramAdapter`/TB 完成 lane shift。
- DCache 内部 store hit 更新：使用本地计算的 aligned mask/data，不直接拿 raw mask 写 cache bank。

若 load 同时在外部和 LSU 各右移一次，LB/LH/LBU/LHU 的非零 offset 测试会失败，`srcWithMext` 的 RV32I 计数会低于 37。

### 10.8 被 flush 的外部 read

外部 read 无 cancel、无 ID。全流水 flush 时：

1. 尚未发出 command 的 load queue 项直接删除。
2. 已发出、未返回的 read 标记 `killed=1`。
3. DCache 保持 WAIT/DRAIN，直到 `dmem_resp_valid`。
4. killed response 只清 outstanding 状态，不写 cache、不产生 completion。
5. drain 完成前不发新 read，避免 response 无法归属。

这条规则是正确性硬约束，不是性能选项。若 flush 直接回到 IDLE，新 load 可能先发出，随后旧 response 被当作新 load 数据。

## 11. Commit、CSR 与精确异常

### 11.1 单提交规则

每拍只检查 `scoreboard[commit_ptr]`：

| Head 状态 | Commit 行为 |
|---|---|
| empty | 无操作 |
| occupied && !done | 等待，不允许年轻项退休 |
| done && normal result | 写 GPR（若 rd!=0），释放槽 |
| done && store | 标记 store slot committed；若接口不能接受 commit mark 则 stall |
| done && CSR | 原子读旧值/写新 CSR，旧值写 rd，释放槽 |
| done && exception | 不写 rd/store，更新 trap CSR，产生 full redirect/flush |
| done && MRET | 更新 mstatus，redirect mepc，full flush |
| done && FENCE/FENCE.I | 等待 memory quiescent，再退休；FENCE.I 触发 frontend flush |

年轻项即使早已 done，也只能等待 commit pointer。这是“乱序完成、顺序提交”的恢复点。

### 11.2 CSR 最小实现范围

| CSR | 地址 | 计划行为 |
|---|---|---|
| `mstatus` | `0x300` | 实现 MIE/MPIE/MPP 的当前测试所需字段 |
| `misa` | `0x301` | 只读常量 `0x4000_1100`：MXL=RV32，只声明 I/M，不声明 F/S/U |
| `mtvec` | `0x305` | direct mode，写入低两位清零 |
| `mscratch` | `0x340` | 普通 R/W |
| `mepc` | `0x341` | trap PC，写入按 4-byte 对齐 |
| `mcause` | `0x342` | 同步异常 cause |
| `mhartid` | `0xF14` | 只读 0 |
| `cycle/cycleh` | `0xC00/0xC80` | 只读 64-bit Core cycle counter 的低/高 32 bit |
| `instret/instreth` | `0xC02/0xC82` | 只读 64-bit 正常退休计数的低/高 32 bit；trap 指令不计 |
| `mtval` | `0x343` | 保存 illegal instruction 或 misaligned target/address；当前测试不依赖但异常合同完整 |

非白名单 CSR 第一版采用“读 0、写忽略”，但只对现有测试承诺，不宣称完整 privileged spec。对只读 counter alias 的真正写操作产生 illegal instruction；`CSRRS/CSRRC` 且 source=0 只是读，不产生非法写。

### 11.3 同步异常

| 异常 | cause | 产生位置 | 提交动作 |
|---|---:|---|---|
| instruction address misaligned | 0 | Branch/JAL/JALR EX | `mepc=branch pc`，`mtval=target`（若实现 mtval） |
| illegal instruction | 2 | Decode | `mepc=pc`，`mtval=instr` |
| breakpoint | 3 | Decode/System | `mepc=pc` |
| load address misaligned | 4 | LSU AGU | 不发 memory request |
| store address misaligned | 6 | LSU AGU | 不分配 Store Buffer |
| ecall from M-mode | 11 | Decode/System | `mepc=pc` |

外部接口没有 access-error 信号，所以第一版不能可靠产生 load/store access fault；未映射 read 由 SoC 返回 0，未映射 write 无效果。文档和实现不能虚构不存在的错误响应。

### 11.4 Trap/MRET 状态更新

Trap：

```text
mepc   <- faulting pc
mcause <- cause
MPIE   <- MIE
MIE    <- 0
MPP    <- M
pc     <- mtvec.base
```

MRET：

```text
MIE  <- MPIE
MPIE <- 1
MPP  <- 0（按实现子集处理）
pc   <- mepc
```

trap redirect 必须高于同拍年轻 branch mispredict。若 branch target 覆盖 trap vector，Core 会从错误地址继续取指，且 faulting 指令可能重复执行。

## 12. 控制流与优先级

### 12.1 全局覆盖关系

从高到低：

```text
cpu_rst
  > Commit trap
  > Commit MRET
  > Commit FENCE.I/system redirect
  > EX branch mispredict
  > predicted next PC
  > sequential PC+4
```

同一拍只允许一个 redirect source，`recovery_ctrl` 输出统一 `{valid,target,kind,full_flush}`。

### 12.2 不同 flush 范围

| 事件 | Fetch pending/FQ/ID | Scoreboard | 未提交 Store | 已提交 Store | LSU/MDU |
|---|---|---|---|---|---|
| branch mispredict | 清 | 保留；并禁止同拍年轻 allocation | 理论上无年轻已发射 store | 保留 | 老请求继续 |
| trap/MRET | 清 | 全清 | 清 | 保留并 drain | 在途请求标 killed 并 drain |
| FENCE.I | 清 | 该 serial head 正常提交后为空 | 应已满足 quiescent | 已排空 | idle |
| reset | 清 | 清 | 清 | reset 期间不承诺完成 | 清状态；外部 reset 同时复位 bridge |

branch mispredict 不能全清 scoreboard，因为其中可能有 branch 之前的老 load/ALU；全清会丢失仍应提交的正确指令。

### 12.3 `valid/ready` 的统一规则

所有内部通道遵循：

- transfer = `valid && ready`。
- `valid && !ready` 时 payload 必须稳定。
- flush 可以无视 ready 清 producer valid，但 consumer 必须同时收到同域 flush。
- 不允许 valid 组合依赖下游 ready、同时 ready 又组合依赖上游 valid 形成环。
- late-ready 的 LSU/DCache 前使用小队列或 hold register 截断长反压。

## 13. 专门提高 IPC 的设计

1. **8 项 scoreboard**：load miss/div 等待时，后继无依赖 ALU 可继续顺序发射并提前完成。
2. **completion-to-Issue 旁路**：相邻相关 ALU 保持每拍一条，不等 Commit 写 RF。
3. **4 项 Fetch Queue**：后端短 stall 不立即饿死前端。
4. **BTB/BHT/RAS 分工**：条件分支、直接/间接跳转和返回分别处理，减少控制气泡。
5. **单拍 Branch Resolve**：通常只有 IF/ID 错误流，不需要通用 branch checkpoint。
6. **2 项 load request queue**：LSU/DCache late-ready 不直接拉长 Issue→Frontend 反压。
7. **4 项 Store Buffer**：store 在执行时完成算址/保存数据，Commit 不必等待外部写；后继 load 可 forwarding。
8. **store byte merge forwarding**：栈、局部变量和 read-after-write 不必等 write-through drain。

边界必须明确：顺序 Issue 仍有 head-of-line blocking。若当前指令依赖未完成 load，后面独立指令也不能越过；这不是 bug，而是本架构用简单控制换面积/频率的核心取舍。

## 14. 专门提高频率的设计

1. **六级寄存边界**：Decode、全 scoreboard RAW、EX/AGU、Commit 不堆在一拍。
2. **小窗口而非大 ROB**：8 项全比较仍可用 flop 实现，避免 rename/free-list/wakeup/select 全局网络。
3. **统一 recovery register**：EX/Commit 只驱动小型 redirect mux，不直接组合穿过整个前端。
4. **Load Queue/结果 hold**：切断 DCache FSM late-ready 到 Issue/ID/FQ 的长组合链。
5. **DCache tag/data 分拍**：地址寄存 → RAM read → tag compare/response，不保留旧实现中复杂的多 index 组合路径。
6. **阻塞式单 outstanding DCache**：第一版不支付 MSHR、response ID、multi-port data array 的布线成本。
7. **两类 completion 口**：避免每个 FU 都直接扇出到全 scoreboard，同时不让 ALU 被 variable result 阻塞。
8. **数组不做数据 reset**：DCache 仅 reset valid，便于推断 FPGA RAM。
9. **参数固定在 package**：关键宽度用 `localparam` 派生并静态检查，避免散落宏产生不一致 mux/数组宽度。

潜在关键路径及约束：

| 路径 | 控制措施 |
|---|---|
| scoreboard 全槽 RAW → operand mux → FU ready | S3 独立一拍；深度固定 8；producer 选择用年龄编码器 |
| EX branch compare/target → PC redirect register | branch 单独小路径；redirect 只写 `fetch_pc_q`，不直穿 IROM data |
| DCache tag compare → load response | lookup 分拍、response register |
| Store Buffer 多项 byte merge | 在 load service 阶段做，不进入 S3 Issue 关键路径 |
| variable completion arbitration → scoreboard write | LSU/MDU 先进入 hold，仲裁结果寄存/定界 |

## 15. 计划文件结构与所有权

```text
rtl/core/
├── myCPU.sv                         # 保留路径和外部端口，重写内部连接
├── core_top.sv                      # 纯结构集成、顶层断言
├── pkg/
│   ├── core_config_pkg.sv           # 参数、地址范围、深度、复位 PC
│   └── core_types_pkg.sv            # enum/packed struct/辅助纯函数
├── frontend/
│   ├── frontend.sv                  # PC、pending metadata、FQ 集成
│   ├── fetch_queue.sv               # 4 项 FIFO
│   └── branch_predictor.sv           # 64 项 BTB/BHT + 8 项 RAS
├── decode/
│   ├── decoder.sv
│   └── imm_gen.sv
├── issue/
│   ├── issue_stage.sv               # 发射条件、操作数快照、FU 路由
│   ├── scoreboard.sv                # 8 项分配/完成/提交窗口
│   ├── raw_resolver.sv              # 最新生产者和旁路选择
│   └── regfile.sv                   # 2R1W GPR
├── execute/
│   ├── fixed_execute.sv             # ALU、branch、AGU 前半
│   ├── alu.sv
│   ├── branch_unit.sv
│   ├── muldiv_unit.sv               # MUL_0/DIV_0 适配、kill/drain
│   └── completion_arbiter.sv
├── memory/
│   ├── memory_unit.sv               # LSU/StoreBuffer/DCache 集成和排序
│   ├── load_queue.sv                # 2 项 load request queue
│   ├── store_buffer.sv              # 4 项 speculative/committed buffer
│   ├── dcache.sv                    # blocking direct-mapped DCache
│   └── dcache_data_bank.sv           # 可综合 RAM byte bank 模板
├── commit/
│   ├── commit_stage.sv
│   └── csr_file.sv
├── control/
│   └── recovery_ctrl.sv             # redirect/flush 唯一优先级源
├── perf/
│   └── perf_counters.sv
└── common/
    ├── fifo.sv
    └── skid_buffer.sv
```

不再建立 `rtl/include/cpu_defines.svh`。模块通过 package import 使用类型和枚举，避免 opcode/macro 在多个 include 中发生重定义或编译顺序依赖。

### 15.1 模块边界速查

| 模块 | 拥有的状态 | 不应拥有的状态 |
|---|---|---|
| frontend | PC、IROM pending、FQ、predictor | GPR、scoreboard、CSR |
| decoder | 无/仅 ID output reg | RAW、FU busy、architectural state |
| scoreboard | 在途顺序、done/result/exception | GPR、DCache line、CSR 寄存器 |
| issue_stage | 当前 ID uop 接受、operand snapshot | 长延迟 FU 生命周期 |
| muldiv_unit | 单个 M 请求和 IP latency metadata | commit pointer |
| store_buffer | store 数据、提交位、drain head | GPR/CSR、load result |
| dcache | tag/data/valid、miss FSM、外部 read ownership | architectural store commit 决策 |
| commit_stage | retirement、GPR write、store commit、trap/CSR 请求 | predictor/cache 数据阵列 |
| recovery_ctrl | redirect 优先级和 flush scope | 业务数据结果 |

若把 store 是否可写外部交给 DCache 自己猜测，DCache 将无法区分 speculative store 与 committed store；这会破坏精确异常。

## 16. 内部接口合同

### 16.1 流水通道

| 通道 | payload | ready 的含义 |
|---|---|---|
| Frontend→Decode | `fetch_entry_t` | ID 本拍能 pop 并保存 |
| Decode→Issue | `uop_t` | 所有 RAW/资源/scoreboard 条件满足并实际分配 |
| Issue→Fixed EX | `exec_req_t` | fixed pipe 输入寄存器可接收；正常应每拍 ready |
| Issue→MDU | `mdu_req_t` | MDU idle 且无 killed request drain |
| AGU→Load Queue | `mem_req_t` | queue 有空项 |
| AGU→Store Buffer | `store_req_t` | speculative tail 有空项 |
| completion→Scoreboard | `completion_t` | fixed 不背压；variable 由 arbiter grant |

### 16.2 Commit 与 Store Buffer

```text
commit_store_valid + store_slot
store_commit_ready
```

只有 handshake 后 scoreboard store head 才能释放。Store Buffer 必须验证 slot 仍 valid、未 committed、对应 transaction ID 匹配；不匹配时应 assertion fail，而不是静默忽略。

### 16.3 DCache CPU 侧

```text
req_valid/req_ready + {write,addr,wdata,wstrb,uncached}
resp_valid + {rdata,error}
kill_outstanding
idle
```

第一版 `error` 固定 0，因为外部无 access-error。`kill_outstanding` 只标记 read 结果作废，不取消已经 handshake 的 committed store。

## 17. 参数与静态约束

`core_config_pkg.sv` 初始值：

```text
XLEN=32
RESET_PC=0x8000_0000
FETCH_QUEUE_DEPTH=4
SCOREBOARD_DEPTH=8
STORE_BUFFER_DEPTH=4
LOAD_QUEUE_DEPTH=2
BTB_ENTRIES=64
RAS_DEPTH=8
DCACHE_LINE_BYTES=16
DCACHE_LINES=512
DRAM_START=0x8010_0000
DRAM_END=0x8014_0000
```

编译期检查：所有环形深度为 2 的幂；`DCACHE_LINE_BYTES==16`；`SCOREBOARD_DEPTH` 可由 transaction ID 完整编码；地址范围按排他上界；固定 RV32 不允许 XLEN 被局部 override。

参数不要泛化到尚未验证的组合。第一版可以将深度作为 package 常量，而不是对每个 module 暴露 parameter，等回归稳定后再开放 PPA 参数。

## 18. Reset、时钟与低功耗

- Core 内部只有 `cpu_clk`，不跨 `w_clk_50Mhz`；counter/display CDC 继续由 `student_top/SocMemBridge` 负责。
- `cpu_rst` 高有效，同步清所有 valid、pointer、FSM、CSR 和 perf counter。
- DCache tag/data RAM、predictor payload RAM 不逐项 reset；只清 valid 和指针。
- 空闲时对 MUL/DIV valid、DCache bank write-enable、predictor update-enable 严格门控。
- 未选 FU 的大操作数可以置零减少翻转，但不得在 branch 关键路径前增加深 mux。

若各模块混用 `rst_n` 和 `rst` 且在中间多次取反，flush/reset 优先级容易不一致；新目录统一一种极性。

## 19. 关键时序示例

### 19.1 正常相关 ALU

```text
cycle       C0   C1   C2   C3        C4                     C5
I0 ADD      PC   IF   ID   Issue     EX/fixed completion    Commit
I1 SUB           PC   IF   ID        Issue(I0 completion)   EX/WB
```

I1 在 C4 使用 I0 completion bypass，不等 C5 GPR write。

### 19.2 Load miss 后独立 ALU 提前完成

```text
I0 LW   Issue → AGU → D$ miss ........ refill/replay → completion → Commit
I1 ADD          Issue → EX/done ───────等待 I0 commit────────────→ Commit
I2 XOR                  Issue → EX/done ─────────────────────────→ Commit
```

I1/I2 的结果留在 scoreboard；它们不能提前写 GPR。若 I1 依赖 I0，I1 会在 Issue stall，I2 也不能越过。

### 19.3 Store 后 Load forwarding

```text
I0 SB [x1+1] = 0xAA → Store Buffer speculative
I1 SH [x1+2] = 0xBBBB → Store Buffer speculative
I2 LW [x1] → 扫描两项，形成 byte mask 1110
           → DCache 读原 word，仅保留 byte0
           → overlay byte1=AA、byte2/3=BB → 返回合并结果
```

Store 即使尚未 drain，Load 也能观察程序顺序上正确的新值。

### 19.4 Branch mispredict

```text
C3: branch 已 Issue
C4: branch S4 resolve，actual_next != pred_next
    - recovery_ctrl 产生 redirect
    - 屏蔽本拍 ID→Issue allocation
    - 清 pending/FQ/ID
    - 保留 branch 和所有更老 scoreboard entry
C5: 从 correct target 发 IROM request
```

若漏掉“屏蔽本拍 allocation”，一条错误路径指令会进入 scoreboard，而当前设计没有按 branch age 删除它的机制。

### 19.5 老 load 在 trap 后迟到

```text
I0 load 已发外部 read
I1 ...
Commit 发生更老同步 trap/full flush
  → scoreboard 清、load 标 killed、DCache 留在 DRAIN
  → 新 trap handler 可以继续前端取指，但新 external read 暂不发
旧 dmem_resp_valid 到达
  → 只解除 DRAIN，不更新 cache/scoreboard
  → 后续新 load 才允许发出
```

## 20. 必须写入 RTL 的不变量与断言

- [ ] `scoreboard_count <= SCOREBOARD_DEPTH`，occupied popcount 与 count 一致。
- [ ] allocation 只发生在空槽，或同拍被正常 commit 的 full-turnover 槽。
- [ ] completion 的 transaction ID 必须命中 occupied entry；killed FU 不得产生 completion。
- [ ] Commit 只释放 `commit_ptr` 且 entry.done。
- [ ] x0 永远不被写，x0 不产生 RAW producer。
- [ ] RAW 在 pointer wrap 后仍选择最新 writer。
- [ ] fixed/variable completion 同拍不得写同一 transaction ID。
- [ ] branch mispredict 同拍 `issue_fire==0`。
- [ ] frontend flush 后旧 pending response 不得 push。
- [ ] speculative store 不得驱动 `dmem_req_write`。
- [ ] committed store 在非 reset flush 后不得丢失。
- [ ] Store Buffer commit slot/transaction ID 必须匹配。
- [ ] Load forwarding 只接受 `store_seq` 早于其 cutoff 的 entry，不得看见年轻 store。
- [ ] 同一时刻最多一个 external read outstanding。
- [ ] killed read response 不得产生 DCache fill write或 LSU completion。
- [ ] `dmem_req_valid && !dmem_req_ready` 时所有 command payload 稳定。
- [ ] MMIO load 发出时必须是 scoreboard head，且 Store Buffer 无更老未 drain 项。
- [ ] misaligned store 不分配 Store Buffer，misaligned load 不访问 DCache。
- [ ] trap/mret redirect 优先级高于 branch redirect。

断言在 Verilator 下启用；FPGA 综合可通过宏关闭仅仿真断言，但不应删除对应设计条件。

## 21. 常见实现坑与自检清单

- [ ] 是否把“单发射”误写成“全核一次只能有一条指令在途”？scoreboard 应允许 8 条。
- [ ] 是否把“乱序完成”误写成“乱序提交”？GPR/CSR/store 仍只能从 head 更新。
- [ ] IROM data 是否和前一拍 pending PC 配对，而非当前 `irom_addr`？
- [ ] Queue credit 是否包含 pending IROM response，避免无 ready 返回时溢出？
- [ ] branch miss 是否禁止同拍 allocation？
- [ ] scoreboard wrap 后是否仍找最近 WAW producer？
- [ ] completion bypass 是否高于 RF 旧值？
- [ ] Load response 的 offset 是否只处理一次？
- [ ] Store raw data/mask 与 cache 内 aligned data/mask 是否分开？
- [ ] Store Buffer flush 是否只删 speculative，保留 committed？
- [ ] partial forwarding 是否能合并多条 store，并让 youngest byte 胜出？
- [ ] MMIO 是否在 Commit 顺序发出，避免 LED/SEG 重复写？
- [ ] DIV 结果是否按 `{quotient,remainder}` 解包？
- [ ] DIV flush 后是否 drain 旧 IP 结果，而不是立即复用 metadata？
- [ ] DCache miss refill response 是否与 word counter 同拍？
- [ ] DCache reset 是否只清 valid，而不是清整个 data array？
- [ ] FENCE 是否等待 committed store 真正排空？
- [ ] `sim-rv32-all` 中 Zb suite 是否被误当成 RV32IM 必须通过项？

## 22. 非目标与后续可扩展点

第一版明确不做：ICache、RVC、MMU/TLB、interrupt、debug、AMO、LR/SC、bitmanip、non-blocking DCache、多 outstanding load、双提交、乱序 Issue。

正确性和 FPGA 时序稳定后，扩展顺序建议：

1. DCache critical-word-first。
2. MUL 允许流水化多 outstanding，并增加 completion FIFO。
3. predictor 分类型计数和更好的 RAS 恢复。
4. Load queue 扩到多 outstanding；前提是外部接口增加 response ID，或在 Core 内严格维持返回顺序。
5. RVC + 指令重对齐；这会改变 PC+4、IROM packing 和 predictor index，不应局部补丁式加入。

## 23. 本架构的完成判据

后续 RTL 只有同时满足以下条件，才算实现了本文，而不是“能跑程序的另一颗核”：

1. 外部 `myCPU`/SoC/TB/FPGA 接口保持不变。
2. 六个逻辑阶段和 valid/ready/flush 行为与本文一致。
3. load/div 等待时，无依赖 ALU 能继续 Issue、完成，但仍顺序 Commit。
4. branch miss 不会把年轻错误 uop 留在 scoreboard。
5. trap 后迟到 LSU/MDU response 不污染新状态。
6. speculative store 永不写外部，committed store 永不因 flush 丢失。
7. DCache 为本文定义的 blocking write-through 结构，且没有 ICache。
8. RV32I、RV32M、rv32mi 当前支持子集、`srcSmoke`、`srcWithMext` 达到各自严格 PASS 条件。
9. 性能计数非零且含义稳定，能证明 IPC/branch/DCache/stall 行为。
10. Verilator 两个 DUT、Vivado source compile 和最终 FPGA profile 不因目录重构失联。

最终架构判断：这是一颗为当前 superScalar 教学/赛事框架定制的 **RV32 顺序单发射、乱序完成、顺序提交 Core**。它借鉴 CVA6 的 scoreboard 与精确提交思想，但用固定同步 IROM、单 outstanding 数据口、小型 DCache 和当前测试 CSR 子集替换应用级处理器的 cache/MMU/特权复杂度。
