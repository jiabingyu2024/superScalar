# IP Timing Alignment Contract

本文档用于提醒后续修改者和 AI：`rtl/ip/` 中的 Verilator 行为模型、`fpga/create_vivado_project.tcl` 中生成的 Vivado IP、以及 `rtl/soc/` 中的桥接逻辑必须保持同一个时序合同。只要调整 IP 打拍数、输出寄存器、读写模式或 latency，就必须同步检查 SoC adapter 和 testbench 行为模型。

## 核心原则

1. `rtl/ip/*.sv` 是仿真模型，不是 FPGA 实际 IP 的源码。
2. FPGA 实际使用的 IP 由 `fpga/create_vivado_project.tcl` 生成，参数才决定上板真实时序。
3. Verilator 通过 `scripts/filelists/ip_verilator.f` 使用 `rtl/ip/` 行为模型；Vivado Tcl 明确禁止把 `rtl/ip/*` 加入 FPGA sources。
4. 任何 IP latency 改动都要同时修改三处：Vivado Tcl 参数、`rtl/ip` 行为模型、消费该 IP 的 RTL 状态机或 adapter。
5. 不能只看 Verilator 通过。若行为模型比 Vivado IP 少一拍或多一拍，CPU 可能仿真正常但上板跑飞，表现为 LED/SEG 不更新或全 0。
6. **所有 latency 合同必须写成“请求在哪个上升沿被接受、raw data 在哪个上升沿之后更新、consumer 在哪个后续上升沿采样”。** `C_READ_LATENCY_A=N`、`read_valid_dN` 或“延迟 N 拍”不能直接互换；valid 与 data 在同一上升沿更新时，下游时序逻辑只能在下一个上升沿安全采样。

## SoC 与 `myCPU` 集成地图

当前上板路径不是把 `myCPU` 直接连到所有板级 IO，而是经过下面几层：

```text
top.sv
  pll: 生成 w_clk_50Mhz 和 cpu_clk，locked 派生 reset
  uart/twin_controller: 50 MHz 域，负责串口虚拟开关/按键和状态回读
  student_top.sv: CPU 域和 50 MHz 域的 SoC 接缝
    myCPU: 只看 CPU 时钟域、IROM 接口、DCache/DMEM 接口
    IROM_0: 指令 ROM，CPU 时钟域
    SocMemBridge: 数据侧地址译码，CPU 时钟域为主
      DramBramAdapter -> DRAM_0: 数据 RAM
      LED/SEG/SW/KEY/CNT MMIO: 板级外设
```

`student_top.sv` 是修改 core 后最先要检查的文件。它定义了 SoC 对 `myCPU` 的外部合同：

| 合同项 | 当前事实 | 修改 core 时的适配点 |
| --- | --- | --- |
| reset | `cpu_rst_sync` 是 CPU 域同步释放、高有效 reset，传给 `myCPU.cpu_rst`。 | 新 core 若需要低有效或异步 reset，必须在 `student_top.sv` 加 wrapper，不要直接把 `pll.locked` 接进 core。 |
| 指令端口 | `irom_addrA/B[31:0]` 由 core 给出，SoC 用 `irom_addrA/B[13:2]` 作为 4 KiB word ROM 地址；`irom_enaA/B` 控制双口 ROM 读；`irom_dataA/B` 返回两路 32 位指令。 | 改成 AXI/AHB/ready-valid 取指、改 reset PC、改 IROM 深度或改 fetch latency 时，必须同步改 `student_top.sv`、`IROM_0` Tcl 和行为模型。 |
| 数据端口 | `dmem_req_*`/`dmem_resp_*` 是单请求方向的 ready-valid 接口，当前 SoC 不支持多个 outstanding transaction。 | 新 core/DCache 若允许多个 outstanding、burst、id、乱序返回，需要重写 `SocMemBridge` 和 `DramBramAdapter`，不能只加信号。 |
| 地址空间 | DRAM: `0x8010_0000` 到 `0x8013_ffff`；MMIO: SW/KEY/SEG/LED/CNT 在 `0x8020_xxxx`。 | 改 linker、reset PC、cacheable 区间或 MMIO 地址时，必须同时改 core/DCache 参数、`SocMemBridge` 常量、测试程序和文档。 |
| 时钟域 | `myCPU`、IROM、DRAM、LED/SEG 寄存器在 `cpu_clk`；UART/twin/counter tick 在 50 MHz。 | 新增任何跨域读写都必须加同步或异步 FIFO，并检查 `digital_twin_cdc.xdc`。 |

## `myCPU` 数据接口合同

当前 `myCPU` 对 SoC 暴露的是简化内存接口：

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

SoC 侧的假设如下：

- `SocMemBridge.req_ready` 对 MMIO 恒为 1，对 DRAM 当前也由 `DramBramAdapter.req_ready=1` 恒为 1。
- 写请求没有单独写响应。core/DCache 在 `req_valid && req_ready && req_write` 后就认为写已被接受。
- 读请求通过 `resp_valid` 返回数据。当前 DRAM Adapter 对读请求的 valid/offset 打 3 级流水，保证 DCache 在 raw BRAM 数据更新后的下一个上升沿采样；MMIO 读由 `mmio_resp_valid_q` 返回，不走该流水。
- `SocMemBridge` 只根据地址选择 DRAM 或 MMIO，当前没有 error response。未命中地址读返回 0，写被忽略。
- `DCache` miss refill 会顺序发 8 个 32-bit 读请求填一条 32-byte cache line；`SocMemBridge` 不支持 burst，只看到 8 次普通单拍读。

如果后续替换或大改 `myCPU`，必须先回答这几个问题：

1. 新 core 是否仍然只有一个 IROM 读端口和一个 DMEM 端口？
2. 新 core 是否要求 IROM 或 DMEM 支持 stall/backpressure？
3. 新 core 是否可能发出多个未完成读请求？
4. 新 core 的 load/store byte lane 约定是“低地址字节在 `wdata[7:0]`”还是已经预移位？
5. 新 core 是否把 MMIO 标成 uncached？如果不标，`DCache` 的 cacheable 地址范围是否仍能保证 `0x8020_xxxx` 不被缓存？

只要任一答案变了，就必须同步审查 `student_top.sv`、`SocMemBridge.sv`、`DramBramAdapter.sv` 和 `DCache.sv`，不能只改 core。

## 当前 IP 时序表

| IP | Verilator 行为模型 | Vivado Tcl 当前参数 | RTL 消费方合同 | 修改时必须同步检查 |
| --- | --- | --- | --- | --- |
| `IROM_0` | `rtl/ip/IROM_0.sv` 在 `ena/enb` 时分别用 `clka/clkb` 锁存 `addra/addrb`，`douta/doutb = mem[addr*_q]`。取指侧按 1 拍 ROM 读延迟使用。 | `Dual_Port_ROM`，`Assume_Synchronous_Clk=true`，A/B 端口同接 CPU 时钟，均使用 enable pin，A/B 端口输出寄存器均关闭。 | `rtl/soc/student_top.sv` 连接 CPU `irom_addrA/B`、`irom_dataA/B`、`irom_enaA/B`，并把 `clka/clkb` 都接到 `w_cpu_clk`。CPU 取指状态机默认下一拍可用。 | 若打开 ROM 输出寄存器、改成更深 pipeline 或让 A/B 口异步时钟，必须调整 CPU fetch/PC 对齐逻辑，并同步改 `rtl/ip/IROM_0.sv`。 |
| `DRAM_0` | `rtl/ip/DRAM_0.sv` 已拆分 memory latch 与 primitive output register：`ena` 更新 latch，`regcea` 更新 `douta`，写边沿按 READ_FIRST 锁存旧 word。 | `Single_Port_RAM`，`Operating_Mode_A=READ_FIRST`，`Use_Byte_Write_Enable=true`，`Register_PortA_Output_of_Memory_Primitives=true`，`Register_PortA_Output_of_Memory_Core=false`，`Use_REGCEA_Pin=true`。重新生成后应得到 `C_HAS_MEM_OUTPUT_REGS_A=1`、`C_HAS_ENA=1`、`C_HAS_REGCEA=1`。 | Adapter 用 request 驱动 `ENA`、用 `read_valid_d1` 驱动 `REGCEA`，并以 d2 对齐 `resp_valid/read_offset`。 | 必须重新生成 Vivado IP 和 bitstream；若生成 XML 中 `C_HAS_REGCEA` 不是 1，则不得上板。 |
| `MUL_0` | `rtl/ip/MUL_0.sv` 是 33x33 signed multiplier，`pipe0 -> pipe1 -> P` 共 3 级寄存输出。 | `mult_gen`，`Multiplier_Construction=Use_Mults`、`OptGoal=Speed`、`PipeStages=3`，33 位 signed 输入，自定义 66 位输出。 | `rtl/core/ex/stage_ex.sv` 用 3 级 `mul_valid_pipe/mul_op_pipe` 对齐 product 和 owner。 | 若 Tcl `PipeStages` 改变，必须同步改行为模型和 metadata valid 深度；不得删除 DSP 构造约束，否则 IP 会退回 LUT multiplier。 |
| `DIV_0` | `rtl/ip/DIV_0.sv` 固定 `DIV_LATENCY=34`，AXI-stream valid 管线后输出 `{quotient, remainder}`。 | `div_gen`，`Latency_Configuration=Manual`，`Latency=34`，`FlowControl=Blocking`，unsigned radix-2 divider，remainder mode。 | `rtl/core/ex/m_unit.sv` 发单拍 input valid，以固定 34 拍计数产生 `o_done`，并按 `div_raw[63:32]=quotient`、`div_raw[31:0]=remainder` 解包；当前未消费 IP 的 ready/output-valid。 | 若 Tcl `Latency`、`FlowControl` 或 output packing 改变，必须同步改行为模型和 `m_unit` 的计数/握手；不得只改 IP。 |
| `pll` | `rtl/ip/pll.sv` 只服务仿真，不代表真实锁相环时钟收敛和相位行为。 | `clk_wiz` 生成 `clk_out1` 系统时钟和 `clk_out2` CPU 时钟，频率由 `FPGA_SYS_CLK_MHZ/FPGA_CPU_CLK_MHZ` 控制。 | `rtl/soc/top.sv` 用 `locked` 派生 reset，同步释放到 50 MHz 和 CPU 时钟域。 | 若改 CPU 频率，必须重新看 timing report、UART `CLK_FREQ`、counter 换算、跨时钟 reset 和 CDC。 |

## DRAM Adapter 特别注意

`DramBramAdapter` 是最容易出现“仿真过、上板不过”的位置，因为它把 CPU/DCache 的 ready-valid 读请求翻译成 Vivado BRAM 的固定延迟读返回。

### 手册依据：BMG 的 latch、output register 与 enable 不是一回事

本节依据 AMD/Xilinx **Block Memory Generator v8.4 Product Guide, PG058, 2021-08-06**。官方入口为
`https://docs.amd.com/v/u/en-US/pg058-blk-mem-gen`，重点章节如下：

- Chapter 2, Table 2-5 `Core Signal Pinout`（PDF 第 30～31 页）：`ENA` 使能端口 A 的 Read、Write 和 reset；`REGCEA` 只使能端口 A 的最后一级 output register。
- Chapter 3, `Optional Output Registers`（PDF 第 53 页）：memory primitive output register 和 core output register 是两个独立可选级，每增加一级都会增加一个 Read latency cycle。
- Chapter 3, `Optional Register Clock Enable Pins`（PDF 第 55～56 页）：默认情况下 output register 由 `EN` 使能；打开 `Use REGCEA Pin` 后，最后一级 output register 改由 `REGCEA` 控制，并可独立于 `EN` 工作。
- Chapter 3, Figure 3-21/3-22（PDF 第 57～58 页）：无 output register 时，地址读取结果先出现在 primitive 的 `LATCH`；使用 primitive output register 时，数据路径是 `memory array -> LATCH -> REG1/DOUT`。
- Chapter 4, `Port [A|B] Optional Output Registers`（PDF 第 83～84 页）：未选择 `REGCE[A|B] Pin` 时，所有 register stage 都由 `ENA/ENB` 使能。

因此 native BMG 端口不能抽象成“`ENA` 脉冲一次，过固定 N 拍后 `DOUT` 自动更新”。正确模型是：

```text
memory array --(edge, ENA)--> memory output latch
memory output latch --(later edge, output-register CE)--> primitive output register / DOUT

output-register CE = Use_REGCEA_Pin ? REGCEA : ENA
```

关键语义：

1. `ENA=0` 时，该端口不执行新的 memory read/write；memory output latch 保持。
2. 打开 primitive output register 后，`DOUT` 是寄存器输出，不再等同于 memory output latch。
3. 未使用独立 `REGCEA` 时，`ENA=0` 也会冻结最后一级 output register。数据已经到达 latch，并不代表它会自动穿过 output register。
4. 使用独立 `REGCEA` 后，`ENA` 可以只负责 memory access，随后在 `ENA=0, REGCEA=1` 的边沿把 latch 数据推到 `DOUT`。
5. `READ_FIRST/WRITE_FIRST/NO_CHANGE` 描述的是**同一端口发生写操作时**，写入值、旧存储值与读输出的关系；它不改变上述 read pipeline，也不能修复 `ENA/REGCEA` 少一个使能边沿的问题。
6. GUI/XCI 中的 `READ_LATENCY`、`C_READ_LATENCY_A` 数值不能脱离 enable 波形解释。它描述配置的 latency 信息，但不会替 adapter 产生后续的 `ENA/REGCEA`；PG058 的 pin contract 和生成模型才是逐边沿验证依据。

### 当前 `DRAM_0` 的真实配置映射

失败 bitstream 所用的旧 Tcl 配置，以及 2026-07-11 已生成但尚未按本次修复 regenerate 的
`DRAM_0.xml/sim/DRAM_0.v`，对应关系是：

| 配置 | 当前值 | 生成模型 | 时序含义 |
| --- | --- | --- | --- |
| `Enable_A` | `Use_ENA_Pin` | `C_HAS_ENA=1` | 只有 `ENA=1` 的边沿才访问 memory latch。 |
| Primitive output register | `true` | `C_HAS_MEM_OUTPUT_REGS_A=1` | latch 后还有 embedded output register。 |
| Core output register | `false` | `C_HAS_MUX_OUTPUT_REGS_A=0` | 64-depth BRAM 拼接后的输出 MUX 后没有额外 core register。 |
| `Use_REGCEA_Pin` | `false` | `C_HAS_REGCEA=0` | PG058 规定最后一级 register 默认由 `ENA` 使能。 |
| Operating mode | `READ_FIRST` | `C_WRITE_MODE_A=READ_FIRST` | 写边沿输出旧存储值；不改变普通读的两级流动。 |

生成的 BMG 行为模型也明确实现了这一点：当 `C_HAS_REGCEA=0` 时，内部
`regce_i = (C_HAS_EN==0 || EN)`；memory read 在 `ENA` 边沿更新 `memory_out_a`，primitive output stage 也只在 `regce_i` 为 1 的边沿更新 `DOUTA`。

失败版本的 `DramBramAdapter.sv` 只把 `.ena(req_valid)`，而 DCache 在
`DC_REFILL_REQ` 接受一次请求后立即进入 `DC_REFILL_WAIT`，所以下一拍
`req_valid=0`。其实际错误时序为：

```text
edge N:          req_valid && !req_write 被接受，DRAM_0.ena=1；内部 memory output 读取目标 word
edge N+1:        DCache 已进入 WAIT，req_valid=0，因此 DRAM_0.ena=0
edge N+1:        primitive output register 的 regce_i=ENA=0，目标 word 不能转移到 douta
after edge N+2:  read_valid_d3/resp_valid 虽变为 1，但 dram_rdata_raw 仍可能是旧 word
next request:    ENA 再次为 1，旧请求的 word 才进入 douta，于是连续 refill 表现为一字滞后
```

这里 `read_valid_d3` 只表达“这个请求已经等待了三拍”，并不具备推动 BMG
内部寄存器的能力。因此继续增加 d4/d5 都不会修复数据错位。

### 修复方案比较

| 方案 | IP 设置 | SoC/模型修改 | 正确性 | 频率/功耗/复杂度 |
| --- | --- | --- | --- | --- |
| **A. 独立 `REGCEA`（推荐）** | 保留 primitive output register；增加 `CONFIG.Use_REGCEA_Pin {true}` | Adapter 用请求边沿驱动 `ENA`，用 `read_valid_d1` 驱动 `REGCEA`；行为模型增加 `regcea` | memory access 和 output transfer 各有明确边沿，支持连续请求和 read 后紧跟 write | 保留 embedded output register 的时序收益；空闲时 64 个 BRAM 不读，功耗最低；只增加一根控制线 |
| B. SoC 把 `ENA` 延长两拍 | IP 不变 | `ENA` 至少为 `req_valid || read_valid_d1`；若采用锁存地址的 FSM，busy 时必须拉低 `req_ready` | 可以修复，但第二拍同时又访问一次 memory latch；必须严谨处理连续 read/write | 不改 IP interface，但控制耦合更强、会产生额外 BRAM 访问和动态功耗 |
| C. Port A Always Enabled | `Enable_A=Always_Enabled` | 删除 `.ena` 连接，重新对齐 valid | pipeline 每拍自然推进 | 最简单但 64 个 BRAM 持续活动，功耗大；不建议作为正式方案，Low Power algorithm 下也不可用 |
| D. 关闭 primitive output register | `Register_PortA_Output_of_Memory_Primitives=false` | raw data 改为 latch 输出，valid/offset 缩短 | 单拍 `ENA` 即可完成 read | 去掉寄存器会恶化 BRAM clock-to-out；与当前频率优化目标冲突，只有重新看 timing 后才能采用 |

不要通过把 `READ_FIRST` 改成 `NO_CHANGE/WRITE_FIRST` 修复本问题：三种模式只改变写边沿的输出语义，不会让 `ENA=0` 时的 output register 自动更新。也不要额外打开 core output register；那会再增加一级 latency，并且仍需要正确的 enable pipeline。

### 已采用方案 A：精确边沿合同

Tcl 增加：

```tcl
CONFIG.Register_PortA_Output_of_Memory_Primitives {true}
CONFIG.Register_PortA_Output_of_Memory_Core {false}
CONFIG.Use_REGCEA_Pin {true}
```

Adapter 建议定义 `read_accept = req_valid && req_ready && !req_write`，并采用：

```text
DRAM_0.ena     = req_valid
DRAM_0.regcea  = read_valid_d1
resp_valid     = read_valid_d2
response lane  = read_offset_d2
```

逐边沿行为：

```text
edge N 前:     read_accept=1, read_valid_d1=0, ENA=1, REGCEA=0, ADDRA=A
edge N 后:     memory latch=A 对应数据；read_valid_d1=1

edge N+1 前:   ENA 可为 0，REGCEA=read_valid_d1=1
edge N+1 后:   DOUT=A 对应数据；read_valid_d2=1，read_offset_d2=A[1:0]

edge N+2 前:   DCache 看到 resp_valid=1 且 DOUT/offset 已稳定
edge N+2:      DCache 同一采样沿消费 A 的 valid、data 和 lane
```

连续读也能自然流水：edge N 由 `ENA` 把 A 放入 latch；edge N+1 可同时用
`REGCEA` 推出 A、用 `ENA` 把 B 放入 latch；edge N+2 再推出 B。read 后紧跟
write 时，edge N+1 的 `REGCEA` 仍推出 A，而 `ENA+WEA` 独立执行写操作。

2026-07-11 已完成对应源码修改：

1. `fpga/create_vivado_project.tcl`：为 `DRAM_0` 增加 `Use_REGCEA_Pin=true`。
2. `rtl/soc/DramBramAdapter.sv`：新增 `.regcea(read_valid_d1)`；响应所有权收敛到 d2，并删除无意义的 d3。
3. `rtl/ip/DRAM_0.sv`：端口增加 `regcea`；`ena` 边沿更新 memory latch，`regcea` 边沿更新 `douta`；写边沿实现 READ_FIRST 旧值锁存。
4. 尚待重新生成 Vivado IP/bitstream，并把 `fpga/diagnostics/post_impl_load_trace_tb.sv` 延长到最终 SEG 写；trace 至少打印 `ENA/REGCEA/read_valid_d1/d2/douta` 与 DCache downstream request/response。

仓库中还存在旧的 `rtl/soc/dram_driver.sv`，其 `DRAM_0` 实例没有连接
`REGCEA`。该模块不在 `scripts/filelists/soc.f`，不属于当前 `student_top` FPGA
构建，因此本次没有把它混入活动修复；若未来重新启用旧 `perip_bridge/dram_driver`
路径，必须先迁移到相同的 ENA/REGCEA 合同，否则读数据会停在 output register 之前。

行为模型的核心结构应等价于：

```systemverilog
always_ff @(posedge clka) begin
    if (ena) begin
        read_data_latch <= mem[addra]; // READ_FIRST: 写边沿也先取得旧值
        for (int i = 0; i < BYTE_COUNT; i++)
            if (wea[i]) mem[addra][i*8 +: 8] <= dina[i*8 +: 8];
    end
    if (regcea)
        douta <= read_data_latch;
end
```

### SoC-only 方案 B 的适用边界

若不希望重新生成带 `REGCEA` 端口的 IP，可以让 `ENA` 连续有效两个边沿，但必须选定并写清一种协议：

- 流水型：`dram_ena = req_valid || read_valid_d1`。第二拍的 ENA 一边把上一请求的 latch 推到 DOUT，一边可能读取当前地址；需要覆盖 read/read、read/write 和空闲 continuation 三种组合。
- 非流水 FSM：第一拍锁存地址并访问 memory，第二拍保持锁存地址再次使能，期间 `req_ready=0`，然后产生 response。该方案最容易证明，但每个 read 独占 adapter 多拍，会降低未来连续请求吞吐。

当前 DCache 已支持 `mem_req_ready` 反压，因此非流水 FSM 在功能上可行；但推荐方案 A 不需要改变 `req_ready=1` 的现有合同，吞吐和功耗都更好。

因此该边界必须长期同时满足：

- 保留 primitive output register 时，除了请求边沿的 `ENA`，还要为 output-transfer 边沿提供 register CE；推荐独立 `REGCEA`，未启用该 pin 时才需要延长 `ENA`。只延迟 `resp_valid` 无效。
- `resp_valid` 与 byte offset 必须和“数据真正到达 `douta`”的事务同级，禁止 valid、数据和 lane 属于不同请求。
- store 写通道保持当拍发给 BRAM，不要被读响应 pipeline 影响。
- `req_ready` 当前恒为 1；如果未来改成可反压 DRAM，就必须重新审查 DCache miss/fill 状态机。

### 2026-07-10 `SEG=0x33800000` 根因与固定注意事项

失败 bitstream 的 post-route 功能仿真复现了板上 `SEG=0x33800000`。按 `srcWithMext.dump` 的 dispatcher 和 pass/fail 计数对齐，实际失败项是 `LH/LW/LBU/LHU`；`SB/SH/LB` 通过，后续测试继续执行，因此不是控制流跑飞。

第一条 cache-line refill 在 DCache 下游端口出现了稳定的一字错位：

```text
request 0x8010000c -> response 0x00000000
request 0x80100010 -> response 0x1234abcd  // 实际属于 0x8010000c
request 0x80100014 -> response 0x55667788  // 实际属于 0x80100010
```

2026-07-11 复核证明，上述“只增加 `read_valid_d3/read_offset_d3` 即修复”的结论不完整。新实现确实综合了 d3 且 bitstream 晚于源码修改，但板上仍为 `0x33800000`。真正残留是 `DRAM_0.ena` 仍只接一拍 `req_valid`：真实 BMG 的 primitive output register 没有独立 `REGCEA`，其时钟使能等于 `ENA`；请求后一拍 `ENA=0`，目标 word 无法从内部 memory output 转移到 `douta`，直到下一请求才推出。因此 d3 只延迟了 valid，没有推进 data。

同时，修复前 `rtl/ip/DRAM_0.sv` 的 `douta <= read_data_d1` 不受 `ena` 控制，和生成 BMG 不一致，导致 Verilator/RTL 行为仿真会在空闲第二拍自动推出数据并掩盖板级问题。当前源码已改为独立 `regcea` 推进 `douta`，但仍需重新跑软件回归和 regenerate IP 验证；这仍与 byte mask、DCache lane mux 或 `Synth 8-7137` 无关。

必须长期遵守：

1. **不要根据 `C_READ_LATENCY_A` 或 IP GUI 的一个数字机械选择 `read_req_dN`。** 还必须检查 `ENA/REGCEA` 如何控制内部读和 output register；数据没有推进时，多加 valid stage 也不会修复。
2. **raw data 与 valid 在同一边沿更新不等于 consumer 能在该边沿取得新值。** 时序逻辑采样的是边沿前的值。
3. **valid、byte offset、transaction address 和 BRAM enable phase 必须属于同一事务。** 只延 valid、不管理 data advance，会继续返回旧 word；只延 valid、不延 offset 会把 uncached byte/halfword lane 再次配错。
4. **验收必须观察 DCache 下游接口。** 对初始化为不同非零值的连续地址，逐项配对 `mem_req_addr` 与 `mem_resp_rdata`；仅看最终 SEG、单个 LW 或全零内存无法暴露一字错位。
5. 若更改任一 BMG output register 选项，先重新生成 IP，再用 post-route 仿真重新确定安全采样边沿；旧的 1/2/3 拍经验表不得作为唯一依据。

### 修改 DRAM latency 的固定流程

每次改 `DRAM_0` 输出寄存器、读 latency、读写模式或 depth 时，按这个顺序做：

1. 改 `fpga/create_vivado_project.tcl` 的 `DRAM_0` 参数。
2. 重新生成一个干净 Vivado project 或 regenerate `DRAM_0`，打开生成的 wrapper，记录 `READ_LATENCY` / `C_READ_LATENCY_A`。
3. 把 `rtl/ip/DRAM_0.sv` 的行为改到相同的读返回拍数和 enable/REGCE 语义；不能只对齐拍数。
4. 按真实 `READ_LATENCY` 调整 `rtl/soc/DramBramAdapter.sv`：
   - 先保证请求 enable 能把目标 word 真正推进到 raw output，再决定 `resp_valid`；不能用 valid pipeline 代替 BRAM enable phase。
   - `read_offset_q` 必须和 `resp_valid` 使用同样级数。
   - 若未来 `req_ready` 不再恒为 1，则只有在 `req_valid && req_ready && !req_write` 被接受时推进读 pipeline。
5. 检查 `rtl/core/memory/DCache.sv`：
   - `DC_UNCACHED_WAIT` 和 `DC_MISS_WAIT` 只看 `mem_resp_valid`，理论上可以接受任意固定读延迟。
   - 但如果 adapter 改成可反压，`DC_MISS_REQ` 必须确认在 `mem_req_ready` 前保持地址和控制稳定。
   - 如果 core 改成多个 outstanding miss，当前 DCache/adapter 没有 tag/id，必须重构。
6. 跑 Verilator SoC 测试时必须使用更新后的 `rtl/ip/DRAM_0.sv`，不能让仿真模型仍是旧拍数。

DRAM byte lane 合同也不能改错：

- core/DCache 发出的 `dmem_req_wdata` 当前是未按地址低位预移位的低位对齐数据，例如 `sb` 使用 `wdata[7:0]` 和 `wstrb=4'b0001`。
- `DramBramAdapter` 根据 `req_addr[1:0]` 左移 `wdata/wstrb` 后写入 BRAM。
- 读回后 `DramBramAdapter` 会按发起读请求时的 `req_addr[1:0]` 右移到低位，core 的 `load_extend` 再按地址低位取 byte/halfword。
- 如果新 core 已经预移位 `wdata/wstrb` 或希望读回原始 word，不要只改 core；必须同步改 adapter 和 load 扩展逻辑。

## IROM / Fetch 特别注意

当前取指路径是“裸 ROM + core 自己控制 PC”的合同：

```text
cycle N:   core 拉高 irom_enaA/B，并给出 irom_addrA/B
cycle N+1: IROM_0 输出 cycle N 地址对应的 irom_dataA/B
```

当前 core 取指侧把 `irom_dataA/B` 当作固定 1 拍 ROM 返回来消费，PC 更新、双发对齐和分支重定向都依赖这个 latency 合同。修改时必须注意：

- 如果 IROM 仍是 1 拍，`student_top.sv` 只需要保持 `irom_word_addrA/B = irom_addrA/B[13:2]` 和 `IROM_0.ena/enb=irom_enaA/B`。
- 如果 IROM 改成 2 拍或更多，core fetch 状态机必须显式增加等待/valid 对齐；不能只在 `student_top` 里给 `irom_dataA/B` 再打一拍。
- 如果新 core 需要 `irom_resp_valid`、`irom_req_ready` 或 instruction bus stall，SoC 必须给 IROM 包一层 adapter；当前 `myCPU` 端口没有这些信号。
- 如果 IROM depth 改变，必须同步改三处：Tcl `Write_Depth_A`、`rtl/ip/IROM_0.sv ADDR_WIDTH` 或加载文件大小、`student_top.sv irom_word_addr` 位宽/截位。
- 如果 reset PC 改到 IROM 以外，必须同步修改 COE 生成、linker/测试程序地址、`DCache` cacheable 区间和 SoC 地址译码。

建议后续把 IROM latency 显式参数化，例如在 core 或 wrapper 中命名为 `IROM_READ_LATENCY`。只要出现这个参数，就要求 Tcl、`rtl/ip/IROM_0.sv` 和 fetch 状态机同名同值。

## MUL / DIV IP 与 core 的对齐

乘法 IP 的有效实例在 `rtl/core/ex/stage_ex.sv`，除法 IP 在 `rtl/core/ex/m_unit.sv`；它们都是 Vivado Tcl 生成的 FPGA IP。后续改 M 扩展时要同时维护这三层：

```text
fpga/create_vivado_project.tcl
  -> Vivado 真实 MUL_0 / DIV_0 IP 参数
rtl/ip/MUL_0.sv, rtl/ip/DIV_0.sv
  -> Verilator 行为模型
rtl/core/ex/stage_ex.sv, rtl/core/ex/m_unit.sv
  -> core 等待、valid、结果选位和特殊情况处理
```

### 乘法 `MUL_0`

当前合同：

- Tcl: `mult_gen`，`Multiplier_Construction=Use_Mults`、`OptGoal=Speed`、`PipeStages=3`，`A/B` 为 33-bit signed，输出 `P[65:0]`。
- 行为模型: `pipe0 -> pipe1 -> P`，等价 3 个寄存级。
- `stage_ex`: `mul_valid_pipe[2:0]` 和 `mul_op_pipe[0:2]` 与 `P` 同拍完成；`mul_result_fifo` 接收完成结果。

修改乘法周期时必须同步：

| 修改项 | 必须同步改 |
| --- | --- |
| `PipeStages` 从 3 改成 N | `rtl/ip/MUL_0.sv` 改成 N 级 pipeline；`stage_ex.sv` 的 `mul_valid_pipe/mul_op_pipe` 深度和结果有效拍同步改。 |
| 输出位宽/输入 signedness 改变 | Tcl `PortAWidth/PortBWidth/Use_Custom_Output_Width`、行为模型端口、`stage_ex.sv` 的 `mul_product` 位宽和 `MULH/MULHU/MULHSU` 选位同时改。 |
| DSP/LUT 构造改变 | Tcl `Multiplier_Construction` 和 `OptGoal` 必须显式冻结；33x33 三拍宽乘法不得依赖工具默认值。 |

建议把乘法 latency 写成唯一参数，例如：

```text
MUL_LATENCY = Vivado PipeStages = rtl/ip/MUL_0 pipeline depth = stage_ex metadata depth = 3
```

若 `MUL_LATENCY=0` 或组合乘法，要重新审查 timing，尤其是 FPGA CPU 频率可能会被乘法组合路径卡住。

### 除法 `DIV_0`

当前合同：

- Tcl: `div_gen`，`Latency=34`，`FlowControl=Blocking`，`Radix2`，unsigned 输入，remainder mode。
- 行为模型: `DIV_LATENCY=34`，输入 valid 后经过 valid 管线输出 `{quotient, remainder}`。
- `m_unit`: input valid 为单拍脉冲，以 `DIV_LATENCY=34` 固定计数产生 `o_done`；IP 的 input ready 和 output valid 当前未消费。除 0 和 `INT_MIN / -1` 仍按相同 34 拍等待，但结果由 core 特殊值覆盖。

官方 PG151 约束是：32-bit quotient 加 integer remainder 不能换成只支持 fractional output 的 High Radix；Radix-2 在 `clocks_per_division=1` 时允许 manual latency 从 0 到 fully-pipelined latency。当前固定使用 `34`，不能用旧工程 timing report 推断其他 latency 的 Fmax。

Vivado 2023.2 实测注意事项：

- 用当前 Tcl 参数生成 `DIV_0` 后，Vivado 自带 demo testbench 中的解包是：
  - `remainder <= m_axis_dout_tdata(31 downto 0)`
  - `quotient  <= m_axis_dout_tdata(63 downto 32)`
- 因此 RTL 和 Verilator 行为模型必须保持 `m_axis_dout_tdata = {quotient, remainder}`。如果误写成 `{remainder, quotient}`，Verilator 会因为模型和 RTL 同错而通过，但 FPGA 真实 `div_gen` 会让 `DIV/DIVU/REM/REMU` 四类子测试全部失败；`srcWithMext` 的 SEG 典型表现是 M 扩展计数停在 `4`，即高位显示 `0x374xxxxx` 而不是 `0x378xxxxx`。
- 以后不要只凭手写注释判断 packing；重新生成 IP 后优先查 `DIV_0.gen/.../demo_tb/tb_DIV_0.vhd` 或等价 wrapper/testbench 中的 quotient/remainder 赋值。

修改除法时必须同步：

| 修改项 | 必须同步改 |
| --- | --- |
| Tcl `Latency` 改变 | `rtl/ip/DIV_0.sv DIV_LATENCY` 与 `m_unit.sv` 的固定计数必须改成同值，并重新验证 `o_done` 采样拍。 |
| Tcl `FlowControl` 改变 | 行为模型必须模拟 `tready/tvalid`；`m_unit` 当前只发一个 input pulse且不看 ready，若 IP 可能反压，必须改成完整握手。 |
| 输出 packing 改变 | 行为模型和 `m_unit.sv` 的 `quot_raw=div_raw[63:32]`、`rem_raw=div_raw[31:0]` 必须同时改。 |
| signed divider 改为 IP 内部处理 | `m_unit` 当前在 IP 外部取绝对值和修正符号；不要和 signed IP 重复修正。 |

M 扩展验证不能只跑一个 `mul`。至少覆盖 `mul/mulh/mulhsu/mulhu/div/divu/rem/remu`、除 0、`0x8000_0000 / -1`、连续两条 M 指令，以及 M 指令后紧跟使用结果的相关场景。

## PLL 与 CDC 约束

`pll` 的 `clk_out1` 是 50 MHz 系统域，`clk_out2` 是 CPU/IROM/DRAM/core 域。虽然两个时钟来自同一个 `clk_wiz`，当前 SoC RTL 按跨时钟域设计来使用它们，因此 Vivado 工程必须显式处理 CDC：

- `fpga/create_vivado_project.tcl` 会生成 late-processing 的 `digital_twin_cdc.xdc`，对 `clk_out1_pll` 和 `clk_out2_pll` 使用 `set_clock_groups -asynchronous`。
- 跨域同步链必须加 `(* ASYNC_REG = "TRUE" *)`，包括 reset 同步、`virtual_sw/key` 同步、counter enable/gray counter 同步、以及给 `twin_controller` 采样用的 `virtual_led/seg` 镜像。
- 物理 `virtual_led/virtual_seg` 可以继续由 CPU 域寄存器直接驱动到 IO；但任何被 50 MHz 逻辑读取、缓存或串口回传的 CPU 域信号都必须先同步到 50 MHz 域。
- 修改 PLL 输出频率后必须重新生成工程并重新看 routed timing summary。旧 build 中的 PLL XCI、timing report 和 bitstream 不会自动继承 Tcl 默认值。

已知板级线索：

- 旧 `digital_twin_srcWithMext` routed timing report 曾显示 `clk_out2_pll -> clk_out1_pll` setup 违例，WNS=-0.131 ns、TNS=-0.750 ns、9 个 failing endpoints。这类问题不会被 Verilator 暴露。
- 2026-07-09 复查 `fpga/build/digital_twin_srcWithMext/digital_twin.runs/impl_1/top_timing_summary_routed.rpt`：CPU 域 `clk_out2_pll` 的 intra-clock WNS 为 +0.433 ns，50 MHz 域 `clk_out1_pll` 的 intra-clock WNS 为 +16.730 ns；整体 WNS=-0.029 ns 只来自 `clk_out2_pll -> clk_out1_pll`，最差路径是 `student_top_inst/mem_bridge/seg_driver/count_reg[4]` 到 `virtual_seg_50_d1_reg[12]`。
- 同一轮 `runme.log` 明确报出 `digital_twin_cdc.xdc` 中的 `if` 命令不被 XDC parser 支持，因此原本想生成的 `set_clock_groups -asynchronous` 没有生效。CDC XDC 必须保持为纯 XDC 命令，不能在 XDC 文件里写 `if`/`else` fallback。
- 动态扫描后的 `virtual_seg[39:0]` 不允许从 CPU 域逐 bit 同步到 50 MHz 域；应同步 raw `seg_wdata`，再在 50 MHz 域生成段码/位选，或者使用握手快照。否则 timing 和功能都可能表现为“Verilator pass，上板 SEG 错号/错数”。

## 修改 Checklist

修改任意 IP 参数、`rtl/ip` 行为模型或 `myCPU` core 前，按顺序检查：

1. 确认修改属于哪一类：取指 IROM、数据 DRAM/MMIO、MUL/DIV、PLL/CDC、core 外部端口、地址空间。
2. 查 `fpga/create_vivado_project.tcl` 中对应 IP 的 latency、输出寄存器、读写模式、握手配置和端口位宽。
3. 重新生成或 inspect 受影响 IP 的 Vivado wrapper，把 `READ_LATENCY`、`C_READ_LATENCY_A`、pipeline stages、AXI-stream packing 等真实参数记录下来。
4. 查 `rtl/ip/<IP>.sv` 是否与 Tcl 生成 IP 的端口和时序一致。
5. 查消费方 RTL：
   - IROM: `student_top.sv` 地址截位和 core fetch 状态机。
   - DRAM: `DramBramAdapter.sv`、`SocMemBridge.sv`、`DCache.sv`。
   - MUL/DIV: `stage_ex.sv`、`m_unit.sv` 的 metadata 深度、固定计数/valid 握手和结果选位。
   - PLL/CDC: `top.sv`、`student_top.sv`、`counter.sv`、`digital_twin_cdc.xdc`。
6. 如果 `myCPU` 外部端口变了，先改 `student_top.sv` wrapper；不要让板级 `top.sv` 直接理解 core 内部协议。
7. 如果地址空间变了，同步改 `SocMemBridge`、`DCache` cacheable 区间、测试程序 linker/COE 生成和文档。
8. 查 Verilator filelist：仿真只应使用 `scripts/filelists/ip_verilator.f` 中的行为模型。
9. 查 Vivado filelist/Tcl：FPGA sources 不应包含 `rtl/ip/*` 行为模型。
10. 跑 SoC 级仿真时，必要时让行为模型模拟真实 Vivado IP 的拍数，而不是为了测试方便缩短 latency。
11. 对存储器读通道记录三个边沿：request accept、raw data update、consumer sample；检查 consumer sample 严格晚于 raw data update。
12. 重新生成 Vivado project 或至少 regenerate affected IP；旧 `fpga/build/...` 不会自动继承 Tcl 参数变化。
13. 检查 `digital_twin_cdc.xdc` 是否被加入约束集，并确认 `clk_out1_pll`/`clk_out2_pll` 的 CDC 分组生效。
14. 上板前看 timing report，并确认 bitstream 来自最新 RTL/Tcl/IP 配置。

## 改 core 时的 SoC 适配速查

| core 修改 | SoC 必查文件 | 典型适配 |
| --- | --- | --- |
| 改 reset PC / 程序入口 | `rtl/core/CoreTypes.sv`、`student_top.sv`、COE/linker 脚本 | 保证 PC 落在 IROM 初始化内容覆盖范围内。 |
| 改 IROM latency 或取指协议 | `student_top.sv`、`rtl/ip/IROM_0.sv`、`fpga/create_vivado_project.tcl`、core fetch FSM | 增加 fetch valid/等待状态，或写 IROM adapter。 |
| 改 load/store 接口 | `myCPU.sv`、`student_top.sv`、`SocMemBridge.sv`、`DramBramAdapter.sv`、`DCache.sv` | 对齐 ready-valid、写响应、outstanding、byte lane、uncached 语义。 |
| 改 DRAM latency/depth/byte enable | `DramBramAdapter.sv`、`rtl/ip/DRAM_0.sv`、Tcl、`DCache.sv` | 按 wrapper 真实 `READ_LATENCY` 调整响应 pipeline 和 offset pipeline。 |
| 改 MMIO 地址或新增外设 | `SocMemBridge.sv`、测试程序、文档 | 更新地址译码、读写返回、reset 值和 side effect。 |
| 改 MUL latency/位宽 | `stage_ex.sv`、`rtl/ip/MUL_0.sv`、Tcl | 对齐 `PipeStages`、metadata 深度、结果位宽和选位。 |
| 改 DIV latency/flow control | `m_unit.sv`、`rtl/ip/DIV_0.sv`、Tcl | 对齐 `Latency`、固定计数、`tready/tvalid` 和 `{quotient,remainder}` packing。 |
| 改 CPU 时钟频率 | Tcl PLL、`top.sv`、counter、UART、timing report | 更新 `FPGA_CPU_CLK_MHZ`，重看 CPU 域 timing 和 CDC 分组。 |
| 引入多发射/乱序/多 outstanding | `SocMemBridge.sv`、`DramBramAdapter.sv`、`DCache.sv` | 当前 SoC 无 id/tag/乱序返回支持，需要重新设计内存桥。 |

## 常见症状

| 症状 | 优先怀疑 |
| --- | --- |
| Verilator pass，但上板 LED/SEG 全 0 | IROM/DRAM 实际读 latency 与行为模型不一致，程序早期读错后跑飞；也检查 reset/PLL locked。 |
| `srcWithMext` 显示 `0x33800000`，且连续非零初始化 word 向后错一项 | 优先检查 registered BMG 的 `ENA/REGCEA`：单拍 `req_valid` 是否只加载内部 memory output、要到下一请求才推出旧 word；其次再检查 `resp_valid` stage，并配对 DCache 下游 request/response。 |
| src 程序能启动但结果随机 | DRAM read offset、byte write enable 或 READ_FIRST/WRITE_FIRST 模式与 adapter 不一致。 |
| M 扩展仿真过但 FPGA 错 | `MUL_0`/`DIV_0` latency、signedness、输出位宽或 AXI-stream valid 时序不一致。 |
| 改 CPU 频率后 UART/计时异常 | `CLK_FREQ`、counter cycles-per-ms、PLL Tcl 参数或 timing 约束未同步。 |
| Routed timing report 出现 `clk_out2_pll -> clk_out1_pll` 违例 | CDC 约束未生效，或 50 MHz 逻辑直接采样了 CPU 域信号。 |

## 维护要求

后续如果调整 IP 打拍数或 Tcl 参数，必须在同一次修改中更新本文档的“当前 IP 时序表”。若发现新的板级时序差异，应把根因写入 `docs/archive/YYYY-MM-DD/`，但当前事实应优先维护在本文档。
