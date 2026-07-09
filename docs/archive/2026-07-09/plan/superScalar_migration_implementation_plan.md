# superScalar 乱序双发射迁移实施计划

> 实施冻结说明：RTL 实施以 `implementation_freeze.md` 为最终决策记录。它覆盖本文早期探索性默认值：DCache line size 为 32B，IROM 为 true dual-port BRAM，BPU 为完整参数化 tournament predictor。

> 日期：2026-07-09
> 输入：`adaptation_questions.md` 的 A1-G1 决策、`nop_core_architecture.md`、`docs/fpga/ip_timing_alignment.md`、当前 `rtl/core` 与 `rtl/soc` 边界。
> 目标：按可综合、Vivado 友好、可上板的标准，把目标架构落成 SystemVerilog RTL。

---

## 0. 执行原则

这次迁移不能按“先写一个能仿真的大核”推进，必须每一步都能回答三个问题：

1. 这个模块是否可综合？
2. 它是否与当前 Vivado IP/SoC 时序合同一致？
3. 它是否能在上板路径中被 `student_top/top` 正确驱动和观测？

硬约束：

- 手写 SystemVerilog。
- 不引入 SpinalHDL 工具链。
- 不重构 `rtl/soc`、`rtl/ip`、TCL 的整体结构，只允许双端口 IROM、DRAM latency、MUL/DIV latency 这类有限 IP/adapter 对齐修改。
- 保留当前 DRAM/MMIO 地址空间：`0x8010_0000 ~ 0x8014_0000`、`0x8020_xxxx`。
- 先做 RV32I/M/M-mode 必需指令，不做 Zb，不做 MMU/TLB。
- 先做 2 宽，保证频率和上板，再用参数扩展。

---

## 1. 交付物清单

### 1.1 文档交付

| 文件 | 目的 |
|---|---|
| `superScalar_target_architecture.md` | 固化迁移后的目标架构和微架构 |
| `superScalar_migration_implementation_plan.md` | 本实施计划 |
| `docs/fpga/ip_timing_alignment.md` | 每次 IP latency/端口改动后同步维护 |
| `docs/rtl_changes.json` 或 archive 记录 | 每个阶段的修改、验证、残余风险 |

### 1.2 RTL 交付

最终新增或替换的核心 RTL：

```text
rtl/core/CoreConfig.sv
rtl/core/OoOTypes.sv
rtl/core/myCPU.sv
rtl/core/ooo_core.sv
rtl/core/front/*
rtl/core/decode/*
rtl/core/rename/*
rtl/core/dispatch/*
rtl/core/issue/*
rtl/core/execute/*
rtl/core/memory/*
rtl/core/commit/*
rtl/core/regs/*
rtl/core/perf/*
```

SoC/IP 有限改动：

```text
rtl/soc/student_top.sv          // 双端口 IROM 接线、myCPU wrapper 接口适配
rtl/soc/DramBramAdapter.sv      // 若 DRAM read latency 改 2 拍
rtl/ip/IROM_0.sv                // Verilator 双端口行为模型
rtl/ip/DRAM_0.sv                // Verilator latency 行为模型
rtl/ip/MUL_0.sv                 // 若未来改 MUL latency，同步行为模型
fpga/create_vivado_project.tcl  // IROM/DRAM/MUL/DIV 真实 IP 参数
scripts/filelists/*.f           // 新 RTL 编译顺序
```

---

## 2. 阶段 1：冻结边界与参数

### 2.1 工作内容

1. 新增 `CoreConfig.sv`：
   - `FETCH_WIDTH=2`
   - `DECODE_WIDTH=2`
   - `RENAME_WIDTH=2`
   - `COMMIT_WIDTH=2`
   - `ROB_DEPTH=32`
   - `PHYS_REGS=63`
   - `INT_IQ_DEPTH=7`
   - `MULDIV_IQ_DEPTH=3`
   - `MEM_IQ_DEPTH=5`
   - `STORE_BUFFER_DEPTH=8`
   - `BPU_GHR_BITS=5`
   - `BPU_PHT_ENTRIES=512`
   - `BPU_BTB_ENTRIES=256`
   - `BPU_RAS_DEPTH=8`
   - `MUL_LATENCY=3`
   - `DRAM_READ_LATENCY=2`
2. 新增 `OoOTypes.sv`：
   - `uop_t`
   - `rob_entry_t`
   - `iq_entry_t`
   - `branch_meta_t`
   - `exception_t`
   - `writeback_t`
   - `mem_req_t`
3. 固定 `myCPU.sv` 外部接口方案：
   - 方案 A：`myCPU` 对外直接暴露双端口 IROM。
   - 方案 B：`myCPU` 仍暴露抽象 fetch 接口，由 `student_top` 内 wrapper 拆成双端口 IROM。
   - 建议采用方案 A，简单直观，但所有 TB/SoC filelist 必须同步。
4. 更新 filelist，保证 package 在所有模块前编译。
5. 在 `CoreConfig.sv` 中区分 NOP 原版事实和 superScalar 决策：
   - NOP 原版 BPU 是 global correlating predictor，非 tournament。
   - superScalar 目标 BPU 可参数化为 GShare/local/choice，但第一版可只打开 GShare。
   - NOP 原版 DCache line=64B；superScalar 第一版建议 line=16B。
   - NOP 原版 INT IQ 为压缩乱序队列，MulDiv/Mem IQ 为 FIFO；superScalar 第一版沿用这个分工。

### 2.2 完成标准

- Verilator 能只 elaboration/compile 空壳 core。
- Vivado 能读入 package 和空壳模块，无 package visibility 问题。
- 文档明确 IROM/DRAM/MUL/DIV latency 参数来源。

### 2.3 风险

- SystemVerilog package 在 Vivado 中的编译顺序敏感，必须把 `CoreConfig.sv`、`OoOTypes.sv` 放在 filelist 最前。
- 参数既用于 RTL 又用于文档/IP；不要让 Tcl 和 RTL 各自定义一份名字相同但值不同的常量。

---

## 3. 阶段 2：IROM 双端口与前端骨架

### 3.1 工作内容

1. 修改 Vivado Tcl：
   - `IROM_0` 生成双读端口 ROM。
   - 两个端口同 `cpu_clk`。
   - 保持 1 拍读延迟。
2. 修改 `rtl/ip/IROM_0.sv`：
   - 增加 `addrb/enb/doutb` 或等价端口。
   - 两端口行为都为“地址寄存 1 拍，下一拍数据有效”。
3. 修改 `student_top.sv`：
   - `irom_addr0/irom_addr1` 分别接 `pc` 和 `pc+4` 的 word 地址。
   - 保留 reset、MMIO、DRAM 连接不动。
4. 实现：
   - `FetchStage`
   - `FetchBuffer`
   - `BranchPredictor` 第一版
   - `RAS`
5. 前端先可接一个临时 in-order consumer，用于验证双路取指 PC/inst 对齐。
6. BPU 第一版实现顺序：
   - 先实现 GShare 5-bit history + 512 项 global PHT + 256 项 BTB + 8 项 RAS。
   - 保存每条指令的 `predict_taken/predict_target/pht_counter/ghr/ras_top`。
   - local history 和 choice PHT 先保留参数和结构位置，等 512 项预算口径确认后再打开。

### 3.2 验证

- 小程序连续取指，检查 `pc0/inst0`、`pc1/inst1` 对齐。
- branch redirect 后，FetchBuffer flush，下一拍从 target 重新取。
- IROM 边界/奇偶 PC 测试：若 `fetch_pc[2]` 不是 0，第二条 valid mask 处理正确。
- Vivado elaboration 确认双端口 IROM blackbox/IP wrapper 端口一致。

### 3.3 完成标准

- 前端可以稳定输出最多 2 条 `{pc, inst}`。
- redirect 不会把旧路径指令送入 decode。
- Verilator 行为模型与 Vivado IROM 端口/latency 文档一致。

---

## 4. 阶段 3：RV32IM Decode 与微操作定义

### 4.1 工作内容

1. 重写或扩展 `Decode.sv` 为 `Rv32Decode.sv`。
2. 覆盖 RV32I：
   - LUI/AUIPC
   - JAL/JALR
   - BEQ/BNE/BLT/BGE/BLTU/BGEU
   - LB/LH/LW/LBU/LHU
   - SB/SH/SW
   - ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
   - ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
3. 覆盖 RV32M：
   - MUL/MULH/MULHSU/MULHU
   - DIV/DIVU/REM/REMU
4. 覆盖 SYSTEM/MISC-MEM：
   - ECALL
   - EBREAK
   - MRET
   - FENCE
   - CSRRS/CSRRC/CSRRW 及 immediate 变体，按 rv32mi 需要裁剪
5. 非目标指令输出 illegal instruction exception。

### 4.2 验证

- 指令编码表单元测试或 Verilator decode-only smoke。
- 对照现有 rv32 测试反汇编，抽样确认立即数、rd/rs、funct3/funct7。
- Zb 指令先判 illegal，避免错误执行成 ALU 指令。

### 4.3 完成标准

- RV32I/M/SYSTEM 目标指令都能生成完整 `uop_t`。
- illegal、ecall、ebreak、mret、fence 的微操作类别明确。

---

## 5. 阶段 4：Rename、ROB、物理寄存器文件

### 5.1 工作内容

实现以下模块：

- `PhysRegFile`
- `Rat`
- `FreeList`
- `BusyTable`
- `RenameStage`
- `Rob`

建议顺序：

1. 先做单宽 rename/commit 骨架。
2. 再扩展到双宽 batch rename。
3. 最后加入同 batch bypass、资源不足 stall、flush 恢复。

Vivado 友好做法：

- `PhysRegFile` 第一版用 FF 数组实现多读多写，写端口来自 INT0/INT1/MulDiv/LSU 的仲裁或固定 WB bus。
- x0 读值硬连 0，禁止分配/写入。
- ROB 用 packed entry 数组 + head/tail/count；不要用 queue。
- FreeList 用环形 FIFO，提供最多 2 个 allocate 和最多 2 个 free。

### 5.2 验证

- 人工 directed：
  - 连续写同一 rd。
  - batch 内 `add x2,x1,x1` 紧跟 `add x3,x2,x2`。
  - ROB 满、FreeList 空、IQ 满反压。
  - flush 后 SpecRAT/FreeList 恢复。
- 先用简单 fake execute 立即完成 uop，验证 commit 顺序。

### 5.3 完成标准

- 2 宽 rename/dispatch/commit 在无执行延迟模型下能按顺序提交。
- 异常/redirect 恢复后不泄漏物理寄存器。

---

## 6. 阶段 5：Issue Queue 与整数执行

### 6.1 工作内容

1. 实现两类 issue queue，不强行统一成一个复杂模块：
   - `IntIssueQueue`：压缩队列，参数化 depth，最多 2 路 dispatch 写入，监听 clearBusy/writeback 唤醒，支持两个 INT pipe oldest-ready 选择。
   - `MulDivIssueQueue`：FIFO，最多 2 路 dispatch 写入，只从 head 发射。
   - `MemIssueQueue`：FIFO，最多 2 路 dispatch 写入，只从 head 发射。
2. 实现两个 INT pipe：
   - `INT0`：ALU + BRU + CSR/SYSTEM。
   - `INT1`：ALU。
3. 实现 bypass/writeback bus：
   - `valid`
   - `pdst`
   - `data`
   - `rob_idx`
   - `exception`
4. 分支 resolve：
   - 比较 predicted direction/target。
   - 生成 redirect。
   - 更新 BPU/BTB/RAS。
   - 通知 ROB/rename flush younger。
5. 第一版不实现 NOP-Core 的 load speculative wakeup；所有 load 依赖按真实 WB/forwarding 唤醒。等 DCache/StoreBuffer 正确性稳定后，再单独增加 speculative wakeup 和 wakeupFailed 恢复。

### 6.2 验证

- ALU directed tests。
- 分支 taken/not-taken/jal/jalr directed。
- 误预测 flush 后不提交旧路径指令。
- `rv32ui` 中不含 load/store 压力的子集先跑。

### 6.3 完成标准

- RV32I 非访存、非 CSR 子集能通过。
- 双 INT pipe 不产生同一物理寄存器多写冲突。
- 分支预测错误恢复正确。

---

## 7. 阶段 6：CSR、异常、MRET、FENCE

### 7.1 工作内容

1. 实现 `CsrFile`：
   - `mstatus`
   - `mtvec`
   - `mscratch`
   - `mepc`
   - `mcause`
   - `mtval`
   - `mie`
   - `mip`
   - `cycle`
   - `minstret`
2. CSR 指令在 INT0 执行，实际 architectural side effect 在 commit 点生效。
3. 实现精确异常：
   - illegal instruction
   - ecall
   - ebreak
   - load/store misaligned
4. 实现 `mret`：
   - commit 点恢复 PC 到 `mepc`。
   - 恢复必要 mstatus 位。
5. 实现 `fence`：
   - 第一版作为序列化指令。
   - 等待 older store 已 retired 或 StoreBuffer 可证明无未完成外部写后提交。

### 7.2 验证

- `rv32mi`。
- ecall/ebreak trap vector directed。
- mret 返回 directed。
- fence 后 store/load 顺序 directed。

### 7.3 完成标准

- `rv32mi` 目标项通过。
- 异常发生后 younger 指令无提交、store 无提前写内存。

---

## 8. 阶段 7：MulDiv

### 8.1 工作内容

1. 实现 `MulDivIssueQueue` 和 `MulDivPipe`。
2. 接入现有 `MUL_0`：
   - 33x33 signed。
   - `MUL_LATENCY=3`。
   - `mul/mulh/mulhsu/mulhu` 选位正确。
3. 接入现有 `DIV_0`：
   - AXI-stream valid 输入。
   - 等 `m_axis_dout_tvalid`。
   - packing: `{quotient, remainder}`。
4. 特殊除法结果不启动 IP，直接完成：
   - divisor = 0。
   - `INT_MIN / -1`。

### 8.2 验证

- `rv32um`。
- 单独 directed：
  - 连续两条 MUL。
  - MUL 后立即使用结果。
  - DIV 后立即使用结果。
  - 四种除法特殊情况。
- Vivado elaboration 确认 `DIV_0` 端口没有多余 tready 连接。

### 8.3 完成标准

- `rv32um` 通过。
- Verilator `rtl/ip/MUL_0.sv`、`rtl/ip/DIV_0.sv` 与 Tcl 参数一致。
- 若板上 M 扩展出错，第一优先检查 DIV packing 和 MUL latency。

---

## 9. 阶段 8：Mem Pipe、StoreBuffer、DCache2Way

### 9.1 工作内容

1. 实现 `StoreBuffer`：
   - execute 入队。
   - commit 标记 retired。
   - retired head 后台写 DCache/MMIO。
   - load 查询 forwarding。
2. 实现 `MemIssueQueue`：
   - 第一版保守策略，older store 地址未知则阻塞 younger load。
3. 实现 `DCache2Way`：
   - 2-way set associative。
   - line size 第一版建议 16B；保留 32B/64B 参数。
   - write-back + write-allocate。
   - dirty bit。
   - LRU。
   - miss writeback/refill FSM。
   - uncached 单次读写。
4. 接入当前 `SocMemBridge`：
   - 一次只发一个外部请求。
   - 等 `dmem_resp_valid` 后推进下一 word。
   - MMIO 强制 uncached。
5. 若 DRAM 目标改成 2 拍：
   - 同步 Tcl、`DRAM_0.sv`、`DramBramAdapter.sv`。
6. StoreBuffer 的 uncached 策略单独落文档和 directed test：
   - cached store：execute 入队，commit 后写 DCache。
   - uncached/MMIO store：execute 入队，commit 后发 DMEM 写。
   - uncached/MMIO load：不得在提交可见前释放目标寄存器生命周期；第一版可选择阻塞到 commit 后访问，或做 NOP-Core 风格的 StoreBuffer LDU 重放。

### 9.2 验证

- load/store directed：
  - byte/half/word 对齐。
  - misaligned exception。
  - store-to-load forwarding。
  - store 提交前异常 flush 不写内存。
  - DCache hit/miss。
  - dirty eviction writeback。
  - MMIO 不缓存。
- `rv32ui` 完整。
- src smoke 初步跑 LED/SEG/CNT。

### 9.3 完成标准

- `rv32ui` 通过。
- store 精确异常成立。
- DCache miss 不依赖外部 burst/multiple outstanding。
- MMIO 写 LED/SEG/CNT 可被 `student_top` 观测。
- 未启用 load speculative wakeup 时，依赖 load 的指令不会提前读到无效数据。

---

## 10. 阶段 9：全核集成与性能计数

### 10.1 工作内容

1. 集成完整 `ooo_core.sv`。
2. `myCPU.sv` wrapper 暴露当前 SoC/debug/perf 端口。
3. 接入 `PerfCounter`：
   - cycle。
   - commit count。
   - branch count/miss。
   - DCache access/miss。
   - ROB full cycles。
   - IQ full cycles。
   - StoreBuffer full cycles。
   - memory stall。
4. 更新 Verilator result JSON 字段，保持现有 src checker 可用。
5. 保留旧顺序核分支或 backup，便于 A/B 对比。

### 10.2 验证

- `rv32ui`
- `rv32um`
- `rv32mi`
- ecall/ebreak/fence/mret directed
- `srcSmoke`
- `srcWithMext/srcWithoutMext` 至少观察运行进度

### 10.3 完成标准

- correctness 测试通过。
- 性能计数不为 X，不因 flush/exception 重复计数。
- Verilator 没有 latch、width、uninitialized 关键警告。

---

## 11. 阶段 10：Vivado 综合与上板闭环

### 11.1 工作内容

1. 更新 `fpga/create_vivado_project.tcl`：
   - 双端口 IROM。
   - DRAM latency。
   - MUL/DIV 参数确认。
   - 新 filelist/source 顺序。
2. 重新生成干净 Vivado project。
3. 跑：
   - elaboration。
   - synthesis。
   - implementation。
   - timing summary。
4. 检查：
   - no blackbox。
   - no inferred latch。
   - no unconstrained clocks。
   - CPU domain WNS >= 0。
   - CDC XDC 生效。
5. 生成 bitstream，上板验证：
   - reset 后非全 0。
   - src LED/SEG 进度。
   - UART/twin 读回状态。

### 11.2 上板失败优先排查表

| 症状 | 优先检查 |
|---|---|
| LED/SEG 全 0 | reset、IROM 初始化、IROM latency/双端口接线、PC reset |
| 仿真过但板上随机跑飞 | DRAM latency、byte lane、Vivado IP stale build |
| M 扩展板上错 | `DIV_0` packing、`MUL_0` latency、IP Tcl 与模型不一致 |
| MMIO 不更新 | DCache cacheable 范围、StoreBuffer retired 写出、`0x8020_xxxx` uncached |
| timing 负 WNS | IQ select、ROB commit、BPU read、PhysRegFile 多端口、DCache tag/data compare |
| CDC 违例 | `digital_twin_cdc.xdc`、CPU->50MHz 裸同步、SEG/LED 镜像路径 |

### 11.3 完成标准

- Vivado routed timing 通过或有明确约束解释。
- bitstream 来自最新 Tcl/IP/RTL。
- 上板可见测试进度，不出现“Verilator pass、FPGA 全 0”。

---

## 12. 推荐实施顺序

按风险和依赖排序：

1. 文档与参数冻结。
2. IROM 双端口 IP/模型/`student_top`。
3. 前端 FetchBuffer + BPU 骨架。
4. Decode。
5. Rename + ROB + PhysRegFile。
6. INT issue/execute/branch flush。
7. CSR/异常/mret/fence。
8. MulDiv IP 接入。
9. StoreBuffer + DCache2Way。
10. 全核集成。
11. Verilator 全回归。
12. Vivado synth/impl/timing。
13. 上板。

不要把 DCache、CSR、MulDiv、BPU 全部等到最后一次性接入。每接一类执行单元就跑对应最小测试，否则 debug 面会大到不可控。

---

## 13. 阶段性测试矩阵

| 阶段 | 最小测试 | 必跑验证 |
|---|---|---|
| IROM/Fetch | 连续取指 directed | Verilator + Vivado elaboration |
| Decode | decode table directed | illegal 指令检查 |
| Rename/ROB | fake execute commit | flush/free list 恢复 |
| INT | ALU/branch directed | rv32ui 子集 |
| CSR/Exception | trap directed | rv32mi |
| MulDiv | M directed | rv32um |
| Memory | load/store directed | rv32ui 完整 |
| DCache | hit/miss/dirty/MMIO | srcSmoke |
| Full SoC | rv32ui/um/mi/src | Verilator result JSON |
| FPGA | clean build | timing + board LED/SEG |

---

## 14. 代码风格与综合注意事项

1. 所有状态机用 `typedef enum logic`。
2. 所有跨模块 payload 用 packed struct，package 中定义。
3. 队列使用 head/tail/count，不使用不可综合 queue。
4. 大数组读写都显式时钟化。
5. `always_comb` 默认赋值完整，避免 latch。
6. `unique case` 只在确实覆盖完整编码时使用；否则要有 default。
7. 对所有 valid/data pipeline，valid 必须和 data 同拍 reset/flush。
8. flush 与 stall 同时发生时，优先级必须全局一致：reset > flush > stall > advance。
9. 所有 debug/perf 信号不得反向影响功能路径。
10. Vivado 关键路径出现后，优先插 pipeline，不靠降低时钟或关闭优化掩盖问题。

---

## 15. 未决但可后续调参的项

这些项不阻塞第一版实现，但必须参数化：

| 项 | 默认 | 后续可调 |
|---|---:|---|
| DCache 容量 | 8 KiB 或资源友好值 | 4/8/16 KiB |
| DCache line size | 16B | 32/64B，需评估单 DMEM refill 代价 |
| Local/choice BPU | 可开 | 若 timing 差，退化 GShare only |
| Commit width | 2 | 若 timing 好可试 3，但与 2 宽前端收益有限 |
| ROB depth | 32 | 16/24/32/48 |
| IQ depth | 7/3/5 | 根据资源和 stall bucket 调 |
| CPU 频率 | 当前工程默认 | 以 routed timing 为准 |

---

## 16. 最终验收定义

任务完成必须同时满足：

1. RTL 可综合，Vivado clean elaboration/synthesis。
2. Verilator 通过目标 ISA/SoC 测试。
3. Vivado IP 参数、仿真模型、adapter、文档四者一致。
4. 上板 bitstream 能运行测试并通过 LED/SEG/UART 可观测路径确认。
5. 文档记录最终参数、测试命令、timing 摘要、板级现象和残余风险。

只达到“模块仿真能跑”不算完成；只达到“Vivado 能综合”但 rv32/src 不过也不算完成。这个迁移的完成线是：同一个 RTL 在仿真和 FPGA 真实 IP 时序下都能工作。
