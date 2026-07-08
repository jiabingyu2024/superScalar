# 五级流水 RTL 修改计划

日期：2026-07-08

## 1. 当前 RTL 状态

当前工作树中，旧 `rtl/core` 超标量/OoO 文件已经处于删除状态，但 `scripts/filelists/core.f` 仍然引用旧文件。实际还存在的 RTL 主要是：

```text
rtl/ip/
  IROM_0.sv
  DRAM_0.sv
  MUL_0.sv
  DIV_0.sv
  pll.sv

rtl/soc/
  student_top.sv
  top.sv
  perip_bridge.sv
  dram_driver.sv
  counter.sv
  display/uart/twin glue
```

结论：这次不是在旧 core 上补丁式修改，而是重建 `rtl/core`，同时把 `ip/` 和 `soc/` 从“旧超标量固定两拍 perip 总线”适配到“五级流水 + D-cache + ready/valid memory bus”。

## 2. 总体目标

| 目标 | 要求 |
| --- | --- |
| 正确性 | 通过 `rv32ui/rv32um/rv32mi` 目标子集，支持 `ecall/ebreak/mret/fence/fence.i` |
| 性能 | 单发射峰值 IPC=1，以 `运行速度 = IPC * Fmax` 为优化目标，而不是单独追 IPC 或单独追频率 |
| 频率 | Vivado 上板优先保证可收敛；避免大组合路径、大 fanout reset/flush、大数组全清零 |
| Verilator | IP 行为模型、core、student_top 都能仿真 |
| Vivado | `DRAM_0/IROM_0` 的 Verilator 平替必须跟 `fpga/create_vivado_project.tcl` 中 Vivado IP 参数对齐；D-cache/RegFile/Buffer 写法可综合 |
| SoC | 尽量保持 `top`/赛事外部接口稳定，`student_top` 内部可重构 |

性能判断公式：

```text
program_time = cycles / Fmax
cycles       = committed_insts / IPC + miss/branch/muldiv/mmio stalls
best_design  = max(IPC * Fmax) on target program
```

因此后续优化按以下规则取舍：

1. 如果某结构提升 IPC 但让 Vivado Fmax 明显下降，必须用 `IPC * Fmax` 比较，不默认保留。
2. 若 D-cache 一拍 hit 路径成为 critical path，允许把 load hit 延后一拍，前提是 Fmax 提升能抵消多出的 load-use bubble。
3. 若小 BPU 能明显减少 branch miss 且不进入 critical path，应优先保留；复杂预测器若降低 Fmax，则不做。
4. store write buffer 通常同时提升 IPC 且不显著伤频率，优先级高。
5. perf/debug 只采样寄存后的事件，不能进入主控制组合链。

## 2.1 性能计数和上板评估指标

必须在 `PerfCounter` 中保留足够少但足够有用的计数，便于 Verilator 和 FPGA 结果一致评估：

| 计数 | 用途 |
| --- | --- |
| `cycle` | 分母，计算 IPC 和总运行时间 |
| `commit` | 单发射提交数 |
| `branch` / `branch_miss` | 判断 BPU 是否值得保留 |
| `load` / `store` | 判断访存密度 |
| `dcache_access` / `dcache_miss` | 判断 D-cache 容量/line 配置 |
| `stall_load_use` | 判断 forwarding/load-use 策略 |
| `stall_mem` | 判断 D-cache miss、write buffer full、MMIO 等待 |
| `stall_muldiv` | 判断 M 扩展对程序影响 |
| `stall_front` | 判断前端 redirect/取指停顿 |

Vivado 评估时至少记录：

```text
Fmax
LUT/FF/BRAM/DSP
critical path module
program cycle count
program_time = cycle_count / Fmax
```

只有 `program_time` 变小，才算优化有效。

## 3. 新 RTL 分层

推荐最终层级：

```text
top
  -> student_top
       -> myCPU
            -> riscv_cpu
                 -> front: PcGen / FetchStage / BranchPredictor
                 -> decode: Decode
                 -> regs: RegFile / CsrFile
                 -> execute: Alu / BranchUnit / MulDivUnit
                 -> memory: LoadStoreUnit / DCache / StoreWriteBuffer
                 -> control: HazardUnit / PipelineCtrl
                 -> perf: PerfCounter
       -> IROM_0   // single-port ROM
       -> SocMemBridge
            -> DramBramAdapter
                 -> DRAM_0
            -> MmioRegs/counter/display
```

关键变化：

1. `myCPU` 继续作为 CPU 封装层，保留赛事/仿真主入口，但可随单发射设计清理旧 2-way IROM B 口。
2. `riscv_cpu` 内部使用更清楚的 ready/valid memory request/response。
3. `student_top` 内部不再让 CPU 直接依赖旧 `perip_rdata` 固定两拍语义。
4. `perip_bridge/dram_driver` 建议重写或替换为 `SocMemBridge + DramBramAdapter`，避免旧延迟约定污染 D-cache。

## 4. `rtl/core` 重建计划

### 4.1 文件清单

新建：

```text
rtl/core/CoreTypes.sv
rtl/core/myCPU.sv
rtl/core/riscv_cpu.sv
rtl/core/front/PcGen.sv
rtl/core/front/FetchStage.sv
rtl/core/front/BranchPredictor.sv
rtl/core/decode/Decode.sv
rtl/core/regs/RegFile.sv
rtl/core/regs/CsrFile.sv
rtl/core/execute/Alu.sv
rtl/core/execute/BranchUnit.sv
rtl/core/execute/MulDivUnit.sv
rtl/core/memory/LoadStoreUnit.sv
rtl/core/memory/DCache.sv
rtl/core/memory/StoreWriteBuffer.sv
rtl/core/control/HazardUnit.sv
rtl/core/control/PipelineCtrl.sv
rtl/core/perf/PerfCounter.sv
```

第一轮可先合并部分模块，但接口边界要按上面设计，后续拆分不改行为。

### 4.2 Core 顶层接口

新 `myCPU` 建议不再保留旧 2-way 取指端口，改成单端口 IROM + ready/valid 数据总线：

```text
cpu_clk/cpu_rst
irom_addr/irom_data/irom_ena
dmem_req_valid/dmem_req_ready
dmem_req_write/dmem_req_addr/dmem_req_wdata/dmem_req_wstrb/dmem_req_uncached
dmem_resp_valid/dmem_resp_rdata
debug perf ports under VERILATOR_TB
```

`riscv_cpu` 内部使用同一组 memory bus，不再使用旧 `perip_*` 固定返回接口：

```text
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

`student_top` 负责把 `myCPU` 的 IROM 单端口和 dmem ready/valid bus 连接到 `IROM_0` 与 `SocMemBridge`。如果 Verilator TB 短期仍依赖旧 `myCPU` 扁平端口，可以临时加一个兼容 wrapper，但新 core 不应背旧接口。

### 4.3 五级流水实现顺序

1. `PCG/IF/ID/EX/MA/WB` pipeline valid 和 payload。
2. RV32I ALU/branch/load/store，RAW 先保守 stall。
3. EX/MA/WB forwarding 和 load-use stall。
4. M 扩展封装 `MUL_0/DIV_0`，EX busy 保持。
5. CSR/system/fence，system 指令 serial 化。
6. D-cache + write buffer。
7. 小 BTB/PHT。

### 4.4 主时序路径预算

为兼顾 IPC 和频率，五级流水不能把所有“看起来能同拍完成”的逻辑都塞进一个组合路径。建议按以下路径预算写 RTL：

| 路径 | 目标 | 频率风险 | 处理 |
| --- | --- | --- | --- |
| PCG -> IROM addr | 简单 `pc_next` mux | BPU/redirect mux 过大 | redirect/BPU 结果寄存化，PC mux 输入少而明确 |
| IROM dout -> IF/ID | 一拍取指 | ROM 输出到 decode 直通 | IF 必须寄存 instruction，不让 decode 直接吃 IROM dout |
| ID decode -> hazard | 一拍完成 | decode + compare + branch target 太长 | decode 控制分层，RAW compare 只比较 rd/rs 小字段 |
| EX forwarding -> ALU -> EX/MA | 一拍完成 | forwarding 大 mux + ALU + branch compare | forwarding 只在操作数前一级，优先级固定 EX > MA > WB |
| MA D-cache hit | 尽量一拍 | tag/data/align/extend 过长 | 首版可寄存数组；若 Fmax 不够，切同步 RAM 或拆 load align |
| WB -> RegFile | 一拍写回 | 写回 mux 过大 | WB 结果提前在 MA/EX 分类型寄存 |

原则：为了单条路径多省一拍而让 Fmax 大幅下降，通常不划算。五级单发射要追的是 `IPC * Fmax`。

### 4.5 分支预测和 redirect 策略

分支优化要保持小而快。推荐分阶段：

| 阶段 | 结构 | IPC 收益 | Fmax 风险 |
| --- | --- | --- | --- |
| bring-up | always not-taken | 正确性简单 | 最低 |
| perf-1 | JAL 在 ID 提前 redirect，conditional 在 EX 判断 | 降低无条件跳转代价 | 低 |
| perf-2 | 64-entry BTB + 2-bit PHT | 降低循环 branch miss | 中低 |

推荐 BPU：

```text
BTB:
  64 entries
  valid/tag/target

PHT:
  64 entries
  2-bit saturating counter

lookup:
  PCG 用 pc index 查表
  命中且 counter taken -> pred_taken/pred_target

update:
  EX 得到 branch/jump 真实结果后更新
```

Vivado 友好约束：

1. BTB/PHT reset 只清 valid/counter 初值，不清 target payload。
2. PCG 的预测输出必须在 PC mux 前保持小 fan-in：`redirect > bpu_taken > pc+4`。
3. 不做复杂全局历史、RAS、2-way BTB，除非 perf counter 证明 branch miss 是主瓶颈且 Fmax 仍有余量。
4. 若 BPU lookup 进入 critical path，先把 entry 数减到 32 或对 BPU 输出打一拍；不要让预测器拖垮全局 Fmax。

正确性边界：

1. 预测只影响取指方向，不影响架构态。
2. EX 真实结果与预测不一致时 flush younger 指令。
3. 已到 MA/WB 的 older 指令不得被 branch flush 清掉。

## 5. `rtl/ip` 修改计划

`rtl/ip/IROM_0.sv` 和 `rtl/ip/DRAM_0.sv` 不是 FPGA 综合时使用的真实 IP，而是 Verilator 行为模型。它们允许修改，但修改原则不是“方便 core”，而是“模拟 Vivado IP 生成器配置后的端口和时序”。真实契约来源是 `fpga/create_vivado_project.tcl`。

### 5.1 `IROM_0.sv`

Vivado IP 参数：

```text
create_ip blk_mem_gen -module_name IROM_0
Memory_Type = Single_Port_ROM
Write_Width_A = 32
Write_Depth_A = 4096
Read_Width_A = 32
Enable_A = Use_ENA_Pin
Register_PortA_Output_of_Memory_Primitives = false
Register_PortA_Output_of_Memory_Core = false
Load_Init_File = true
```

当前 Verilator 模型事实：

```text
单端口 ROM
addr 在 posedge 寄存
dout 组合读取 mem[addr_q]
```

计划：

1. 将 Vivado Tcl 和 `rtl/ip/IROM_0.sv` 平替模型都改为单端口 ROM。
2. 当前模型与 Tcl 的“输出不注册”意图基本一致：地址寄存后，`dout` 由寄存地址组合读出。
3. `student_top` 地址映射从 `irom_addrA/B` 改为单个 `irom_addr[13:2]`。
4. 文档明确 IF 必须保存 request PC，不允许用当前 PC 解释当前 `douta`。
5. 若后续修改 Vivado Tcl，把 IROM 输出寄存打开，则必须同步修改 `IROM_0.sv` 行为模型和 FetchStage 相位。

不建议：

1. 不在 IROM 内做分支预测或 PC 逻辑。
2. 不把 IROM 改成零延迟组合 ROM，否则 Verilator 会比 FPGA 少一拍取指相位。

### 5.2 `DRAM_0.sv`

Vivado IP 参数：

```text
create_ip blk_mem_gen -module_name DRAM_0
Memory_Type = Single_Port_RAM
Write_Width_A = 32
Write_Depth_A = 65536
Read_Width_A = 32
Enable_A = Use_ENA_Pin
Use_Byte_Write_Enable = true
Byte_Size = 8
Operating_Mode_A = READ_FIRST
Register_PortA_Output_of_Memory_Primitives = true
Register_PortA_Output_of_Memory_Core = false
Load_Init_File = true
```

当前 Verilator 模型事实：

```text
单端口 32-bit RAM，65536 words
read_en 时寄存 rd_addr_q/rd_valid_q
下一拍 douta <= mem[rd_addr_q]
write 周期按 byte enable 更新
write 周期不推进 read-return pipeline
```

计划：

1. `DRAM_0` 继续作为 Vivado BRAM IP 平替保留，允许按 Tcl 参数修正模型。
2. 第一优先级是匹配 `Single_Port_RAM + READ_FIRST + byte write + primitive output register`。
3. 对 `DramBramAdapter` 外部定义为一拍读响应：read request 被接受后的下一拍 `resp_valid` 有效；不再叠加旧 `perip_bridge` 的第二拍选择延迟。
4. 新增 `DramBramAdapter`，把 ready/valid request 转为 `DRAM_0` 端口。
5. `DramBramAdapter` 对外用 `resp_valid` 表示读返回，不再要求 CPU 写 `wait_cnt==2`。
6. write request 可在 `req_valid && req_ready` 周期完成；read request 由 adapter 在 BRAM 返回时产生 `resp_valid`。
7. 如果实际 Vivado IP 仿真显示 `READ_FIRST` 同地址读写行为与当前模型不同，优先改 `DRAM_0.sv` 平替模型，不改 CPU。
8. 如果 Vivado BRAM 参数需要调整才能稳定得到一拍响应，则同步修改 Tcl 和 `DRAM_0.sv`，以 Tcl 为真实契约。

建议接口：

```systemverilog
module DramBramAdapter (
    input  logic        clk,
    input  logic        rst,
    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,
    output logic        resp_valid,
    output logic [31:0] resp_rdata
);
```

注意：

1. `req_addr` 是 byte address，adapter 内部转 word address。
2. `req_wdata/req_wstrb` 建议在 adapter 内按 `addr[1:0]` 左移后接 `DRAM_0`。
3. `resp_rdata` 建议由 adapter 按 `addr[1:0]` 右移成 CPU 视角的 word，再交给 LSU/D-cache 做 byte/half extract。
4. `DramBramAdapter` 要把底层 BRAM 的实际返回相位封装掉；D-cache miss FSM 只等 `resp_valid`，计划目标是一拍响应，不再保留旧两拍 perip 采样模型。

### 5.3 `MUL_0.sv`

当前事实：3 拍固定 latency，没有 valid 输入输出。

计划：

1. 保留 IP 模型。
2. 新增 `MulDivUnit` 外层计数/valid 封装。
3. MUL 请求进入后锁存 rd/op/符号信息，3 拍后输出 result valid。
4. 不让 `MUL_0` 输出直接参与 EX 组合路径。

### 5.4 `DIV_0.sv`

当前事实：34 拍 fixed valid pipeline，ready 恒 1。

计划：

1. 保留 IP 模型。
2. `MulDivUnit` 只在接受 DIV 指令时打一拍 `tvalid`。
3. EX 在 DIV busy 期间保持指令 payload。
4. signed div/rem 在 `MulDivUnit` 外层做绝对值、符号修正，IP 继续用 unsigned。

## 6. `rtl/soc` 修改计划

### 6.1 `student_top.sv`

当前问题：

1. 内部实例化 `myCPU`，但 debug perf 口还是旧 OoO 大量计数。
2. IROM 当前按 A/B 双端口接线，属于旧 2-way 取指残留。
3. CPU 到外设仍是旧 `perip_*` 无 ready/valid 接口。
4. `CORE_NEW` 分支是临时兼容，不适合作为长期架构边界。

计划：

1. 保持 `student_top` 外部端口不变。
2. 内部仍例化单端口 `IROM_0` 和新的 `SocMemBridge`。
3. 清理 `VERILATOR_TB` debug perf 端口，只保留新五级真正有用的计数：
   - cycle
   - commit
   - branch
   - branch_miss
   - load
   - store
   - dcache_access
   - dcache_miss
   - stall_front
   - stall_mem
   - stall_muldiv
   - stall_load_use
4. 若 testbench 暂时依赖旧 debug 名称，可第一阶段保留同名输出但接 0 或映射到新计数，第二阶段再清理 TB。
5. 移除 `CORE_NEW` 长期分支，统一实例化新 `myCPU`。

### 6.2 `perip_bridge.sv`

当前问题：

1. 读返回选择固定延迟两拍。
2. 没有 `req_ready/resp_valid`。
3. 读请求和“无访问”都靠 `perip_addr/perip_wen` 组合推断。
4. 和 D-cache miss FSM/write buffer 不匹配。

计划：建议替换为 `SocMemBridge.sv`。

`SocMemBridge` 职责：

```text
接收 CPU/D-cache memory request
按地址分流：
  DRAM cached/uncached data RAM range
  MMIO SW/KEY/SEG/LED/counter
返回 ready/valid response
```

地址表保留：

| 地址 | 目标 | cache 属性 |
| --- | --- | --- |
| `0x8010_0000..0x8013_FFFF` | DRAM | cached |
| `0x8020_0000` | SW0 | uncached |
| `0x8020_0004` | SW1 | uncached |
| `0x8020_0010` | KEY | uncached |
| `0x8020_0020` | SEG | uncached |
| `0x8020_0040` | LED | uncached |
| `0x8020_0050` | counter | uncached |

`SocMemBridge` 返回策略：

1. DRAM read：转给 `DramBramAdapter`，等待 `resp_valid`。
2. DRAM write：写 adapter，通常 1 拍 accept，无 read response 或返回 store ack。
3. MMIO read：可以 1 拍或注册 1 拍返回，但必须用 `resp_valid` 表达。
4. MMIO write：写 LED/SEG/counter config 后返回 ack。

仲裁优先级建议：

```text
MMIO request
  > D-cache miss fill read
  > foreground uncached load
  > write buffer drain
```

原因：

1. MMIO 有副作用和实时性，不能被普通 write buffer 长时间压住。
2. D-cache miss 阻塞前台流水，应优先服务，直接影响 IPC。
3. write buffer drain 是后台工作，可以让路；只有 buffer full 时才反压前台。
4. 单端口 `DRAM_0` 同一拍只能 read 或 write，仲裁必须集中在 `SocMemBridge/DramBramAdapter`，不要分散在 D-cache 和 LSU 各自抢端口。

Vivado 友好点：

1. 地址 decode 结果打一拍后进入具体目标，避免 `addr compare -> target mux -> BRAM` 成为长路径。
2. `resp_valid/resp_rdata` 用目标选择寄存，不做多层组合返回。
3. `counter/display` 仍保持原模块边界，桥内只做 MMIO 寄存和选择。

### 6.3 `dram_driver.sv`

当前问题：

1. 只适配旧 `perip_*`。
2. offset 延迟与 `perip_bridge` 两拍选择耦合。
3. 没有 ready/valid。

计划：

1. 不继续扩展旧 `dram_driver`。
2. 功能迁移进 `DramBramAdapter`。
3. 旧文件可删除或从 filelist 移除。

### 6.4 `counter.sv`

当前约束：受保护文件，默认不改。

计划：

1. `SocMemBridge` 继续实例化 `counter`。
2. `cnt_clk` 和 `cpu_clk` 跨域维持当前用法，不在本轮修改 counter 内部。
3. MMIO read counter 必须 uncached。

### 6.5 `top.sv`

当前结构可保留：

```text
pll -> cpu_clk / 50MHz
uart/twin_controller on 50MHz
student_top on cpu_clk
```

计划：

1. 不改外部端口。
2. 保持 `w_clk_rst(~locked)` 作为 CPU 高有效 reset。
3. 后续若 Vivado 时序差，再单独处理 reset 同步释放，不和 core 重构混做。

### 6.6 `fpga/create_vivado_project.tcl`

Vivado 工程脚本也要跟 RTL 架构同步：

1. `IROM_0` 从 `Dual_Port_ROM` 改为 `Single_Port_ROM`，删除 B 口相关配置。
2. 保持 `DRAM_0` 为 `Single_Port_RAM`，byte write，`READ_FIRST`。
3. `DRAM_0` 一拍响应契约由 `DramBramAdapter` 验证；如果 IP 配置导致多一拍，优先调整 adapter 或 IP 参数，不把等待拍数扩散到 core。
4. 删除旧 OoO 名称相关 sanity 统计，替换为新层级：
   - `riscv_cpu`
   - `DCache`
   - `StoreWriteBuffer`
   - `RegFile`
   - `MulDivUnit`
5. Vivado 默认 `FPGA_CPU_CLK_MHZ=100` 可作为保守目标；完成基础正确性后用 100/125/150MHz 三档尝试，按 `program_time` 选择。

上板友好策略：

| 项目 | 默认 | 如果时序差 |
| --- | --- | --- |
| `flatten_hierarchy` | `none` | 保持层级便于定位，不急着 flatten |
| power opt | 关闭 | 先保证实现稳定 |
| D-cache data | fast-hit 小数组 | 改同步 RAM 或多打一拍 |
| BPU | 小 direct-mapped | 若进入 critical path，先减 entry 或打一拍 |
| reset | 只清控制位 | 避免给 data/tag 加 reset |

## 7. D-cache 与 DRAM 详细接口计划

### 7.1 Core 内部 D-cache 请求

`LoadStoreUnit` 向 `DCache` 发：

```text
lsu_req_valid
lsu_req_ready
lsu_req_write
lsu_req_size       // byte/half/word
lsu_req_unsigned
lsu_req_addr
lsu_req_wdata
lsu_resp_valid
lsu_resp_rdata
lsu_resp_fault     // 第一版可固定 0
```

### 7.2 D-cache 向 SoC memory bus

```text
mem_req_valid
mem_req_ready
mem_req_write
mem_req_addr
mem_req_wdata
mem_req_wstrb
mem_req_uncached
mem_resp_valid
mem_resp_rdata
```

### 7.3 D-cache 结构

首版参数：

```text
容量：默认 2 KiB，备选 1 KiB
line：16B，4 words
映射：direct-mapped
store：write-through + no-write-allocate
write buffer：4 entries，备选 2 entries
MMIO：uncached
```

地址划分以 1 KiB 为例：

```text
addr[1:0]   byte offset
addr[3:2]   word offset in line
addr[9:4]   index, 64 lines
addr[31:10] tag
```

推荐参数取舍：

| 参数 | 默认 | 备选 | 取舍理由 |
| --- | --- | --- | --- |
| 容量 | 2 KiB | 1 KiB | 2 KiB 降低冲突 miss；若 Vivado Fmax/资源受压，退到 1 KiB |
| line size | 16B | 32B 暂不推荐 | 16B fill 只需 4 个 word，miss penalty 可控；32B 可能多读无用数据 |
| 相联度 | direct-mapped | 2-way 暂不做 | direct-mapped hit path 短；2-way tag compare/data mux 容易伤 Fmax |
| data array | 首版寄存器/分布式读 | Fmax 不够改同步 RAM | 寄存器读利于一拍 hit；同步 RAM 利于 Fmax/BRAM 资源 |
| write policy | write-through | write-back 暂不做 | write-back 需要 dirty/evict/fence，验证风险高 |
| write allocate | no-write-allocate | write-allocate 暂不做 | store miss 不拉 line，减少 miss FSM 复杂度 |

### 7.3.1 D-cache Vivado 实现策略

D-cache 最容易成为 Vivado critical path。建议按两档实现：

| 档位 | 结构 | IPC | Fmax | 使用条件 |
| --- | --- | --- | --- | --- |
| A: 一拍 hit | tag/data 用小数组组合读，MA 同拍 compare/align | load hit 快 | 可能较低 | Verilator 和初版 FPGA，若 critical path 可接受 |
| B: 高频 hit | tag/data 用同步 RAM 或寄存一级，load hit 多一拍 | load-use 多停 | Fmax 更稳 | 若 A 档 D-cache hit path 成为 top critical path |

切换规则：

```text
若 A 档 Fmax 下降比例 > load-hit IPC 收益，则切 B 档。
若目标程序 load miss 很少、load-use 很多，则优先 A 档。
若目标程序频率受 D-cache mux 限制明显，则优先 B 档。
```

RTL 上可以预留参数：

```text
DCACHE_FAST_HIT = 1  // A 档
DCACHE_FAST_HIT = 0  // B 档
```

但不要过度参数化所有结构；只保留这类直接影响 IPC/Fmax 的开关。

### 7.4 D-cache hit/miss 行为

load hit：

```text
MA 查 tag/data
命中 -> 取 word -> byte/half/word extract -> WB
```

load miss：

```text
锁存 miss addr/op/rd
冻结前台流水
对 line_base + 0/4/8/12 发 read
等待 mem_resp_valid 写入 line
写 tag/valid
返回目标 word
```

store hit：

```text
cache line byte merge
store request 入 write buffer
若 write buffer 未满，流水不停
```

store miss：

```text
no-write-allocate
store request 入 write buffer
若 write buffer 未满，流水不停
```

load 与 write buffer 同 word 冲突：

第一版建议保守处理：

```text
若 load addr 与任一 write buffer entry word address 相同
  等 write buffer drain 后再执行 load
```

后续优化再做字节级 forwarding。

### 7.5 StoreWriteBuffer

store buffer 不是旧 OoO `StoreBuffer`。它只做写穿透解耦，保持顺序机语义：

```text
entry:
  valid
  addr[31:0]
  wdata[31:0]   // 已按 byte offset 左移或 raw，必须和 adapter 统一
  wstrb[3:0]
```

推荐行为：

1. store hit/miss 都先尝试 enqueue。
2. buffer 未满，store 指令可以进入 WB/commit，不等 DRAM 写完成。
3. buffer 后台按 FIFO 顺序向 `SocMemBridge` 发写请求。
4. load 若与 buffer 中任一 entry 同 word address 冲突，第一版等待 buffer drain。
5. `fence/fence.i`、CSR serial、trap 进入前 drain write buffer，保证外部可见顺序。

IPC/Fmax 取舍：

| 方案 | IPC | Fmax/复杂度 | 建议 |
| --- | --- | --- | --- |
| 2-entry FIFO | 已能吸收短 store burst | 比较器少 | 若 Fmax 紧张使用 |
| 4-entry FIFO | 更适合 memcpy/数组写 | 多几个比较器 | 默认使用 |
| 字节级 forwarding | load-after-store 快 | mux/compare 更复杂 | 第二轮优化 |

实现注意：

1. full/empty/head/tail/count 用小寄存器，reset 只清 valid/count。
2. 冲突比较只比较 word address `addr[31:2]`。
3. MMIO store 不进入普通合并逻辑，必须保持顺序；可直接发出并等待 ack，或先 drain buffer 再执行。

## 8. filelist 修改计划

### 8.1 `scripts/filelists/core.f`

删除旧 OoO 条目，替换为新五级文件：

```text
rtl/core/CoreTypes.sv
rtl/core/front/BranchPredictor.sv
rtl/core/front/PcGen.sv
rtl/core/front/FetchStage.sv
rtl/core/decode/Decode.sv
rtl/core/regs/RegFile.sv
rtl/core/regs/CsrFile.sv
rtl/core/execute/Alu.sv
rtl/core/execute/BranchUnit.sv
rtl/core/execute/MulDivUnit.sv
rtl/core/memory/StoreWriteBuffer.sv
rtl/core/memory/DCache.sv
rtl/core/memory/LoadStoreUnit.sv
rtl/core/control/HazardUnit.sv
rtl/core/control/PipelineCtrl.sv
rtl/core/perf/PerfCounter.sv
rtl/core/riscv_cpu.sv
rtl/core/myCPU.sv
```

### 8.2 `scripts/filelists/soc.f`

替换：

```text
- rtl/soc/dram_driver.sv
- rtl/soc/perip_bridge.sv
+ rtl/soc/DramBramAdapter.sv
+ rtl/soc/SocMemBridge.sv
```

保留：

```text
rtl/soc/seg7.sv
rtl/soc/display_seg.sv
rtl/soc/counter.sv
rtl/soc/uart.sv
rtl/soc/twin_controller.sv
rtl/soc/student_top.sv
rtl/soc/top.sv
```

### 8.3 `scripts/filelists/ip_verilator.f`

保留：

```text
rtl/ip/IROM_0.sv
rtl/ip/DRAM_0.sv
rtl/ip/MUL_0.sv
rtl/ip/DIV_0.sv
rtl/ip/pll.sv
```

但文档注明：这些是仿真行为模型；Vivado 工程可以用生成 IP 或同端口 BRAM wrapper。

### 8.4 `fpga/create_vivado_project.tcl`

同步修改 IP 参数：

```text
IROM_0:
  Memory_Type = Single_Port_ROM
  只保留 A 口

DRAM_0:
  保持 Single_Port_RAM + byte write + READ_FIRST
  对外由 DramBramAdapter 封装为 read request 后下一拍 resp_valid
```

Tcl、`rtl/ip/*.sv` 平替模型、`student_top` 接线必须三者一致。不能只改 Verilator 模型，否则 FPGA 上板会出现端口或相位不一致。

## 9. 实施阶段

### Phase 0：接口骨架

1. 新建 `rtl/core` 骨架和 `CoreTypes.sv`。
2. 新建 `DramBramAdapter/SocMemBridge` 空实现或最小直通实现。
3. 更新 filelist。
4. `make verilator-build` 至少能 elaboration。
5. 修改 Vivado Tcl：IROM 单端口、sanity 层级名更新。

验收：

```text
make verilator-build
make verilator-build-src
```

### Phase 1：无 cache 五级流水

1. RV32I 基础流水。
2. LSU 直接通过 memory bus 访问 `SocMemBridge`。
3. 所有 RAW 先保守 stall。
4. 跑 `rv32ui`。
5. 暂不追 IPC，先确保 PC/flush/load/store 相位正确。

验收：

```text
make sim-rv32 SUITE=rv32ui
```

### Phase 2：forwarding 与 IPC 基础优化

1. EX/MA/WB forwarding。
2. load-use stall。
3. perf 计数。
4. 跑 `rv32ui` 并观察 IPC。
5. 对 ALU dependency loop 做定向测试，确认不再每条 RAW 都停到 WB。

验收：

```text
rv32ui 通过
ALU->ALU dependent: 0 bubble
load-use: 只在必要时 bubble
```

### Phase 3：RV32M

1. `MulDivUnit` 接 `MUL_0/DIV_0`。
2. EX busy freeze。
3. 跑 `rv32um`。
4. perf 记录 `stall_muldiv`，避免误把 DIV busy 归到 memory stall。

### Phase 4：CSR/system

1. `CsrFile`。
2. `ecall/ebreak/mret/fence/fence.i`。
3. 跑 `rv32mi`。
4. `fence/fence.i` 必须 drain write buffer。

### Phase 5：D-cache/write buffer

1. direct-mapped D-cache。
2. write-through store buffer。
3. MMIO uncached。
4. cache 定向测试。
5. 跑 `rv32ui/rv32um/rv32mi/srcSmoke`。
6. 分别记录 cache off/on 的 cycle、IPC、D-cache miss。

### Phase 6：Vivado 收敛

1. 检查 D-cache hit path critical path。
2. 必要时 data array 切同步 RAM。
3. 减少 reset/flush fanout。
4. 清理 debug/perf 对主路径的影响。
5. 使用 100/125/150MHz 或 Vivado 实际 Fmax 做比较。

### Phase 7：程序级速度优化

目标不是模块局部最优，而是目标程序 `program_time` 最小。

需要比较的配置：

| 配置 | 说明 |
| --- | --- |
| `no_cache` | uncached LSU，作为正确性和基线 |
| `dcache_fast_hit` | 一拍 hit D-cache |
| `dcache_sync_hit` | 同步 RAM/多打一拍 D-cache |
| `dcache_fast_hit_bpu` | 一拍 hit + 小 BTB/PHT |
| `dcache_sync_hit_bpu` | 高频 D-cache + 小 BTB/PHT |

每个配置记录：

```text
cycle_count
commit_count
IPC
Fmax
program_time = cycle_count / Fmax
dcache_miss_rate
branch_miss_rate
top critical path
```

保留规则：

1. 如果配置 A 的 IPC 高但 Fmax 降低，只有 `program_time` 更小才保留。
2. 如果 D-cache 让 Fmax 掉太多且目标程序 miss 很少，选择同步 RAM/多拍 hit 版本。
3. 如果 branch miss 不是主瓶颈，BPU 可以保持最小或关闭。
4. 如果 store buffer full 很少，不增加 buffer 深度。

## 10. 关键风险

| 风险 | 影响 | 计划中的防护 |
| --- | --- | --- |
| 旧 perip 固定两拍残留 | D-cache FSM 和 LSU 等待错误 | 改 ready/valid memory bus |
| `DRAM_0` latency 被 core 写死 | 后续换 BRAM/IP 会坏 | 只让 adapter 理解底层 latency |
| IROM PC/inst 错位 | 第一条跳转后全错 | IF 保存 request PC |
| MMIO 被 D-cache 缓存 | counter/SW/SEG 行为错误 | 地址分流，MMIO uncached |
| store buffer 后 load 读旧值 | store-load 顺序错误 | 同 word 冲突先 drain |
| D-cache reset 清全 data | Vivado fanout/资源爆炸 | 只清 valid |
| debug perf 旧端口太多 | 新 core 背旧 OoO 接口 | 分阶段映射或清理 |
| `counter.sv` 被误改 | 赛事行为风险 | 本轮只通过 bridge 连接，不改 counter |

## 10.1 Vivado 友好 RTL 编码规则

必须遵守：

1. 大数组只 reset `valid/head/tail/count`，不 reset `data/tag/target` payload。
2. 新增模块优先同步 reset；跨大范围 fanout 的异步 reset 不再扩散。
3. `stall/flush` 不直接扇到所有 data flop；只控制 valid 和少量 stage enable。
4. `DCache`、BTB、PHT、write buffer 的 data payload 写入时完整覆盖，无效时输出清零。
5. `always_comb` 不跨层级做大 mux：cache tag compare、data select、load align、WB mux 分块。
6. forwarding mux 固定三层优先级，不做动态数组循环选择。
7. `PerfCounter` 只接寄存后的 event pulse，不反馈主控制。
8. `ifdef VERILATOR_TB` debug 信号只在仿真暴露，综合路径不保留大量 debug fanout。
9. 谨慎使用 `dont_touch`。顶层可保留少量 `keep_hierarchy` 便于看报告，但不要给 `riscv_cpu/DCache/RegFile` 大范围 `dont_touch`，否则 Vivado 无法优化关键路径。
10. 所有 ready/valid 反馈路径避免组合环：`req_ready` 可以由小 FSM 状态组合生成，但不能依赖同周期下游 `resp_valid` 再反馈上游 valid。

建议综合检查：

```text
report_timing_summary
report_utilization -hierarchical
report_high_fanout_nets
report_control_sets
```

如果 high fanout top nets 是 `rst/stall/flush/debug/perf`，优先重构控制分发，而不是盲目加约束。

## 11. 第一批具体文件操作

建议第一批只做架构切换，不一次写完所有功能：

1. 新建 `rtl/core/CoreTypes.sv`。
2. 新建 `rtl/core/riscv_cpu.sv`，先空流水骨架。
3. 新建 `rtl/core/myCPU.sv`，保持端口兼容。
4. 新建 `rtl/soc/DramBramAdapter.sv`。
5. 新建 `rtl/soc/SocMemBridge.sv`。
6. 更新 `scripts/filelists/core.f` 和 `scripts/filelists/soc.f`。
7. 暂时保留 `perip_bridge.sv/dram_driver.sv` 文件但从新 filelist 移除，便于对照。
8. `student_top.sv` 改为接新 `myCPU + SocMemBridge`。

完成后再进入功能实现。不要一边改 SoC 总线、一边写 D-cache、一边调 CSR；否则波形上很难判断是哪一层错。
