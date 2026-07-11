# 100 MHz 时序 RTL 优化实施与验证记录

> 日期：2026-07-11  
> 时序诊断来源：`061_vivado_100mhz_timing_baseline`  
> routed 报告版本：`4762e00314f73810344185077f002c4c7db0dea6`  
> 实施时工作树基线：`78f41bbe0dd0fc799dc16d37feea38b0875d8e20`  
> 本轮约束：按用户要求不启动 Vivado，仅做 RTL、Verilator 与软件负载验证

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
| `rtl/core/backend/CoreBackend.sv` | completion 对齐、4-entry allocated dispatch buffer | `backup/20260711_203654`, `backup/20260711_205339` |
| `rtl/core/dispatch/ROB.sv` | 2-wide retire stage | `backup/20260711_210815` |
| `rtl/core/frontend/BranchPredictor.sv` | gshare lookup、table update RMW stage | `backup/20260711_211752`, `backup/20260711_212655` |
| `doc/rtl_changes.json` | 本次 incremental-fix manifest | 不适用 |

