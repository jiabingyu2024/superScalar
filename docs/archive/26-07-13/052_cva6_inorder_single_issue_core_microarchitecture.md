# CVA6 顺序单发射 Core：流水线与微架构深度分析

> 分析对象：工作区 `cva6/`，提交 `f0c274cad66b84cd58379880741680351c7ce9ab`（`v5.3.0-160-gf0c274ca`）  
> 分析边界：经典 `SuperscalarEn=0` 架构；不把 CV32A65X 的双发射扩展混入本文。  
> 参考配置：`cv64a6_imafdc_sv39_config_pkg.sv`。CVA6 高度可配置，cache、FPU、MMU、提交口数量会随配置变化。  
> 判读原则：以当前 RTL 为准；仓库中的早期 Ariane 文档若与 RTL 不一致，以 RTL 为准。

## 0. 先给结论

CVA6 是一颗 **6 级、顺序单发射、顺序提交** 的应用级 RISC-V 核。它不是乱序发射处理器，也没有保留站、物理寄存器重命名和通用 ROB；但它用一个环形 scoreboard 保存所有在途指令及其结果，使不同功能单元能够 **乱序完成/乱序回写**，再由 commit pointer 恢复为顺序提交。

它提升 IPC 的核心思路不是“从等待队列里挑别的指令发射”，而是：长延迟指令一旦成功发射，就允许其后的无依赖指令继续顺序发射；结果按 transaction ID 回到各自 scoreboard 槽位。若下一条恰好依赖尚未完成的指令，因为仍是顺序发射，后面所有指令都会被堵住。因此它的延迟隐藏能力明显强于普通 5 级顺序核，但弱于真正的 OoO 核。

经典单发射配置每拍最多发射 1 条，所以长期退休 IPC 上界仍为 1。部分配置具有 2 个 commit port，它能在长延迟造成的退休积压解除后快速排空 scoreboard，但不能把长期 IPC 提高到 1 以上。

## 1. 模块定位

顶层 [`cva6.sv`](../../../../cva6/core/cva6.sv) 连接六个逻辑流水级：`frontend → id_stage → issue_stage → ex_stage → commit_stage`，其中 frontend 内含 PC Generation 与 Instruction Fetch 两级。

主通路为：

```text
PC Gen → I$/ITLB → Fetch/Realign/InstrQueue → Decode
       → Scoreboard Allocate + Read Operands → Functional Units
       → Result + Transaction ID 回写 Scoreboard → In-order Commit
```

旁路控制通路为：

```text
EX Branch Resolve ──→ Frontend redirect / predictor update
Commit Exception  ──→ CSR trap state / Frontend trap PC
Commit fence/CSR  ──→ Controller ──→ 分级 flush、cache/TLB flush
```

这个架构的“精确状态边界”在 Commit：普通 GPR/FPR、CSR 和 store 的不可回滚效果都由提交级允许后才发生。

## 2. 六级流水线：严格按一拍一级理解

下表描述无 stall、I$ hit、普通整数 ALU 指令的概念时序。cache/MMU/乘除法会让某一级停留多拍，但不会改变六个逻辑级的划分。

| 级 | 一拍内主要工作 | 级间状态/关键寄存 | 为什么这样切 |
|---|---|---|---|
| S0 PC Gen | 选择取指 PC，发起对齐 fetch block 请求 | `npc_q` | 隔离重定向优先级和 I$ 请求路径 |
| S1 IF | 接收 I$ 返回，保存数据/地址/异常，指令重对齐、预译码分支、压入 instruction queue | `icache_*_q`、instruction FIFO | 隔离 cache 延迟并吸收前后端速率差 |
| S2 ID | RVC 解压、完整译码、形成 `scoreboard_entry_t` | `id_stage.issue_q` | 截断大译码组合逻辑，稳定送入发射级 |
| S3 Issue/RO | 分配 transaction ID，查 RAW，选择寄存器堆/旁路操作数，检查 FU ready | `fu_data_q`、各 FU `valid_q`；scoreboard 槽位分配 | 隔离寄存器堆、全 scoreboard 比较和 FU 调度路径 |
| S4 EX/WB | ALU/branch/CSR/mul/LSU/FPU 执行；结果携 transaction ID 回写对应槽位 | scoreboard `mem_q[trans_id]` | 功能单元可不同延迟、不同顺序完成 |
| S5 Commit | 只观察最老槽位；写 GPR/FPR/CSR，批准 store，产生精确异常与 flush | 架构寄存器、CSR、store commit queue | 建立唯一、精确、可回滚的架构状态边界 |

普通 ALU 指令示意：

```text
周期 C0       C1       C2       C3          C4          C5
指令 I0  PC Gen → IF/Queue → Decode → Issue/RO → EX + SB-WB → Commit
```

这里的“EX + SB-WB”表示 ALU 在 S4 组合地产生结果，周期末写入 scoreboard。Commit 在下一拍看到 `sbe.valid=1` 后更新架构状态。

## 3. 核心数据结构

### 3.1 `fetch_entry_t`

定义在 [`cva6.sv`](../../../../cva6/core/cva6.sv)，包含：

| 字段 | 语义 | 生命周期 |
|---|---|---|
| `address` | 当前指令虚拟 PC | Fetch → Decode |
| `instruction` | 32-bit 原始或待解压指令槽 | Fetch → Decode |
| `branch_predict` | 预测控制流类型和预测目标 | Fetch → Branch Unit |
| `ex` | 取指访问异常/页故障等 | 一直随指令到 Commit |

设计意图：预测信息和早期异常与指令绑定，避免 flush、变长指令重对齐后“PC/异常串槽”。

若改错：异常可能落在错误 PC 上，或分支单元拿另一条指令的预测结果，造成错误重定向。

### 3.2 `scoreboard_entry_t`

这是 CVA6 后端最核心的微操作载体，主要字段有：`pc`、`trans_id`、`fu`、`op`、`rs1/rs2/rd`、`result`、`valid`、立即数选择、异常、预测信息和压缩指令标志。

特别要注意 `result` 的复用：

- 发射前：通常保存立即数或第三源寄存器编号。
- 执行后：保存真正的执行结果。
- Commit：作为最终写回数据或 CSR/store 相关数据。

这种复用减少 scoreboard 每槽位宽度，但要求 `valid` 和 `fu/op` 严格区分当前含义。

若改错：最常见后果是立即数被当结果提交，或未完成指令被提前退休。

### 3.3 Scoreboard 不是普通记分牌，也不是完整 ROB

当前 [`scoreboard.sv`](../../../../cva6/core/scoreboard.sv) 的槽位包含：

```systemverilog
logic issued;
logic cancelled;
scoreboard_entry_t sbe;
```

并维护两个环形指针：

- `issue_pointer_q`：下一条新指令占用的槽位。
- `commit_pointer_q`：当前最老、允许提交的槽位。

它具备 ROB 的三个关键特征：保存程序顺序、缓存执行结果、顺序提交；但没有真正 OoO 调度所需的保留站和物理寄存器映射。因此更准确的工程描述是：**带结果缓存和顺序退休能力的 scoreboard/轻量 ROB 混合体**。

## 4. 前端：PC、预测、取指和队列

### 4.1 PC 选择及覆盖优先级

[`frontend.sv`](../../../../cva6/core/frontend/frontend.sv) 的 `npc_select` 先给默认/预测值，再按后续条件覆盖。按最终覆盖关系，从低到高是：

1. 当前 PC 或 reset boot PC。
2. 分支预测目标。
3. 正常顺序 fetch block 地址加一块。
4. instruction queue overflow replay。
5. EX 分支误预测重定向。
6. `eret` 的 `epc`。
7. exception/interrupt 的 trap vector。
8. Commit 侧 CSR/fence/AMO flush 后的重启 PC。
9. Debug PC。

工程上“代码中越后写优先级越高”。异常、提交副作用和 debug 必须覆盖所有投机 PC。

若把优先级改错：同拍分支误预测与异常并发时可能先取分支目标，而不是 trap vector，破坏精确异常。

### 4.2 取指粒度与变长指令

单发射模式的派生配置为 `FETCH_WIDTH=32`。启用 RVC 时，一个 32-bit fetch block 最多包含两条 16-bit 指令。`instr_realign` 负责：

- 从对齐 fetch block 中切出 16/32-bit 指令。
- 保存跨 fetch block 的半条 32-bit 指令。
- flush 时丢弃未完成半条，防止拼接新旧控制流的数据。

若删掉 incomplete-instruction 状态：跨 32-bit 边界的非压缩指令会被错误拼接或重复执行。

### 4.3 分支预测并非一个“大一统预测器”

前端并行使用：

- `instr_scan`：轻量预译码，识别 branch、JAL、JALR、call、return。
- BHT：条件分支 2-bit 饱和计数器；无有效历史时采用“后向跳转 taken、前向跳转 not-taken”的静态策略。
- BTB：为间接 JALR 保存目标；当前实现只在 JALR 误预测后更新。
- RAS：call push、return pop，预测返回目标。
- 直接 JAL：立即数目标在前端直接计算，不依赖 BTB。

当前 BHT/BTB 都以部分 PC 直接索引，存在 alias；不要引用早期文档中“必然有完整 tag”的描述，当前 `btb_prediction_t` 只有 `valid + target_address`。

若 predictor update 的 PC 索引或 RVC 行号算错：不同半字位置会互相污染，表现为重复且难定位的误预测。

### 4.4 Instruction Queue 的作用

[`instr_queue.sv`](../../../../cva6/core/frontend/instr_queue.sv) 不是一个简单单 FIFO。RVC 单发射时按 `INSTR_PER_FETCH` 分 bank，每个 instruction FIFO 深度为 4，另有深度 2 的预测目标地址 FIFO。

它完成四件事：

1. 解耦 I$/前端与后端 stall。
2. 保存 PC、指令、异常和预测信息的对应关系。
3. 预测 taken 后只保留第一条有效控制流以前的正确指令流。
4. 空间不足时不要求上游精确 credit，而是产生 `replay_addr`，从最后未接收位置重新取指。

Replay 的取舍：控制简单、能让 I$ 更积极地工作，但 overflow 时会重复取指，浪费带宽和能量。

若 replay 地址取成 fetch block 起点而非第一条未入队指令：会重复执行；若取到其后：会漏指令。

## 5. Decode：把 ISA 语义变成后端控制项

[`id_stage.sv`](../../../../cva6/core/id_stage.sv) 的单发射主路径为：

```text
InstrQueue head
  → RVC decompress
  → 可选 macro/Zcmt/CVXIF 处理
  → decoder
  → scoreboard_entry_t
  → issue_q 寄存
```

`issue_q` 是真正的 ID/Issue 流水寄存器。其 valid/ready 规则是：

- Issue acknowledge 后清除当前 valid。
- 同拍若有新 fetch entry，可直接补入，保持满吞吐。
- `flush_i` 无条件清 valid。
- 宏指令或 CV-X-IF 握手未完成时，对前端拉低 ready。

Decode 同时把取指异常、非法指令异常以及满足条件的中断编码进 `sbe.ex`。中断因此被绑定到一条具体指令，最终到达队首时才触发，保证精确性。

若 flush 只清 combinational valid 而不清 `issue_q.valid`：错误路径指令会在下一拍重新冒出并进入 scoreboard。

## 6. Issue/Read Operands：单发射核的性能核心

### 6.1 顺序发射的严格含义

每拍只检查 ID 给出的最老一条指令。它满足以下条件才发射：

- scoreboard 有空槽。
- 所需功能单元及共享回写总线可用。
- 所有 RAW 源操作数已在寄存器堆或旁路网络可获得。
- CV-X-IF 等外部握手已接受。

如果这条指令因 load-use RAW 卡住，后面的独立指令不能越过它。这是 CVA6 与真正 OoO 发射的本质差别。

### 6.2 Transaction ID：乱序完成的基础

发射时，`scoreboard` 把当前 `issue_pointer` 写入 `sbe.trans_id`。各 FU 必须原样带回这个 ID：

```text
Issue slot k
  → FU request {operands, op, trans_id=k}
  → 任意延迟
  → WB {result, exception, trans_id=k}
  → scoreboard[k]
```

因此，一个后发 ALU 可以先于早发 load 完成，二者结果不会串槽。

若 FU 丢失/错传 transaction ID：结果会写入另一条指令，属于静默数据破坏，通常直到 Commit 才暴露。

### 6.3 RAW 检查为何要找“最新生产者”

[`raw_checker.sv`](../../../../cva6/core/raw_checker.sv) 将所有有效 scoreboard 槽位的 `rd` 与当前 `rs` 比较，再结合环形 `issue_pointer` 找程序顺序上最近的生产者。

当前 RTL 允许多个同名 `rd` 在途。例如：

```text
I0: x5 = ...
I1: x5 = ...
I2: ... = x5
```

I2 必须依赖 I1，而不是 I0。transaction ID 给结果做了版本区分；顺序 commit 又确保最终架构值正确。这是一种“隐式结果命名”，但没有 rename map/free list，所以不能称为物理寄存器重命名。

若 RAW encoder 只取数组最低/最高下标，而不考虑环形指针 wrap：scoreboard 绕回后会选择旧生产者。

### 6.4 两级旁路优先级

发射级先从 scoreboard 已保存结果构造 `fwd_res`，再用“本拍 FU writeback 总线”覆盖同一 transaction ID：

```text
本拍 FU 结果 > scoreboard 中已登记结果 > 架构寄存器堆
```

这使连续相关 ALU 可以无气泡：

```text
C3: I0 Issue
C4: I0 EX/WB，同时 I1 从 WB 总线旁路并 Issue
C5: I1 EX/WB
```

注意 CSR 结果通常不能在普通发射旁路，因为 CSR 真正读取/修改架构状态要等 Commit。

若把寄存器堆优先级放到旁路之前：刚提交/刚完成值会被旧寄存器值覆盖，产生经典 RAW bug。

### 6.5 结构冲突不是 FU 数量这么简单

ALU、Branch、CSR、AES、Mul/Div 共享 fixed-latency result bus（FLU WB）。因此即使 ALU 本身空闲，也可能因为乘法即将回写或除法占用共享路径而禁止发射。

乘法器有一级流水寄存，可每拍接受乘法；Issue 必须预测下一拍的总线碰撞。串行除法延迟不定，运行时会阻塞共享 FLU 路径。

若不做“即将回写”的冲突预判：同拍两个 FU 会争同一个 scoreboard 写回口，必有一个结果丢失。

## 7. Execute：并行 FU、共享回写、不同延迟

### 7.1 ALU 与 Branch

ALU 是单拍组合单元。Branch Unit 复用 ALU 比较结果，并在同一 EX 拍内完成：

- 条件判断。
- `PC + imm` 或 `rs1 + imm` 目标计算。
- JAL/JALR link address。
- 实际 taken/target 与预测比较。
- 生成 `bp_resolve_t`，反馈 Frontend 和 Controller。

源码刻意避免在 branch 输入前再加一层 input-silencing mux，因为分支路径已经关键。单拍分支解析降低了控制冒险窗口，但 target adder + compare + prediction compare 容易成为 Fmax 限制。

若把 Branch 随意拆成两拍而不增加投机恢复容量：误预测窗口扩大，更多错误路径状态可能进入后端，现有 flush 假设会失效。

### 7.2 乘除法

- Multiply：组合乘法后接一级输出寄存，依赖综合器 retiming；可流水接受。
- Divide：串行迭代，最坏约与 XLEN 同数量级的周期；支持 flush。
- Mul 优先于 divider 输出，因为 multiplier 不能背压，而 divider 可以等待。

若把输出仲裁优先级反过来：divider 与 mul 同拍完成时，不能停住的 mul 结果会丢。

### 7.3 CSR Buffer

CSR FU 只缓存 CSR 地址/操作所需信息，真正 CSR 读改写在 Commit 发生。这样可以保证 CSR 副作用严格按程序顺序发生。

代价是 CSR buffer 很浅，连续 CSR 会形成结构 stall；但 CSR 通常低频，设计选择面积和简单性优先。

### 7.4 共享结果总线的取舍

共享 FLU WB 减少 scoreboard 写端口、宽 mux、布线和功耗，非常利于频率/面积；代价是 Issue 需要复杂的提前冲突判断，并降低某些 FU 组合的并行性。

这是 CVA6 很典型的工程取向：**保留多 FU 的延迟解耦，不支付“每 FU 一个全宽回写口”的成本。**

## 8. LSU：高频与精确状态最集中的模块

### 8.1 总体数据流

```text
Issue operands
  → AGU: rs1 + imm，生成 VA/byte-enable
  → lsu_bypass
  → Load Unit 或 Store Unit
  → DTLB/PMP + D$
  → {result/exception, trans_id}
  → 可配置 return pipeline regs
  → Scoreboard WB
```

### 8.2 `lsu_bypass` 为什么存在

LSU 是否真正能接受请求，可能要等到很晚才能知道：地址加法、DTLB、store-buffer alias 和 D$ grant 都参与。若把最终 ready 直接组合回 Issue，会形成一条跨越大半个 core 的长反压路径。

[`lsu_bypass.sv`](../../../../cva6/core/lsu_bypass.sv) 用小型两项存储把 Issue 的 ready 与 LSU 内部晚到决策解耦。空时可 bypass，阻塞时保存请求。

若删掉：`LSU ready → Issue hazard → ID ready → InstrQueue` 很可能成为频率关键路径；若 FIFO 深度/计数错：会覆盖尚未完成的访存请求。

### 8.3 Load：VIPT 风格的 index/tag 分拍

Load Unit 先用 VA page offset/index 向 D$ 发请求，同时做 DTLB；下一拍再给物理 tag。TLB hit 时，地址翻译延迟与 cache data-array 访问重叠。

若 TLB miss：杀掉已发出的 cache 请求，让 PTW 完成翻译，随后重放。若翻译异常：kill request，只把异常携 transaction ID 回写 scoreboard。

这条路径把：

```text
AGU → DTLB → D$ index/tag compare → data return
```

拆开，避免全塞在一拍。经典 CV64 配置还设置 `NrLoadPipeRegs=1`，在 LSU 返回到 scoreboard 前再打一拍，以频率换 load-use 延迟。

### 8.4 Load Buffer 与多个 outstanding load

Load 发出后把 `{trans_id, address offset, operation}` 保存到 load buffer，D$ response 携 `data_id` 找回对应项。不同 load 可在途，其完成顺序由 response ID 归位。

这能在 cache 系统允许时提高 memory-level parallelism；但 Issue 仍顺序，若第一条等待数据的 load 是后继指令的数据源，流水会因 RAW 堵住。

若 response ID 和 load-buffer index 不一致：数据会用错误的 sign extension/offset 写到错误指令。

### 8.5 Store：两级队列保证精确状态

Store Buffer 分为：

1. speculative queue：地址翻译和数据准备完成，但指令尚未提交。
2. commit queue：Commit 已批准，必然要写入 memory hierarchy。

流程：

```text
Store EX 完成 → speculative queue
Store 到 scoreboard 队首且无异常 → Commit 发 lsu_commit
→ 移入 commit queue → D$ grant 后按序写出
```

全流水 flush 只清 speculative queue；commit queue 中的 store 已是架构状态，必须继续排空。

若 flush 同时清 commit queue：已经退休的 store 会丢失；若错误保留 speculative queue：错误路径 store 会污染内存。

### 8.6 Store-to-load 相关采用保守阻塞

当前实现没有完整 store-to-load forwarding。Load 的 page offset `[11:3]` 与 speculative/commit 两个 store queue 全比较，只要匹配就等待 store 排空。

优点：无需等待完整物理地址，也不需要复杂 byte merge；比较位数短。缺点：不同物理页但相同 page offset 会假相关，且同一个 8-byte 区域的不同字节也可能保守阻塞。

这是明显的 IPC 优化空间，但增加 forwarding 时必须处理：最年轻 store 选择、部分字节覆盖、多 store 合并、异常 store 取消和端序。

## 9. Commit：精确状态和顺序退休

Scoreboard 只把 `commit_pointer` 指向的最老项暴露给 [`commit_stage.sv`](../../../../cva6/core/commit_stage.sv)。只有 `sbe.valid` 才表示执行完成。

Commit 行为：

| 指令类别 | 提交动作 | 可能阻塞原因 |
|---|---|---|
| ALU/Mul/Load | 写 GPR/FPR | 队首结果未完成 |
| Store | 通知 LSU 把最老 speculative store 转为 committed | commit queue 满 |
| CSR | 真正读写 CSR，并把 CSR 旧值写 rd | CSR 访问异常 |
| Fence/SFence | 等 store/write buffer 排空，再 flush cache/TLB/pipeline | 尚有 store 在途 |
| AMO | 在 commit 点执行/等待原子响应，完成后全流水 flush | cache/AMO response 未到 |
| Exception | 不写架构结果，更新 trap CSR，重定向 trap vector | 无；必须精确处理 |

部分单发射配置有两个 commit port。第二口只能退休无特殊副作用的类别，不能越过第一口，也不能提交 store/CSR/AMO 等复杂指令。它主要用于释放长延迟之后积压的已完成项。

若允许 port1 在 port0 未提交时提交：程序顺序被破坏；若允许 port1 提交 CSR/store：需要额外解决双副作用排序和异常优先级，当前 RTL 没有该合同。

## 10. 控制流、Flush 与覆盖关系

### 10.1 三种不同范围的清除

不能把所有 `flush` 理解成同一个动作：

| 事件 | Frontend/ID | 未发射项 | Scoreboard 已发射项 | LSU speculative store | committed store |
|---|---|---|---|---|---|
| Branch mispredict | 清 | 阻止/清 | 单发射下错误后继不会成功进入 | 无错误 store 进入 | 保留 |
| Exception/eret/debug | 清 | 清 | 全清 | 清 | 保留并继续排空 |
| CSR side effect/AMO | 清并从 commit PC 后重启 | 清 | 全清 | 清 | 保留 |
| Fence/SFence | 清 | 清 | 全清 | 先等待满足顺序条件 | 已提交写完成/排空 |

单发射分支在 S4 解析。同拍 Issue 可能正在组合检查下一条，但误预测信号经 controller 产生 `flush_unissued_instr`，scoreboard 在时钟沿禁止其入队，Issue/EX valid 也被清。因此不需要保存任意深度的分支 checkpoint。

### 10.2 Controller 的覆盖关系

[`controller.sv`](../../../../cva6/core/controller.sv) 是组合 flush 生成器，后写条件会覆盖或叠加前面的控制：

- mispredict：只清 IF 和未发射路径。
- fence/CSR：增加 ID、EX、cache/TLB 清除及 commit PC 重启。
- exception/eret/debug：最后覆盖 `set_pc_commit`，因为 Frontend 应使用 trap/epc/debug PC，而非普通 commit PC。

D$ flush 信号专门寄存一拍，因为它可能是长时序路径；fence active 状态保持 halt，直到 cache acknowledge。

若对 mispredict 直接全清 scoreboard：虽然可能功能正确，但会丢掉分支之前仍在途的老指令，无法恢复；若不清未发射路径：错误后继会占 scoreboard 槽位。

## 11. 三个关键时序示例

### 11.1 正常 ALU + RAW 旁路

```text
周期       C0       C1       C2       C3          C4             C5       C6
I0 ADD     PC       IF       ID       Issue       EX/WB          Commit
I1 SUB              PC       IF       ID           Issue(fwd)     EX/WB    Commit
```

I1 在 C4 不等 I0 写回架构寄存器，而是直接使用 C4 的 FU WB 数据。故相关 ALU 可一拍一发射。

### 11.2 Load miss 后，独立 ALU 越过完成但不能越过提交

```text
I0 LOAD:  Issue → D$ miss ..................... → WB → Commit
I1 ADD :          Issue → EX/WB ───────────────等待──→ Commit
I2 ADD :                  Issue → EX/WB ───────等待──→ Commit
```

I1/I2 可在 I0 等待期间完成，结果存于各自 scoreboard 槽位；commit pointer 卡在 I0，故它们不能提前改变架构状态。这就是 CVA6 隐藏 load latency 的核心。

若 I1 依赖 I0，则 I1 在 Issue 处 stall，I2 即使独立也不能越过 I1；这是顺序发射的主要 IPC 限制。

### 11.3 分支误预测

```text
C3：Branch 在 Issue 发射
C4：Branch Unit 计算实际 taken/target，发现 mispredict
    → Frontend kill 当前 I$ 请求/清 InstrQueue
    → ID issue_q 清除
    → 本拍下一条错误指令禁止进入 scoreboard/EX
    → npc 选择正确 target，更新 BHT 或 BTB
C5+：从正确 target 重新填充 PC Gen、IF、ID、Issue
```

Branch 之前的老指令保留并继续顺序提交；Branch 自己正常把 link/result 写回；Branch 之后的未发射错误流被丢弃。

## 12. 专门提升 IPC 的微架构设计

### 12.1 Scoreboard 容纳多个在途指令

参考配置为 8 项。长延迟 load/div 不必冻结整个后端；只要下一条无 RAW 且 FU 可用，就继续发射。

边界：深度越大，全槽位 RAW 比较、mux 和布线越重；顺序发射也使过深 scoreboard 收益递减。

### 12.2 当前 WB 到 Issue 的直接旁路

把结果产生到消费者发射间隔压到 0 个气泡，是整数代码维持接近 IPC 1 的必要条件。

### 12.3 前后端 instruction queue 解耦

I$ 暂时抖动和后端短 stall 可被 FIFO 吸收；前端能提前积累多条 RVC 指令。

### 12.4 BHT + BTB + RAS + 静态后向 taken

分别覆盖条件分支、间接跳转和函数返回，避免用一个巨大预测结构拉长 PC 路径。

### 12.5 单拍 Branch Resolve

分支在 Issue 后下一拍即解析，使错误路径通常只存在于尚未分配的前端/ID 状态，不需要复杂 checkpoint。

### 12.6 Load buffer 与 store buffer

Load 可以在途，store 可以提前算址/翻译/缓存，但到 Commit 才变为不可撤销；访存延迟和精确状态同时兼顾。

### 12.7 可配置双提交

不能提高单发射稳态上界，但能在队首长延迟解除后更快释放 scoreboard，减少“scoreboard full 反压 Issue”的尾部效应。

## 13. 专门提升频率的微架构设计

### 13.1 六级切分与明确寄存边界

Decode 后 `issue_q`、Issue 后 `fu_data_q/FU valid_q`、Execute 后 scoreboard result state，把译码、全局相关检查、执行三段重逻辑拆开。

### 13.2 LSU late-ready 解耦

`lsu_bypass` 切断 DTLB/store alias/D$ grant 到 Issue 的长组合反压链。

### 13.3 VIPT 重叠和 tag 分拍

VA index 与 DTLB 并行，物理 tag 下一拍提供；TLB hit 时不额外损失吞吐，却显著缩短单拍逻辑深度。

### 13.4 可配置 Load/Store 返回寄存

`NrLoadPipeRegs`、`NrStorePipeRegs` 是显式 PPA 旋钮：增加寄存提高 Fmax，但增加 load-use 延迟和 scoreboard 占用时间。

### 13.5 共享 WB 口

减少 scoreboard 多写口面积、宽 mux 和全局布线；代价是 Issue 的结构冲突更严格。

### 13.6 乘法器寄存与 retiming

乘法不要求一拍穿过完整乘积阵列；输出寄存允许综合器重定时，换取高频和每拍吞吐。

### 13.7 ASIC/FPGA 分实现

- BHT/BTB：ASIC 可用 flop/异步读，FPGA 使用同步 RAM/BRAM 路径。
- GPR：ASIC flop regfile 组合读；FPGA 复制 RAM 以实现多写口，并记录“哪个副本持有最新值”。
- Instruction FIFO：ASIC 仅在 push 时更新存储阵列，降低无效翻转；FPGA 映射 RAM。

### 13.8 Input silencing

EX 对未选 FU 输入置零，减少无关大逻辑翻转和动态功耗；Branch Unit 例外，因为在其关键输入前增加 mux 可能伤害 Fmax。这体现了功耗与时序的局部权衡。

## 14. 已知 IPC 与频率瓶颈

| 瓶颈 | 原因 | 典型表现 | 优化风险 |
|---|---|---|---|
| 顺序发射 head-of-line blocking | 依赖指令阻塞所有后继 | load-use 后大量空发射拍 | 引入 OoO issue 会要求 wakeup/select、rename/ROB 重构 |
| Store→Load 无 forwarding | page offset 命中即等 store drain | memcpy、栈访问受限 | byte merge 和异常恢复复杂 |
| 分支 EX 路径关键 | compare + target add + predictor compare | Fmax 或误预测代价 | 拆拍会扩大恢复窗口 |
| 全 scoreboard RAW compare | 每源寄存器并行比较全部槽 | 深度增大后 Issue 关键 | 分层/分 bank 会增加选择逻辑 |
| FLU 共享 WB | 多 FU 共用一口 | mul 回写前限制 ALU/branch/CSR | 加 WB 口增加面积、布线和 SB 写冲突 |
| CSR/序列化操作 | 只在 Commit 做副作用 | 连续 CSR/fence stall | 提前执行需要严格回滚 |
| 非幂等 load 序列化 | 必须等到 commit 次序且排空 store | MMIO load 高延迟 | 放宽会造成重复外设读副作用 |
| Load return pipeline | 为 Fmax 多打一拍 | load-use penalty 增加 | 去寄存可能导致 LSU→SB 关键路径失败 |

## 15. 关键代码模式与“改错会怎样”

### 15.1 按 transaction ID 回写

```systemverilog
if (wt_valid_i[i] && mem_q[trans_id_i[i]].issued) begin
  mem_n[trans_id_i[i]].sbe.valid  = 1'b1;
  mem_n[trans_id_i[i]].sbe.result = wbdata_i[i];
end
```

为什么：FU 可变延迟、可乱序完成，不能按“当前队首”写结果。  
改错后：load、mul、ALU 并行时结果串槽。

### 15.2 Flush 时只删除可撤销状态

```systemverilog
if (flush_i) begin
  speculative_status_cnt_n = '0;
  // committed store queue 不清
end
```

为什么：speculative store 尚未成为架构状态，committed store 已经退休。  
改错后：前者保留会错误写内存，后者清除会丢已提交写。

### 15.3 Load 返回路径参数化打拍

```systemverilog
shift_reg #(.Depth(CVA6Cfg.NrLoadPipeRegs)) i_pipe_reg_load (...);
```

为什么：同一 RTL 可面向不同工艺/FPGA选择 Fmax 或 load-use latency。  
改错后：transaction ID、result、exception 若未作为整体同拍，会发生元数据错位。

### 15.4 Commit 只消费最老项

```systemverilog
commit_instr_o[i] = mem_q[commit_pointer_q[i]].sbe;
```

为什么：乱序完成必须在此重新排序。  
改错后：年轻异常/结果可能越过老指令，精确异常与顺序内存语义失效。

## 16. 可直接复用的设计模式

1. **统一 uop/scoreboard entry**：PC、FU、op、寄存器号、结果、异常、预测信息全程同槽携带。
2. **transaction ID 回写**：所有可变延迟 FU 请求与响应都带 ID，禁止依赖返回顺序。
3. **唯一 Commit 副作用点**：GPR/CSR/store 的不可撤销更新集中批准。
4. **speculative/committed 双 store queue**：执行与架构可见性解耦。
5. **WB 优先的 operand bypass**：当前 FU 结果覆盖 scoreboard 旧快照，再覆盖 regfile。
6. **小 FIFO 切断 late-ready**：尤其适用于 LSU、cache、coprocessor 接口。
7. **flush 分域**：误预测局部清、异常全后端清、已提交状态永不清。
8. **PPA 参数化打拍**：数据、ID、异常和 valid 必须一起进入 shift register。

## 17. 常见坑与自检清单

- [ ] 是否明确区分“顺序发射”和“乱序完成”，没有误称为 OoO issue？
- [ ] 所有 FU response 是否携带并保持正确 `trans_id`？
- [ ] 环形 scoreboard wrap 后，RAW 是否仍选择最新生产者？
- [ ] 当前拍 WB 是否优先于 scoreboard 和 regfile 旧值？
- [ ] `x0` 是否从 RAW 检查和实际写回中排除？
- [ ] `valid`、`issued`、`cancelled` 是否分别表达“完成”“占槽”“丢弃”？
- [ ] branch mispredict 是否只清年轻状态，没有误清分支之前的老指令？
- [ ] exception flush 是否清除所有未提交 store，同时保留 committed store？
- [ ] store commit queue 满时，Commit 是否真正反压而非丢 store？
- [ ] load cache kill、TLB miss replay、flush 后迟到 response 是否会被过滤？
- [ ] 数据返回打拍时，result/exception/ID/valid 是否严格对齐？
- [ ] 非幂等 load 是否等到 commit 次序且排空相关写缓冲？
- [ ] 两个 commit port 同写一个 rd 时，年轻 port 是否最终胜出？
- [ ] fence/CSR/exception 同拍时，PC 重定向优先级是否符合架构语义？

## 18. 最小实践任务：手写一个简化 CVA6 后端

目标：实现 **RV32I、单发射、4 项 scoreboard、顺序提交、ALU + 3-cycle Load** 的简化核后端；不做 MMU、cache、store、CSR、分支预测和异常嵌套。

### 功能边界

- 每拍最多接收/发射 1 条已译码 uop。
- ALU 延迟 1 拍，Load 固定延迟 3 拍。
- ALU 与 Load 各有独立 response port，均返回 transaction ID。
- 允许 Load 等待期间继续发射无依赖 ALU。
- 支持 scoreboard/result 和当拍 WB 到 Issue 的旁路。
- 始终只按 commit pointer 写架构寄存器。

### 实现步骤

1. 定义 `uop_t`：`pc, fu, rs1, rs2, rd, imm, trans_id, result, done, exception`。
2. 写 4 项环形 scoreboard：`issue_ptr, commit_ptr, occupied[3:0]`。
3. 发射时扫描全部 occupied 槽，查 rs1/rs2 的最新生产者；先不允许多个同名 rd，以降低第一版难度。
4. 加 regfile 和三层 operand mux：`WB > SB result > RF`。
5. ALU request 后一拍返回；Load 用 3 级 shift register 传 `{valid,id,data}`。
6. response 按 ID 更新 scoreboard 槽的 `done/result`。
7. commit 只检查 `scoreboard[commit_ptr]`，完成后写 rd、释放槽位、指针加一。
8. 最后增加 flush：清全部 occupied，但保留架构 regfile。

### 必测序列

```text
1) ADD x1,... ; SUB x2,x1,...                 // 当拍 WB 旁路
2) LOAD x1 ; ADD x2(独立) ; ADD x3(独立)     // 乱序完成、顺序提交
3) LOAD x1 ; ADD x2,x1 ; ADD x3(独立)        // 顺序发射头阻塞
4) scoreboard 指针绕回两次                  // 环形相关检查
5) load response 与 ALU response 同拍         // 多 WB 口和 ID 正确性
6) load 在途时 flush，随后迟到 response        // 不能污染新分配槽
```

完成判据：波形中能清楚看到 I1/I2 先于老 load 完成，但 commit pointer 始终按程序顺序移动；flush 后迟到 load response 因目标槽 `occupied=0` 被丢弃。

## 19. 联动源码索引

| 主题 | 首要文件 |
|---|---|
| 顶层连接、核心类型 | [`cva6/core/cva6.sv`](../../../../cva6/core/cva6.sv) |
| 配置派生 | [`cva6/core/include/build_config_pkg.sv`](../../../../cva6/core/include/build_config_pkg.sv) |
| 参考单发射配置 | [`cva6/core/include/cv64a6_imafdc_sv39_config_pkg.sv`](../../../../cva6/core/include/cv64a6_imafdc_sv39_config_pkg.sv) |
| PC、预测、fetch | [`cva6/core/frontend/frontend.sv`](../../../../cva6/core/frontend/frontend.sv) |
| 指令队列/replay | [`cva6/core/frontend/instr_queue.sv`](../../../../cva6/core/frontend/instr_queue.sv) |
| Decode 与 ID/Issue 寄存 | [`cva6/core/id_stage.sv`](../../../../cva6/core/id_stage.sv) |
| Scoreboard | [`cva6/core/scoreboard.sv`](../../../../cva6/core/scoreboard.sv) |
| 发射、RAW、旁路、regfile | [`cva6/core/issue_read_operands.sv`](../../../../cva6/core/issue_read_operands.sv)、[`raw_checker.sv`](../../../../cva6/core/raw_checker.sv) |
| FU 集成/共享 WB | [`cva6/core/ex_stage.sv`](../../../../cva6/core/ex_stage.sv) |
| 分支解析 | [`cva6/core/branch_unit.sv`](../../../../cva6/core/branch_unit.sv) |
| LSU 总体 | [`cva6/core/load_store_unit.sv`](../../../../cva6/core/load_store_unit.sv) |
| Load/Store/Buffer | [`load_unit.sv`](../../../../cva6/core/load_unit.sv)、[`store_unit.sv`](../../../../cva6/core/store_unit.sv)、[`store_buffer.sv`](../../../../cva6/core/store_buffer.sv) |
| Commit/精确异常 | [`cva6/core/commit_stage.sv`](../../../../cva6/core/commit_stage.sv) |
| Flush 控制 | [`cva6/core/controller.sv`](../../../../cva6/core/controller.sv) |

## 20. 最后一句架构判断

CVA6 单发射后端的本质不是“六级普通顺序流水线加一个记分牌”，而是：**以顺序 Issue 保持控制简单，以 transaction-ID scoreboard 吸收多 FU 的可变延迟和乱序完成，再以唯一 Commit 点恢复精确架构状态。** 它把真正 OoO 核最昂贵的 rename、wakeup/select 和大 ROB 去掉，换取较高频率与较低面积，同时保留了对 cache/load/mul/div 延迟的一部分隐藏能力。
