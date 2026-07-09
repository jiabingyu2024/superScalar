# superScalar 迁移后目标架构与微架构

> 实施冻结说明：RTL 实施以 `implementation_freeze.md` 为最终决策记录。若本文旧段落仍保留 16B DCache line 或 GShare-only 起步等探索性建议，实施时以 32B DCache line、真双口 IROM、完整参数化 tournament BPU 为准。

> 日期：2026-07-09
> 目标：把 NOP-Core 的乱序多发射思想迁移到 superScalar，但边界适配当前 RISC-V SoC、Vivado IP、板级 MMIO 和上板时序合同。
> 实现方式：手写 SystemVerilog，要求可综合、Vivado 友好、可上板，不以“仅仿真通过”为完成标准。

---

## 1. 总体目标

迁移后的 superScalar 是一个面向 FPGA 上板的 RV32IM 乱序双发射处理器。设计采用 Tomasulo 风格发射队列、物理寄存器重命名、ROB 顺序提交、精确异常、StoreBuffer 延迟写内存、写回写分配 DCache 和参数化分支预测器。

源码阅读后的迁移口径：NOP-Core 原版是 `fetchWidth=4/decodeWidth=3/retireWidth=3`，INT IQ 使用可乱序压缩队列，MulDiv/Mem IQ 使用 FIFO。superScalar 第一版不照搬 3 宽，而是按当前 SoC 和 Vivado 时序风险收敛到 2 宽，并保留“INT 可乱序、Mem/MulDiv 保守 FIFO”的边界。

与 NOP-Core 的关系是“参考微架构，不直接移植语言/总线/ISA”：

| 维度 | NOP-Core | superScalar 迁移目标 |
|---|---|---|
| ISA | LA32R | RV32I + RV32M + 必要 M-mode CSR/异常 |
| 实现语言 | Scala/SpinalHDL 生成 Verilog | 手写 SystemVerilog |
| 发射宽度 | 3 宽 | 2 宽起步 |
| 取指 | ICache + AXI iBus | 不做 ICache，IROM BRAM 改双读端口支持 2 路取指 |
| 数据存储 | AXI DCache/uncached | 保留 superScalar 单 DMEM req/resp 边界 |
| 地址转换 | TLB/MMU | 不做虚实转换，物理地址直访 |
| 上板边界 | NOP-Core 自有 SoC | 适配当前 `student_top.sv`、`SocMemBridge.sv`、Vivado IP 和 `0x8020_xxxx` MMIO |

本设计的第一目标是正确、可综合、可在 Vivado 中收敛。性能优化按参数化方式保留空间，不能为了 IPC 引入当前 SoC 不支持的多 outstanding、乱序内存返回或不可约束 CDC。

---

## 2. SoC 边界合同

迁移后的 `myCPU` 顶层仍挂在当前 `student_top.sv` 下。除 IROM 可有限扩展为双端口外，SoC 边界不重构。

### 2.1 时钟与复位

- `cpu_clk`：core、IROM、DRAM、DCache、ROB、寄存器文件和 MMIO 寄存器主时钟。
- `w_clk_50Mhz`：UART/twin/counter/display 侧时钟。
- `cpu_rst`：CPU 域同步释放、高有效 reset。
- 新 core 内部只使用同步 reset；若某个 Vivado RAM/IP 需要独立 reset，必须在 wrapper 内处理，不能把板级异步 reset 直接打入深层模块。
- 任何 CPU 域到 50 MHz 域的观测信号必须经现有 CDC 规则同步，不能新增裸跨域组合路径。

### 2.2 指令存储接口

A1 决策：不做 ICache；允许修改 IROM BRAM IP 为双端口，从而支持 2 路取指。

目标取指合同：

```text
cycle N:
  fetch 发出 pc0 = fetch_pc、pc1 = fetch_pc + 4
  irom_ena0/irom_ena1 有效，IROM 接收两个 word 地址

cycle N+1:
  irom_data0/irom_data1 返回对应两条 32-bit 指令
  fetch stage 同拍携带 pc0/pc1、预测信息和 valid mask
```

实现约束：

- Vivado 侧把 `IROM_0` 从单端口 ROM 调整为 true dual-port ROM 或等价双读端口 ROM。
- Verilator 行为模型 `rtl/ip/IROM_0.sv` 必须同步改成同样端口和同样 1 拍读延迟。
- `student_top.sv` 内做端口适配，保留原程序镜像和 `irom_addr[13:2]` 地址截位语义。
- 取指每拍最多 2 条，遇到跨自然 8 字节边界、分支预测跳转或 IROM 范围边界时用 valid mask 限制第二条。
- 不做指令 cache line refill，不引入 instruction bus outstanding，也不让前端要求 SoC 支持 stallable AXI。

### 2.3 数据存储接口

A2 决策：按 `docs/fpga/ip_timing_alignment.md` 的 IP 时序维护方式，目标 DRAM 响应合同采用固定 2 拍读返回；DCache miss 首词等效为“发请求 1 拍 + DRAM 2 拍”，即首次拿到数据约 3 拍。

外部接口仍是当前 DMEM ready/valid：

```text
request:
  dmem_req_valid
  dmem_req_ready
  dmem_req_write
  dmem_req_addr
  dmem_req_wdata
  dmem_req_wstrb
  dmem_req_uncached

response:
  dmem_resp_valid
  dmem_resp_rdata
```

关键限制：

- SoC 侧不支持多个 outstanding transaction。
- DCache refill 不使用外部 burst，而是发起连续 32-bit word 读请求；每次请求必须等对应响应回来后再发下一 word，除非后续明确重写 `SocMemBridge/DramBramAdapter`。
- 写请求没有写响应；StoreBuffer 在提交后发出写请求，并以 `req_valid && req_ready` 作为接受点。
- byte lane 继续沿用当前 SoC 合同：core 发低位对齐 `wdata/wstrb`，adapter 根据 `addr[1:0]` 左移写入；读回数据由 adapter 右移到低位。

如果把真实 Vivado `DRAM_0` 改成 2 拍读返回，必须同一批修改：

1. `fpga/create_vivado_project.tcl` 中 `DRAM_0` 输出寄存/latency 参数。
2. `rtl/ip/DRAM_0.sv` 仿真行为模型。
3. `rtl/soc/DramBramAdapter.sv` 的 `resp_valid` 和 offset pipeline。
4. DCache miss/uncached 等待状态的回归测试。

### 2.4 地址空间与 MMIO

A3 决策：cacheable/DRAM 范围保持当前 SoC 设计：

```text
DRAM/cacheable: 0x8010_0000 <= addr < 0x8014_0000  // 256 KiB
MMIO:           0x8020_xxxx
```

当前 MMIO 地址：

| 地址 | 设备 |
|---|---|
| `0x8020_0000` | SW0 |
| `0x8020_0004` | SW1 |
| `0x8020_0010` | KEY |
| `0x8020_0020` | SEG |
| `0x8020_0040` | LED |
| `0x8020_0050` | CNT |

DCache 只缓存 `0x8010_0000 ~ 0x8014_0000`。其他地址强制 uncached，不允许把 MMIO 放进 cache。

---

## 3. 全局微架构参数

| 参数 | 第一版目标 | 说明 |
|---|---:|---|
| `FETCH_WIDTH` | 2 | 双端口 IROM 每拍最多取 2 条 |
| `DECODE_WIDTH` | 2 | RV32 固定 32-bit 指令，先不做压缩指令 |
| `RENAME_WIDTH` | 2 | batch 内依赖由 rename 旁路处理 |
| `DISPATCH_WIDTH` | 2 | 每拍最多写入两个 ROB/IQ 条目 |
| `COMMIT_WIDTH` | 2 | 与 2 宽实现匹配，降低 ROB commit 关键路径 |
| `ROB_DEPTH` | 32 | 沿用建议，后续可调 |
| `PHYS_REGS` | 63 | x0 固定零，额外物理寄存器覆盖 32 深 ROB |
| `INT_IQ_DEPTH` | 7 | 参数化 |
| `MULDIV_IQ_DEPTH` | 3 | 参数化 |
| `MEM_IQ_DEPTH` | 5 | 参数化 |
| `STORE_BUFFER_DEPTH` | 8 | 参数化 |
| `DCACHE_WAYS` | 2 | 2-way set associative，写回写分配 |
| `DCACHE_LINE_BYTES` | 16 起步 | 当前 SoC 无 burst，先降低 refill 代价；后续可调 |
| `MUL_LATENCY` | 3 | 保持现有 `MUL_0` IP 三拍 |
| `DIV_LATENCY` | 由 `DIV_0` valid 决定 | 保留 Vivado `DIV_0` IP |

所有深度和宽度必须写成 parameter/localparam，并集中放在包或 `OoOConfig.sv` 中，避免散落魔数。

---

## 4. 前端

### 4.1 PC 与取指队列

前端由 `PcGen`、`FetchStage`、`FetchBuffer`、`BranchPredictor` 组成。

PC 选择优先级：

```text
异常/中断 redirect
  > mret redirect
  > 分支误预测 redirect
  > RAS return target
  > BTB/BPU predicted target
  > fetch_pc + 8
```

`FetchBuffer` 存储每条指令的：

- `valid`
- `pc`
- `inst`
- `pred_taken`
- `pred_target`
- `pred_kind`
- `ras_used`
- `bpu_meta`

FetchBuffer 必须支持：

- 每拍最多 push 2 条。
- 每拍最多 pop 2 条给 decode。
- redirect 时同步 flush。
- full 时反压 PC 发射，不再访问 IROM。

### 4.2 分支预测器

B3 决策：实现参数可配置的全局/局部竞争历史预测器，默认资源如下：

| 结构 | 默认值 | 说明 |
|---|---:|---|
| Global history | 5 bit | 投机更新，redirect 恢复 |
| Global PHT | 512 项 | GShare index，2-bit 饱和计数器 |
| Local history/PHT | 参数化 | 可配置打开；是否也给 512 项需确认 |
| Choice PHT | 参数化 | 可配置打开；是否也给 512 项需确认 |
| BTB | 256 项 | 直接映射或低复杂度组相联，存 tag/target/kind |
| RAS | 8 项 | JAL/JALR call/return 维护 |

注意：NOP-Core 原版不是 tournament predictor。源码中 `BPUConfig` 为 global correlating predictor，`useGlobal=true/useLocal=false/useHybrid=false`，PHT 为 8192 项，GHR 为 5 bit，地址索引用 `GHR @@ PC` 拼接方式。superScalar 的“全局与局部竞争历史预测器”是迁移时新增/调整的目标，不是 NOP 原样照搬。

Vivado 友好约束：

- PHT/BTB/RAS 读路径不能成为 decode/rename 组合关键路径；预测读结果在 fetch pipe 中打一拍。
- PHT 用分布式 RAM 或寄存器数组均可，512 项规模优先保证时序。
- BTB 推荐用同步读 RAM + tag compare；若组合读导致 timing 差，改成 fetch 两级。
- BPU 更新在分支实际执行或提交处进行，但必须保证误预测 flush 后全局历史可恢复。
- RAS 必须保存 recover top；只做 push/pop、不做 mispredict 恢复会在调用/返回密集程序中逐渐错位。

第一版建议实现 `GShare + BTB + RAS` 并预留 local/choice 参数和端口；若 tournament 打开后影响频率，可退化到 GShare only。

---

## 5. Decode、Rename、Dispatch

### 5.1 ISA 范围

C1 决策：第一阶段只覆盖：

- `rv32ui`
- `rv32um`
- `rv32mi`
- `ecall`
- `ebreak`
- `fence`
- `mret`

先不做 Zb/Bitmanip，不做压缩指令，不做 S/U mode，不做 MMU。

Decode 输出统一微操作 `uop_t`，至少包含：

- `valid`
- `pc`
- `inst`
- `fu_type`：INT/BRU/LSU/MULDIV/CSR/SYSTEM
- `alu_op`
- `branch_op`
- `lsu_op`、`mem_size`、`mem_signed`
- `muldiv_op`
- `csr_op`
- `rs1/rs2/rd`
- `imm`
- `has_rd`
- `is_load/is_store/is_branch/is_jump/is_csr/is_fence/is_trap/is_mret`
- 预测元数据

### 5.2 重命名

重命名结构：

- `SpecRAT[32]`：推测 arch -> phys。
- `ArchRAT[32]`：已提交 arch -> phys。
- `FreeList`：空闲物理寄存器 FIFO。
- `BusyTable[PHYS_REGS]`：物理寄存器结果是否 ready。

规则：

- x0 不分配物理寄存器，读恒 0，写被丢弃。
- 每拍最多重命名 2 条。
- 同 batch 内 younger 指令读 older 指令写的 rd 时，使用本拍新物理寄存器。
- redirect/异常时 `SpecRAT <= ArchRAT`，并恢复 FreeList/BusyTable 到提交状态。
- 分配 ROB 和物理寄存器必须是原子动作；ROB/IQ/FreeList 任一资源不足则整批 stall 或部分接受时保持顺序一致。

### 5.3 Dispatch

Dispatch 根据 `fu_type` 写入：

- Int IQ：ALU/BRU/CSR/SYSTEM/FENCE。
- MulDiv IQ：M 扩展。
- Mem IQ：load/store。

同一拍两条指令可写入不同 IQ；若写同一 IQ，需要双写端口或仲裁。第一版为了可综合和时序，建议 IQ 支持 2 路入队但每类每拍最多接受两条；实现上使用尾指针加 packed entry 数组，不使用不可综合动态队列。

---

## 6. 发射与执行

### 6.1 发射队列

IQ entry 保存：

- `valid`
- `uop`
- `rob_idx`
- `pdst`
- `psrc1/psrc2`
- `src1_ready/src2_ready`
- `src1_value/src2_value` 可选；第一版推荐 RRD 读寄存器，不在 IQ 存 full data

唤醒来源：

- INT WB
- MulDiv WB
- LSU load WB
- CSR/SYSTEM 完成

选择策略：

- INT IQ 内 age-based oldest ready，每拍最多 issue 2 条到两个 INT pipeline。
- MulDiv 每拍最多 issue 1 条，FIFO head ready 才发射。
- Mem 每拍最多 issue 1 条，FIFO head ready 才发射，保守按程序序处理 memory hazard。

按 NOP-Core 源码细节，第一版建议：

- INT IQ：做压缩队列，支持多个执行端口 oldest-ready 选择。
- MulDiv IQ：做 FIFO，只从 head 发射。
- Mem IQ：做 FIFO，只从 head 发射。

这样能保留整数乱序收益，同时避免 memory dependence 和可变延迟除法把恢复逻辑放大。

### 6.2 整数流水线

两个 INT pipeline：

```text
ISS -> RRD -> EXE -> WB
```

- `INT0`：ALU + BRU + CSR/SYSTEM。
- `INT1`：ALU。

分支在 EXE 级计算实际方向和目标，与预测元数据比较。误预测时：

1. 发 redirect PC。
2. flush FetchBuffer、Decode、Rename 后端 younger uop。
3. ROB 标记从误预测分支之后的所有未提交项无效。
4. 恢复 SpecRAT/FreeList/BusyTable。
5. 更新 BPU/BTB/RAS。

### 6.3 MulDiv 流水线

D1/D2 决策：

- `MUL_0` 保持 3 拍。
- `DIV_0` 保留 Vivado IP，等待 `m_axis_dout_tvalid`。

MulDivUnit 必须参数化：

```text
MUL_LATENCY = 3
DIV_LATENCY = 34  // 仅行为模型和文档记录；RTL 等 valid
```

乘法输入使用 33-bit signed 扩展，支持：

- `mul`
- `mulh`
- `mulhsu`
- `mulhu`

除法特殊情况在启动 IP 前处理：

- divisor = 0
- `INT_MIN / -1`

DIV packing 必须保持 `div_data[63:32] = quotient`、`div_data[31:0] = remainder`，与 Vivado IP demo/testbench 证据一致。

### 6.4 Load/Store 流水线

内存执行路径：

```text
ISS -> RRD -> ADDR -> MEM1 -> MEM2 -> WB
```

- `ADDR` 计算有效物理地址，检查非对齐访问。
- `MEM1/MEM2` 访问 DCache tag/data。
- load 命中在 MEM2 形成数据，WB 写回物理寄存器。
- store 计算地址和数据后进入 StoreBuffer，提交前不改变 cache/DRAM/MMIO。

第一版不做激进 load speculation：

- load 发射前检查 older store 地址是否未知。
- 若 older store 地址已知且同地址，走 StoreBuffer forwarding。
- 若 older store 地址未知，load 等待，避免内存顺序恢复逻辑扩大。
- 不启用 NOP-Core 的 load speculative wakeup。NOP 原版会在 MEM1 提前 clearBusy，若 MEM2 miss/stuck 再通过 `SpeculativeWakeupHandler` 暂停依赖 RRD；这对 IPC 有帮助，但第一版手写 SV 风险较高，建议跑通后作为优化项。

---

## 7. DCache 与 StoreBuffer

E1/F1 决策：采用写回写分配 DCache，并保留乱序 store 入队、顺序提交后写内存的 StoreBuffer。

### 7.1 DCache

目标结构：

| 项 | 值 |
|---|---|
| 组织 | 2-way set associative |
| 容量 | 参数化，建议第一版 8 KiB 或按 BRAM 资源下调 |
| line size | 16B 起步，匹配当前单 word DMEM refill；后续可调到 32B/64B |
| 写策略 | write-back + write-allocate |
| 替换 | 2-way LRU |
| cacheable | `0x8010_0000 ~ 0x8014_0000` |

NOP-Core 原版 DCache 是 64B line、2-way、每 way 4KiB，总容量 8KiB；data RAM 物理上按 32-bit word 组织，并不是每次读整行。superScalar 因为外部 DMEM 没有 AXI burst，第一版 line size 下调到 16B 更稳，后续如果 SocMemBridge 支持 burst 或连续请求流水化，再提高 line size。

当前 SoC 无 burst，因此 line refill 用连续单 word 请求：

```text
MISS_SELECT_VICTIM
  -> WRITEBACK_DIRTY_WORDS  // 如 victim dirty
  -> REFILL_WORD0
  -> REFILL_WORD1
  -> ...
  -> UPDATE_TAG_VALID_DIRTY
  -> REPLAY_LOAD_OR_STORE
```

Vivado 友好实现：

- data RAM 每 way 使用同步读 RAM，优先推断 BRAM 或用 XPM。
- tag/valid/dirty/LRU 可用寄存器数组或小 RAM。
- 不用异步大数组读。
- DCache FSM 一次只处理一个 miss，避免外部 outstanding 需求。

### 7.2 StoreBuffer

StoreBuffer entry：

- `valid`
- `retired`
- `rob_idx`
- `addr`
- `wdata`
- `wstrb`
- `cacheable`
- `size`

行为：

- store 在执行完成后入队，`retired=0`。
- commit 到该 store 时只标记 `retired=1`。
- StoreBuffer head 若 retired，则后台写 DCache 或 uncached MMIO/DRAM。
- younger load 查询 StoreBuffer；地址命中且 mask 覆盖时前传，否则等待。
- 异常/flush 时清除未 retired 的 store，保留已 retired 且正在写出的条目。

NOP-Core 的 StoreBuffer 还承载 uncached load/store：uncached load 需要等提交点后通过 StoreBuffer 重新访问 `udBus`，避免目标物理寄存器被提前回收。superScalar 第一版可以保留这个思想，但要改写成单 DMEM req/resp 版本：MMIO/uncached load 在 commit 可见前不能让 younger 指令依赖其结果提交。

---

## 8. ROB、提交、异常与 CSR

### 8.1 ROB

ROB 深度 32，每拍最多 dispatch 2、commit 2。

ROB entry：

- `valid`
- `done`
- `pc`
- `inst`
- `uop_class`
- `rd`
- `pdst`
- `old_pdst`
- `has_rd`
- `exception_valid`
- `exception_cause`
- `exception_tval`
- `is_store`
- `store_buffer_idx`
- `branch_mispredict`

提交顺序：

1. 从 ROB head 起按序检查最多 2 条。
2. 遇到未 done 或异常停止。
3. 正常提交更新 ArchRAT，回收 old phys，释放 ROB。
4. store 提交只标记 StoreBuffer retired。
5. CSR/系统指令在提交点生效，保证精确异常。

### 8.2 CSR 和异常

C2 决策：不做虚实转换，不做 TLB/MMU。

第一版 M-mode CSR：

- `mstatus`
- `mtvec`
- `mscratch`
- `mepc`
- `mcause`
- `mtval`
- `mie`
- `mip`
- `cycle/minstret` 或通过现有 perf counter 暴露

指令：

- `ecall`
- `ebreak`
- `mret`
- `fence`：第一版作为流水线/StoreBuffer 排空屏障，不改变内存模型。

异常优先级需覆盖：

- instruction illegal
- load/store address misaligned
- ecall from M-mode
- breakpoint
- mret

异常处理在 commit 点精确触发：

```text
flush younger
SpecRAT <= ArchRAT
恢复 FreeList/BusyTable
mepc <= faulting pc
mcause <= cause
mtval <= tval
pc <= mtvec
```

---

## 9. 可综合与 Vivado 友好约束

这是硬约束，不是编码偏好：

1. 所有 RTL 必须使用 synthesizable SystemVerilog；禁止 `#delay`、不可综合 `initial` 状态初始化、动态数组、class、queue。
2. 大容量结构优先同步读 RAM/XPM/BRAM；组合读大数组必须避免。
3. 多写端口寄存器文件不要直接推断巨型多端口 BRAM。第一版用 FF register file + 明确 bypass；若资源超标再做 banking/复制。
4. 分支预测、IQ 选择、ROB commit、FreeList 分配必须分级打拍，避免单周期大扇入。
5. 所有 IP latency 参数必须同时维护 Tcl、`rtl/ip` 行为模型、消费方 RTL 和文档。
6. 仿真通过不代表上板通过；每个阶段完成后必须至少做 Verilator SoC 回归和 Vivado synth/elab 检查。
7. 不新增未经约束的 CDC；CPU 频率或 PLL 改动必须重新看 routed timing。
8. `rtl/ip/*` 行为模型仅用于 Verilator，不加入 FPGA sources。

---

## 10. 目标模块层次

```text
rtl/core/
  CoreConfig.sv
  OoOTypes.sv
  myCPU.sv
  ooo_core.sv

  front/
    FetchStage.sv
    FetchBuffer.sv
    BranchPredictor.sv
    RAS.sv

  decode/
    Rv32Decode.sv

  rename/
    RenameStage.sv
    Rat.sv
    FreeList.sv
    BusyTable.sv

  dispatch/
    DispatchStage.sv

  issue/
    IssueQueue.sv
    IssueSelect.sv

  execute/
    IntPipe.sv
    BranchResolve.sv
    MulDivPipe.sv
    CsrPipe.sv

  memory/
    MemPipe.sv
    DCache2Way.sv
    StoreBuffer.sv

  commit/
    Rob.sv
    CommitStage.sv
    ExceptionUnit.sv

  regs/
    PhysRegFile.sv
    CsrFile.sv

  perf/
    PerfCounter.sv
```

`myCPU.sv` 是唯一对 `student_top.sv` 暴露 SoC 合同的 wrapper。内部模块名和端口可以演进，但外部边界必须稳定，除双端口 IROM 改造外不让板级顶层理解乱序核内部协议。

---

## 11. 第一版完成判据

架构完成不是“写完代码”，而是满足以下条件：

1. `rv32ui`、`rv32um`、`rv32mi`、`ecall/ebreak/fence/mret` 在 Verilator SoC 环境通过。
2. `srcSmoke` 或现有 src profile 能在 `student_top` 下跑到可观测 LED/SEG/CNT 行为。
3. Vivado elaboration、synthesis 通过，无 latch、无未约束黑盒、无不可综合结构。
4. 关键 IP 的 Tcl 参数、`rtl/ip` 模型和消费方状态机一致。
5. 上板 bitstream 使用最新 IP 重新生成，LED/SEG 不出现全 0 或明显跑飞。
6. timing report 中 CPU 域无负 WNS；若存在 CDC 相关 false path/asynchronous group 问题，必须在 XDC 中明确处理并记录。
