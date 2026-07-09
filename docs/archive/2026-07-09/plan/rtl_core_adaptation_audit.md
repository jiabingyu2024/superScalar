# rtl/core 适配审计：NOP-Core 迁移版当前缺口

> 日期：2026-07-09
> 范围：对比 `docs/archive/2026-07-09/plan/implementation_freeze.md`、`superScalar_target_architecture.md` 与当前 `rtl/core/`、`rtl/soc/`、`scripts/filelists/`。
> 结论：当前 `rtl/core` 不是已可替换 SoC 的完整 OoO core，而是“单发射顺序核主路径 + 部分 OoO shadow/backend 模块 + 未接入 SoC 的新接口”的中间态。后续适配应先统一顶层接口和 filelist，再补齐前端、DCache/LSU、提交恢复、CSR/异常等闭环。

## 1. 总体状态

当前代码存在三套边界没有对齐：

| 层级 | 当前事实 | 目标合同 | 影响 |
|---|---|---|---|
| `rtl/core/myCPU.sv` | 对外是双端口 IROM `irom_addrA/B`，数据侧是旧 `perip_*` 直连，无 `dmem_req/resp`。 | 双端口 IROM + 单 outstanding DMEM ready/valid。 | 不能直接接当前 `student_top.sv`。 |
| `rtl/soc/student_top.sv` | 仍按单端口 IROM 和 `dmem_req_*` 例化 `myCPU`。 | 需要 true dual-port IROM 接线和新 `myCPU` 端口。 | 当前端口名/数量不匹配，编译会断。 |
| `scripts/filelists/core.f` | 仍是旧五级核路径：`rtl/core/front/*`、`rtl/core/memory/DCache.sv`、`riscv_cpu.sv`。 | 应列当前 `CoreConfigPkg/CoreTypesPkg/interfaces/common/frontend/backend/...`。 | filelist 指向不存在文件，无法构建当前 core。 |

因此第一阶段不是直接调 OoO bug，而是先做“工程边界归一化”。

## 2. 最高优先级适配项

### 2.1 顶层 `myCPU` 接口必须重定版

当前 `rtl/core/myCPU.sv`：

- IROM 已变成 A/B 双端口地址和数据。
- 数据侧仍输出 `perip_addr/perip_wen/perip_mask/perip_wdata`，并把 `dromAccess.accessReady` 固定为 1。
- 没有 `dmem_req_valid/ready/write/addr/wdata/wstrb/uncached` 和 `dmem_resp_valid/rdata`。

目标应统一为：

```text
IROM:
  irom_addrA/irom_dataA/irom_enaA
  irom_addrB/irom_dataB/irom_enaB

DMEM:
  dmem_req_valid
  dmem_req_ready
  dmem_req_write
  dmem_req_addr
  dmem_req_wdata
  dmem_req_wstrb
  dmem_req_uncached
  dmem_resp_valid
  dmem_resp_rdata
```

适配动作：

1. 修改 `rtl/core/myCPU.sv` 数据侧端口，删除 `perip_*` 直连接口。
2. 让 core/DCache 通过 ready/valid 访问 `SocMemBridge`。
3. 写请求以 `req_valid && req_ready && req_write` 为完成点；读请求必须等待 `resp_valid`。
4. `dmem_req_uncached` 由 DCache/cacheable 判断产生，MMIO 和非 DRAM 地址必须 uncached。

风险：

- 如果仍把 `accessReady` 固定为 1，DCache miss、load 返回、MMIO 读都会被当成组合/当拍完成，和 SoC 固定延迟合同冲突。

### 2.2 `student_top.sv` 必须改成双端口 IROM

当前 `rtl/soc/student_top.sv`：

- 只有 `irom_addr`、`instruction`、`irom_ena`。
- `IROM_0` 只有 `addra/douta` 单端口。

适配动作：

1. 增加 `irom_addrA/B`、`instructionA/B`、`irom_enaA/B`。
2. `irom_word_addrA = irom_addrA[13:2]`，`irom_word_addrB = irom_addrB[13:2]`。
3. `IROM_0` 行为模型和 Vivado Tcl 改为 true dual-port ROM，保持 1 拍读延迟。
4. 若选择复制两份 ROM 而不是真双口，两个 ROM 的初始化文件必须完全一致。

风险：

- 只改 core 不改 SoC 会端口不匹配。
- 只改 SoC 不改 `rtl/ip/IROM_0.sv` 和 Vivado Tcl，会出现仿真/上板模型不一致。

### 2.3 filelist 需要重建

当前 `scripts/filelists/core.f` 仍引用旧五级核文件，且其中 `rtl/core/memory/DCache.sv` 在当前树中不存在。

适配动作：

1. 新建或替换 `scripts/filelists/core.f`，按 package/interface/common/模块顺序列当前文件。
2. `CoreConfigPkg.sv`、`CoreTypesPkg.sv`、`CoreUtilPkg.sv` 必须排在所有 import 它们的模块前。
3. interface 文件 `IromAccessIF.sv`、`DramAccessIF.sv`、`DebugIF.sv`、`PerfIF.sv` 需要早于使用它们的模块。
4. 删除旧路径 `rtl/core/front`、`rtl/core/memory`、`riscv_cpu.sv` 的引用，除非明确恢复这些文件。

风险：

- Vivado/SystemVerilog package 编译顺序敏感；filelist 不先修，后续 RTL 功能验证没有意义。

## 3. 前端适配缺口

| 项 | 当前事实 | 目标 | 待适配 |
|---|---|---|---|
| PC reset | `CorePcGen` reset 到 `32'h8000_0000`；顺序核 `core.sv` 也 reset 到 `0x8000_0000`。 | 需要和测试镜像/linker/IROM 地址映射一致。文档中 NOP 原版是 `0x1c000000`，当前 SoC 文档多处按 `0x8000_0000`/DRAM `0x8010_0000`。 | 固化 reset PC，检查 linker、COE、dump、IROM 地址截位。 |
| fetch valid mask | `CoreIromFetch2` 对两路都直接 `valid_q`，没有处理奇地址/8B 边界/redirect 后第二条无效。 | 2-way fetch 必须能 mask lane1。 | 增加 `valid_mask`，至少处理 `pc[2]` 和 branch/redirect 场景。 |
| branch predictor | `CoreIromFetch2` 固定 `pred_taken=0`，`pred_target=pc+8`；`BranchPredictor.sv` 尚未接入顶层数据流。 | 参数化 tournament：GShare 512、local 512、choice 512、BTB 256、RAS 8。 | 接入 PC 选择、fetch packet meta、执行/提交更新、flush 恢复。 |
| RAS 恢复 | `ReturnStack.sv` 存在，但未见顶层闭环。 | call/return 预测必须保存 recover top。 | 在 fetch packet/branch meta 中携带 RAS recover 信息。 |
| FetchBuffer flush | `CoreFetchBuffer` 支持 `clear_i`。 | redirect/异常/mret 必须清空旧路径。 | 顶层恢复信号要驱动 fetch buffer clear，并阻止 IROM 旧响应入队。 |

特别注意：

- 双端口 IROM 是 1 拍同步读，fetch 需要保存请求 PC 和有效 mask，在 N+1 和两路 `inst` 对齐。
- redirect 发生时，N 或 N-1 已经发出的 IROM 响应不能被当成新路径指令送入 decode。

## 4. OoO 主路径适配缺口

当前 `rtl/core/core.sv` 仍是顺序状态机主路径：

- 状态包括 `ST_FETCH_REQ/ST_FETCH_WAIT/ST_EXEC/ST_MEM_REQ/ST_MEM_WAIT/ST_MEM_RESP/ST_STORE_COMMIT/ST_DIV`。
- `CoreFetchBuffer/CoreRv32Decoder/CoreBackend` 只作为 `shadow_*` 路径挂在顺序核旁边，用于流/结果比较。
- 真正对外驱动 PC、寄存器、CSR、memory 的仍是顺序核逻辑。

适配动作：

1. 新建或重写 `core.sv` 为真正 OoO top：
   - `PcGen -> IromFetch2 -> FetchBuffer -> Decode -> Rename -> Dispatch -> IQ -> Execute -> ROB -> Commit`
2. 删除或隔离 `shadow_*` 比较逻辑，避免成为正式路径负担。
3. 由 OoO backend 的 recover/commit 驱动前端 flush、RAT/FreeList/BusyTable 恢复、StoreBuffer 提交。
4. perf 计数改由真实流水事件产生，不再依赖顺序核状态机。

风险：

- 如果只逐步把 shadow backend 接到顺序核旁边，最终会出现两套状态源：顺序 GPR/CSR 与 OoO ROB/PRF 不一致。

## 5. Decode/类型系统缺口

当前 `CoreDecodeUop` 信息偏粗：

- 有 opcode/rd/rs/imm/tube/is_load/is_store/is_branch/is_jal/is_jalr/is_system/illegal。
- 缺少明确的 `alu_op`、`branch_op`、`lsu_op`、`mem_size`、`mem_signed`、`muldiv_op`、`csr_op`、`is_trap`、`is_mret`、`is_fence`、异常码、预测 meta。

当前 `CoreRv32Decoder`：

- 能粗分类 RV32 opcode。
- SYSTEM 只按 `funct3 != 0` 判断写 rd，没有区分 CSRRS/CSRRC/CSRRW、ecall/ebreak/mret。
- RV32M 只把 funct7 `0000001` 放入 `TUBE_TYPE_MUL`，没有区分 MUL 与 DIV/REM 的不同执行延迟/接口。
- load/store 没有生成 byte/half/word、有符号/无符号信息。

适配动作：

1. 扩展 `CoreDecodeUop` 为目标文档中的完整微操作。
2. Decode 覆盖 RV32I、RV32M、rv32mi 必需 SYSTEM、`fence/mret/ecall/ebreak`。
3. 非目标指令必须稳定产生 illegal instruction exception，不应落入 ALU 默认路径。
4. 分支预测 meta 应随 uop 进入 ROB，用于 resolve 和 BPU 更新。

风险：

- Decode 信息不足会迫使后级继续用 opcode/funct3/funct7 重解码，容易造成 CSR、异常、load/store lane、mul/div 行为分叉。

## 6. Rename/ROB/提交恢复缺口

已具备的基础：

- `CoreRenameUnit` 有 sRAT/aRAT、同 batch older lane bypass、commit 更新 aRAT、recover 用 aRAT 恢复 sRAT。
- `CoreROB` 支持多路 allocate/complete/retire。
- `CoreCommitUnit` 能按 ROB head retire，并在 exception/branch_miss 时发 recover。

需要适配/修正：

| 项 | 当前缺口 | 需要补齐 |
|---|---|---|
| FreeList 恢复 | `CoreFreeList` 在 `clear_i || recover_i` 下清空/重置的语义需复核，当前 rename 只恢复 RAT，不足以恢复 free list 的精确状态。 | 设计 checkpoint 或基于 aRAT/ROB 重建 free list，确保 flush 不泄漏/重复释放物理寄存器。 |
| commit 宽度遇异常 | `CoreCommitUnit` 在同一 always_comb 里逐 lane 扫描 recover，但 older lane 已 commit、fault lane 不 commit 的精确规则需要明确。 | 异常 lane 之前的 older 指令可提交；异常 lane 及 younger 不能提交；recover PC 按异常/mret/branch 类型选择。 |
| branch recovery | 当前 recover 只有 `recover_pc`，没有携带恢复类型、BPU 更新、RAS/GHR 恢复。 | 增加 recovery packet。 |
| CSR/系统指令序列化 | 当前 backend 无 serializing 机制。 | CSR、fence、mret、ecall/ebreak 需要阻止 younger 越过副作用点。 |
| store commit | 当前 commit 不通知 StoreBuffer 对应 ROB store 已提交。 | StoreBuffer entry 需要 ROB index/retired 标记，commit 时按 ROB 顺序解锁。 |

风险：

- 乱序核最容易错的是“看似能提交，flush 后物理寄存器状态已经坏了”。FreeList 恢复必须先设计清楚再扩大测试。

## 7. Execute/MulDiv/LSU 缺口

### 7.1 ExecuteCluster 当前还不是真实执行簇

当前 `CoreExecuteCluster`：

- ALU/branch 组合完成。
- MUL 用 `*` 组合计算结果，不使用 `MUL_0` 3 拍 IP。
- DIV/REM 没有实现。
- MEM uop 只计算地址，把地址当 result complete，未访问内存。
- 没有旁路网络、load 返回仲裁、长延迟 unit backpressure。

目标：

- INT0/INT1：ALU，INT0 还承担 BRU/CSR/SYSTEM。
- MulDiv：MUL 固定 3 拍，DIV 使用 `DIV_0` valid 握手。
- LSU：地址生成、DCache/uncached 请求、load align/extend、store data/mask、StoreBuffer 查询/前递。

### 7.2 StoreBuffer 当前只是单 entry 写缓冲

当前 `CoreStoreBuffer`：

- 只有一个 entry。
- push 后直接通过 `DramAccessIF.StoreBuffer` 写出。
- 没有 ROB index、retired 标记、load 查询/前递、顺序提交语义。

目标 StoreBuffer：

- 深度 8。
- store 执行后入队但 `retired=0`。
- commit 对应 ROB store 后标记 `retired=1`。
- 只有 retired store 可以写 DCache/uncached memory/MMIO。
- load 需要查询 older store，命中同地址/字节时前递，否则按顺序规则等待或访问 DCache。

风险：

- store 提交前写内存会破坏精确异常；分支误预测或 trap 后无法撤销内存副作用。

### 7.3 DCache 缺失

当前树中没有 `rtl/core/memory/DCache.sv`，只有 `backup/20260709_121900_debug_srcWithMext/DCache.sv`。目标冻结为：

- 2-way set associative。
- 32-byte line。
- write-back + write-allocate。
- cacheable: `0x8010_0000 <= addr < 0x8014_0000`。
- MMIO/其他地址 uncached。
- 外部 `SocMemBridge` 不支持 burst，不支持多个 outstanding。

适配动作：

1. 新建 `rtl/core/memory/DCache.sv` 或从 backup/旧版迁移后重写。
2. miss refill 按 32B line 即 8 个 32-bit word 顺序请求；每个 word 等响应后再发下一个，除非后续重写 SoC bridge。
3. dirty victim 需要逐 word writeback。
4. 对 load hit 返回对齐后的 word，再由 LoadAligner 做 byte/half sign extend。
5. store hit 写 cache line 并置 dirty；store miss write-allocate。
6. uncached load/store 直接走 DMEM ready/valid，不进入 cache array。

风险：

- 文档 `docs/fpga/ip_timing_alignment.md` 旧段落仍写 16B/4 words；冻结文档改为 32B/8 words。实现和文档需要统一，否则 DCache refill FSM 会按错行大小。

## 8. SoC/IP 适配缺口

| 文件 | 当前状态 | 需要改 |
|---|---|---|
| `rtl/ip/IROM_0.sv` | 单端口 ROM。 | 改 true dual-port 或复制 ROM 模型，两个端口均 1 拍读。 |
| `fpga/create_vivado_project.tcl` | IROM 当前按 Single_Port_ROM 参数生成。 | 改 true dual-port ROM，记录端口和 latency。 |
| `rtl/soc/student_top.sv` | 单端口 IROM 接线，myCPU 端口按旧核。 | 接双端口 IROM 和新 DMEM 接口。 |
| `rtl/soc/DramBramAdapter.sv` | 当前 DRAM 读 1 拍，`resp_valid <= req_valid && !req_write`。 | 冻结目标写 DRAM read latency=2 时，需要把 `resp_valid` 和 `read_offset` 延迟 2 拍，并同步 `rtl/ip/DRAM_0.sv`/Tcl。 |
| `rtl/ip/DRAM_0.sv` | 需复核实际读 latency。 | 与 DramBramAdapter 和 Vivado IP 保持一致。 |
| `SocMemBridge.sv` | 单 outstanding ready/valid，可用。 | 保持不支持 burst/id/乱序返回；DCache 必须适配它，而不是反过来假设 AXI。 |

## 9. 可保留/可复用模块

以下模块可作为后续实现基础，但需要接入正式 top 并补验证：

- `common/MultiPushFifo.sv`：可用于 FetchBuffer。
- `frontend/FetchBuffer.sv`：接口基本匹配 2 push / 2 pop。
- `rename/RenameUnit.sv`：已有 sRAT/aRAT 和 batch 内 rename bypass。
- `dispatch/ROB.sv`：已有多路分配/完成/提交骨架。
- `issue/IntIssueQueue.sv`、`MemIssueQueue.sv`、`MulDivIssueQueue.sv`：可保留队列分工，但要验证 ready/wakeup/flush。
- `execute/PhysRegFile.sv`：可作为多读多写 PRF 起点。
- `commit/CsrFile.sv`、`TrapUnit.sv`、`RecoveryUnit.sv`：若接口与新 recovery packet 匹配，可复用设计思路。

不建议直接沿用为正式实现的部分：

- `rtl/core/core.sv` 当前顺序状态机主路径。
- `CoreExecuteCluster` 里的组合 MUL、MEM 地址即 complete。
- `CoreStoreBuffer` 单 entry 且未绑定 commit。
- `DramAccessIF` 当前 read/store 仲裁接口，语义不等价于目标 DCache/DMEM ready-valid。

## 10. 建议实施顺序

1. 冻结并修改顶层接口：`myCPU`、`student_top`、`IROM_0`、Vivado Tcl、filelist。
2. 建一个最小 OoO top，只串起 `PcGen/IromFetch2/FetchBuffer/Decode/CoreBackend`，先不跑 DCache。
3. 扩展 `CoreTypesPkg` 和 `CoreRv32Decoder`，让 uop 信息足够后级使用。
4. 修 Rename/ROB/FreeList recover，做 fake execute commit 回归。
5. 替换 `ExecuteCluster`：INT/BRU/MulDiv 长延迟真实化。
6. 新建 LSU + StoreBuffer + DCache，接 `SocMemBridge` ready/valid。
7. 接 CSR/trap/mret/fence 精确异常和恢复。
8. 更新 perf/debug 输出和 Verilator/Vivado filelist。

## 11. 需要你确认的问题

1. reset PC 是否固定为 `0x8000_0000`？当前 core 和脚本倾向这个值，但 DRAM/cacheable 从 `0x8010_0000` 开始，需确认 IROM 程序镜像地址和 linker 口径。
就是这个不用变
2. IROM 双端口选择 true dual-port ROM，还是复制两份同内容 ROM？true dual-port 更贴合冻结文档；复制 ROM 更容易规避 IP 端口限制但多用 BRAM。
true 双端口，参考vivado bram ip
3. DRAM 读 latency 是否现在就从 1 拍改到冻结目标 2 拍？如果改，必须同批改 `DramBramAdapter.sv`、`rtl/ip/DRAM_0.sv` 和 Tcl。
改为两拍，并加上cathe
4. DCache line size 以 `implementation_freeze.md` 的 32B 为准，对吗？旧文档 `ip_timing_alignment.md` 仍有 16B/4 words 描述，需要同步修。
前者
5. 现有 `backup/20260709_121900_debug_srcWithMext/DCache.sv` 是否允许作为迁移参考？当前正式 `rtl/core/memory/DCache.sv` 不存在。
否
6. 是否接受先让 OoO v1 不支持 load speculative wakeup、所有 load 等 DCache/uncached 实际返回后再唤醒？这与冻结文档一致，能显著降低 replay 复杂度。
是
7. CSR/异常目标是只跑 `rv32ui/rv32um/rv32mi` 必需 M-mode，还是要兼容当前顺序核里已经出现的 `stvec/satp/pmp*` 读写空实现？
只跑必要的
## 12. 当前最小可验证里程碑

最小里程碑建议定义为：

```text
双端口 IROM + 新 filelist + OoO fetch/decode/backend fake execute
  -> 能从 IROM 连续取 2 条
  -> Decode 生成 uop
  -> Rename/ROB 分配
  -> fake execute 当拍 complete
  -> ROB 2 宽顺序 commit
  -> branch recover 能 flush fetch buffer
```

这个里程碑不包含 DCache、CSR、真实 MulDiv。它的价值是先证明接口、filelist、2 宽主数据流、ROB/rename 恢复方向是通的，再进入内存系统。
