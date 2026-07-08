# 单发射五级流水高 IPC/高频微架构与 RTL 修改计划

日期：2026-07-08

## 1. 目标重定义

根据 `docs/design/pipe5_plan.md`，当前分支不再做固定 2-way 超标量/乱序处理器，改为单发射、顺序执行、顺序提交的五级流水 `riscv_cpu`。新目标不是“最保守能跑”，而是在保证正确性的基础上，让单发射设计尽量接近 `IPC=1`，同时 RTL 必须能稳定通过 Verilator 仿真并对 Vivado 综合/实现友好。

设计目标：

| 项目 | 目标 |
| --- | --- |
| 正确性 | 通过 `rv32ui`、`rv32um`、`rv32mi` 目标子集，支持 `ecall/ebreak/mret/fence/fence.i` |
| 峰值 IPC | 单发射峰值为 1，每周期最多提交 1 条 |
| 平均 IPC | 除 cache miss、除法、多周期 CSR/trap 外，常规 ALU/load-hit/store-hit/branch 代码尽量少插泡 |
| 频率 | 避免超长组合链、高扇出异步 reset、大面积全局 flush、巨大 mux/CAM |
| Verilator | 代码可仿真、可追踪、避免依赖综合器隐式初始化 |
| Vivado | 使用同步时序、清晰 RAM 推断、数组 reset 只清 valid/tag 控制位，避免大规模组合读写存储 |
| I-cache | 不做；IROM 改为单端口 ROM，继续使用一拍取指契约 |
| D-cache | 做一拍 hit、阻塞 miss 的 Vivado 友好 D-cache，MMIO uncached |

核心取舍：

1. 不做 OoO/rename/ROB，保持顺序精确状态，降低验证复杂度。
2. 不做 superscalar，峰值 IPC 限定为 1，但通过 forwarding、早期 redirect、一拍 D-cache hit、store buffer 等减少非必要 stall。
3. D-cache 首版做 blocking miss，不做 non-blocking load；但 store 通过小型 write buffer 尽量不阻塞前台流水。
4. 频率优先级高于复杂预测/复杂 cache 相联度。宁可 direct-mapped + 短路径，也不做第一版 2-way set associative。

## 2. 推荐流水线

建议 RTL 仍按五级流水实现，但前端拆出 PC 生成逻辑：

```text
PCG -> IF -> ID -> EX -> MA -> WB
```

`PCG` 不是额外提交级，只负责当前 PC、预测 next PC、IROM 请求和 redirect 优先级。由于 `IROM_0.sv` 是一拍寄存地址、随后组合读数据，PCG 和 IF 之间必须保存请求 PC/预测信息。

主数据流：

```text
PCG:
  pc_q
  -> branch predictor / static predictor
  -> irom_addrA, irom_enaA
  -> pc_next

IF:
  保存 req_pc/pred_taken/pred_target
  -> 绑定上一拍 IROM 返回 instruction
  -> if_id_reg

ID:
  decode
  -> regfile read
  -> immediate/control generation
  -> hazard check
  -> early JAL target 可在 ID 生成

EX:
  ALU/compare/branch target/JALR target
  -> forwarding 选择
  -> MUL/DIV 多周期保持
  -> redirect 判定

MA:
  D-cache tag/data hit path
  -> load align/extend
  -> store hit update + write buffer enqueue
  -> miss FSM 阻塞

WB:
  GPR/CSR writeback
  -> commit/debug/perf event
```

## 3. 性能策略

### 3.1 单发射 IPC 边界

单发射峰值 IPC 不可能超过 1。优化目标是减少以下泡泡：

| 泡泡来源 | 必须保留 | 可优化手段 |
| --- | --- | --- |
| RAW 数据相关 | load-use 可能必须停 | EX/MA/WB forwarding |
| branch redirect | 错预测必须 flush younger | 静态 BTFNT 或小 BPU，JAL 早期 redirect |
| D-cache miss | blocking miss 必须停 | 一拍 hit、critical-word-first、store buffer |
| store 写外部 memory | 不应每次阻塞前台 | write buffer |
| MUL/DIV | 多周期执行必须停对应指令 | EX 持有，其他控制保持简单 |
| CSR/trap | 精确状态要求停 | serial 化，范围小 |

目标常规路径：

```text
ALU -> ALU dependent:        0 bubble，EX forwarding
ALU -> branch dependent:     0 bubble，EX forwarding 给比较器
load hit -> independent:     0 bubble
load hit -> dependent:       1 bubble 或更少，取决于 MA->EX 时序
store hit:                   0 bubble，若 write buffer 非满
JAL:                         尽量 1 bubble，ID/EX redirect
conditional branch correct:  0 bubble
conditional branch miss:     flush IF/ID，约 2 bubble
```

### 3.2 分支策略

第一版建议不要固定纯 not-taken 到底。为了较高 IPC，至少实现静态预测：

| 指令 | 初版预测 |
| --- | --- |
| JAL | ID 识别后 redirect，后续可在 PCG 预测 |
| JALR | 默认 not-taken，EX 得到 target 后 redirect |
| conditional branch | BTFNT：target < pc 预测 taken，target >= pc 预测 not-taken |

但 BTFNT 需要 branch immediate，PCG 拿不到指令。实际分两阶段：

1. Phase A：固定 not-taken，优先把流水正确性和 forwarding 跑通。
2. Phase B：加小型 BTB/PHT，PCG 用 `pc_q` 查预测；EX 更新预测器。

推荐 BPU 结构：

| 结构 | 建议 |
| --- | --- |
| BTB | 64 或 128 entry direct-mapped，valid/tag/target |
| PHT | 2-bit saturating counter，和 BTB 同 index |
| 更新 | EX 阶段知道真实 taken/target 后更新 |
| reset | 只清 valid，不清 target/tag payload |
| Vivado | 小数组可用寄存器或 distributed RAM，避免大规模异步 reset |

正确性要求：预测只能影响取指方向，不能影响架构态。EX 真实结果与预测不一致时 flush IF/ID 并重定向。

### 3.3 D-cache 策略

用户需要 D-cache，同时要求高 IPC 和高频。推荐首版：

| 属性 | 选择 | 原因 |
| --- | --- | --- |
| 类型 | direct-mapped blocking D-cache | hit 路径短，容易综合收敛 |
| 容量 | 1 KiB 或 2 KiB | 小而可控，先保证时序 |
| line | 16B，4 word | fill FSM 简单 |
| hit latency | 1 cycle MA hit | load-hit 不额外增加 miss FSM 延迟 |
| miss | blocking，critical-word-first 可选 | 正确性简单 |
| store | write-through + small write buffer | store hit 不因外部写阻塞前台 |
| store miss | no-write-allocate，写入 write buffer | 避免 miss 时分配复杂性 |
| MMIO | uncached，且绕过 write buffer 合并 | SW/KEY/SEG/LED/counter 不能缓存 |
| reset | 只清 valid bit | data/tag payload 不全清，写入时完整覆盖 |

D-cache 一拍 hit 设计要点：

```text
EX 周期末:
  ex_ma_addr/ex_ma_mem_op 打入 MA

MA 周期:
  index 选择 tag/data
  tag compare
  load hit: data word -> align/extend -> ma_wb
  store hit: byte merge 更新 data array，同时 write buffer enqueue
  miss: 锁存 miss context，冻结流水，进入 fill FSM
```

Vivado 友好说明：

1. 如果 data array 用同步 RAM，严格 1-cycle hit 会变成 EX 发地址、MA 取数据、WB 使用，仍可接受；不要为了“组合读一拍”推断出巨大 LUT mux。
2. 小容量 direct-mapped 可以先用寄存器数组 + 组合读，验证方便；上板前若 Fmax 不够，再切为同步 RAM。
3. tag compare、byte select、load sign extend 必须分层写，避免一条 `always_comb` 里塞完整 cache/memory 控制。

## 4. 接口和时序契约

### 4.1 `myCPU` 顶层端口

| 端口 | 新语义 | 关键约束 |
| --- | --- | --- |
| `irom_addr` | 当前 PCG 请求地址 | 单端口 IROM，对齐 IF 保存的请求 PC |
| `irom_data` | 上一拍请求的指令 | 不能按当前 PC 解释 |
| `irom_ena` | 取指使能 | stall 时保持 PC/IF payload 稳定 |
| `dmem_req_*` | D-cache/LSU 访问请求 | ready/valid，不再使用旧固定两拍 perip 总线 |
| `dmem_resp_*` | DRAM/MMIO 返回 | DRAM read 目标为请求后下一拍 `resp_valid` |

### 4.2 IROM

`rtl/ip/IROM_0.sv` 计划改为单端口 ROM，时序契约：

```text
T0: CPU 输出 word address，IROM posedge 寄存 address
T0 后: dout = mem[addr_q]
T1: IF 使用上一拍 PC 对应的 dout
```

RTL 自检点：

1. `if_pc` 必须等于发出 `irom_addr` 时的 PC。
2. branch flush 时，要清掉已经取回但属于错路的 IF/ID。
3. stall 时，不能让 `if_pc` 保持但 `if_inst` 换成另一条。

### 4.3 DRAM/MMIO

旧 `perip_bridge` 当前统一两拍读返回，但新设计不沿用该契约。新 `DramBramAdapter/SocMemBridge` 对 core 暴露 ready/valid：

```text
T0: read request accepted
T1: resp_valid + resp_rdata valid
```

store 写入在 request accepted 后生效或返回 store ack。D-cache fill、uncached load、MMIO load 都等待 `resp_valid`，不在 core 内写死等待拍数。

## 5. 控制流与优先级

建议全局优先级：

```text
reset
  > trap/mret redirect
  > branch/jump mispredict redirect
  > dcache_miss_wait / uncached_wait / muldiv_busy
  > load_use_stall / structural_stall
  > normal_advance
```

控制范围：

| 控制 | 来源 | 行为 |
| --- | --- | --- |
| `flush_if_id` | EX redirect 或 trap | 清 younger 指令 |
| `flush_id_ex` | redirect 或 ID 插 bubble | 防止错路/冲突进入 EX |
| `stall_front` | load-use、EX busy、MA busy | 冻结 PCG/IF/ID |
| `stall_ex` | MUL/DIV busy 或 MA 不能接收 | 保持 ID/EX 或 EX 内部状态 |
| `stall_ma` | D-cache miss/fill/uncached wait | 保持 EX/MA miss context，冻结更早级 |
| `wb_commit` | MA/WB valid 且未 kill | GPR/CSR 写和 perf commit |

重要边界：

1. EX 发现 branch miss 时，只 flush IF/ID 和必要的 ID/EX younger bubble；MA/WB 中更老指令必须继续完成。
2. D-cache miss 时冻结整条前台流水，但 WB 中已完成的更老指令可以提交，具体取决于寄存器切分。第一版可以全局冻结，简单但多损失少量 IPC。
3. trap/mret 是精确控制事件，建议要求前序已到 WB 或流水可证明有序后再更新 CSR/PC。

## 6. RTL 结构计划

### 6.1 文件结构

建议重建 `rtl/core`，不要在旧 OoO 文件上继续补丁式修改：

```text
rtl/core/
  CoreTypes.sv
  myCPU.sv
  riscv_cpu.sv
  front/
    PcGen.sv
    FetchStage.sv
    BranchPredictor.sv
  decode/
    Decode.sv
  regs/
    RegFile.sv
    CsrFile.sv
  execute/
    Alu.sv
    BranchUnit.sv
    MulDivUnit.sv
  memory/
    LoadStoreUnit.sv
    DCache.sv
    StoreWriteBuffer.sv
  control/
    HazardUnit.sv
    PipelineCtrl.sv
  perf/
    PerfCounter.sv
```

若第一轮希望更快通过 Verilator，可先合并成较少文件，但逻辑边界不要混：

```text
CoreTypes.sv
RegFile.sv
CsrFile.sv
Decode.sv
Alu.sv
MulDivUnit.sv
DCache.sv
HazardUnit.sv
riscv_cpu.sv
myCPU.sv
```

### 6.2 必须删除的旧 OoO 结构

| 旧结构 | 新结构 |
| --- | --- |
| Rename/FreeList/SpecRAT/ArchRAT | 删除，直接 x0-x31 |
| ROB/CommitStage | 删除，WB 即顺序提交点 |
| IssueQueue/Payload | 删除，流水寄存器直接携带控制和数据 |
| StoreBuffer | 替换为小型 write-through `StoreWriteBuffer`，不承载乱序语义 |
| RecoveryManager/checkpoint | 替换为 EX redirect + pipeline flush |
| ReadyTable/physical regfile | 删除，使用简单 GPR + forwarding |

### 6.3 Vivado 友好编码规则

RTL 必须遵守以下规则：

1. 大数组 reset 只清 valid/tag-valid/count/head/tail，不清完整 data payload。
2. 避免大面积异步 reset；新增 core 模块默认同步 reset 或只 reset 控制位。
3. cache/tag/write buffer 用固定小参数，避免过度参数化导致综合展开不可控。
4. 不写跨多个大数组的巨型 `always_comb`；tag compare、data select、control FSM 分开。
5. forwarding 优先级用明确的小 mux：EX 优先于 MA，MA 优先于 WB。
6. `rd != 0` 比较提前生成 `rd_we_nonzero`，减少重复比较。
7. 乘除法 IP 外层必须有 `busy/valid` 寄存，不让 IP 延迟直接拉长 EX 组合路径。
8. perf counter 不进入主控制组合链，只采样已注册事件。
9. Verilator 专用 debug 口放 `ifdef VERILATOR_TB`，不要污染综合关键路径。
10. filelist 顺序固定：types -> leaf modules -> composite modules -> top adapter。

## 7. 分阶段实施计划

### Phase 0：骨架和工程切换

目标：新五级 core 能 elaboration，顶层端口兼容。

实现：

1. 重建 `rtl/core` 新文件。
2. `myCPU` 保持原端口。
3. `scripts/filelists/core.f` 切到新文件。
4. `docs/design/project_framework.md` 和 `docs/design/rtl_core_design.md` 后续同步改成五级流水事实。

验证：

```text
make verilator-build
make verilator-build-src
```

### Phase 1：RV32I 正确性，保守 stall

目标：先跑通正确性，不追 IPC。

实现：

1. PCG/IF/ID/EX/MA/WB pipeline regs。
2. RV32I ALU、branch、JAL/JALR、load/store。
3. RAW 全部 stall 到 WB。
4. load/store 暂走 uncached ready/valid LSU，DRAM read 目标为一拍返回。
5. 分支 EX redirect，flush younger。

验证：

```text
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
```

### Phase 2：IPC 基础优化

目标：常规 ALU 相关代码接近 IPC=1。

实现：

1. EX/MA/WB -> EX forwarding。
2. WB -> ID read bypass。
3. load-use 精确 stall，不再所有 RAW 都等 WB。
4. JAL 尽量提前 redirect。
5. perf counter 增加 `stall_load_use/stall_mem/stall_muldiv/branch_miss/cache_miss`。

验证：

```text
make sim-rv32 SUITE=rv32ui
```

检查点：

1. ALU dependency loop 不应每条都插泡。
2. branch miss 只清 younger，不丢 older WB。
3. Verilator 波形中 forwarding 优先级清楚。

### Phase 3：RV32M 多周期执行

目标：M 扩展正确，EX busy 控制干净。

实现：

1. `MulDivUnit` 封装 `MUL_0`/`DIV_0`。
2. EX 遇到 M 指令后保持 payload，直到 result valid。
3. front/ID freeze，WB 仍按有序策略处理。

验证：

```text
make sim-rv32 SUITE=rv32um
```

### Phase 4：CSR/rv32mi/system

目标：通过 rv32mi 目标子集。

实现：

1. `CsrFile` 支持 `mstatus/mtvec/mscratch/mepc/mcause/misa` 子集。
2. `ecall/ebreak/mret` 精确 redirect。
3. `fence/fence.i` 作为 serial NOP。
4. CSR/system 指令 serial 化，避免和普通写回乱序交错。

验证：

```text
make sim-rv32 SUITE=rv32mi
make sim-rv32-all
```

### Phase 5：一拍 hit D-cache + write buffer

目标：在正确性基础上减少访存 IPC 损失，同时保持频率友好。

实现：

1. direct-mapped D-cache，16B line，1KiB/2KiB。
2. DRAM 地址 cached，MMIO 地址 uncached。
3. load hit 正常进入 WB。
4. load miss blocking fill，fill 完成后返回目标 word。
5. store hit 更新 cache line，并 enqueue write buffer。
6. store miss no-write-allocate，只 enqueue write buffer。
7. write buffer 满时才阻塞 store。

验证：

```text
make sim-rv32 SUITE=rv32ui
make sim-rv32 SUITE=rv32um
make sim-rv32 SUITE=rv32mi
make sim-src TEST=srcSmoke
```

定向 cache 测试：

| 测试 | 目标 |
| --- | --- |
| 连续 load 同 line | hit 路径和 tag/index |
| 跨 line load | fill FSM 和 offset |
| store hit 后 load | cache byte merge |
| store miss 后 load | write-through 和 refill |
| store buffer 连续写 | buffer full stall |
| MMIO counter/SW/KEY | uncached，不读旧值 |
| byte/half load-store | mask/extend/offset |

### Phase 6：BPU 和频率优化

目标：改善分支密集代码 IPC，并做 Vivado 收敛。

实现：

1. 小 BTB/PHT。
2. EX 更新预测器。
3. perf 统计 branch miss。
4. 如 Vivado Fmax 不够，将 D-cache data array 切同步 RAM，必要时让 load hit 多一拍但提高频率。
5. 对高扇出 stall/flush 做局部注册或分区。

验证：

```text
make sim-rv32-all
make sim-src TEST=srcSmoke
make verilator-build
```

再跑 Vivado synthesis，重点看：

1. critical path 是否在 D-cache hit path。
2. forwarding mux 是否过宽。
3. reset/flush fanout 是否过大。
4. perf/debug 是否进入主路径。

## 8. 关键 bug 风险

| 风险 | 表现 | 自检 |
| --- | --- | --- |
| IROM PC/inst 错位 | dump 从第一条 branch 后全错 | `if_pc` 必须对应上一拍 request |
| redirect flush 过宽 | 更老指令写回丢失 | EX redirect 不能 kill MA/WB older |
| redirect flush 过窄 | 错路指令提交 | IF/ID 和必要 ID/EX 必须清 valid |
| forwarding 优先级错 | 连续写同 rd 时读到旧值 | EX > MA > WB |
| load-use 未 stall | load 后立即使用读到旧值 | load 数据未可用时插 bubble |
| x0 被写/forward | x0 非 0，测试随机炸 | `rd_we_nonzero` 统一约束 |
| cache store hit 不更新 line | store 后 load 命中旧值 | byte merge 覆盖对应 lane |
| MMIO 被 cache | counter/SW/SEG 行为异常 | `0x8020_xxxx` 必须 uncached |
| write buffer 和 load 同地址 | load 读不到刚 store 的值 | load 查 write buffer 或 store 到同地址时 drain |
| fill 采样相位错 | cache line 写入 0/旧数据 | 只在 `mem_resp_valid` 采样，不数固定等待拍 |
| MUL/DIV busy payload 被覆盖 | M 指令结果写错 rd | EX busy 时保持控制和 operands |
| CSR 非精确 | `mret` 返回错 PC | system 指令 serial 化 |
| Vivado reset 过大 | implementation 卡死或 Fmax 低 | 大数组只清 valid |

## 9. 最小实践任务

先手写“高 IPC 五级流水最小版”，不要一开始接 D-cache 和 CSR：

功能边界：

1. RV32I ALU、branch、JAL/JALR、LUI/AUIPC。
2. `lw/sw` 使用 uncached ready/valid LSU，DRAM read 目标为一拍返回。
3. 完整 EX/MA/WB forwarding。
4. load-use 精确 stall。
5. 无 M、无 CSR、无 D-cache。

步骤：

1. 写 `CoreTypes.sv`，定义四组 pipeline payload 和控制枚举。
2. 写 `riscv_cpu.sv`，先把五级连通，valid/ready/flush 关系跑清楚。
3. 写 `RegFile.sv`，x0 固定 0，WB 写，ID 读，补 WB->ID bypass。
4. 写 `Decode.sv` 和 `Alu.sv`，先跑 ALU 测试。
5. 加 branch/JAL/JALR redirect，验证 flush 边界。
6. 加 uncached LSU，严格按 `dmem_resp_valid` 采样。
7. 加 forwarding 和 load-use stall，观察 IPC。
8. 再接 `MulDivUnit`、`CsrFile`。
9. 最后接 D-cache/write buffer，并用定向 cache 测试压 bug。

这条路线的关键是：正确性靠顺序提交和精确 flush 保证，IPC 靠 forwarding、hit-fast memory、store 解耦和分支预测减少气泡，频率靠短组合路径、同步边界和 Vivado 友好的数组/reset 写法保证。
