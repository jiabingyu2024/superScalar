# Vivado implementation 修复 Phase 1-4 执行记录

日期：2026-07-10  
对应计划：`docs/archive/2026-07-10/053_vivado_implementation_and_fpga_optimization_plan.md`

## 1. 本轮范围

本轮执行计划 Phase 1-4 中不需要启动 Vivado 长任务的部分：

1. 修复有效 RTL 中异步 reset 与同步 clear/recover 混写。
2. 删除顶层用户 XDC 中重复的输入 `create_clock`。
3. 将 PLL 输出域 CDC 约束改为 implementation-only。
4. 增加独立 build tag 和 power-opt 属性回显，整理 Windows Vivado GUI Tcl Console 分阶段命令。
5. 在 WSL 下完成 RV32、`srcSmoke` 和小窗口 `srcWithMext` difftest 验证。

未启动 Vivado 综合、布局布线或 bitstream；相关结论必须等待用户运行后确认。

## 2. RTL 修改

以下有效源码中的：

```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst || clear_i || recover_i) begin
```

已统一拆成：

```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        // asynchronous reset
    end else if (clear_i || recover_i) begin
        // synchronous pipeline clear/recovery
```

涉及文件：

- `rtl/core/backend/CoreBackend.sv`
- `rtl/core/rename/Rat.sv`
- `rtl/core/rename/FreeList.sv`
- `rtl/core/rename/BusyTable.sv`
- `rtl/core/dispatch/ROB.sv`
- `rtl/core/issue/CompressedQueue.sv`
- `rtl/core/common/CounterFreeList.sv`
- `rtl/core/common/PipeReg.sv`
- `rtl/core/common/MultiPushFifo.sv`
- `rtl/core/common/SkidBuffer.sv`
- `rtl/core/common/SyncFifo.sv`
- `rtl/core/common/ResettableValid.sv`
- `rtl/core/frontend/ReturnStack.sv`

本轮保留原有 reset/clear 赋值内容和优先级，没有删除 payload reset，也没有进行 RAM 化或队列结构优化。对 `rtl/` 排除 backup 后重新扫描，未发现残留的同类首层 `rst || clear` 写法。

## 3. 时钟与 CDC 约束修改

### 3.1 输入主时钟唯一所有权

从 `fpga/digital_twin.xdc` 删除：

```tcl
create_clock -name sys_clk_p -period 5.000 [get_ports { i_sys_clk_p }]
```

输入 200 MHz 时钟由 Clocking Wizard 生成的 `pll.xdc` 唯一定义。板级 XDC 继续负责 package pin 和 I/O standard。

### 3.2 CDC 只在 implementation 加载

`fpga/create_vivado_project.tcl` 对生成的 `digital_twin_cdc.xdc` 设置：

```tcl
set_property USED_IN_SYNTHESIS false [get_files $cdc_xdc_file]
set_property USED_IN_IMPLEMENTATION true [get_files $cdc_xdc_file]
set_property PROCESSING_ORDER LATE [get_files $cdc_xdc_file]
```

这样综合阶段不会在 PLL OOC black box 尚未链接时查询 `clk_out1_pll/clk_out2_pll`，实现 link 后才应用异步 clock group。

## 4. Vivado 工程入口修改

### 4.1 独立 build tag

新增环境变量：

```text
FPGA_BUILD_TAG=implfix_p0
```

`srcWithMext` 对应新目录为：

```text
fpga/build/digital_twin_srcWithMext_implfix_p0/
```

避免旧 XPR、DCP、IP 和 run 属性污染本轮结论。

### 4.2 Power optimization

`FPGA_ENABLE_POWER_OPT` 继续默认 `false`，并在工程生成结束时打印实际的：

- `STEPS.POWER_OPT_DESIGN.IS_ENABLED`
- `STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED`
- CDC `USED_IN_SYNTHESIS/USED_IN_IMPLEMENTATION`
- CDC `PROCESSING_ORDER`

### 4.3 分阶段运行

不新增额外 Vivado 启动 Tcl。用户直接在 Windows Vivado GUI Tcl Console 中用 `launch_runs ... -to_step ...` 逐阶段运行，并在每阶段后检查 `STATUS` 和报告。完整命令统一维护在 `docs/fpga/vivado_project.md`。

## 5. WSL 验证结果

### 5.1 RV32 测试集

重建 `myCPU` Verilator 模型后运行：

```bash
python3 scripts/run_verilator.py rv32 --suite rv32ui --no-build
python3 scripts/run_verilator.py rv32 --suite rv32um --no-build
python3 scripts/run_verilator.py rv32 --suite rv32mi --no-build
```

结果：

| Suite | 结果 |
| --- | ---: |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |

### 5.2 `srcSmoke`

```bash
python3 scripts/run_verilator.py src --test srcSmoke --no-build --max-cycles 50000000
```

结果：PASS，完成于 33,798,107 cycles；LED pass signature 命中，SEG 为 `0x37000675`。

### 5.3 小窗口 `srcWithMext` difftest

```bash
python3 scripts/run_difftest.py src --test srcWithMext --no-build --max-cycles 200000
```

结果按窗口上限为 TIMEOUT，这是预期结果，不代表功能失败。窗口内：

- difftest commit：130,739
- MMIO skip：4
- last PC：`0x80000e14`
- RV32I count：37
- M extension count：8
- RV32I fail count：0
- 未观察到提前 crash、fail marker 或 commit self-check 异常

未运行全量 `srcWithMext`。

## 6. 用户侧 Vivado 执行顺序

Windows Vivado GUI Tcl Console：

```tcl
cd E:/Resources/03_competitions/26_03_jcs/2607round/superScalar
set ::env(FPGA_MEM_PROFILE) srcWithMext
set ::env(FPGA_BUILD_TAG) implfix_p0
set ::env(FPGA_ENABLE_POWER_OPT) false
source fpga/create_vivado_project.tcl

launch_runs synth_1 -jobs 4
wait_on_run synth_1
get_property STATUS [get_runs synth_1]
```

后续 `opt/place/route/bitstream` 和报告命令见 `docs/fpga/vivado_project.md`。用户可以在任一阶段停止；前一阶段失败时不要继续下一阶段。

## 7. Vivado 验收重点

新日志必须确认：

1. `Synth 8-5413` 为 0。
2. `Constraints 18-1055/1056` 为 0。
3. 综合阶段 `Vivado 12-4739` 为 0。
4. implementation 中 `clk_out1_pll`、`clk_out2_pll` 均存在，CDC clock group 非空。
5. `power_opt_design` 和 post-place power opt 实际 disabled。
6. `check_timing` 无未解释的 no_clock/multiple_clock/unconstrained endpoints。
7. route 后 setup/hold、DRC、methodology 和 CDC 无 blocker。

在收到新 Vivado 报告前，本轮状态为：RTL/仿真/约束源码修改完成，等待用户运行 Vivado 确认综合与实现。
