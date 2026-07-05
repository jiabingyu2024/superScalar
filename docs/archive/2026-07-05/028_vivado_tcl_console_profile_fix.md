# Vivado Tcl Console profile 参数修正记录

## 背景

在 Vivado GUI 的 Tcl Console 中执行：

```tcl
source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

会报错：

```text
ERROR: [Common 17-170] Unknown option '-tclargs'
```

原因是 `-tclargs` 是 `vivado -source ...` 命令行入口的参数，不是 Tcl `source` 命令的参数。进入 Vivado GUI 之后，`source` 只接受脚本文件和 Tcl `source` 自身支持的选项。

## 修改内容

1. `fpga/create_vivado_project.tcl` 新增 `FPGA_MEM_PROFILE` 环境变量入口。
2. 保留命令行 `-tclargs` 入口，并让 `argv/-tclargs` 优先于环境变量。
3. 更新 `docs/fpga/vivado_project.md`，明确区分两种用法：
   - 外部命令行启动 Vivado：使用 `vivado -mode batch/gui -source ... -tclargs <profile>`。
   - Vivado GUI Tcl Console：使用 `set ::env(FPGA_MEM_PROFILE) <profile>` 后再 `source ...`。

## 当前推荐命令

Vivado Tcl Console：

```tcl
cd E:/Resources/03_competitions/26_03_jcs/2607round/superScalar
set ::env(FPGA_MEM_PROFILE) srcWithMext
source fpga/create_vivado_project.tcl
open_project fpga/build/digital_twin_srcWithMext/digital_twin.xpr
```

外部命令行：

```sh
vivado -mode gui -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

## 设计约束

本次修改只改变 Tcl 参数入口，不改变：

1. `rtl/` 源文件组织。
2. `fpga/coe/<profile>` 和 `data/<profile>` 的 COE 查找顺序。
3. `IROM_0`、`DRAM_0`、`MUL_0`、`DIV_0` 的 IP 参数。
4. SoC 50MHz 固定时钟约定。
