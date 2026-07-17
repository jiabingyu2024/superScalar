# PYNQ-Z2 开发板验证

本目录包含一个独立的 PYNQ-Z2 构建工程。该工程只引用本目录之外的
CPU/SoC RTL 和测试镜像；Vivado 生成的所有文件均保存在
`fpga/test_prj/build/` 目录下。

## 硬件连接

1. 将 EES_363DP 数字逻辑子板安装到 PYNQ-Z2 的 Arduino 排针上。
2. 将子板电源开关 `SW7` 拨至 `ON`。
3. 给 PYNQ-Z2 上电，并连接其用于下载的 USB/JTAG 接口。
4. 保持以太网 PHY 正常工作，因为 PHY 输出的 125 MHz 时钟连接到 PL
   引脚 `H16`。测试过程中可随时按下 `BTN0`，复位处理器并重新运行测试。

PYNQ-Z2 和 EES_363DP 数字 I/O 的电平标准均为 3.3 V。请勿向 Arduino
信号引脚施加 5 V 电压。

## 构建与下载

### Windows 下的 Vivado GUI Tcl Console

正常启动 Vivado，然后在 GUI 的 **Tcl Console** 中输入以下命令。
Windows 路径应使用正斜杠：

```tcl
cd {E:/Resources/03_competitions/26_03_jcs/2607round/superScalar}
set ::env(FPGA_MEM_PROFILE) srcWithMext
set ::env(FPGA_CPU_CLK_MHZ) 50.000
source fpga/test_prj/create_project.tcl
```

工程将创建并打开在：
`fpga/test_prj/build/srcWithMext/pynq_superscalar.xpr`。如需在同一个 GUI
Tcl Console 中生成比特流，请执行：

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

生成的比特流文件为：

```text
fpga/test_prj/build/srcWithMext/pynq_superscalar.runs/impl_1/pynq_top.bit
```

如需使用运行时间更短且已经验证的冒烟测试镜像，请将
`FPGA_MEM_PROFILE` 改为 `srcSmoke`。PYNQ 封装层的 PLL 固定输出 50 MHz，
因此应将 `FPGA_CPU_CLK_MHZ` 保持为 `50.000`。

### Windows PowerShell 批处理模式

在仓库根目录下执行：

```powershell
vivado -mode batch -source fpga/test_prj/build_bitstream.tcl -tclargs srcSmoke 4
vivado -mode batch -source fpga/test_prj/program_board.tcl -tclargs srcSmoke
```

这里默认使用 `srcSmoke` 镜像，因为仓库中的仿真已经观察到该测试的
PASS 标志和运行时间显示。如需选择其他测试数据目录，该目录必须同时包含
`irom.coe` 和 `dram.coe`，并将上述两条命令中的 `srcSmoke` 替换为对应的
目录名称。

如只需创建工程而不运行综合和实现，请执行：

```powershell
vivado -mode batch -source fpga/test_prj/create_project.tcl -tclargs srcSmoke
```

需要进行交互式运行时，请打开
`fpga/test_prj/build/srcSmoke/pynq_superscalar.xpr`。

## 上板现象

| 输出 | 含义 |
|---|---|
| `LED0` 闪烁 | CPU 测试仍在运行 |
| `LED1` 常亮 | 已观察到 PASS 标志 `0x01221c08` |
| `LED2` 常亮 | 已观察到 FAIL 标志 `0x24181824` |
| `LED3` | 当前显示页，其状态与 `SW0` 相同 |
| `SW0 = 0` | 子板显示低四位，通常表示已运行的毫秒数 |
| `SW0 = 1` | 子板显示高四位或测试计数字段 |
| `BTN0` | 复位并重新运行测试 |

对于当前的 `srcSmoke` 参考结果，SoC 最终显示值为 `0x37000797`：当
`SW0=0` 时，子板显示 `0797`，同时 `LED1` 常亮。实际 FPGA 运行时间可能
略有差异，但 `LED1` 常亮且数值时间显示稳定，即为预期的测试成功现象。

子板上的 LED1..LED8 信号与八根七段数码管段选信号共用相同的物理引脚。
因此，数码管工作时这些 LED 的亮灭不能作为独立的状态指示；请以 PYNQ-Z2
开发板上的四个 LED 为准。

## 引脚资料说明

- PYNQ-Z2 用户手册：PL 时钟引脚 `H16`、开发板按键/开关/LED，以及
  Arduino 排针的 FPGA 引脚映射。
- EES_363DP 数字逻辑子板手册：共阳极数码管、通过 2N5401 器件实现的
  低有效位选，以及段选和位选引脚映射。
- PYNQ-Z2 原理图：用于交叉核对 `SYSCLK` 和 Arduino 网络名称。
