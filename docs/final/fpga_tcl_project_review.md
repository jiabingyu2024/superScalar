# Vivado Tcl 工程当前审查说明

## 1. Tcl 职责

`fpga/create_vivado_project.tcl` 当前职责是“重建 Vivado 工程”，不是自动综合脚本。

它完成：

1. 解析 memory profile、part、时钟频率、综合策略环境变量。
2. 查找 `irom.coe`、`dram.coe`、XDC。
3. 创建 Vivado project。
4. 添加 RTL sources 和 constraints。
5. 创建 `pll/IROM_0/DRAM_0/MUL_0/DIV_0` 五个 Vivado IP。
6. 生成 IP target，更新 compile order。
7. 给 synth/impl run 挂 post sanity report Tcl。
8. 打印工程路径，提示用户打开 GUI 后运行 synthesis/implementation。

最后一行提示是当前行为边界：

```tcl
puts "Open the .xpr in Vivado, then run synthesis and implementation from the GUI."
```

如果用户期望 batch 一键综合，当前 Tcl 还需要增加 `launch_runs synth_1; wait_on_run synth_1` 之类逻辑。

## 2. 参数和环境变量

| 环境变量 | 默认值 | 作用 |
|---|---:|---|
| `FPGA_MEM_PROFILE` | `src0` | 选择 COE profile。命令行 `-tclargs` 第一个参数优先级更高。 |
| `FPGA_INPUT_CLK_MHZ` | `200.000` | 输入差分时钟频率，传给 clk_wiz。 |
| `FPGA_PART` | `xc7k325tffg900-2` | Vivado part。 |
| `FPGA_SYS_CLK_MHZ` | `50.000` | PLL 输出 1，SoC/UART/counter 时钟。 |
| `FPGA_CPU_CLK_MHZ` | `50.000` | PLL 输出 2，CPU 时钟。默认对齐官方模板；提频需显式覆盖并确认时序。 |
| `FPGA_FLATTEN_HIERARCHY` | `rebuilt` | synth flatten strategy；需要原始层级调试时可临时设为 `none`。 |
| `FPGA_KEEP_EQUIVALENT_REGISTERS` | `true` | 保留等价寄存器，利于结构观察。 |
| `FPGA_ENABLE_POWER_OPT` | `false` | impl power opt 开关。 |

命令行用法：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
```

Vivado Tcl Console 内不能用 `source ... -tclargs ...`。应使用：

```tcl
set ::env(FPGA_MEM_PROFILE) srcSmoke
source fpga/create_vivado_project.tcl
```

## 3. COE 和 XDC 查找规则

COE profile 查找顺序：

```text
fpga/coe/<profile>/
data/<profile>/
```

必需文件：

```text
irom.coe
dram.coe
```

XDC 查找顺序：

```text
fpga/constraints/digital_twin.xdc
fpga/digital_twin.xdc
```

当前仓库有 `fpga/digital_twin.xdc`，因此 Tcl 可找到约束文件。

## 4. RTL source 收集规则

Tcl 使用递归收集：

```tcl
set core_files [collect_sv_files [file join $repo_dir rtl core]]
set soc_files  [collect_sv_files [file join $repo_dir rtl soc]]
set rtl_files  [lsort [concat $core_files $soc_files]]
add_files -norecurse -fileset sources_1 $ordered_rtl
```

它不会加入 `rtl/ip/*.sv`。这是正确的，因为 FPGA 工程使用 Vivado IP 生成同名模块。

与仿真 filelist 的差异：

| 构建 | IP 来源 | SoC 文件来源 |
|---|---|---|
| Verilator | `rtl/ip/*.sv` 行为模型 | `scripts/filelists/soc.f` 显式列出主路径 SoC 文件 |
| Vivado Tcl | `create_ip` 生成真实 IP | 递归加入 `rtl/soc/*.sv` |

递归加入的风险：`rtl/soc/dram_driver.sv` 和 `rtl/soc/perip_bridge.sv` 是旧桥接路径，主路径不实例化，但 Vivado 仍要解析它们。如果以后 IP 端口或语法变化，这些未使用文件也可能造成工程失败。更稳的长期做法是 Tcl 改为使用 `scripts/filelists/core.f` 和 `scripts/filelists/soc.f`。

## 5. IP 生成审查

### 5.1 `pll`

Tcl 创建 `clk_wiz`：

```text
module_name: pll
input: differential clock capable pin
input freq: FPGA_INPUT_CLK_MHZ
output1: clk_out1 = FPGA_SYS_CLK_MHZ
output2: clk_out2 = FPGA_CPU_CLK_MHZ
locked: enabled
reset: disabled
```

与 `top.sv` 端口匹配：

```systemverilog
.clk_in1_p(i_sys_clk_p)
.clk_in1_n(i_sys_clk_n)
.clk_out1(w_clk_50Mhz)
.clk_out2(cpu_clk)
.locked(w_clk_rst)
```

### 5.2 `IROM_0`

Tcl 配置：

```text
blk_mem_gen
Single_Port_ROM
width 32
depth 4096
ena pin enabled
output register disabled
COE = irom.coe
```

与 `student_top.sv` 匹配：

```systemverilog
.addra(irom_word_addr)
.clka(w_cpu_clk)
.ena(irom_ena)
.douta(instruction)
```

### 5.3 `DRAM_0`

Tcl 配置：

```text
blk_mem_gen
Single_Port_RAM
width 32
depth 65536
byte write enable
read_first
memory primitive output register enabled
core output register disabled
COE = dram.coe
```

与 `DramBramAdapter.sv` 匹配：

```systemverilog
DRAM_0 dram (
.addra(dram_addr)
.clka(clk)
.dina(dram_wdata)
.ena(req_valid)
.wea(dram_we)
.douta(dram_rdata_raw)
);
```

注意：Vivado 生成的 `DRAM_0_stub.v` 不暴露 `ADDR_WIDTH/DATA_WIDTH` parameter。因此 `DramBramAdapter` 不能写成 `DRAM_0 #(.ADDR_WIDTH(...), .DATA_WIDTH(...))`。地址宽度只能在 adapter 内部用于 `dram_addr` 切片，IP 本身的深度/宽度由 Tcl 中的 blk_mem_gen 配置决定。

### 5.4 `MUL_0`

Tcl 配置：

```text
mult_gen
33 x 33 signed
parallel multiplier
pipeline stages = 3
custom output width 66 bit
```

与 `MulDivUnit.sv` 匹配：

```systemverilog
.CLK(clk)
.A(mul_a_c)
.B(mul_b_c)
.P(mul_product)
```

### 5.5 `DIV_0`

Tcl 配置：

```text
div_gen
Radix2
32-bit dividend/quotient
32-bit divisor
unsigned operand
manual latency 34
blocking flow control
```

与 `MulDivUnit.sv` 匹配：

```systemverilog
.aclk(clk)
.s_axis_dividend_tvalid(div_start_c)
.s_axis_dividend_tdata(div_lhs_abs_c)
.s_axis_divisor_tvalid(div_start_c)
.s_axis_divisor_tdata(div_rhs_abs_c)
.m_axis_dout_tvalid(div_valid)
.m_axis_dout_tdata(div_data)
```

注意：`s_axis_*_tready` 当前悬空未使用。Tcl 设置 blocking flow control 后，通常应检查 IP 是否总能在 `div_start_c` 那拍接受输入。实际是否完全匹配仍需 Vivado IP 生成后检查端口和行为。

## 6. XDC 审查

`fpga/digital_twin.xdc` 当前 153 行，覆盖：

| 端口 | 覆盖情况 |
|---|---|
| `i_uart_rx` | PACKAGE_PIN + LVCMOS33 |
| `o_uart_tx` | PACKAGE_PIN + LVCMOS33 |
| `i_sys_clk_p/n` | PACKAGE_PIN + DIFF_HSTL_II_18 |
| `virtual_led[31:0]` | 每 bit PACKAGE_PIN + LVCMOS18 |
| `virtual_seg[39:0]` | 每 bit PACKAGE_PIN + LVCMOS18 |

缺口：没有 `create_clock`。当前 `rg` 未找到：

```text
create_clock
set_clock
false_path
input_delay
output_delay
```

这不阻止 RTL 综合，但会让时序分析缺少输入基准时钟。建议后续补：

```tcl
create_clock -name sys_clk_p -period 5.000 [get_ports i_sys_clk_p]
```

具体周期应与板卡差分输入时钟一致；当前 Tcl 默认 `FPGA_INPUT_CLK_MHZ=200.000`，对应 5.000 ns。

## 7. post sanity report

Tcl 写入两个 post hook：

```text
post_synth_sanity.tcl
post_impl_sanity.tcl
```

报告内容：

1. hierarchical utilization
2. blackbox report
3. `student_top_inst` cell 数
4. `Core_cpu` cell 数
5. IssueQueue/ROB/ExecuteMulStage 名称 cell 数
6. LUT/FF cell 数

当前主 RTL 没有真正 IssueQueue/ROB/ExecuteMulStage，因此这些名称计数为 0 不应自动判为失败。真正需要关注的是：

```text
student_top_cells > 0
core_cpu_cells > 0
lut_cells/ff_cells 不应异常过低
blackbox report 不应有未解析主路径模块
```

## 8. Tcl 审查结论

当前 Tcl 作为“可重复生成工程”的脚本是基本成立的：

1. 仓库路径通过 `script_dir/repo_dir` 派生，不依赖固定工作目录。
2. COE/XDC 有 fallback 查找规则。
3. FPGA IP 与 RTL 实例名一致。
4. 不混入 `rtl/ip` 仿真模型，避免 FPGA IP 重名冲突。
5. 设置了 keep hierarchy、综合策略和 sanity report hook。

需要记录的不足：

1. 不自动运行综合/实现。
2. XDC 缺 `create_clock`。
3. RTL source 递归收集会带入未使用 legacy 文件。
4. `DIV_0/MUL_0` 的具体 CONFIG property 是否完全适配 Vivado 2023.2，只能由实际 Vivado 生成确认。
5. Vivado IP wrapper 通常不带行为模型里的参数；RTL 实例化真实 IP 时不要对 `pll/IROM_0/DRAM_0/MUL_0/DIV_0` 做 named parameter override。

## 9. 建议后续冻结改进

优先级从高到低：

1. 给 XDC 补 `create_clock`。
2. 给 Tcl 增加可选环境变量 `FPGA_RUN_SYNTH=true`，在需要时自动跑 `synth_1` 并检查 run status。
3. 将 Tcl source 收集改为读取 `scripts/filelists/core.f` 和 `scripts/filelists/soc.f`，避免 legacy 文件影响工程。
4. 更新 sanity 脚本，把 IssueQueue/ROB 检查改成当前核心适用的名称，或标注为历史字段。
