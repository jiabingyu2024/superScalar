# 050 FPGA 上板 SEG/LED 全 0 问题审查与修复

日期：2026-07-08

## 1. 问题现象

用户现象：

```text
Verilator 仿真通过；
使用 Tcl 建立 Vivado 工程并上板后，SEG 全是 0，LED 全灭，没有反应。
```

用户给出的 Vivado 工程路径：

```text
E:\Resources\03_competitions\26_03_jcs\2607round\superScalar\fpga\build\digital_twin_srcWithMext
```

WSL 下对应路径：

```text
/mnt/e/Resources/03_competitions/26_03_jcs/2607round/superScalar/fpga/build/digital_twin_srcWithMext
```

参考官方模板：

```text
E:\Resources\03_competitions\26_03_jcs\2026年资料\JYD2025_Contest-rv32i
```

## 2. 审查结论

这次不把“IP 类型不一致”作为最终原因。当前设计可以适配自己的 IP 封装。

本轮定位到两个更实际的 FPGA-only 风险：

1. **Tcl 递归收集 RTL，把旧桥接路径和当前主路径同时加入工程。**
   - Verilator 用 `scripts/filelists/soc.f`，只编译当前主路径。
   - 旧 Tcl 递归加入整个 `rtl/soc`，会把 `perip_bridge.sv/dram_driver.sv` 这类旧路径一起带进 Vivado。
   - 已有 Vivado log 里出现额外 `DRAM/IROM` blackbox 名称，说明工程边界不干净。

2. **FPGA 顶层 reset 释放和 Verilator reset 释放不同。**
   - Verilator TB 直接把 `student_top.w_clk_rst` 从 1 拉到 0，释放干净。
   - FPGA 顶层原来直接用 `pll.locked` / `~pll.locked` 作为各时钟域 reset。
   - `pll.locked` 相对 `w_clk_50Mhz/cpu_clk` 不是同步释放信号，可能导致 CPU/SoC 状态机从不同周期释放。
   - 上板表现可能是 CPU 没有进入预期执行流，SEG/LED 保持 reset 后 0。

已排除或降级的方向：

1. **器件型号/XDC 引脚错误不是主因。**
   - 官方模板 part 是 `xc7k325tffg900-2`，当前 Tcl 默认一致。
   - 官方 XDC 和当前 `fpga/digital_twin.xdc` 的顶层端口/引脚基本一致。

2. **CPU 被综合优化掉不是主因。**
   - 现有 Vivado `synth_sanity.txt`：

```text
student_top_cells=2
core_cpu_cells=1
lut_cells=10495
ff_cells=22294
```

   - `impl_sanity.txt`：

```text
student_top_cells=2
core_cpu_cells=1
lut_cells=13564
ff_cells=26403
```

   - 说明主 CPU 子树确实进入了实现结果。

3. **IROM/DRAM 完全没进 bitstream 不是主因。**
   - impl 层级资源显示 `student_top_inst` 下有 `RAMB36=68`。

4. **时序问题本轮先不作为根因。**
   - 虽然现有 report 里有 timing failed 记录，但按用户要求，本轮先假设时序已闭合，继续审查非 timing 问题。

## 3. 官方模板对比

### 3.1 顶层外壳

官方 `top.sv` 与当前工程顶层结构基本一致：

```text
top
  -> pll
  -> uart
  -> twin_controller
  -> student_top
```

顶层端口也一致：

```text
i_sys_clk_p/n
i_uart_rx
o_uart_tx
virtual_led[31:0]
virtual_seg[39:0]
```

### 3.2 器件和约束

官方 `digital_twin.xpr`：

```text
Part = xc7k325tffg900-2
```

官方 XDC 与当前 XDC 的 pin/IOSTANDARD 对应关系一致。器件型号和引脚不是当前优先怀疑点。

### 3.3 PLL 频率

官方实际工程引用的是：

```text
digital_twin.srcs/sources_1/ip/pll_1/pll.xci
```

该 XCI 中：

```text
PRIM_IN_FREQ = 200.000
CLKOUT1_REQUESTED_OUT_FREQ = 50.000
CLKOUT2_REQUESTED_OUT_FREQ = 50
```

当前 Tcl 原默认 CPU 输出是 100 MHz。虽然本轮按用户要求不把时序作为根因，但默认频率已经改为 50 MHz，以对齐官方模板和 Verilator 默认频率。后续若要提频，仍可显式设置：

```sh
FPGA_CPU_CLK_MHZ=100.000 vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

## 4. 已实施修复

### 4.1 Tcl 改为显式 filelist

原 Tcl：

```tcl
set core_files [collect_sv_files [file join $repo_dir rtl core]]
set soc_files  [collect_sv_files [file join $repo_dir rtl soc]]
set rtl_files  [lsort [concat $core_files $soc_files]]
```

问题：递归扫目录会把旧模块也加入 Vivado sources。

现改为读取：

```text
scripts/filelists/core.f
scripts/filelists/soc.f
```

并显式禁止 FPGA source filelist 混入 `rtl/ip/*` Verilator 行为模型。

效果：

```text
FPGA 主路径只包含当前 RTL：
CoreTypes / DCache / MulDivUnit / riscv_cpu / myCPU
SocMemBridge / DramBramAdapter / uart / twin_controller / student_top / top

不再把旧 perip_bridge/dram_driver 加入 Tcl 工程。
```

### 4.2 顶层 50 MHz 域 reset 同步

原先 `uart/twin_controller` 直接使用 `pll.locked` 作为 `rst_n`：

```systemverilog
.rst_n(w_clk_rst)
```

现增加 50 MHz 域同步释放：

```systemverilog
always_ff @(posedge w_clk_50Mhz or negedge w_clk_rst) begin
    if (!w_clk_rst) begin
        rst_50m_meta <= 1'b1;
        rst_50m_sync <= 1'b1;
    end else begin
        rst_50m_meta <= 1'b0;
        rst_50m_sync <= rst_50m_meta;
    end
end

assign rst_50m_n = ~rst_50m_sync;
```

`uart/twin_controller` 改为接 `rst_50m_n`。

### 4.3 `student_top` 内部同步 CPU/counter 域 reset

`student_top` 输入 `w_clk_rst` 仍保持兼容，不改顶层端口。但内部增加：

```text
cpu_rst_sync：同步释放到 w_cpu_clk
cnt_rst_sync：同步释放到 w_clk_50Mhz
```

CPU、SW/KEY 同步寄存器、SoC CPU 域逻辑使用 `cpu_rst_sync`。

由于用户明确要求 **不允许修改 `counter.sv`**，本轮没有改 counter 文件。`counter` 仍保持单一 `rst` 端口，由外层传入 `cnt_rst_sync`。

## 5. 验证结果

恢复 counter 接口后，Verilator 构建通过：

```text
OBJCACHE= make verilator-build-src BUILD_JOBS=1
PASS
```

快速功能回归：

```text
python3 scripts/run_verilator.py src --test srcSmoke --no-build
srcSmoke: PASS
```

这说明：

1. reset 同步改动没有破坏 `student_top` 仿真。
2. `counter.sv` 未修改。
3. Tcl source 边界修复不影响 Verilator 路径。

## 6. 当前仍需上板验证的点

请重新生成 Vivado 工程，不要复用旧 build：

```sh
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

然后重新综合、实现、生成 bitstream。

上板后观察：

1. 上电后是否不再保持全 0。
2. `srcWithMext` 初始阶段是否出现右侧 lamp 逐步点亮。
3. SEG 高位是否从 `0x37800000` 附近开始变化。
4. 最终是否能到：

```text
对号
右侧 8 灯全亮
SEG 高位 0x378xxxxx
```

## 7. 如果仍然全 0，下一步定位

若重建工程后仍然全 0，下一步不要先改 CPU，应插入最小硬件可见性检查：

1. 在 `top` 临时把 `virtual_led[0]` 接到 `pll.locked`，确认板上/数字孪生能看到 PLL lock。
2. 再把 `virtual_led[1]` 接到 CPU reset released，确认 reset 释放。
3. 再把 `virtual_led[2]` 接到 `irom_ena` 或 `dmem_req_valid`，确认 CPU 是否开始取指/访存。
4. 如果 `irom_ena` 不动，看 reset/clock。
5. 如果 `irom_ena` 动但没有 MMIO 写，看 IROM 初始化/取指时序。
6. 如果 MMIO 写动但 LED/SEG 不动，看 `SocMemBridge` 地址译码和输出连线。

这些 debug 只应作为临时 bring-up，不应进入最终提交版本。

## 8. 本轮改动文件

```text
fpga/create_vivado_project.tcl
rtl/soc/top.sv
rtl/soc/student_top.sv
rtl/soc/SocMemBridge.sv
```

未修改：

```text
rtl/soc/counter.sv
```

## 9. 当前判断

在先假设时序闭合、IP 类型差异不是根因的前提下，最合理的解释是：

```text
Verilator 的 DUT 是 student_top，reset 释放理想；
上板 DUT 是 top，reset 来自 pll.locked，并穿过两个时钟域；
旧 Tcl 又把非主路径 legacy RTL 混入工程。

因此上板全 0 更像 FPGA 顶层集成和初始化边界问题，而不是 CPU 指令功能问题。
```

本轮修复集中在这两个边界：Tcl source 收敛到当前主路径，reset 释放按时钟域同步。
