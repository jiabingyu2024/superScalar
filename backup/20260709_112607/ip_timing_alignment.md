# IP Timing Alignment Contract

本文档用于提醒后续修改者和 AI：`rtl/ip/` 中的 Verilator 行为模型、`fpga/create_vivado_project.tcl` 中生成的 Vivado IP、以及 `rtl/soc/` 中的桥接逻辑必须保持同一个时序合同。只要调整 IP 打拍数、输出寄存器、读写模式或 latency，就必须同步检查 SoC adapter 和 testbench 行为模型。

## 核心原则

1. `rtl/ip/*.sv` 是仿真模型，不是 FPGA 实际 IP 的源码。
2. FPGA 实际使用的 IP 由 `fpga/create_vivado_project.tcl` 生成，参数才决定上板真实时序。
3. Verilator 通过 `scripts/filelists/ip_verilator.f` 使用 `rtl/ip/` 行为模型；Vivado Tcl 明确禁止把 `rtl/ip/*` 加入 FPGA sources。
4. 任何 IP latency 改动都要同时修改三处：Vivado Tcl 参数、`rtl/ip` 行为模型、消费该 IP 的 RTL 状态机或 adapter。
5. 不能只看 Verilator 通过。若行为模型比 Vivado IP 少一拍或多一拍，CPU 可能仿真正常但上板跑飞，表现为 LED/SEG 不更新或全 0。

## 当前 IP 时序表

| IP | Verilator 行为模型 | Vivado Tcl 当前参数 | RTL 消费方合同 | 修改时必须同步检查 |
| --- | --- | --- | --- | --- |
| `IROM_0` | `rtl/ip/IROM_0.sv` 在 `ena` 时锁存 `addra`，`douta = mem[addra_q]`。取指侧按 1 拍 ROM 读延迟使用。 | `Single_Port_ROM`，`Enable_A=Use_ENA_Pin`，`Register_PortA_Output_of_Memory_Primitives=false`，`Register_PortA_Output_of_Memory_Core=false`。 | `rtl/soc/student_top.sv` 连接 CPU `irom_addr/irom_data/irom_ena`。CPU 取指状态机默认下一拍可用。 | 若打开 ROM 输出寄存器或改成更深 pipeline，必须调整 CPU fetch/PC 对齐逻辑，并同步改 `rtl/ip/IROM_0.sv`。 |
| `DRAM_0` | `rtl/ip/DRAM_0.sv` 在读周期 `douta <= mem[addra]`，行为模型本身是 1 拍读返回。 | `Single_Port_RAM`，`Operating_Mode_A=READ_FIRST`，`Use_Byte_Write_Enable=true`，`Register_PortA_Output_of_Memory_Primitives=true`，`Register_PortA_Output_of_Memory_Core=false`。当前 FPGA DRAM 比行为模型多 1 拍。 | `rtl/soc/DramBramAdapter.sv` 当前把读响应和 byte offset 延后到 2 拍，以匹配 Vivado BRAM primitive output register。 | 若关闭 `Register_PortA_Output_of_Memory_Primitives`，adapter 读响应应回到 1 拍；若打开 core output register 或增加 pipeline，adapter 还要继续加拍。 |
| `MUL_0` | `rtl/ip/MUL_0.sv` 是 33x33 signed multiplier，`pipe0/pipe1/P` 共 3 级寄存输出。 | `mult_gen`，`PipeStages=3`，33 位 signed 输入，自定义 66 位输出。 | `rtl/core/execute/MulDivUnit.sv` 用 `mul_count_q` 等待固定乘法结果拍数。 | 若 Tcl `PipeStages` 改变，必须同步改 `MUL_0.sv` pipeline 深度和 `MulDivUnit.sv` 的等待计数。 |
| `DIV_0` | `rtl/ip/DIV_0.sv` 固定 `DIV_LATENCY=34`，AXI-stream valid 管线后给出 quotient/remainder。 | `div_gen`，`Latency_Configuration=Manual`，`Latency=34`，`FlowControl=Blocking`，unsigned radix-2 divider。 | `rtl/core/execute/MulDivUnit.sv` 等待 `m_axis_dout_tvalid`，不硬编码完成拍数，但仿真模型必须与 Tcl latency 一致。 | 若 Tcl `Latency` 或 `FlowControl` 改变，必须同步改 `DIV_0.sv`，并检查 `MulDivUnit.sv` 是否还满足握手协议。 |
| `pll` | `rtl/ip/pll.sv` 只服务仿真，不代表真实锁相环时钟收敛和相位行为。 | `clk_wiz` 生成 `clk_out1` 系统时钟和 `clk_out2` CPU 时钟，频率由 `FPGA_SYS_CLK_MHZ/FPGA_CPU_CLK_MHZ` 控制。 | `rtl/soc/top.sv` 用 `locked` 派生 reset，同步释放到 50 MHz 和 CPU 时钟域。 | 若改 CPU 频率，必须重新看 timing report、UART `CLK_FREQ`、counter 换算、跨时钟 reset 和 CDC。 |

## DRAM Adapter 特别注意

`DramBramAdapter` 是最容易出现“仿真过、上板不过”的位置，因为它把 CPU/DCache 的 ready-valid 读请求翻译成 Vivado BRAM 的固定延迟读返回。

当前合同：

```text
cycle N:   req_valid && !req_write 被接受，DRAM_0.ena=1，addra 有效
cycle N+1: Vivado primitive 内部读出，但 primitive output register 仍在打一拍
cycle N+2: dram_rdata_raw 对应 cycle N 的地址，adapter 拉高 resp_valid
```

因此当前 `DramBramAdapter.sv` 必须：

- 对读请求 valid 打 2 拍后生成 `resp_valid`。
- 对 `req_addr[1:0]` 的 byte offset 同步打 2 拍。
- store 写通道保持当拍发给 BRAM，不要被读响应 pipeline 影响。
- `req_ready` 当前恒为 1；如果未来改成可反压 DRAM，就必须重新审查 DCache miss/fill 状态机。

如果 Vivado Tcl 中 `DRAM_0` 的输出寄存器参数改变，按下面规则调整：

| `Register_PortA_Output_of_Memory_Primitives` | `Register_PortA_Output_of_Memory_Core` | 预期读返回 | Adapter 响应 |
| --- | --- | --- | --- |
| `false` | `false` | 1 拍 | `resp_valid <= read_req_d1` |
| `true` | `false` | 2 拍 | `resp_valid <= read_req_d2` |
| `true` | `true` | 通常 3 拍 | `resp_valid <= read_req_d3`，并实测确认 |

## 修改 Checklist

修改任意 IP 参数或 `rtl/ip` 行为模型前，按顺序检查：

1. 查 `fpga/create_vivado_project.tcl` 中对应 IP 的 latency、输出寄存器、读写模式和握手配置。
2. 查 `rtl/ip/<IP>.sv` 是否与 Tcl 生成 IP 的端口和时序一致。
3. 查消费方 RTL：`DramBramAdapter.sv`、取指路径、`MulDivUnit.sv` 或 reset/clock 逻辑。
4. 查 Verilator filelist：仿真只应使用 `scripts/filelists/ip_verilator.f` 中的行为模型。
5. 查 Vivado filelist/Tcl：FPGA sources 不应包含 `rtl/ip/*` 行为模型。
6. 跑 SoC 级仿真时，必要时让行为模型模拟真实 Vivado IP 的拍数，而不是为了测试方便缩短 latency。
7. 重新生成 Vivado project 或至少 regenerate affected IP；旧 `fpga/build/...` 不会自动继承 Tcl 参数变化。
8. 上板前看 timing report，并确认 bitstream 来自最新 RTL/Tcl/IP 配置。

## 常见症状

| 症状 | 优先怀疑 |
| --- | --- |
| Verilator pass，但上板 LED/SEG 全 0 | IROM/DRAM 实际读 latency 与行为模型不一致，程序早期读错后跑飞；也检查 reset/PLL locked。 |
| src 程序能启动但结果随机 | DRAM read offset、byte write enable 或 READ_FIRST/WRITE_FIRST 模式与 adapter 不一致。 |
| M 扩展仿真过但 FPGA 错 | `MUL_0`/`DIV_0` latency、signedness、输出位宽或 AXI-stream valid 时序不一致。 |
| 改 CPU 频率后 UART/计时异常 | `CLK_FREQ`、counter cycles-per-ms、PLL Tcl 参数或 timing 约束未同步。 |

## 维护要求

后续如果调整 IP 打拍数或 Tcl 参数，必须在同一次修改中更新本文档的“当前 IP 时序表”。若发现新的板级时序差异，应把根因写入 `docs/archive/YYYY-MM-DD/`，但当前事实应优先维护在本文档。
