# Vivado implementation 资源异常偏低修复

## 背景

用户在 Vivado implementation 后观察到 LUT 只用了几个，明显不符合二路乱序 CPU 的资源规模，怀疑内部逻辑被优化裁掉。

用户提供的 Tcl Console 结果显示：

1. `get_property top [current_fileset]` 返回 `top`，顶层未选错。
2. `report_compile_order` 中 `DRAM_0/IROM_0/DIV_0/MUL_0/pll` DCP 和全部 RTL 均在 sources_1 中。
3. `Missing instances` 为空，说明不是明显 blackbox 或文件未加入。
4. `student_top_inst` 和 `student_top_inst/Core_cpu` 能查到，但 `IssueQueue/ROB/ExecuteMulStage` 查不到。

静态判断：Tcl 文件列表和 IP 加入路径基本正确；资源只剩极少 LUT 更像 Vivado 综合/实现阶段跨层级拍平、重建、或将 CPU 内部判为对顶层输出无影响后大规模裁剪。由于用户需要快速修复，采用 Tcl 综合策略和 RTL 关键实例保护的双保险。

## 修改内容

### Tcl

文件：`fpga/create_vivado_project.tcl`

1. 新增 `FPGA_FLATTEN_HIERARCHY` 环境变量，默认值为 `none`。
2. 对 `synth_1` 设置：

```tcl
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $flatten_hierarchy [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]
```

3. 生成 post-synth/post-opt sanity Tcl，自动输出：

```text
reports/synth_sanity.txt
reports/synth_util_hier.rpt
reports/synth_blackbox.rpt
reports/impl_sanity.txt
reports/impl_util_hier.rpt
reports/impl_blackbox.rpt
```

4. 若 `Core_cpu` 查不到，或 LUT/FF 数异常低，会在 Tcl Console 打印 `CRITICAL WARNING`。

### RTL

文件：

1. `rtl/soc/top.sv`
2. `rtl/soc/student_top.sv`

对两级关键实例添加：

```systemverilog
(* keep_hierarchy = "yes", dont_touch = "true" *)
```

保护对象：

```text
top.student_top_inst
student_top.Core_cpu
```

## 工程取舍

`dont_touch` 和 `FLATTEN_HIERARCHY=none` 会降低 Vivado 跨层级优化空间，可能影响最终频率/QoR。但在 bring-up 阶段，首要目标是确认 CPU 没有被裁剪、资源规模可信。等资源和功能确认后，可以逐步放宽：

1. 先去掉 `dont_touch`，保留 `keep_hierarchy`。
2. 再把 `FPGA_FLATTEN_HIERARCHY` 临时设为 `rebuilt` 对比 QoR。
3. 若资源仍正常，再考虑作为性能/频率版本默认策略。

## 文档

更新 `docs/fpga/vivado_project.md`，新增“资源异常偏低排查”章节，记录：

1. 如何区分 Tcl/IP 加入问题、顶层/裁剪问题、层级拍平问题。
2. 自动 sanity 报告路径。
3. Vivado GUI/Tcl Console 中的手工检查命令。
4. 重新生成工程和临时恢复 `rebuilt` 的方法。

## 验证

未运行 Vivado。已做静态检查：

```sh
tclsh info complete fpga/create_vivado_project.tcl
git diff --check
```

结果：

1. Tcl 文本完整。
2. diff 无尾随空白问题。

下一步应重新生成 Vivado 工程并运行 synthesis/implementation，重点查看 `reports/synth_sanity.txt` 和 `reports/impl_sanity.txt`。
