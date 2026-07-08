# 当前设计文件级可综合性审查

## 1. 审查范围和结论边界

本审查只基于文件读取和静态检查，没有调用 Vivado，也没有跑 `synth_1`。

结论：

```text
主路径 RTL 从文件结构和 SystemVerilog 写法看具备综合条件；
当前 Tcl 能创建包含真实 Vivado IP 的 FPGA 工程；
但最终“已综合通过”必须以后续 Vivado synth_1 日志为准。
```

不能把本文件级审查等同于：

1. Vivado IP property 已全部被实际接受。
2. 时序已收敛。
3. 约束已完整。
4. 没有 Vivado 前端兼容性 warning。

## 2. 已确认的可综合条件

### 2.1 主路径没有明显仿真专用语句

对 `rtl/core` 和 `rtl/soc` 搜索以下不可综合或仿真专用模式：

```text
initial
#delay
force/release
wait/fork/join
$display/$finish
```

当前未在主 RTL 中发现这些模式。

### 2.2 Verilator 调试口已隔离

`myCPU.sv` 和 `student_top.sv` 中的调试端口均包在：

```systemverilog
`ifdef VERILATOR_TB
...
`endif
```

FPGA Tcl 默认不会定义 `VERILATOR_TB`，因此这些端口不会进入 FPGA 顶层接口，也不会影响综合端口匹配。

如果调试端口不加条件编译，Vivado 顶层可能出现未约束端口，或者 `top -> student_top` 实例端口不匹配。

### 2.3 FPGA IP 与 RTL 实例名一致

| RTL 实例 | 依赖模块名 | Tcl 来源 |
|---|---|---|
| `top.pll_inst` | `pll` | `create_ip clk_wiz -module_name pll` |
| `student_top.Mem_IROM` | `IROM_0` | `create_ip blk_mem_gen -module_name IROM_0` |
| `DramBramAdapter.dram` | `DRAM_0` | `create_ip blk_mem_gen -module_name DRAM_0` |
| `MulDivUnit.mul_ip` | `MUL_0` | `create_ip mult_gen -module_name MUL_0` |
| `MulDivUnit.div_ip` | `DIV_0` | `create_ip div_gen -module_name DIV_0` |

FPGA Tcl 不加入 `rtl/ip`，因此不会和 Vivado 生成的 IP wrapper 重名。

Vivado 生成的 `DRAM_0` wrapper 不带 `ADDR_WIDTH/DATA_WIDTH` 参数，当前 `DramBramAdapter.sv` 已改为无参数实例化 `DRAM_0 dram (...)`。如果重新加上 named parameter override，Vivado 会报 `[Synth 8-7136] parameter 'ADDR_WIDTH' ... does not exist`。

### 2.4 顶层端口约束基本覆盖

`top.sv` 顶层端口：

```text
i_sys_clk_p
i_sys_clk_n
i_uart_rx
o_uart_tx
virtual_led[31:0]
virtual_seg[39:0]
```

`fpga/digital_twin.xdc` 对这些端口都给了 PACKAGE_PIN 和 IOSTANDARD。未发现顶层端口完全缺 pin 的情况。

### 2.5 主数据通路是同步 RTL

主路径使用 `always_ff @(posedge clk)` 和 `always_comb`，没有门控时钟写法。CPU、DCache、MulDiv、SoC bridge、counter 都是单时钟或明确双时钟输入的同步结构。

需要注意：`counter.sv` 同时使用 `cpu_clk` 和 `cnt_clk`，内部做了跨时钟同步；这属于 CDC 设计点，文件级可综合不代表 CDC 已形式验证。

## 3. 需要 Vivado 实际确认的点

### 3.1 IP CONFIG property

Tcl 通过 `set_ip_config_required/optional` 适配大小写不同的 CONFIG property。静态看写法稳健，但具体 Vivado 2023.2 IP 是否暴露所有 required property，必须实际运行 Tcl 才能确认。

重点关注：

```text
mult_gen: PipeStages, OutputWidthHigh/Low, signed 33-bit
div_gen: FlowControl, Latency_Configuration, Latency, AXI stream port shape
```

### 3.2 Vivado SystemVerilog 前端兼容

当前 RTL 使用了一些 Vivado 通常支持但仍建议由 synth 验证的 SV 写法：

1. block-scope declaration，例如 `logic [INDEX_W-1:0] fill_index;`
2. unpacked array memory，例如 `logic [31:0] data_q [0:LINE_COUNT-1][0:WORDS_PER_LINE-1];`
3. function/task 内部组合逻辑和 `unique case`
4. 参数类型 `int unsigned`、`logic [31:0]`

这些不是不可综合写法，但不同工具前端报错/警告风格不同。

### 3.3 XDC 缺少时钟约束

没有 `create_clock` 不阻止综合，但会影响 timing analysis。若后续直接跑 implementation，可能出现 unconstrained clock 或 generated clock 推导不完整。

建议补：

```tcl
create_clock -name sys_clk_p -period 5.000 [get_ports i_sys_clk_p]
```

### 3.4 递归收集 legacy RTL

Vivado Tcl 当前递归加入：

```text
rtl/soc/dram_driver.sv
rtl/soc/perip_bridge.sv
```

这两个文件当前不是主路径，但会被 Vivado 解析。它们目前看起来是普通可综合 RTL，并依赖 `DRAM_0`、`display_seg`、`counter`。如果后续删除或改动 `DRAM_0` 端口，旧文件可能先于主路径暴露错误。

长期更稳做法：Tcl 使用显式 filelist，只加入 `scripts/filelists/core.f` 和 `scripts/filelists/soc.f`。

## 4. 当前主路径 blackbox 风险

若 Tcl 成功生成所有 IP，主路径不应有 blackbox：

```text
pll      由 clk_wiz 生成
IROM_0   由 blk_mem_gen 生成
DRAM_0   由 blk_mem_gen 生成
MUL_0    由 mult_gen 生成
DIV_0    由 div_gen 生成
```

若 Vivado blackbox report 中仍出现以上模块，优先检查：

1. IP 是否创建失败。
2. IP generate_target 是否失败。
3. RTL 是否在 IP 生成前后 compile order 异常。
4. 是否误加入/误排除了 `sources_1`。

## 5. 当前综合资源/时序预期

文件级预期：

1. `student_top_inst` 和 `Core_cpu` 应存在。
2. LUT/FF 不应异常低；若低到接近空设计，说明 CPU 或输出链路可能被优化。
3. BRAM 应主要来自 `IROM_0/DRAM_0`。
4. DSP 或 LUT multiplier 资源取决于 `MUL_0` IP 配置。
5. Divider IP 可能占用较多 LUT/FF，且是 CPU 频率关键路径附近的风险模块之一。

当前 Tcl 的 sanity script 中还检查 `IssueQueue/ROB/ExecuteMulStage` 名称。由于当前主路径不是乱序/超标量实现，这些名称为 0 不是当前版本 blocker。

## 6. 可综合性结论

按文件审查，当前版本可以进入综合：

```text
结论等级：文件级可综合，待 Vivado synth_1 实证
主路径：top -> student_top -> myCPU -> riscv_cpu
IP 依赖：由 Tcl 生成，不使用 rtl/ip 仿真模型
约束状态：pin 完整，clock 约束缺失
最大风险：Tcl 未自动综合、XDC 缺 create_clock、递归收集 legacy RTL、Vivado IP property 需实测
```

## 7. 正式冻结前自检清单

1. `vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke` 能创建工程。
2. `open_project ...; launch_runs synth_1; wait_on_run synth_1` 成功。
3. `report_blackbox` 没有 `pll/IROM_0/DRAM_0/MUL_0/DIV_0/myCPU/riscv_cpu/SocMemBridge`。
4. `report_utilization -hierarchical` 中 `student_top_inst/Core_cpu` 非空。
5. XDC 已补 `create_clock`，并确认无 unconstrained primary clock。
6. `srcSmoke` Verilator 结果仍是 `SEG=0x37xxxxxx`，RV32I count 37。
7. `srcWithMext` Verilator 结果仍是 `SEG=0x378xxxxx`，右侧 8 灯全亮。
8. 若修改 Tcl source 收集方式，确认 FPGA 工程不加入 `rtl/ip/*.sv`。
9. 若修改 IP 参数，确认 `MulDivUnit` 端口宽度和 latency 计数同步更新。
10. 若上板频率改动，`FPGA_CPU_CLK_MHZ`、仿真 `CPU_FREQ_MHZ` 和文档中的性能解释要分开记录，不能混为一谈。
