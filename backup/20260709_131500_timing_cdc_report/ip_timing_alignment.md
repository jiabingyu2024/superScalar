# IP Timing Alignment Contract

本文档用于提醒后续修改者和 AI：`rtl/ip/` 中的 Verilator 行为模型、`fpga/create_vivado_project.tcl` 中生成的 Vivado IP、以及 `rtl/soc/` 中的桥接逻辑必须保持同一个时序合同。只要调整 IP 打拍数、输出寄存器、读写模式或 latency，就必须同步检查 SoC adapter 和 testbench 行为模型。

## 核心原则

1. `rtl/ip/*.sv` 是仿真模型，不是 FPGA 实际 IP 的源码。
2. FPGA 实际使用的 IP 由 `fpga/create_vivado_project.tcl` 生成，参数才决定上板真实时序。
3. Verilator 通过 `scripts/filelists/ip_verilator.f` 使用 `rtl/ip/` 行为模型；Vivado Tcl 明确禁止把 `rtl/ip/*` 加入 FPGA sources。
4. 任何 IP latency 改动都要同时修改三处：Vivado Tcl 参数、`rtl/ip` 行为模型、消费该 IP 的 RTL 状态机或 adapter。
5. 不能只看 Verilator 通过。若行为模型比 Vivado IP 少一拍或多一拍，CPU 可能仿真正常但上板跑飞，表现为 LED/SEG 不更新或全 0。

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
| 指令端口 | `irom_addr[31:0]` 由 core 给出，SoC 用 `irom_addr[13:2]` 作为 4 KiB word ROM 地址；`irom_ena` 控制 ROM 读；`irom_data` 返回 32 位指令。 | 改成 AXI/AHB/ready-valid 取指、改 reset PC、改 IROM 深度或改 fetch latency 时，必须同步改 `student_top.sv`、`IROM_0` Tcl 和行为模型。 |
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
- 读请求通过 `resp_valid` 返回数据。当前 DRAM 读返回 1 拍；MMIO 读也由 `mmio_resp_valid_q` 打 1 拍返回。
- `SocMemBridge` 只根据地址选择 DRAM 或 MMIO，当前没有 error response。未命中地址读返回 0，写被忽略。
- `DCache` miss refill 会顺序发 4 个 32-bit 读请求填一条 16-byte cache line；`SocMemBridge` 不支持 burst，只看到 4 次普通单拍读。

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
| `IROM_0` | `rtl/ip/IROM_0.sv` 在 `ena` 时锁存 `addra`，`douta = mem[addra_q]`。取指侧按 1 拍 ROM 读延迟使用。 | `Single_Port_ROM`，`Enable_A=Use_ENA_Pin`，`Register_PortA_Output_of_Memory_Primitives=false`，`Register_PortA_Output_of_Memory_Core=false`。 | `rtl/soc/student_top.sv` 连接 CPU `irom_addr/irom_data/irom_ena`。CPU 取指状态机默认下一拍可用。 | 若打开 ROM 输出寄存器或改成更深 pipeline，必须调整 CPU fetch/PC 对齐逻辑，并同步改 `rtl/ip/IROM_0.sv`。 |
| `DRAM_0` | `rtl/ip/DRAM_0.sv` 在读周期 `douta <= mem[addra]`，行为模型是 1 拍读返回。 | `Single_Port_RAM`，`Operating_Mode_A=READ_FIRST`，`Use_Byte_Write_Enable=true`，`Register_PortA_Output_of_Memory_Primitives=false`，`Register_PortA_Output_of_Memory_Core=false`。FPGA DRAM 必须保持 `READ_LATENCY=1`。 | `rtl/soc/DramBramAdapter.sv` 当前把读响应和 byte offset 延后 1 拍。 | 若打开任意输出寄存器或增加 pipeline，必须先确认生成 wrapper 的 `C_READ_LATENCY_A`，再同步调整 adapter 和 `rtl/ip/DRAM_0.sv`。 |
| `MUL_0` | `rtl/ip/MUL_0.sv` 是 33x33 signed multiplier，`pipe0/pipe1/P` 共 3 级寄存输出。 | `mult_gen`，`PipeStages=3`，33 位 signed 输入，自定义 66 位输出。 | `rtl/core/execute/MulDivUnit.sv` 用 `mul_count_q` 等待固定乘法结果拍数。 | 若 Tcl `PipeStages` 改变，必须同步改 `MUL_0.sv` pipeline 深度和 `MulDivUnit.sv` 的等待计数。 |
| `DIV_0` | `rtl/ip/DIV_0.sv` 固定 `DIV_LATENCY=34`，AXI-stream valid 管线后给出 quotient/remainder。 | `div_gen`，`Latency_Configuration=Manual`，`Latency=34`，`FlowControl=Blocking`，unsigned radix-2 divider。 | `rtl/core/execute/MulDivUnit.sv` 等待 `m_axis_dout_tvalid`，不硬编码完成拍数，但仿真模型必须与 Tcl latency 一致。 | 若 Tcl `Latency` 或 `FlowControl` 改变，必须同步改 `DIV_0.sv`，并检查 `MulDivUnit.sv` 是否还满足握手协议。 |
| `pll` | `rtl/ip/pll.sv` 只服务仿真，不代表真实锁相环时钟收敛和相位行为。 | `clk_wiz` 生成 `clk_out1` 系统时钟和 `clk_out2` CPU 时钟，频率由 `FPGA_SYS_CLK_MHZ/FPGA_CPU_CLK_MHZ` 控制。 | `rtl/soc/top.sv` 用 `locked` 派生 reset，同步释放到 50 MHz 和 CPU 时钟域。 | 若改 CPU 频率，必须重新看 timing report、UART `CLK_FREQ`、counter 换算、跨时钟 reset 和 CDC。 |

## DRAM Adapter 特别注意

`DramBramAdapter` 是最容易出现“仿真过、上板不过”的位置，因为它把 CPU/DCache 的 ready-valid 读请求翻译成 Vivado BRAM 的固定延迟读返回。

当前合同：

```text
cycle N:   req_valid && !req_write 被接受，DRAM_0.ena=1，addra 有效
cycle N+1: dram_rdata_raw 对应 cycle N 的地址，adapter 拉高 resp_valid
```

因此当前 `DramBramAdapter.sv` 必须：

- 对读请求 valid 打 1 拍后生成 `resp_valid`。
- 对 `req_addr[1:0]` 的 byte offset 同步打 1 拍。
- store 写通道保持当拍发给 BRAM，不要被读响应 pipeline 影响。
- `req_ready` 当前恒为 1；如果未来改成可反压 DRAM，就必须重新审查 DCache miss/fill 状态机。

Vivado Block Memory Generator v8.4 PG058 明确说明：BMG 有两级可选输出寄存器，分别是 primitive embedded output register 和 core output register；summary tab 的 Total Port A Read Latency 由 Port A output register 选项控制。对当前 native single-port RAM 合同，可以按下面规则调整：

| `Register_PortA_Output_of_Memory_Primitives` | `Register_PortA_Output_of_Memory_Core` | 预期读返回 | Adapter 响应 |
| --- | --- | --- | --- |
| `false` | `false` | 1 拍 | `resp_valid <= read_req_d1`，byte offset 打 1 拍 |
| `true` | `false` | 2 拍 | `resp_valid <= read_req_d2`，byte offset 打 2 拍 |
| `false` | `true` | 2 拍 | `resp_valid <= read_req_d2`，byte offset 打 2 拍 |
| `true` | `true` | 3 拍 | `resp_valid <= read_req_d3`，byte offset 打 3 拍 |

生成工程后仍然要检查 `DRAM_0.xci` 或 `sim/DRAM_0.v` 里的 `C_READ_LATENCY_A` / `READ_LATENCY`，目的是确认当前 bitstream 使用的 IP 已经按最新 Tcl 重新生成，而不是旧 build 的 stale IP。

### 修改 DRAM latency 的固定流程

每次改 `DRAM_0` 输出寄存器、读 latency、读写模式或 depth 时，按这个顺序做：

1. 改 `fpga/create_vivado_project.tcl` 的 `DRAM_0` 参数。
2. 重新生成一个干净 Vivado project 或 regenerate `DRAM_0`，打开生成的 wrapper，记录 `READ_LATENCY` / `C_READ_LATENCY_A`。
3. 把 `rtl/ip/DRAM_0.sv` 的行为改到同样的读返回拍数。
4. 按真实 `READ_LATENCY` 调整 `rtl/soc/DramBramAdapter.sv`：
   - `resp_valid` 延迟拍数必须等于 BRAM 读返回拍数。
   - `read_offset_q` 必须和读请求一起延迟同样拍数。
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
cycle N:   core 拉高 irom_ena，并给出 irom_addr
cycle N+1: IROM_0 输出 cycle N 地址对应的 irom_data
```

当前 `riscv_cpu.sv` 直接在 `ST_EXEC` 使用 `irom_data` 作为 `exec_inst_c`，并在等待 load/muldiv 时继续预取 `pred_next_pc_c`。这意味着 IROM latency、PC 更新和分支重定向是绑在一起的。修改时必须注意：

- 如果 IROM 仍是 1 拍，`student_top.sv` 只需要保持 `irom_word_addr = irom_addr[13:2]` 和 `IROM_0.ena=irom_ena`。
- 如果 IROM 改成 2 拍或更多，core fetch 状态机必须显式增加等待/valid 对齐；不能只在 `student_top` 里给 `irom_data` 再打一拍。
- 如果新 core 需要 `irom_resp_valid`、`irom_req_ready` 或 instruction bus stall，SoC 必须给 IROM 包一层 adapter；当前 `myCPU` 端口没有这些信号。
- 如果 IROM depth 改变，必须同步改三处：Tcl `Write_Depth_A`、`rtl/ip/IROM_0.sv ADDR_WIDTH` 或加载文件大小、`student_top.sv irom_word_addr` 位宽/截位。
- 如果 reset PC 改到 IROM 以外，必须同步修改 COE 生成、linker/测试程序地址、`DCache` cacheable 区间和 SoC 地址译码。

建议后续把 IROM latency 显式参数化，例如在 core 或 wrapper 中命名为 `IROM_READ_LATENCY`。只要出现这个参数，就要求 Tcl、`rtl/ip/IROM_0.sv` 和 fetch 状态机同名同值。

## MUL / DIV IP 与 core 的对齐

乘除法 IP 虽然实例化在 `rtl/core/execute/MulDivUnit.sv`，但它们仍然是 Vivado Tcl 生成的 FPGA IP。后续改 M 扩展时要同时维护这三层：

```text
fpga/create_vivado_project.tcl
  -> Vivado 真实 MUL_0 / DIV_0 IP 参数
rtl/ip/MUL_0.sv, rtl/ip/DIV_0.sv
  -> Verilator 行为模型
rtl/core/execute/MulDivUnit.sv
  -> core 等待、valid、结果选位和特殊情况处理
```

### 乘法 `MUL_0`

当前合同：

- Tcl: `mult_gen`，`PipeStages=3`，`A/B` 为 33-bit signed，输出 `P[65:0]`。
- 行为模型: `pipe0 -> pipe1 -> P`，等价 3 个寄存级。
- `MulDivUnit`: 启动乘法时 `mul_count_q <= 2'd2`，随后倒计数到 0 取 `mul_product`。

修改乘法周期时必须同步：

| 修改项 | 必须同步改 |
| --- | --- |
| `PipeStages` 从 3 改成 N | `rtl/ip/MUL_0.sv` 改成 N 级 pipeline；`MulDivUnit.sv` 的 `mul_count_q` 宽度和初值改成 `N-1` 或用参数统一。 |
| 输出位宽/输入 signedness 改变 | Tcl `PortAWidth/PortBWidth/Use_Custom_Output_Width`、行为模型端口、`MulDivUnit` 的 `mul_product` 位宽和 `MULH/MULHU/MULHSU` 选位同时改。 |
| IP 从固定 latency 改成 valid 握手 | `MulDivUnit` 不能再用倒计数，必须改成等待 IP valid，并处理 busy/start 不重入。 |

建议把乘法 latency 写成唯一参数，例如：

```text
MUL_LATENCY = Vivado PipeStages = rtl/ip/MUL_0 pipeline depth = MulDivUnit wait cycles
```

若 `MUL_LATENCY=0` 或组合乘法，要重新审查 timing，尤其是 FPGA CPU 频率可能会被乘法组合路径卡住。

### 除法 `DIV_0`

当前合同：

- Tcl: `div_gen`，`Latency=34`，`FlowControl=Blocking`，`Radix2`，unsigned 输入，remainder mode。
- 行为模型: `DIV_LATENCY=34`，输入 valid 后经过 valid 管线输出 `{remainder, quotient}`。
- `MulDivUnit`: 对正常除法等待 `m_axis_dout_tvalid`，对除 0 和 `INT_MIN / -1` 由 core 内部走 `MD_SPECIAL`，不启动 IP。

修改除法时必须同步：

| 修改项 | 必须同步改 |
| --- | --- |
| Tcl `Latency` 改变 | `rtl/ip/DIV_0.sv DIV_LATENCY` 改成同值；`MulDivUnit` 若仍等 `div_valid`，通常无需改等待计数。 |
| Tcl `FlowControl` 改变 | 行为模型必须模拟 `tready/tvalid`；`MulDivUnit` 当前忽略 `tready`，若真实 IP 会反压，必须改 start 握手。 |
| 输出 packing 改变 | 行为模型和 `MulDivUnit` 的 `div_quot_u=div_data[31:0]`、`div_rem_u=div_data[63:32]` 必须同时改。 |
| signed divider 改为 IP 内部处理 | `MulDivUnit` 当前在 IP 外部取绝对值和修正符号；不要和 signed IP 重复修正。 |

M 扩展验证不能只跑一个 `mul`。至少覆盖 `mul/mulh/mulhsu/mulhu/div/divu/rem/remu`、除 0、`0x8000_0000 / -1`、连续两条 M 指令，以及 M 指令后紧跟使用结果的相关场景。

## PLL 与 CDC 约束

`pll` 的 `clk_out1` 是 50 MHz 系统域，`clk_out2` 是 CPU/IROM/DRAM/core 域。虽然两个时钟来自同一个 `clk_wiz`，当前 SoC RTL 按跨时钟域设计来使用它们，因此 Vivado 工程必须显式处理 CDC：

- `fpga/create_vivado_project.tcl` 会生成 late-processing 的 `digital_twin_cdc.xdc`，对 `clk_out1_pll` 和 `clk_out2_pll` 使用 `set_clock_groups -asynchronous`。
- 跨域同步链必须加 `(* ASYNC_REG = "TRUE" *)`，包括 reset 同步、`virtual_sw/key` 同步、counter enable/gray counter 同步、以及给 `twin_controller` 采样用的 `virtual_led/seg` 镜像。
- 物理 `virtual_led/virtual_seg` 可以继续由 CPU 域寄存器直接驱动到 IO；但任何被 50 MHz 逻辑读取、缓存或串口回传的 CPU 域信号都必须先同步到 50 MHz 域。
- 修改 PLL 输出频率后必须重新生成工程并重新看 routed timing summary。旧 build 中的 PLL XCI、timing report 和 bitstream 不会自动继承 Tcl 默认值。

已知板级线索：旧 `digital_twin_srcWithMext` routed timing report 曾显示 `clk_out2_pll -> clk_out1_pll` setup 违例，WNS=-0.131 ns、TNS=-0.750 ns、9 个 failing endpoints。这类问题不会被 Verilator 暴露。

## 修改 Checklist

修改任意 IP 参数、`rtl/ip` 行为模型或 `myCPU` core 前，按顺序检查：

1. 确认修改属于哪一类：取指 IROM、数据 DRAM/MMIO、MUL/DIV、PLL/CDC、core 外部端口、地址空间。
2. 查 `fpga/create_vivado_project.tcl` 中对应 IP 的 latency、输出寄存器、读写模式、握手配置和端口位宽。
3. 重新生成或 inspect 受影响 IP 的 Vivado wrapper，把 `READ_LATENCY`、`C_READ_LATENCY_A`、pipeline stages、AXI-stream packing 等真实参数记录下来。
4. 查 `rtl/ip/<IP>.sv` 是否与 Tcl 生成 IP 的端口和时序一致。
5. 查消费方 RTL：
   - IROM: `student_top.sv` 地址截位和 core fetch 状态机。
   - DRAM: `DramBramAdapter.sv`、`SocMemBridge.sv`、`DCache.sv`。
   - MUL/DIV: `MulDivUnit.sv` 等待计数、valid 握手、结果选位。
   - PLL/CDC: `top.sv`、`student_top.sv`、`counter.sv`、`digital_twin_cdc.xdc`。
6. 如果 `myCPU` 外部端口变了，先改 `student_top.sv` wrapper；不要让板级 `top.sv` 直接理解 core 内部协议。
7. 如果地址空间变了，同步改 `SocMemBridge`、`DCache` cacheable 区间、测试程序 linker/COE 生成和文档。
8. 查 Verilator filelist：仿真只应使用 `scripts/filelists/ip_verilator.f` 中的行为模型。
9. 查 Vivado filelist/Tcl：FPGA sources 不应包含 `rtl/ip/*` 行为模型。
10. 跑 SoC 级仿真时，必要时让行为模型模拟真实 Vivado IP 的拍数，而不是为了测试方便缩短 latency。
11. 重新生成 Vivado project 或至少 regenerate affected IP；旧 `fpga/build/...` 不会自动继承 Tcl 参数变化。
12. 检查 `digital_twin_cdc.xdc` 是否被加入约束集，并确认 `clk_out1_pll`/`clk_out2_pll` 的 CDC 分组生效。
13. 上板前看 timing report，并确认 bitstream 来自最新 RTL/Tcl/IP 配置。

## 改 core 时的 SoC 适配速查

| core 修改 | SoC 必查文件 | 典型适配 |
| --- | --- | --- |
| 改 reset PC / 程序入口 | `rtl/core/CoreTypes.sv`、`student_top.sv`、COE/linker 脚本 | 保证 PC 落在 IROM 初始化内容覆盖范围内。 |
| 改 IROM latency 或取指协议 | `student_top.sv`、`rtl/ip/IROM_0.sv`、`fpga/create_vivado_project.tcl`、core fetch FSM | 增加 fetch valid/等待状态，或写 IROM adapter。 |
| 改 load/store 接口 | `myCPU.sv`、`student_top.sv`、`SocMemBridge.sv`、`DramBramAdapter.sv`、`DCache.sv` | 对齐 ready-valid、写响应、outstanding、byte lane、uncached 语义。 |
| 改 DRAM latency/depth/byte enable | `DramBramAdapter.sv`、`rtl/ip/DRAM_0.sv`、Tcl、`DCache.sv` | 按 wrapper 真实 `READ_LATENCY` 调整响应 pipeline 和 offset pipeline。 |
| 改 MMIO 地址或新增外设 | `SocMemBridge.sv`、测试程序、文档 | 更新地址译码、读写返回、reset 值和 side effect。 |
| 改 MUL latency/位宽 | `MulDivUnit.sv`、`rtl/ip/MUL_0.sv`、Tcl | 对齐 `PipeStages`、等待计数、结果位宽和选位。 |
| 改 DIV latency/flow control | `MulDivUnit.sv`、`rtl/ip/DIV_0.sv`、Tcl | 对齐 `Latency`、`tready/tvalid` 和 `{rem,quot}` packing。 |
| 改 CPU 时钟频率 | Tcl PLL、`top.sv`、counter、UART、timing report | 更新 `FPGA_CPU_CLK_MHZ`，重看 CPU 域 timing 和 CDC 分组。 |
| 引入多发射/乱序/多 outstanding | `SocMemBridge.sv`、`DramBramAdapter.sv`、`DCache.sv` | 当前 SoC 无 id/tag/乱序返回支持，需要重新设计内存桥。 |

## 常见症状

| 症状 | 优先怀疑 |
| --- | --- |
| Verilator pass，但上板 LED/SEG 全 0 | IROM/DRAM 实际读 latency 与行为模型不一致，程序早期读错后跑飞；也检查 reset/PLL locked。 |
| src 程序能启动但结果随机 | DRAM read offset、byte write enable 或 READ_FIRST/WRITE_FIRST 模式与 adapter 不一致。 |
| M 扩展仿真过但 FPGA 错 | `MUL_0`/`DIV_0` latency、signedness、输出位宽或 AXI-stream valid 时序不一致。 |
| 改 CPU 频率后 UART/计时异常 | `CLK_FREQ`、counter cycles-per-ms、PLL Tcl 参数或 timing 约束未同步。 |
| Routed timing report 出现 `clk_out2_pll -> clk_out1_pll` 违例 | CDC 约束未生效，或 50 MHz 逻辑直接采样了 CPU 域信号。 |

## 维护要求

后续如果调整 IP 打拍数或 Tcl 参数，必须在同一次修改中更新本文档的“当前 IP 时序表”。若发现新的板级时序差异，应把根因写入 `docs/archive/YYYY-MM-DD/`，但当前事实应优先维护在本文档。
