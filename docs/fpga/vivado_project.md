# Vivado GUI 工程操作手册

本文只描述 Windows Vivado GUI 中的 Tcl Console 流程。工程结构、IP latency 和 RTL/行为模型对齐规则见 [IP 时序与接口契约](ip_timing_alignment.md)。

## 1. 基本原则

1. 在 Vivado GUI 的 `Window -> Tcl Console` 中执行命令。
2. Tcl Console 使用正斜杠 Windows 路径，例如 `E:/Resources/.../superScalar`。
3. `source` 命令后不能附加 `-tclargs`；profile、频率和 build tag 通过 `::env(...)` 传入。
4. 修改 RTL、XDC 或 IP 参数后生成新的 build 目录，不复用旧 DCP/run 状态。
5. 综合和实现由用户在 GUI Tcl Console 中逐阶段启动，本仓库不额外提供启动脚本。

## 2. 生成独立工程

打开 Vivado GUI 和 Tcl Console，进入仓库根目录：

```tcl
cd E:/Resources/03_competitions/26_03_jcs/2607round/superScalar
```

为本轮修复生成独立工程：

```tcl
set ::env(FPGA_MEM_PROFILE) srcWithMext
set ::env(FPGA_BUILD_TAG) implfix_p0
set ::env(FPGA_ENABLE_POWER_OPT) false
source fpga/create_vivado_project.tcl
```

生成目录：

```text
fpga/build/digital_twin_srcWithMext_implfix_p0/
```

脚本执行后工程已经是 current project，通常不需要再次 `open_project`。重新打开 GUI 时使用：

```tcl
open_project fpga/build/digital_twin_srcWithMext_implfix_p0/digital_twin.xpr
```

完成生成后可清理环境变量，避免下一次 source 误继承：

```tcl
unset ::env(FPGA_MEM_PROFILE)
unset ::env(FPGA_BUILD_TAG)
unset ::env(FPGA_ENABLE_POWER_OPT)
```

## 3. 生成后先检查配置

不要立即启动综合。先在 Tcl Console 执行：

```tcl
get_property PART [current_project]
get_property TOP [get_filesets sources_1]
get_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY [get_runs synth_1]
get_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS [get_runs synth_1]
get_property STEPS.POWER_OPT_DESIGN.IS_ENABLED [get_runs impl_1]
get_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED [get_runs impl_1]
```

本轮基线期望：

```text
PART                                      xc7k325tffg900-2
TOP                                       top
FLATTEN_HIERARCHY                         none
KEEP_EQUIVALENT_REGISTERS                 true
POWER_OPT_DESIGN.IS_ENABLED               false
POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED    false
```

检查 CDC 文件属性：

```tcl
set cdc_file [get_files -quiet *digital_twin_cdc.xdc]
puts "cdc_file=$cdc_file"
puts "used_in_synthesis=[get_property USED_IN_SYNTHESIS $cdc_file]"
puts "used_in_implementation=[get_property USED_IN_IMPLEMENTATION $cdc_file]"
puts "processing_order=[get_property PROCESSING_ORDER $cdc_file]"
```

期望值：

```text
used_in_synthesis=0
used_in_implementation=1
processing_order=LATE
```

检查源文件边界：

```tcl
report_compile_order -used_in synthesis
get_files -quiet */rtl/ip/*.sv
get_ips
```

FPGA sources 应包含 `rtl/core/**/*.sv`、`rtl/soc/**/*.sv` 和 Vivado IP；`rtl/ip/*.sv` 是 Verilator 行为模型，不应进入 FPGA sources。

## 4. 分阶段综合与实现

### 4.1 综合

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
get_property STATUS [get_runs synth_1]
open_run synth_1
```

综合完成后先检查：

```tcl
report_blackbox
report_utilization -hierarchical -hierarchical_depth 12
report_control_sets -verbose
get_cells -hier -quiet *student_top_inst*
get_cells -hier -quiet *Core_cpu*
```

本轮 DCache RAM 模板还必须确认：

1. utilization summary 中 `LUT as Memory` 非零，旧基线为 0。
2. hierarchical utilization 中 `CoreDCache` FF 相比旧基线 71,570 大幅下降。
3. `CoreDCache` LUT 相比旧基线 49,520 明显下降。
4. synthesis log 不包含 `ram_style` 被忽略或 RAM inference 失败信息。

如果以上条件不满足，先停止 implementation 并检查 `data_way0_q/data_way1_q/tag_way0_q/tag_way1_q` 的推断结果。

日志必须重点搜索：

```text
Synth 8-5413
Constraints 18-1055
Constraints 18-1056
Vivado 12-4739
```

本轮期望以上四类消息均为 0。综合不满足时不要继续 implementation。

### 4.2 运行到 opt_design

```tcl
launch_runs impl_1 -to_step opt_design -jobs 4
wait_on_run impl_1
get_property STATUS [get_runs impl_1]
open_run impl_1
```

检查 PLL 输出时钟和 clock group：

```tcl
get_clocks -quiet clk_out1_pll
get_clocks -quiet clk_out2_pll
report_clocks
report_clock_interaction -delay_type min_max
report_cdc -details
```

`clk_out1_pll` 和 `clk_out2_pll` 都必须返回非空对象。若为空，不得用 false path 临时掩盖，应先检查 PLL XDC 和 CDC 文件加载阶段。

### 4.3 运行到 place_design

```tcl
launch_runs impl_1 -to_step place_design -jobs 4
wait_on_run impl_1
get_property STATUS [get_runs impl_1]
open_run impl_1
report_utilization -hierarchical -hierarchical_depth 12
report_timing_summary -delay_type min_max -report_unconstrained
report_high_fanout_nets -timing -max_nets 100
```

### 4.4 运行到 route_design

```tcl
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
get_property STATUS [get_runs impl_1]
open_run impl_1
```

route 后生成最终检查报告：

```tcl
file mkdir fpga/build/digital_twin_srcWithMext_implfix_p0/reports/manual
set rpt_dir fpga/build/digital_twin_srcWithMext_implfix_p0/reports/manual

report_clocks -file $rpt_dir/clocks.rpt
report_clock_interaction -delay_type min_max -file $rpt_dir/clock_interaction.rpt
report_cdc -details -file $rpt_dir/cdc.rpt
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file $rpt_dir/timing_summary.rpt
report_utilization -hierarchical -hierarchical_depth 12 -file $rpt_dir/utilization_hier.rpt
report_methodology -file $rpt_dir/methodology.rpt
report_drc -file $rpt_dir/drc.rpt
report_high_fanout_nets -timing -max_nets 100 -file $rpt_dir/high_fanout_nets.rpt
report_control_sets -verbose -file $rpt_dir/control_sets.rpt
report_power -file $rpt_dir/power.rpt
check_timing -verbose -file $rpt_dir/check_timing.rpt
```

### 4.5 生成 bitstream

只有 timing、DRC、methodology 和 CDC 均无 blocker 时再执行：

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
get_property STATUS [get_runs impl_1]
```

## 5. Profile 与频率

当前 profile 来自：

```text
fpga/coe/<profile>/irom.coe
fpga/coe/<profile>/dram.coe
```

若不存在，则回退到：

```text
data/<profile>/irom.coe
data/<profile>/dram.coe
```

Tcl Console 中选择 profile：

```tcl
set ::env(FPGA_MEM_PROFILE) srcSmoke
```

默认时钟：

| 时钟 | 默认频率 | 用途 |
| --- | ---: | --- |
| 输入差分时钟 | 200 MHz | 板载输入 |
| `clk_out1` | 50 MHz | UART、counter、twin/controller |
| `clk_out2` | 50 MHz | CPU、IROM、DRAM CPU 侧 |

只调整 CPU 时钟的示例：

```tcl
set ::env(FPGA_INPUT_CLK_MHZ) 200.000
set ::env(FPGA_SYS_CLK_MHZ) 50.000
set ::env(FPGA_CPU_CLK_MHZ) 100.000
```

修改频率后必须生成新的 build tag 并重新综合、实现。不要修改 50 MHz SoC 时钟，除非同步审查 UART 和 counter 参数。

## 6. 当前 IP 与源码边界

| IP | Vivado core | 关键用途 |
| --- | --- | --- |
| `pll` | Clocking Wizard | 200 MHz 输入，生成 SoC/CPU 时钟 |
| `IROM_0` | Block Memory Generator | 16 KiB 双口 ROM |
| `DRAM_0` | Block Memory Generator | 256 KiB byte-write RAM |
| `MUL_0` | Multiplier Generator | 单实例 33x33 signed multiplier |
| `DIV_0` | Divider Generator | 单实例 unsigned 32/32 divider |

以下三层必须保持一致：

```text
fpga/create_vivado_project.tcl  -> 真实 FPGA IP 参数
rtl/ip/*.sv                     -> Verilator 行为模型
rtl/core/*                      -> IP 消费者的 latency/valid/packing
```

具体 latency、端口和 packing 规则统一维护在 [ip_timing_alignment.md](ip_timing_alignment.md)。

## 7. 常见问题

| 现象 | 优先检查 |
| --- | --- |
| `Synth 8-5413` | 异步 reset 的首层条件是否混入同步 clear/recover |
| `Constraints 18-1055/1056` | 顶层 XDC 是否重复覆盖 PLL 输入 clock |
| 综合阶段 `Vivado 12-4739` | CDC XDC 是否错误启用于 synthesis |
| `clk_out1_pll/clk_out2_pll` 为空 | PLL DCP/XDC 是否已在 implementation link 后加载 |
| implementation 在 power opt 崩溃 | 确认两个 power-opt step 都为 false，并使用新 build tag |
| LUT/FF 异常偏低 | 检查 compile order、blackbox、top 和 `Core_cpu` 是否存在 |
| LUT/FF 异常偏高 | 检查宽数组复位、多组合读端口、全表压缩和 RAM inference |
| route 后存在跨时钟负 slack | 先验证 CDC 结构和 clock group 是否正确，不直接添加 false path |

## 8. 本轮报告回传

完成用户侧 Vivado 运行后，优先保留下列文件供继续分析：

```text
digital_twin.runs/synth_1/runme.log
digital_twin.runs/impl_1/runme.log
reports/manual/timing_summary.rpt
reports/manual/utilization_hier.rpt
reports/manual/cdc.rpt
reports/manual/clock_interaction.rpt
reports/manual/methodology.rpt
reports/manual/drc.rpt
reports/manual/high_fanout_nets.rpt
reports/manual/control_sets.rpt
reports/manual/check_timing.rpt
```
