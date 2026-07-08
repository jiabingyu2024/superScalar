# Vivado 工程与 IP 生成约定

本文记录当前 `fpga/create_vivado_project.tcl` 的设计事实。Tcl 应适配仓库结构，不反向要求移动 `rtl/`、`data/` 或 `fpga/` 文件。

## 工程入口

推荐入口：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs src0
```

默认生成目录：

```text
fpga/build/digital_twin_<profile>/digital_twin.xpr
```

`fpga/build/` 属于生成物，应被 git ignore。

### 在 Vivado GUI 中使用 Tcl

推荐流程是“先用 Tcl 生成工程，再用 GUI 打开 `.xpr` 做综合、实现、看时序”。不要在 GUI 里手工逐个添加 RTL/IP，否则后续路径和 IP 参数容易和仓库 Tcl 脱节。

#### 方法 A：Vivado Tcl Console 运行

1. 打开 Vivado GUI。
2. 菜单选择 `Window -> Tcl Console`。
3. 在 Tcl Console 中进入仓库根目录：

```tcl
cd E:/Resources/03_competitions/26_03_jcs/2607round/superScalar
```

Windows Vivado 中使用 Windows 路径，例如：

```tcl
cd D:/your/path/to/superScalar
```

4. 设置测试 profile 名并运行工程生成脚本：

```tcl
set ::env(FPGA_MEM_PROFILE) srcSmoke
source fpga/create_vivado_project.tcl
```

注意：`-tclargs` 只能用于外部命令行启动 Vivado 时的 `vivado -source ... -tclargs ...`，不能写在 Vivado Tcl Console 的 `source` 命令后面。若在 Tcl Console 里执行 `source fpga/create_vivado_project.tcl -tclargs srcSmoke`，Vivado 会报 `Unknown option '-tclargs'`。

5. 脚本完成后打开生成的工程：

```tcl
open_project fpga/build/digital_twin_srcSmoke/digital_twin.xpr
```

也可以从 GUI 菜单 `File -> Project -> Open` 打开同一个 `.xpr`。

#### 方法 B：命令行生成后再打开 GUI

Linux/WSL 环境：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
vivado fpga/build/digital_twin_srcSmoke/digital_twin.xpr
```

Windows PowerShell 示例：

```powershell
cd D:\your\path\to\superScalar
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
vivado fpga/build/digital_twin_srcSmoke/digital_twin.xpr
```

如果 `vivado` 不在 PATH 中，使用 Vivado 安装目录下的 `vivado.bat`。

#### 方法 C：GUI 启动时执行 Tcl

```sh
vivado -mode gui -source fpga/create_vivado_project.tcl -tclargs srcSmoke
```

这种方式会启动 GUI 并执行 Tcl。脚本完成后通常已经创建好工程；如果当前界面没有自动打开工程，在 Tcl Console 中执行：

```tcl
open_project fpga/build/digital_twin_srcSmoke/digital_twin.xpr
```

## 选择 COE/Profile

命令行启动 Vivado 时，`-tclargs` 后面的第一个参数就是 profile 名。Tcl 会查找该 profile 下的 `irom.coe` 和 `dram.coe`。

示例：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs src0
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

在 Vivado Tcl Console 里已经进入 GUI 后，不使用 `-tclargs`，改用环境变量：

```tcl
set ::env(FPGA_MEM_PROFILE) srcWithMext
source fpga/create_vivado_project.tcl
```

脚本读取 profile 的优先级为：

```text
命令行 -tclargs/argv > FPGA_MEM_PROFILE 环境变量 > 默认 src0
```

查找顺序：

```text
fpga/coe/<profile>/irom.coe
fpga/coe/<profile>/dram.coe
```

如果上述目录不存在，则使用：

```text
data/<profile>/irom.coe
data/<profile>/dram.coe
```

因此当前仓库可以直接使用 `data/srcSmoke/irom.coe` 和 `data/srcSmoke/dram.coe`。如果后续需要上板专用 COE，不建议改 Tcl 中的固定路径；更好的方式是在 `fpga/coe/` 下放置同名 profile：

```text
fpga/coe/srcSmoke/irom.coe
fpga/coe/srcSmoke/dram.coe
```

这样 Tcl 会优先使用 `fpga/coe/srcSmoke/`，不会影响 `data/` 中的仿真输入。

## 修改频率

当前 `top.sv` 里有两个时钟：

| 时钟 | 来源 | 用途 |
| --- | --- | --- |
| `w_clk_50Mhz` | `pll.clk_out1` | SoC 外设、UART、twin_controller、counter/display。 |
| `cpu_clk` | `pll.clk_out2` | CPU core、IROM、DRAM/perip_bridge CPU 侧。 |

Tcl 默认：

```tcl
set input_clk_mhz 200.000
set sys_clk_mhz   50.000
set cpu_clk_mhz   50.000
```

不建议修改 `sys_clk_mhz`，因为 `rtl/soc/counter.sv` 和 UART 参数按 50MHz SoC 时钟工作。CPU 默认按 50MHz，对齐官方模板和 Verilator 默认频率；若要进一步提高 CPU 频率，只改 `FPGA_CPU_CLK_MHZ`，并必须重新确认 Vivado timing 和上板行为。

### 命令行临时修改频率

Linux/WSL shell：

```sh
FPGA_CPU_CLK_MHZ=150.000 vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
```

同时显式保持 SoC 50MHz：

```sh
FPGA_SYS_CLK_MHZ=50.000 FPGA_CPU_CLK_MHZ=150.000 \
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
```

Windows PowerShell：

```powershell
$env:FPGA_CPU_CLK_MHZ = "150.000"
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
Remove-Item Env:FPGA_CPU_CLK_MHZ
```

Windows CMD：

```bat
set FPGA_CPU_CLK_MHZ=150.000
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
set FPGA_CPU_CLK_MHZ=
```

### Vivado GUI Tcl Console 修改频率

在 `source` 前设置环境变量：

```tcl
set ::env(FPGA_MEM_PROFILE) srcSmoke
set ::env(FPGA_CPU_CLK_MHZ) 150.000
source fpga/create_vivado_project.tcl
```

如果也要显式设置输入差分时钟和 SoC 时钟：

```tcl
set ::env(FPGA_MEM_PROFILE) srcSmoke
set ::env(FPGA_INPUT_CLK_MHZ) 200.000
set ::env(FPGA_SYS_CLK_MHZ) 50.000
set ::env(FPGA_CPU_CLK_MHZ) 150.000
source fpga/create_vivado_project.tcl
```

### 直接修改 Tcl 默认值

如果希望长期默认使用某个 CPU 频率，可以改 `fpga/create_vivado_project.tcl`：

```tcl
set cpu_clk_mhz   150.000
```

不建议把 `sys_clk_mhz` 从 50MHz 改掉，除非同步审查并修改 UART、counter 和相关文档。

## 资源异常偏低排查

如果 implementation 后资源只剩很少 LUT/FF，优先不要直接相信 utilization。先区分三类问题：

| 现象 | 判断 | 处理 |
| --- | --- | --- |
| `report_compile_order` 中缺 RTL/IP，或 `report_blackbox` 非空 | Tcl/IP 加入问题 | 先修 Tcl/IP 生成。 |
| `student_top_inst/Core_cpu` 不存在 | 顶层选择、实例连接或综合裁剪问题 | 检查 top、reset/clock、输出可观测路径。 |
| `Core_cpu` 存在但内部模块名查不到 | 常见于层级拍平 | 用 hierarchical utilization 或关闭 flatten 后重跑。 |

当前 Tcl 默认设置：

```tcl
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]
```

同时 RTL 在两级关键实例上加了保留属性：

```text
top.student_top_inst
student_top.Core_cpu
```

目的不是长期追求最好频率，而是避免 Vivado 在 bring-up 阶段跨层级把 CPU 逻辑裁掉，导致资源报告只剩外设/常量逻辑。后续确认资源与功能稳定后，可以再评估是否把 `dont_touch` 放宽，仅保留 `keep_hierarchy` 或恢复 `rebuilt` 层级以改善 QoR。

### 自动 sanity 报告

脚本会为 synth 和 implementation opt 阶段挂 post Tcl，报告输出到：

```text
fpga/build/digital_twin_<profile>/reports/
```

关键文件：

| 文件 | 用途 |
| --- | --- |
| `synth_sanity.txt` | 记录 `Core_cpu`、`IssueQueue`、`ROB`、`ExecuteMulStage` 是否还能按层级名找到，以及 LUT/FF cell 粗略数量。 |
| `synth_util_hier.rpt` | 综合后层级资源报告。 |
| `synth_blackbox.rpt` | 综合后黑盒报告。 |
| `impl_sanity.txt` | implementation `opt_design` 后同类检查。 |
| `impl_util_hier.rpt` | implementation 早期层级资源报告。 |
| `impl_blackbox.rpt` | implementation 早期黑盒报告。 |

如果 Tcl Console 出现：

```text
CRITICAL WARNING: FPGA sanity check sees very low resource count
```

说明当前实现结果仍然不可信，应先打开上述报告确认 `Core_cpu` 是否被保留、IP 是否黑盒、LUT/FF 数是否符合预期。

### 手工检查命令

打开综合结果后：

```tcl
open_run synth_1
get_property top [current_fileset]
report_blackbox
report_utilization -hierarchical -hierarchical_depth 12
get_cells -hier *student_top_inst*
get_cells -hier *Core_cpu*
get_cells -hier *IssueQueue*
get_cells -hier *ROB*
get_cells -hier *ExecuteMulStage*
```

注意：若 `FLATTEN_HIERARCHY` 不是 `none`，内部模块名查不到不一定代表 RTL 没加入；可能只是被 Vivado 拍平或重建层级。当前默认关闭 flatten，是为了让资源异常更容易定位。

### 重新生成并重跑

修改 Tcl/RTL 后建议重新生成工程，不要在旧工程上增量猜测：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
vivado fpga/build/digital_twin_srcWithMext/digital_twin.xpr
```

在 GUI 中打开后重新运行 synthesis/implementation。若想临时恢复 Vivado 默认层级策略，可在 source 前设置：

```tcl
set ::env(FPGA_FLATTEN_HIERARCHY) rebuilt
source fpga/create_vivado_project.tcl
```

## RTL 源文件边界

Tcl 只收集：

1. `rtl/core/**/*.sv`
2. `rtl/soc/**/*.sv`
3. `fpga/constraints/digital_twin.xdc` 或当前仓库已有的 `fpga/digital_twin.xdc`

`rtl/ip/*.sv` 是 Verilator 行为模型，不加入 FPGA sources。FPGA 使用 Tcl 创建同名 Vivado IP。

## 输入文件查找

当前 Tcl 会按顺序查找：

| 输入 | 优先路径 | 兼容路径 |
| --- | --- | --- |
| COE profile | `fpga/coe/<profile>/` | `data/<profile>/` |
| XDC | `fpga/constraints/digital_twin.xdc` | `fpga/digital_twin.xdc` |

这允许后续把上板专用 COE 移到 `fpga/coe/`，同时不破坏当前 `data/srcSmoke/irom.coe`、`data/srcSmoke/dram.coe` 的仓库布局。

## 当前生成的 IP

| IP module | Vivado IP | 作用 | 关键参数 |
| --- | --- | --- | --- |
| `pll` | `clk_wiz` | 生成系统时钟和 CPU 时钟 | 默认输入 200 MHz，输出 `FPGA_SYS_CLK_MHZ/FPGA_CPU_CLK_MHZ`，可由环境变量覆盖。 |
| `IROM_0` | `blk_mem_gen` | 16 KiB 双口 ROM | 32 bit 宽，4096 深度，加载当前 profile 的 `irom.coe`，查找路径见上节。 |
| `DRAM_0` | `blk_mem_gen` | 256 KiB 单口 RAM | 32 bit 宽，65536 深度，byte write enable，加载当前 profile 的 `dram.coe`，查找路径见上节。 |
| `MUL_0` | `mult_gen` | core 内唯一硬件乘法器 | signed 33x33，parallel multiplier，speed 优先，3 级 pipeline，66 bit 输出。 |
| `DIV_0` | `div_gen` | core 内唯一硬件除法器 | unsigned 32/32，Radix-2，remainder 输出，1 clock/division，34 级 pipeline。 |

## MUL_0 约定

`MUL_0` 的端口必须和 `rtl/ip/MUL_0.sv` 行为模型一致：

```systemverilog
module MUL_0 (
    input  logic               CLK,
    input  logic signed [32:0] A,
    input  logic signed [32:0] B,
    output logic signed [65:0] P
);
```

当前 core 只例化一颗 `MUL_0`。`IssueQueue` 只允许 issue slot 0 发射 `TUBE_TYPE_MUL`，`ExecuteMulStage` 负责记录该 uop 来自哪个 lane，并在 3 拍后把结果送回对应写回 lane。

Vivado `mult_gen` 属性名可能随版本有轻微差异。Tcl 对端口宽度、符号、输出宽度、pipeline 等契约属性做严格检查；对 speed 优化目标只做可选设置。若运行 Tcl 时在 `MUL_0` 的 `CONFIG.*` 属性处报错，应优先用当前 Vivado 版本的 IP customization GUI/`report_property [get_ips MUL_0]` 对齐属性名，而不是修改 RTL 端口。

## DIV_0 约定

`DIV_0` 的端口必须和 `rtl/ip/DIV_0.sv` 行为模型一致：

```systemverilog
module DIV_0 (
    input  logic        aclk,
    input  logic        s_axis_dividend_tvalid,
    output logic        s_axis_dividend_tready,
    input  logic [31:0] s_axis_dividend_tdata,
    input  logic        s_axis_divisor_tvalid,
    output logic        s_axis_divisor_tready,
    input  logic [31:0] s_axis_divisor_tdata,
    output logic        m_axis_dout_tvalid,
    output logic [63:0] m_axis_dout_tdata
);
```

当前 core 只例化一颗 `DIV_0`，并只允许 issue slot 0 发射 `TUBE_TYPE_MUL`。`DIV_0` 只做 unsigned 32/32，RISC-V 的 signed 语义、除零、`0x80000000 / -1` 溢出都在 `ExecuteMulStage` 外围处理。

`DIV_0` 在 Tcl 中按 `FlowControl=Blocking` 配置。该配置下 Vivado 生成的输出通道只有 `m_axis_dout_tvalid/tdata`，没有 `m_axis_dout_tready`。core 现有 M 扩展写回路径也没有对除法输出做反压，因此 RTL 和 `rtl/ip/DIV_0.sv` 行为模型都采用“输出 valid 后立即消费”的边界。

32 bit quotient/remainder 的输出打包约定：

```text
m_axis_dout_tdata[31:0]  = quotient
m_axis_dout_tdata[63:32] = remainder
```

Vivado `div_gen` 属性名同样可能随版本变化。若 Tcl 在 `DIV_0` 的 `CONFIG.*` 属性处报错，优先用当前 Vivado 版本的 `report_property [get_ips DIV_0]` 对齐属性名，保持 RTL 端口和行为模型不变。
