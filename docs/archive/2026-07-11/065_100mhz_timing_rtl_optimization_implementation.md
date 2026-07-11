# 100 MHz 时序 RTL 优化实施与验证记录

> 日期：2026-07-11  
> 时序诊断来源：`061_vivado_100mhz_timing_baseline`  
> routed 报告版本：`4762e00314f73810344185077f002c4c7db0dea6`  
> 实施时工作树基线：`78f41bbe0dd0fc799dc16d37feea38b0875d8e20`  
> 初始批次约束：按用户要求不启动 Vivado，仅做 RTL、Verilator 与软件负载验证

> **当前证据边界（23:08 增补）**：第 11～16 节记录了随后实施的 issue elastic
> stage、ROB completion 字段分组、dispatch ring FIFO 和 recovery payload CE 清理。
> 这些修改之后按用户要求未编译、未仿真、未调用 Vivado；第 7 节回归数据只属于
> 四项增补修改之前的 RTL，不可作为当前工作树的验证结果。

## 1. 结论与证据边界

本轮已对旧 routed 报告中覆盖 94.16% 失败 endpoint 的三个主路径族，以及 BPU/PC
次级路径做了结构性修复：

1. execute completion/writeback 增加固定吞吐寄存边界，PRF write 与 completion 对齐；
2. rename 后增加 4-entry allocated dispatch buffer，ROB 与 IQ 不再同拍接收 sRAT
   组合 payload；
3. ROB 增加 2-wide retire stage，Commit/recovery 不再由 `head_q` 经过 32-entry
   动态 mux 直接驱动全核；
4. BPU 采用单级 gshare direction lookup，并把 PHT/BTB RMW 写入再寄存一级。

最终功能回归：RV32MI 4/4、RV32UI 40/40、RV32UM 8/8 全部 PASS，`srcSmoke`
PASS。`srcWithMext` 在 500k 和 50M 固定周期窗口内均无 fail marker，RV32I
37/37、M 扩展 8/8、fail counter=0。

但本轮没有运行综合、布局或布线，所以只能确认“RTL 已建立预期时序边界”，不能
宣称 100 MHz 已通过。最终判据仍是当前工作树生成的新 routed DCP 中 CPU setup
`WNS >= 0`、`TNS = 0`、failing endpoints `= 0`。

## 2. 基线违例与实施映射

| 旧 routed 路径族 | 失败 endpoint | 旧最差 slack | 本轮 RTL 处理 | 新 routed 必查 |
| --- | ---: | ---: | --- | --- |
| `complete_prd` → IQ/PRF/execute/PRF | 5,139 | -4.495 ns | registered WB、全读口 bypass、early wakeup | 旧 `complete_prd_reg` 源点应消失；PRF WE/WADDR/WDATA 起点应为 `wb_*_q` |
| `srat_q` → ROB/INT/MEM/MUL IQ | 20,145 | -4.472 ns | 4-entry allocated dispatch buffer；ROB index 在 dequeue 原子分配 | ROB/IQ payload 起点应为 `dispatch_buffer_entry_q`，不再是 `srat_q` |
| `ROB head_q` → recovery/DCache/DRAM/queues | 19,478 | -3.820 ns | 2-wide retire stage，Commit 只读 stage 寄存器 | `head_q` 只能到 retire-stage D，不应再直接到 DCache、DRAM 或 broad clear |
| BPU `update_pc_q` → PHT/BTB | 2,075 | -1.752 ns | table-update RMW bundle，写阵列只由 bundle 寄存器驱动 | PHT/BTB 写地址和写数据起点应为 `table_update_*_q` |
| PC → BPU → PCGen | 138 | -3.504 ns | tournament 三表串联改为单 gshare direction lookup | 重新检查 PC feedback levels、WNS 与 BPU 资源/拥塞 |

旧报告绑定提交 `4762e003`，而本轮 RTL 基于后续工作树继续修改。上表的“应消失”
是网表拓扑验收目标，不是已经得到的新 Vivado 证据。

## 3. 修改一：execute/writeback 时序切分

### 3.1 修改文件

- `rtl/core/execute/ExecuteCluster.sv`
- `rtl/core/backend/CoreBackend.sv`

备份：

- `backup/20260711_201714/ExecuteCluster.sv`
- `backup/20260711_203654/ExecuteCluster.sv`
- `backup/20260711_203654/CoreBackend.sv`

### 3.2 修改前后数据流

修改前：

```text
completion wakeup
→ IQ ready/select
→ PRF async read
→ ALU/AGU/exception
→ PRF write decode + completion
```

修改后：

```text
execution result
→ wb_*_d
→ [wb_*_q]
→ PRF WE/WADDR/WDATA + backend completion
```

`wb_valid_q` 独立承担 reset/flush 可见性；宽 payload 不挂异步 reset。每个执行槽
仍可每拍产生一个 WB，吞吐没有被单槽 busy handshake 限制。

### 3.3 唤醒与数据可见性

仅把 PRF 写打一拍会造成“消费者已唤醒但 PRF 仍是旧值”。本轮同时实现：

- IQ/Dispatch 使用 registered `exec_complete_*` 做 early wakeup；
- 所有 PRF 读口经 `prf_rdata_effective` 比较 `wb_valid_q/wb_prd_q`；
- 命中同拍 WB 时直接转发 `wb_result_q`；
- ROB、BusyTable、StoreBuffer 与 PRF 写入看到同一 completion 时刻；
- 删除 backend 的第二级 `complete_*` 寄存，避免无意义多一拍和 IPC 损失。

若删掉全读口 bypass，会出现依赖指令读取旧 PRF；若 PRF write 与 completion valid
错位，会出现幽灵唤醒或 ROB 永久等待。Verilator assertion 已检查 PRF write 与
completion 对齐。

### 3.4 A/B 性能

| 版本 | `srcSmoke` cycles | IPC | 结论 |
| --- | ---: | ---: | --- |
| 本轮修改前工作树 | 33,087,618 | 0.929610 | 参考点 |
| 仅 registered WB | 37,962,639 | 0.810234 | 依赖链多等一拍，不接受 |
| early wakeup + bypass，保留 backend 二级 completion | 36,440,915 | 0.844068 | 有改善，仍有冗余延迟 |
| 删除 backend 二级 completion | 33,087,618 | 0.929610 | 恢复参考性能，最终保留 |

## 4. 修改二：allocated dispatch buffer

### 4.1 修改文件与备份

- 修改：`rtl/core/backend/CoreBackend.sv`
- 备份：`backup/20260711_205339/CoreBackend.sv`

### 4.2 所有权模型

buffer 深度为 4，双入双出，存储完整 `CoreRenamedUop`：

```text
decode
→ rename/free-list/sRAT
→ [dispatch_buffer_entry_q]
→ ROB allocation + Dispatch acceptance（同一个原子事件）
→ INT/MEM/MUL IQ
```

关键契约：

- enqueue 边沿分配 PRD、更新 sRAT，并由 buffer 接管 uop；
- ROB index 不在 rename 组合周期消费，而在 buffer dequeue 时生成并写回 uop；
- ROB allocation、目标 IQ acceptance、buffer pop 必须同拍同时成立；
- lane1 只有 lane0 已 fire 才能被 offer，保持 program-order prefix；
- recovery 清 count/valid，FreeList 按 ARAT 重建，buffer 中的 speculative PRD 被回收；
- serial 指令只有 ROB 与 dispatch buffer 都为空时才能 enqueue。

如果只注册 payload、不转移资源所有权，会产生 PRD 泄漏、ROB index 重用或 IQ 已收
但 ROB 未分配。本实现通过 `rename_alloc_valid` 与 `rob_alloc_valid` 分离了“buffer
取得所有权”和“ROB/IQ 取得所有权”。

### 4.3 等待期间 wakeup

buffer entry 可能因 ROB/IQ backpressure 停留多拍。completion 是单周期 pulse，
所以每拍都将匹配的 `exec_complete_prd` 累积进 entry 的 `src1_ready/src2_ready`；
enqueue 同拍也做一次匹配。否则依赖完成发生在等待期间时，uop 会永久保持 not-ready。

### 4.4 验证点

assertion 覆盖：

- enqueue lane prefix；
- dequeue lane prefix；
- count 不超过深度；
- ROB allocation 与 buffer pop 所有权一致；
- dispatch uop 的 ROB index 与本拍 `rob_alloc_idx` 一致。

该边界单独加入后，`srcSmoke` 为 36,383,487 cycles、IPC 0.8454，功能 PASS。

## 5. 修改三：ROB retire stage 与 recovery 隔离

### 5.1 修改文件与备份

- 修改：`rtl/core/dispatch/ROB.sv`
- 备份：`backup/20260711_210815/ROB.sv`

### 5.2 为什么不直接寄存 recovery

若简单把 `recover_valid` 延后一拍，错误路径 load/MMIO/store 可能在 recovery pending
窗口产生可见副作用。此次选择寄存 Commit 的输入，而不是寄存 recovery 的输出：

```text
head_q + entry_q dynamic select
→ [retire_stage_entry_q / retire_stage_valid_q]
→ Commit exception/mret/branch-miss decode
→ same-cycle recover/clear
```

Commit 仍在检测 branch miss/trap 的同一周期阻止 younger retire，并在同一边沿清 ROB、
IQ、StoreBuffer、Execute 与 frontend；错误路径副作用契约没有增加一个空窗。

### 5.3 stage 所有权

- done prefix 从 ROB array 移入 2-wide retire stage 时，ROB head/count 前进；
- stage 成为该 entry 的唯一所有者，Commit 下一边沿消费；
- stage 支持 pop、survivor compaction、同拍 refill，稳态保持 2-wide commit；
- `empty_o` 同时检查 array count 和 stage valid，serial 不会越过尚未提交的 stage entry；
- recovery/clear 优先清 stage valid，宽 stage payload reset-free。

若 `empty_o` 只看 ROB array，serial 可能越过 stage 中尚未提交的旧指令；若移入 stage
后仍保留 array 所有权，会发生重复提交。

该修改后的 `srcSmoke` 为 37,730,903 cycles、IPC 0.81521，功能 PASS。

## 6. 修改四：BPU lookup 与 table update

### 6.1 修改文件与备份

- 修改：`rtl/core/frontend/BranchPredictor.sv`
- 原 tournament 备份：`backup/20260711_211752/BranchPredictor.sv`
- 当前 gshare 决策前备份：`backup/20260711_212655/BranchPredictor.sv`

### 6.2 lookup 缩短

修改前 direction 路径：

```text
PC → local-history table → XOR → local PHT
PC/GHR → global PHT
PC → choice PHT → local/global mux → BTB gate → next PC
```

修改后：

```text
PC/GHR → single gshare PHT → BTB gate → next PC
```

BTB tag/target 与 RAS 行为保留。该选择明显减少 lookup levels 和三组 PHT 资源，但
`srcSmoke` 分支命中率由中间 tournament 版本约 81% 降到 74.834%，最终 IPC 为
0.723657。用户在看到 A/B 数据后明确选择“先接受”，因此本轮保留 gshare；后续若
追求 50 MHz 单核 IPC，应评估 fast/slow predictor 或更短历史长度。

### 6.3 update RMW pipeline

PHT/BTB 写入只由 `table_update_*_q` 驱动：

```text
commit branch update
→ [update_*_q]
→ PHT read + saturating update + same-index bypass
→ [table_update_*_q]
→ PHT/BTB write
```

连续两拍更新同一 PHT entry 时，后一拍从 pending `table_update_direction_counter_q`
前递，而不是读取尚未在本边沿生效的旧 counter。GHR/RAS 在第一级推进，保证连续
退休分支形成有序历史。

若删除同地址前递，连续同方向分支可能丢失一次 saturating increment/decrement；
功能测试通常仍过，但 predictor 训练会变慢并产生难解释的性能漂移。

## 7. 最终验证结果

### 7.1 构建与 ISA 回归

最终 RTL 使用：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=
```

结果：

| Suite | 结果 |
| --- | ---: |
| RV32MI | 4/4 PASS |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |

### 7.2 `srcSmoke`

| 项目 | 最终结果 |
| --- | ---: |
| 状态 | PASS |
| cycles | 42,504,434 |
| commits | 30,758,614 |
| IPC | 0.723657 |
| branch hit rate | 74.8340% |
| pass marker | 对号，存在 |
| fail marker | 不存在 |

### 7.3 `srcWithMext` 500k correctness window

命令：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 NO_BUILD=1 OBJCACHE=
```

| 项目 | 结果 |
| --- | ---: |
| 工具终态 | TIMEOUT（达到固定 500k 上限） |
| RV32I pass/fail | 37 / 0 |
| M extension count | 8 |
| commits | 618,633 |
| IPC | 1.23727 |
| fail marker/assertion | 无 |

该 workload 在 500k 内不会产生最终 pass LED，故不能把 TIMEOUT 写成整体 PASS；本项
通过标准是用户指定的“500k correctness window”内 37 项 RV32I、8 项 M extension
均完成且 fail counter 为 0。

### 7.4 `srcWithMext` 50M performance window

命令：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=50000000 NO_BUILD=1 OBJCACHE=
```

| 项目 | 结果 |
| --- | ---: |
| 工具终态 | TIMEOUT（达到固定 50M 上限） |
| core cycles | 49,999,998 |
| commits | 60,732,969 |
| IPC | 1.21466 |
| branch hit rate | 97.5573% |
| RV32I pass/fail | 37 / 0 |
| M extension count | 8 |
| fail marker/assertion | 无 |

修改前同口径记录为 60,789,745 commits、IPC 1.215790；最终下降约 0.093%。尽管
`srcSmoke` 对 predictor 更敏感而下降明显，用户指定的 50M 主性能窗口基本持平。

## 8. 本轮未运行 Vivado

遵照用户要求，本轮没有调用 `vivado`、`vivado.bat`、Tcl batch synthesis 或任何
place/route 命令。因此以下状态均未知：

- 当前工作树 CPU setup WNS/TNS；
- 当前 failing endpoint 数量与新 top path；
- 新增 dispatch/retire/WB 寄存器的 placement 与 route delay；
- gshare BPU 的 LUT/FF/LUTRAM 资源变化；
- hold、recovery、DRC、CDC 是否仍满足原有状态。

不得沿用 `061` 旧 DCP 的 `-4.495 ns` 来描述当前 RTL，也不得仅凭结构修改宣称
100 MHz 已关闭。

## 9. 后续 Vivado 验收清单

用户允许长时间实现后，从 clean current-worktree 工程执行 synth/place/route，再用
`061_vivado_100mhz_timing_baseline/export_routed_reports.tcl` 和
`export_all_setup_endpoints.tcl` 同口径导出。

必须检查：

1. CPU setup `WNS >= 0`、`TNS = 0`、failing endpoints `= 0`；
2. hold/recovery/pulse-width 继续 PASS；
3. 旧 `complete_prd_reg`、`srat_q→ROB/IQ`、`head_q→DCache/DRAM` 路径族消失；
4. BPU table endpoint 的 startpoint 为 `table_update_*_q`；
5. 新 top path 是否转移到 `dispatch_buffer_entry_q→IQ/ROB`、`head_q→retire_stage`、
   `exec_complete_rob_idx→ROB` 或 DCache 本地 mux；
6. 重新统计 WNS/TNS、47,536 旧失败 endpoint 的消除比例与所有新失败 endpoint；
7. 比较 LUT/FF/LUTRAM/MUXF、control set、high fanout、congestion、DRC 与 CDC；
8. routed 后重新跑 post-implementation smoke/必要的数字孪生验证。

若仍有负 slack，下一轮优先级为：

1. 对 `exec_complete_rob_idx→ROB` 做显式 ROB bank/热冷字段拆分；
2. 对 dispatch buffer/retire stage 使用 stable-slot 而非宽 payload compaction；
3. 对 PC feedback 采用 fast BTB/bimodal path + 慢速 predictor 覆盖，而不是直接增加
   fetch 停顿级；
4. 对 DCache refill/writeback/address mux 做本地 request stage；
5. 最后才使用 physical optimization、critical-net replication 或 MUXF remap。

## 10. 变更文件与备份总表

| 文件 | 主要修改 | 备份 |
| --- | --- | --- |
| `rtl/core/execute/ExecuteCluster.sv` | registered WB、PRF 全读口 bypass | `backup/20260711_201714`, `backup/20260711_203654` |
| `rtl/core/backend/CoreBackend.sv` | completion 对齐、allocated dispatch ring、elastic issue stage | `backup/20260711_203654`, `backup/20260711_205339`, `backup/20260711_223858` |
| `rtl/core/dispatch/ROB.sv` | 2-wide retire stage、allocation/completion 字段分组 | `backup/20260711_210815`, `backup/20260711_223858` |
| `rtl/core/frontend/BranchPredictor.sv` | gshare lookup、table update RMW stage | `backup/20260711_211752`, `backup/20260711_212655` |
| `rtl/core/issue/CompressedQueue.sv` | payload recovery CE 清理 | `backup/20260711_223858` |
| `rtl/core/dispatch/DispatchUnit.sv` | MEM payload recovery CE 清理 | `backup/20260711_223858` |
| `rtl/core/issue/MemIssueQueue.sv` | stable-slot payload recovery CE 清理 | `backup/20260711_223858` |
| `rtl/core/execute/MulDivPipe.sv` | MUL/DIV metadata recovery CE 清理 | `backup/20260711_223858` |
| `rtl/core/common/MultiPushFifo.sv` | FIFO payload recovery CE 清理 | `backup/20260711_223858` |
| `doc/rtl_changes.json` | 本次 incremental-fix manifest | 不适用 |

## 11. 四项剩余结构优化总览（23:08 增补）

本次在不改变模块接口和 filelist 的前提下，完成以下四项结构修改：

| 项目 | 修改前关键组合路径/物理风险 | 修改后寄存或所有权边界 |
| --- | --- | --- |
| IQ grant/issue | completion → wakeup → oldest-ready select → PRF read → execute | completion → IQ select → `*_issue_uop_q`；下一拍才进入 PRF/execute |
| ROB completion | 4 路动态 ROB index 写整份 `CoreRobEntry` | allocation bank、completion bank、`valid_q/done_q` hot vector 分离 |
| allocated dispatch buffer | pop 后 survivor 全量搬移，4 份宽 uop 参与 compaction | head/tail/count ring；pop 只移 head，push 只写 tail slot |
| recovery payload CE | recovery/clear 驱动多个宽 payload 阵列的 CE | recovery 只清 valid/count/state；payload 无 recovery/reset CE |

这四项属于“从 RTL 拓扑上建立时序边界”，不是 routed timing closure 证据。100 MHz
最终结论仍必须由当前工作树的新 routed DCP 给出。

## 12. IQ grant 到 execute 的真实 elastic 寄存级

### 12.1 实施位置

- 文件：`rtl/core/backend/CoreBackend.sv`
- 新增 INT：`int_select_* → int_issue_valid_q/int_issue_uop_q`
- 新增 MEM：`mem_select_* → mem_issue_valid_q/mem_issue_uop_q`
- 新增 MUL/DIV：`mul_select_* → mul_issue_valid_q/mul_issue_uop_q`
- MEM 的 `lookahead/slot/age` 与 uop 同拍寄存，不能跨拍错配。

当前周期关系：

```text
周期 N：completion/wakeup → IQ oldest-ready select → select payload
边沿 N：select payload 被 issue_q 接收，IQ entry 所有权转移到 stage
周期 N+1：issue_q → PRF async read/bypass → Execute
边沿 N+1：Execute 接收；同一边沿 stage 可以 consume + refill
```

每个 slot 使用标准 elastic 条件：

```text
slot_available = !issue_valid_q || execute_ready
IQ ready       = !clear && !recover && slot_available
```

因此 Execute backpressure 时 payload 和 valid 保持；Execute 消费旧 entry 的同拍可以
接收新 grant，稳态吞吐仍是 INT 2/cycle、MEM 1/cycle、MUL/DIV 1/cycle。该修改增加
grant-to-execute 一拍 latency，但不应降低无阻塞稳态 issue bandwidth。

关键正确性约束：

1. recovery 只清 `*_issue_valid_q`，宽 uop 不需要清零；
2. MEM probe metadata 必须与 `mem_issue_uop_q` 同时装载和保持；
3. IQ 在 entry 进入 stage 时即可移除，stage 成为唯一所有者；
4. completion 在周期 N 唤醒并选中的消费者到 N+1 才读 PRF，已越过同拍旧值窗口；
5. 若删除 stage valid 的 recovery 清除，wrong-path uop 会在恢复后继续执行；若只寄存
   uop 而不寄存 MEM metadata，会对错误 slot 做 probe resolve。

静态拓扑结论：IQ instance 只连接 `*_select_*`，Execute instance 只连接寄存后的
`*_issue_*`，原 completion → IQ select → PRF/execute 的单周期组合长环已被切断。

## 13. ROB completion 写入口字段分组

### 13.1 存储拆分

文件：`rtl/core/dispatch/ROB.sv`。原 `CoreRobEntry entry_q[32]` 拆为：

```text
alloc_payload_q[32]
  = rob_idx + decode uop + prd + old_prd + alloc_prd

completion_payload_q[32]
  = result + exception/cause + branch redirect + CSR write payload

valid_q[32] / done_q[32]
  = 高频所有权/完成状态
```

两路 allocation 只写 allocation bank；四路 execution completion 与一路 store
completion 只写 completion bank 和 `done_q`。retire head 处通过 `assemble_entry()`
组合一次完整 `CoreRobEntry`，并终止在已有的 `retire_stage_entry_q`。

该方案不是声称 RAM 已被物理 floorplan 成 4 个 bank，而是先按“写端口所有者和字段
热度”拆 bank：动态 completion index 不再译码、选择和写入 PC/inst/PRD/old-PRD
等 allocation-only 宽字段。新 routed 报告应检查综合后是否保留预期分组，以及 top
path 是否收敛到 completion bank 的局部 D input。

关键正确性约束：

1. completion 与 store completion 必须在置 `done_q` 的同一边沿写全 completion 字段；
2. retire 只在旧状态 `valid && done` 时采样，因此不会观察半更新 payload；
3. entry 移入 retire stage 后立即清 array 的 `valid_q/done_q`，避免重复退休；
4. `empty_o` 同时检查 array count 和 retire-stage valid；
5. recovery 只清 ownership，不清两个 payload bank；新 allocation/completion 在重新变
   valid/done 前会覆盖其拥有的全部字段。

若 allocation 仍初始化 completion 字段，会重新把 allocation 写端扩散到 completion
bank；若 completion 只置 done 而漏写任一字段，retire 会读到上一代 ROB owner 的陈旧值。

## 14. Allocated dispatch buffer stable-slot ring FIFO

文件：`rtl/core/backend/CoreBackend.sv`。4-entry buffer 现在使用：

```text
dispatch_buffer_head_q
dispatch_buffer_tail_q
dispatch_buffer_count_q
dispatch_buffer_entry_q[4]
```

修改前每拍根据 pop 数量压缩 survivor，再把 survivor 和新 push 重写进 4 个宽 slot；
这会形成“4 个旧 payload → 多级选择/排列 → 4 个寄存器 D”的大 mux。修改后：

```text
read lane i = entry_q[wrap(head + i)]
pop         = head  += pop_count
push lane i = entry_q[wrap(tail + push_offset[i])] <= rename_uop[i]
              tail += push_count
count       = count + push_count - pop_count
```

已有 entry 的完整 payload 不再因队首 pop 而移动。等待期间只允许 completion 累积
更新每个 slot 的 `src1_ready/src2_ready`；push 同拍也先合并 wakeup，避免单周期
completion pulse 丢失。

初版 ring 为保持简单的 ready cone，在 full 状态不使用同拍 pop 释放的空间接收
rename；50M 性能结果证明该取舍会形成周期性 backpressure，现已改为用注册所有权导出的
`pop_count` 参与容量计算：`free_after_pop = depth - count + pop_count`。full+pop 同拍可
在 tail/head 重合的刚释放 slot 上完成 push，payload 仍不做 compaction。lane1 offer 继续
依赖 lane0 fire，ROB allocation、目标 IQ acceptance 和 buffer pop 仍是同一个原子事件。

若 head/tail wrap 错一位会造成覆盖未消费 entry；若 count 与 push/pop 不原子更新会
出现 PRD 泄漏或同一 uop 重复进入 ROB；若删掉驻留期间 wakeup 累积，等待 IQ 空间的
依赖 uop 可能永久不 ready。

## 15. Recovery 只清所有权，不控制宽 payload

除上述 backend/ROB 外，本次还移除了以下 payload 进程中的 `!rst && !clear_i` CE：

| 文件 | payload | recovery 后可见性所有者 |
| --- | --- | --- |
| `rtl/core/issue/CompressedQueue.sv` | `entry_q[]` | `valid_q/count_q` |
| `rtl/core/dispatch/DispatchUnit.sv` | MEM buffer `mem_entry_q[]` | `mem_count_q` |
| `rtl/core/issue/MemIssueQueue.sv` | stable-slot `entry_q[]` | `valid_q/count_q` |
| `rtl/core/execute/MulDivPipe.sv` | MUL metadata、active DIV metadata | `mul_valid_q/state_q/div_drain_q` |
| `rtl/core/common/MultiPushFifo.sv` | FIFO `mem_q[]` | `count_q/rd_ptr_q/wr_ptr_q` |

原则是“清 owner，不清 storage”：clear/recovery 边沿后，旧 payload 允许继续保持、移位
或被局部 push 覆盖，但所有输出必须先由 valid/count/state 判定，不可直接观察无 owner
的 slot。这样 recovery net 只驱动窄状态寄存器，而不再成为成百上千 payload FF 的
同步 CE/复位条件。

没有改动 Execute 中已接受 load 的 drain/response 所有权逻辑。cache response 是外部
事务，不能因为 recovery 简单丢弃握手状态；本次只处理由本地 valid/count 可以完整
屏蔽的 payload。

若某输出绕过 valid 直接读 stale payload，该模式会产生幽灵指令；若把尚未完成的外部
事务状态也按此原则盲目清除，会造成 DCache response 无 owner 或总线死锁。

## 16. 本次静态审查与待验证项

### 16.1 已完成的只读/文本静态检查

- `git diff --check`：无空白错误；
- 无模块端口、参数、filelist 或 memory map 修改；
- backend 中不存在旧 `dispatch_buffer_next_entry/next_count` compaction 状态；
- IQ 的 `issue_*` 输出接到 `*_select_*`，Execute 只接 `*_issue_*_q` 派生信号；
- ROB completion 写块只访问 completion bank，allocation 写块只访问 allocation bank；
- recovery/clear 对本次目标宽 payload 进程不再形成 CE；剩余 `!rst && !clear_i` 命中
  是 `VERILATOR_TB` assertion guard，不是综合 payload 寄存器；
- ring FIFO count、lane prefix、ROB allocation/pop 原子关系保留原 assertion；
- ROB retire stage 的 program-order prefix、single ownership、empty 语义保持。

### 16.2 本次明确未执行

按用户要求，本次四项修改后：

- 未运行 Verilator build/lint；
- 未运行 RV32MI/RV32UI/RV32UM；
- 未运行 `srcSmoke`、`srcWithMext 500k/50M`；
- 未调用 Vivado，也未运行 synth/place/route。

因此第 7 节只能作为修改前参考。下一次功能验收应先跑全量回归；下一次物理验收必须
从当前工作树生成新 routed DCP，并重点检查：

1. completion → IQ select 的 endpoint 是否终止在 `*_issue_uop_q`；
2. `dispatch_buffer_entry_q` 是否只在 tail slot 写完整 payload，不再出现 survivor mux；
3. ROB completion index 是否只扇出到 `done_q` 和 completion bank；
4. recovery/clear high-fanout endpoint 是否集中到 valid/count/state；
5. CPU setup 是否达到 `WNS >= 0`、`TNS = 0`、failing endpoints `= 0`。

## 17. 四项结构修改后的 50M 性能回退分析

### 17.1 对比结果

用户在四项结构修改后完成了正确性回归；最新结果位于
`build/result/difftest/src/srcWithMext.json`。与修改前同口径
`build/result/src/srcWithMext.json` 对比如下：

| 指标 | 修改前 | 四项修改后 | 变化/含义 |
| --- | ---: | ---: | --- |
| commit | 60,732,969 | 46,962,398 | -22.68% |
| IPC | 1.214660 | 0.939248 | -22.67% |
| branch hit rate | 97.5573% | 97.5518% | 基本不变，排除 BPU 主因 |
| DCache hit rate | 98.3671% | 98.4082% | 基本不变，排除 cache 主因 |
| average dispatch width | 1.23275 | 0.954724 | 明显下降 |
| dispatch block cycles | 52,518 | 8,485,308 | ring 容量气泡 |
| ROB full cycles | 28,350 | 5,158,084 | 下游延迟向 ROB 放大 |
| free-list empty cycles | 36,955 | 6,885,543 | 退休延迟导致 PRD 回收变慢 |
| ROB head wait INT | 12,189,335 | 20,859,368 | 固定一拍 INT 依赖延迟 |
| commit width-0 cycles | 12,362,317 | 20,993,346 | head 等待直接形成空提交周期 |

结论：回退不来自 ROB hot/cold split、recovery CE 清理、BPU 或 DCache，而是两个局部
微架构取舍叠加：

1. issue elastic stage 把所有 INT producer→consumer 延迟固定增加一拍；
2. stable-slot ring 初版 full+pop 时仍拒绝 rename，制造了 843 万量级的 dispatch block。

## 18. 性能修复一：result-ready scheduler early wakeup

### 18.1 新周期关系

Execute 在本拍 `wb_valid_d && wb_prf_we_d` 已经确定时提前宣布 PRD：

```text
周期 N：producer result/exception/PRF-WE 已确定
        wb_prd_d → scheduler_wakeup → IQ ready/select
边沿 N：dependent 进入自己的 int/mem/mul issue_q
周期 N+1：producer result 已在 wb_q；dependent 从 wb_q bypass 取数并执行
```

这恢复了固定一拍 ALU 的 producer→consumer 启动间隔，同时保留真实寄存切分：

```text
Execute registered input / registered memory response
→ wb_valid_d + wb_prf_we_d + wb_prd_d
→ scheduler wakeup compare / oldest-ready select
→ dependent issue_uop_q
```

该路径不携带 result data，也不会穿过 PRF async read 再回到 Execute。真实
`exec_complete_*` 继续独立驱动 BusyTable、ROB、PRF write 和 Execute result bypass；
early wakeup 只送到 INT/MEM/MUL 三个 IQ 的 `src_ready` 调度状态，不送 DispatchUnit、
dispatch buffer、BusyTable 或任何架构状态，以限制扇出和新路径范围。

### 18.2 可变延迟操作为什么仍然安全

- load 未返回时 `wb_valid_d=0`，不会提前宣布；只有 full-forward 或真实 response 到达才宣布；
- DIV/REM 未完成时 `muldiv_complete_valid=0`，不会提前宣布；
- store、异常结果和无目标 PRD 的指令使 `wb_prf_we_d=0`，不会宣布；
- CSR/system 保持原有 serial/异常契约，只有最终确认写 PRF 的 result 才能宣布。

`VERILATOR_TB` 下新增契约：每个 early-announced PRD 必须在下一拍出现在相同
completion slot。该断言覆盖 INT、load 和 MUL/DIV 四个 completion slot；若 pipeline
latency 或异常契约以后改变，回归会直接报错，而不是静默产生旧值依赖 bug。

## 19. 性能修复二：ring full+pop 容量旁路

rename ready 从：

```text
count + lane_index < depth
```

改为：

```text
count - pop_count + lane_index < depth
```

`pop_count` 只由当前注册 head entry、ROB registered occupancy、Dispatch/IQ ready 和
issue-stage/Execute registered ready 决定，不依赖 rename valid，因此不会形成
rename-valid→ready 组合环。full 且 pop 1 项时允许 push lane0；pop 2 项时允许 push 两项。

当 full 时 `tail == head`，push 写地址正是同拍已 pop 的旧 head slot。always_ff 中
完整 push payload 对该 slot 的局部 ready-bit wakeup 写拥有最终优先级；head/tail/count
分别按 pop/push 原子推进，队列顺序保持为“未 pop survivor → 本拍新 push”。

若容量计算不扣 `pop_count`，每次 ring 填满都至少产生一个 rename bubble；若反过来
允许超过 `pop_count` 的 push，会覆盖仍有 owner 的 survivor。

## 20. 本次性能修复验证结果与边界

### 20.1 已运行结果

使用 `student_top` difftest 同口径模型。固定周期窗口显示 `TIMEOUT` 是预期终态，不是
功能失败；判断依据为计数进度、fail counter、assertion 和 IPC。

| 版本 | 500k IPC | 50M IPC | 50M commits | 说明 |
| --- | ---: | ---: | ---: | --- |
| 四项结构修改前 | 1.23727 | 1.214660 | 60,732,969 | 目标参考 |
| 四项结构修改后 | 未单独归档 | 0.939248 | 46,962,398 | 性能回退版本 |
| INT early wakeup + ring full/pop | 1.13242 | 1.104460 | 55,222,794 | 恢复约 60% 损失 |
| 通用 result-ready early wakeup + ring full/pop | 1.23197 | 1.206600 | 60,329,924 | 50M 相对回退版 +28.47% |
| 最终 IQ-only 局部化 early wakeup | 1.23197 | 未重跑 | 未重跑 | 用户要求停止慢仿真 |

通用版本 50M 相对旧目标只低 `0.66%`，同时：

| 指标 | 回退版 | 修复后 50M | 旧目标 |
| --- | ---: | ---: | ---: |
| ROB head wait INT | 20,859,368 | 12,383,367 | 12,189,335 |
| ROB full | 5,158,084 | 187,493 | 28,350 |
| average dispatch width | 0.954724 | 1.22580 | 1.23275 |
| average commit width | 0.939248 | 1.20660 | 1.21466 |

最终局部化版本 500k：RV32I `37/0`、M extension `8`、IPC `1.23197`，没有 early-wakeup
assertion、difftest 或 RTL assertion 失败。局部化前后 500k IPC 完全一致，说明从
Dispatch/dispatch-buffer 去掉 early wakeup 没有短窗口性能损失。

### 20.2 时序风险控制决策

1. early wakeup 仅扇出到 3 个 IQ，终点为各 `*_issue_uop_q`；
2. result data 不进入 scheduler wakeup，consumer 下一拍只从 registered `wb_q` bypass；
3. BusyTable、ROB、PRF 和架构 completion 仍使用 `exec_complete_*`；
4. 曾评估 FreeList commit-free→same-cycle rename 复用以追最后 `0.66%`，但它会建立
   Commit/ARAT/live-mask→FreeList priority→Rename 新路径，收益不值得时序风险，已完全撤回；
5. `rtl/core/rename/FreeList.sv` 与本批修改前备份逐字一致。

### 20.3 尚未执行

按用户最新要求不再等待慢仿真，最终局部化版本未重跑 50M、RV32 全量或 `srcSmoke`；
也没有调用 Vivado。后续若做物理验收，应确认 scheduler early-wakeup path 终止在 IQ
issue payload register，且旧 completion→PRF→Execute 长环没有恢复。
