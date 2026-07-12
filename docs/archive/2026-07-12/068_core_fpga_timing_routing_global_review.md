# Core FPGA 时序、布局布线与低 IPC 风险优化全局审查

## 1. 审查目标与边界

本次对当前 `rtl/core` 做全局只读审查，目标是在不明显影响 IPC 的前提下，继续寻找：

- 缩短组合路径；
- 降低宽 payload 搬移和大范围 mux；
- 降低高扇出、控制集和跨模块布线；
- 改善 Xilinx FPGA LUTRAM/BRAM/寄存器映射；
- 提高 Vivado placement、routing 的可收敛性。

本次没有修改 RTL。当前工作树中已有的 INT/MEM/MUL IQ 局部 tag-only early wakeup、MEM IQ stable slot、II=1 post-remove age、store data owner capture、ROB 冷热字段平坦化修改必须保留。

必须注意：现有 routed Vivado 报告对应较早 RTL；最新未提交修复尚未重新综合，因此旧 WNS/TNS 只能用于识别历史热点，不能用于宣称当前版本优化有效或无效。

当前 `srcWithMext 500k` 功能/性能基准为：

| 项目 | 结果 |
|---|---:|
| commits | 617,609 |
| IPC | 1.23522 |
| RV32I | 37 |
| M | 8 |
| fail/assertion | 0 |

后续结构等价优化的 IPC 目标是相对该值下降不超过 0.2%，理想结果为 0%。

## 2. 结论与优先级

| 优先级 | 模块 | 当前主要问题 | 推荐结构 | IPC 风险 |
|---|---|---|---|---|
| P0 | INT IQ | 每拍压缩、宽 payload 全搬移 | stable slot + age rank + 双 oldest-ready | 极低 |
| P0 | DCache | 1024-depth async LUTRAM，写地址/WE 高扇出 | 按 word bank 成 8×128 深度 | 极低 |
| P0 | ExecuteCluster | MEM/MUL 槽仍可能综合通用 ALU/branch/CSR 锥 | 按固定 issue slot 专用化 | 极低 |
| P1 | FreeList/BusyTable | 64 项双优先编码、全表计数、恢复 32×64 decode | 分级 PE + 注册计数 + committed-live mask | 极低 |
| P1 | StoreBuffer | 8 项宽记录每拍全量 compact | head-only shift 或窄控制局部更新 | 极低 |
| P1 | BranchPredictor | PHT 全表异步复位，妨碍 RAM 映射 | PHT payload reset-free，仅复位 valid | 很低 |
| P1/P2 | PRF | 64×32、8 异步读、4 写，布局拥塞 | 按执行消费者复制 storage | IPC 不变，资源增加 |
| P2 | ROB | 仍保存完整 `CoreDecodeUop` | compact commit metadata | 极低 |
| P2 | Fetch FIFO | 宽 payload、双 push/pop、动态索引 | 奇偶 bank FIFO | 极低 |
| P2 | 全核 reset | 大量异步 reset 控制集 | 仅 valid/state 同步复位 | IPC 不变，中等验证风险 |

如果下一轮只选择三个修改，建议依次选择：

1. INT IQ stable slot；
2. Execute 固定槽位专用化；
3. DCache word banking。

## 3. P0：INT IQ stable slot

文件：`rtl/core/issue/CompressedQueue.sv`、`rtl/core/issue/IntIssueQueue.sv`

当前 `CoreCompressedQueue` 在每周期把所有 surviving entry 压缩到队首：

```systemverilog
if (valid_q[e] && !issue_remove[e]) begin
    next_entry[next_count[PTR_WIDTH-1:0]] = ready_entry[e];
    next_valid[next_count[PTR_WIDTH-1:0]] = 1'b1;
    next_count = next_count + 1'b1;
end
```

该结构导致：

- 8 个 active entry 的完整 `CoreRenamedUop` 每拍参与全量压缩；
- 双 issue 同时存在两套 oldest-ready 选择；
- entry 之间形成大量 all-to-all 宽 mux；
- payload 即使没有 remove，也挂在复杂 next-state D 端。

旧实现报告中 active INT queue 约为 11,624 LUT、2,636 FF，cold queue 约为 2,607 LUT、1,183 FF，是当前最明显的“用 LUT 搬运冷 payload”结构之一。

推荐复用当前 `CoreMemIssueQueue` 的 stable-slot 模式：

- payload 固定在物理 slot；
- 使用独立 `valid_q[slot]`；
- 每项保存小型 `age_q`；
- issue 后只清 valid，并更新比 remove age 年轻项的 age；
- push 只写空闲 slot；
- 两个 issue port 依次选择最小 age 的 ready entry；
- 同拍 remove+replacement 使用 post-remove age；
- wakeup 只更新本地 ready bit，不移动 payload。

必须保持：IQ 深度、两发射端口、oldest-ready 次序、early wakeup 时刻和 steady-state II=2。

若删错或改错：可能出现两个端口选择同一项、remove+push 年龄重复、年轻项优先于年老项，或同拍 replacement 丢失。

## 4. P0：DCache 按 word banking

文件：`rtl/core/memory/DCache.sv`

当前每个 way 为一个 1024×32 的异步 distributed RAM：

```systemverilog
(* ram_style = "distributed" *) logic [31:0] data_way0_q [0:DATA_DEPTH-1];
(* ram_style = "distributed" *) logic [31:0] data_way1_q [0:DATA_DEPTH-1];
```

其地址为 `{set_index, word_index}`。虽然现在已经推断 LUTRAM，但 1024-depth 的异步 LUTRAM 仍会形成较深级联选择和大范围写地址网络。

旧 routed 证据包括：

- DCache 使用约 1,520 LUTRAM；
- 多个 DCache 写控制网 fanout 为 585～1,057；
- `data_write_addr[*]` fanout 约 591；
- QoR 路径曾落在 `mem_req_count_q -> DCache RAM WE`。

推荐保持零周期异步读，只改变物理组织：

```text
way
 ├─ word_bank[0]: 128 × 32
 ├─ word_bank[1]: 128 × 32
 ...
 └─ word_bank[7]: 128 × 32
```

读取时 8 个浅 LUTRAM 以 `set_index` 并行读，再由 `word_index` 选择。写入时 `word_index` 只译码为 8 个局部 bank WE，`set_index` 只进入对应的 128-depth RAM。

该方案不改变：

- DCache hit latency；
- refill II；
- critical-word-first；
- dirty writeback；
- CPU/DramAccessIF 接口。

预期收益是缩小 write address/WE 扇出、减少深 LUTRAM 级联并改善 bank 分散放置。

若删错或改错：重点会出现在 refill word wrap、writeback 的下一 word 预读、`DC_FINISH` store merge，以及同址写旁路的 bank 选择。

## 5. P0：Execute 固定槽位专用化

文件：`rtl/core/execute/ExecuteCluster.sv`

当前对全部 `ISSUE_WIDTH` 槽执行统一大循环，并由动态 `uop.tube` 选择 ALU、branch、MEM、CSR 和 MUL 路径。但实际槽位合同是固定的：

```text
slot 0..1：INT/BRC/SYS
slot 2   ：MEM
slot 3   ：MULDIV
```

综合器无法仅凭系统语义排除“MEM slot 中出现 branch/CSR”，因此 MEM/MUL 槽可能仍保留无用 ALU、branch、CSR、异常判断和大结果 mux。

推荐拆分为：

- `gen_int_slot`：ALU、branch、CSR、INT exception；
- `mem_slot`：地址、forwarding、load response、store completion、misalign；
- `muldiv_slot`：只接 `CoreMulDivPipe` completion；
- CSR read/exists/privilege 判断只为可能执行 SYS 的 INT slot 生成。

这是纯组合逻辑裁剪，不增加周期，也不改变 registered WB 或 early wakeup。

若删错或改错：必须确保 decode exception、CSR fault、load/store misalign 的 cause/result 仍随正确 ROB owner 完成。

## 6. P1：FreeList 分级优先编码与注册计数

文件：`rtl/core/rename/FreeList.sv`

当前每个分配端口都扫描 63 个 PRD，随后又遍历全表计算 `free_count`。旧实现约使用 3,703 LUT，却只有 63 个主要状态位，说明组合编码和 live-mask 网络成本较高。

推荐：

1. 将 64-bit free bitmap 分成 8×8；
2. 先编码 non-empty group，再编码组内 bit；
3. 第二分配端口局部 mask 第一候选后重算；
4. 使用 `free_count_q`，按 alloc/free 增减，不再每拍 popcount；
5. normal allocation 直接以 `free_q` 为准，避免重复叠加 `live_mask`；
6. recover 使用预维护的 committed physical live mask。

初版应保持现有行为：本周期 retire 释放的 PRD 不在同周期重新分配，避免引入新的组合旁路。

若删错或改错：双分配可能取得相同 PRD，或 bitmap 与 count 在同拍双 alloc/双 free 时不一致。

## 7. P1：ARAT committed-live mask

文件：`rtl/core/rename/RenameUnit.sv`、`rtl/core/rename/BusyTable.sv`、`rtl/core/rename/FreeList.sv`

当前 BusyTable 和 FreeList 在 recover 时分别把 32 项 ARAT 动态索引展开为 64-bit mask，相当于保留两套 32×64 decode/mux。

建议在 Rename/ARAT 侧增量维护：

```systemverilog
logic [PHY_REG_NUM-1:0] arat_live_mask_q;
```

每次 commit 按程序顺序：

- 清除该 architectural register 的旧 ARAT PRD；
- 设置新 PRD；
- lane1 对同一 architectural register 的更新覆盖 lane0；
- x0 固定 live。

recover 时可直接：

```text
BusyTable.ready_q <= arat_live_mask_q
FreeList.free_q   <= ~arat_live_mask_q
```

若删错或改错：同周期两条指令写同一 architectural register 时，错误的并行 clear/set 会丢失最终映射。

## 8. P1：StoreBuffer 去除通用 compact

文件：`rtl/core/execute/StoreBuffer.sv`

当前逻辑先构造 `marked_entry`，再把 8 项完整记录动态压缩。实际上 StoreBuffer 只有 head drain，不会任意删除中间项；recover 时需要保留的 retired store 也应当是连续前缀。

建议改成 head-only shift：

- 无 pop：每个 entry 原位接受 completion/commit 更新；
- pop：`entry[i] <= marked_entry[i+1]`，只形成相邻 2:1 mux；
- clear：保留 retired prefix并截断 count；
- simultaneous pop+push：push 到 post-pop tail；
- forwarding仍按老到年轻扫描，年轻 store byte 覆盖年老 store byte。

这比通用 compact 更符合 StoreBuffer 的真实删除合同。

若删错或改错：不能在恢复时删除已经退休但尚未写入内存的 store，否则破坏精确状态。

## 9. P1：Branch Predictor PHT reset-free

文件：`rtl/core/frontend/BranchPredictor.sv`

当前 reset 会初始化全部 512 个 2-bit direction counter。方向 PHT 只有在 BTB valid/hit 时才影响预测，而 BTB valid 已经单独复位，因此 PHT payload 不属于 architectural reset state。

建议：

- 只复位 `btb_valid_q`、GHR、RAS count和pipeline valid；
- `direction_pht_q` 不挂异步 reset；
- 第一次有效分支更新自然写入 counter；
- 如需要确定性，可使用 FPGA initialization 或后台 scrub，不要使用全表异步复位。

IPC 只可能在启动热身阶段出现很小差异，长期 IPC 和功能正确性不应变化。

若删错或改错：必须保证 BTB invalid 时，PHT taken 不能单独改变 fetch PC。

## 10. P1/P2：PRF 本地复制 A/B

文件：`rtl/core/execute/PhysRegFile.sv`、`rtl/core/execute/ExecuteCluster.sv`

当前 PRF 为 64×32、8 异步读口、4 写口。旧报告中 `CorePhysRegFile` 约为 9,149 LUT、2,016 FF，且 Vivado congestion 建议直接指向 `u_prf`。

不建议增加同步读流水级，因为这会增加 dependent ALU、branch 和 load-use latency。

更合适的低 IPC 风险方案是复制 storage：

```text
PRF copy 0 -> INT slot 0
PRF copy 1 -> INT slot 1
PRF copy 2 -> MEM
PRF copy 3 -> MULDIV
```

所有 WB 写广播到所有副本；每个副本的读 mux与对应执行单元局部放置。可先做两副本 A/B：INT 一副本、MEM+MULDIV 一副本，再根据 placed congestion 决定是否做四副本。

该方案保持 IPC，但会把 FF 从约 2k 增加到约 4k 或 8k。不能只比较综合 LUT，必须比较 post-place/post-route QoR。

若删错或改错：所有副本必须具有完全相同的多写优先级；同一 PRD 多端口写入应增加断言。

## 11. P2 后续项

### 11.1 ROB compact commit metadata

文件：`rtl/core/dispatch/ROB.sv`

当前仍为每个 ROB entry 保存完整 `CoreDecodeUop`。commit 实际需要的字段主要是 pc、inst、rd/rs1、branch/jal/jalr、load/store、mret/serial、prediction信息和少量 debug/tube 分类。

可以定义 `CoreRobAllocMeta`，不保存 execute-only immediate、ALU op、mem size等字段，从而缩小 ROB payload和 head read mux。

但旧报告中的 ROB 20,956 LUT、9,396 FF 对应平坦化之前，必须先获得最新综合数据再决定是否继续修改。

### 11.2 FetchBuffer 奇偶 bank

文件：`rtl/core/common/MultiPushFifo.sv`、`rtl/core/frontend/FetchBuffer.sv`

利用连续两个 FIFO 地址必然落在不同奇偶 bank，可实现两个单写 bank和小型输出交换网络，减少宽 payload双写动态索引成本，并保持 fall-through read和2-wide吞吐。

### 11.3 全核 reset 控制集

在移除 PHT 全表 reset后，再逐步将局部控制状态改为同步 reset，前提是顶层同步后的 reset保证至少一个 CPU clock周期。优先对象是 FIFO pointer/count、IQ valid/count、issue valid、ROB valid/head/tail和 DCache state/valid，而不是宽 payload。

不应一次性机械替换全核 reset；每个模块都必须重新检查 reset、clear、recover 的覆盖优先级。

## 12. 暂不建议的方案

以下方案可能提高 Fmax，但不符合“基本不影响 IPC”的目标：

1. DCache data/tag直接改同步 BRAM：load hit和load-use至少增加一拍；
2. PRF增加同步读流水级：所有依赖链和branch resolution延后；
3. 降低 INT IQ、ROB或PRF深度：提高结构阻塞；
4. 取消 registered WB：重新形成 IQ→PRF→Execute→wakeup 长组合环；
5. 把局部 early wakeup重新合为全局网络；
6. 给 StoreBuffer forwarding增加额外流水级；
7. 为时序关闭 MEM lookahead；
8. 仅依赖 Vivado implementation strategy掩盖 RTL结构问题。

## 13. 推荐实施与验证顺序

```text
A0  当前 RTL clean synth + place，建立最新真实基线
 ↓
A1  INT IQ stable slot
 ↓
A2  Execute 固定槽位专用化
 ↓
A3  DCache word banking
 ↓
A4  FreeList 分级 PE + committed-live mask
 ↓
A5  StoreBuffer head-only shift
 ↓
B1  BPU PHT reset-free
 ↓
B2  PRF 两副本/四副本 A/B
 ↓
B3  根据新资源报告决定 ROB metadata 裁剪
```

每一步必须单独记录：

- RV32I 37、M 8、assertion 0；
- `srcWithMext 500k` commits、cycles、IPC，与 1.23522 比较；
- synthesis hierarchical LUT/FF/LUTRAM/BRAM/DSP；
- post-place WNS/TNS；
- routed WNS/TNS/WHS/THS；
- `report_high_fanout_nets`；
- control sets；
- `Synth 8-7137` 等 RAM/reset相关警告；
- route runtime和峰值内存。

只有上一项通过功能、IPC和 QoR 门槛后，才进入下一项，避免多个结构同时修改后无法归因。

## 14. 2026-07-12 实施结果

按照用户要求，本轮只实施表中标为“极低 IPC 风险”的结构优化，不实施 BPU PHT reset-free、PRF复制和全核 reset迁移，也没有调用 Vivado。

### 14.1 已完成批次

| 批次 | 文件 | 实际修改 | 关键保持项 |
|---|---|---|---|
| 1 | `issue/CompressedQueue.sv` | active/cold INT IQ及MUL IQ改为 stable slot和age-ranked select | oldest-ready、双发射、同拍replacement |
| 2 | `execute/ExecuteCluster.sv` | INT、MEM、MULDIV固定槽位逻辑专用化 | registered WB、early wakeup周期 |
| 3 | `memory/DCache.sv` | 每way改为8个128×32 word bank | async hit、refill、critical word、writeback |
| 4 | `backend/CoreBackend.sv`、`rename/BusyTable.sv`、`rename/FreeList.sv` | committed live mask、直接恢复、分级PE、注册count | ARAT语义、同拍双alloc/free |
| 5 | `execute/StoreBuffer.sv` | 通用compact改为head pop相邻shift | store data owner、retired prefix、forwarding顺序 |
| 6 | `dispatch/ROB.sv` | 完整decode uop缩为retirement metadata | 精确异常、BPU、serial、debug、store检查 |
| 7 | `common/MultiPushFifo.sv` | Fetch FIFO改为奇偶浅bank | 2-wide fall-through、稀疏push、同拍pop/push |

备份目录：

```text
backup/20260712_174700/
```

### 14.2 回归中发现并修复的恢复边沿合同

第4批初版在 ADD/JALR/RV32MI 定向测试中暴露恢复错误，未继续叠加后续修改，定位后修复了两个问题：

1. `arat_map_o` 的组合输出已经叠加当前 commit，不能用于寻找旧 committed PRD；live mask必须清除 ROB entry携带的 `free_old_prd`。
2. branch/trap退休和 recover发生在同一边沿，BusyTable和FreeList必须使用包含本拍commit的 `arat_live_mask_d`，不能使用前一拍 `arat_live_mask_q`。

修复后原失败的 JALR、ADD和 RV32MI 全部通过。

若该修复删除或改错：恢复会错误释放本拍刚提交的新PRD，或继续保留旧PRD，随后出现错误operand、free-list泄漏或重复分配。

### 14.3 累计正确性回归

| 回归 | 结果 |
|---|---|
| Verilator RV32 model | build PASS |
| Verilator src model | build PASS |
| src difftest model | build PASS |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |
| `srcSmoke` difftest 200k | 124,305 commits；RV32I display=37；预期 TIMEOUT；无 selfcheck错误 |
| `srcWithMext` difftest 200k | 255,647 commits；RV32I=37、fail=0、M=8；IPC 1.27822；预期 TIMEOUT；无 selfcheck错误 |

### 14.4 `srcWithMext 500k` IPC验收

| 项目 | 修改前基线 | 本轮结果 | 变化 |
|---|---:|---:|---:|
| cycles | 500,000 | 500,000 | 0 |
| commits | 617,609 | 617,609 | 0 |
| IPC | 1.23522 | 1.23522 | 0.00000% |
| RV32I | 37 | 37 | 0 |
| fail | 0 | 0 | 0 |
| M | 8 | 8 | 0 |

固定窗口达到上限后 TIMEOUT 是预期状态。没有 assertion、fail marker或差分自检错误，因此本轮不需要因 IPC 回退撤销任何批次。

### 14.5 证据边界

本轮没有调用 Vivado，因此目前只能确认：

- RTL可以编译；
- 约定正确性回归通过；
- 500k IPC没有下降；
- 源码结构上移除了多处宽compact、全表恢复decode和通用执行mux。

尚不能确认实际 LUT/FF/LUTRAM变化、placed/routed WNS/TNS、拥塞、route runtime和峰值内存。后续只有在用户允许的新 clean Vivado运行后，才能评价物理 QoR；旧061 checkpoint不能作为本轮结果。
