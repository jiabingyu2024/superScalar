# 200 MHz 时序违例分析

## 结论

Kintex-7 `xc7k325tffg900-2`、`clk_out2_pll=200 MHz`（5.000 ns）当前没有通过 routed timing。最近一次完整 routed 报告位于 `fpga/build/digital_twin_srcWithMext_200.000MHz/reports/timing_summary_200.000MHz.rpt`，其结果为：

| 项目 | 结果 |
|---|---:|
| CPU 时钟 | 200.000 MHz / 5.000 ns |
| WNS（综合 max delay 汇总） | -1.708 ns |
| TNS | -3516.455 ns |
| setup 失败端点 | 7888 / 20611 |
| WHS | +0.106 ns |
| hold 失败端点 | 0 |
| `async_default` 路径组 WNS | -1.405 ns |
| `async_default` TNS / 失败端点 | -936.530 ns / 884 |

这里的 WNS 由数据 setup 和异步 reset recovery 两类路径共同影响。hold 已通过，问题集中在 CPU 数据路径和 reset release 约束。

## 主要 setup 路径

### C1 反馈到 C0 AGU

最差数据路径：

```text
u_reg_id_c1/o_rs2_addr_reg[4]/C
  -> stage_ex forwarding/ALU
  -> agu
  -> u_reg_id_c1/o_mem_addr_reg[29]/D
```

- slack: `-1.708 ns`
- data delay: `6.655 ns`
- logic: `2.166 ns`
- route: `4.489 ns`
- logic levels: `23`（11 个 CARRY4、8 个 LUT6）

这是同一个 C1 寄存器组的 Q 到 D 反馈。C1 结果旁路到 C0 AGU 能提高相关 load/store 的 IPC，但会把 EX/ALU、AGU 加法器和 C1 地址寄存器串成一个 5 ns 内路径。由于布线占 67.5%，单纯减少 LUT 很难补足 1.7 ns。

同类路径还包括：

- `o_reg_c1/o_rd_addr_reg[1]/C -> o_mem_addr_reg[*]/D`，约 `-1.61 ns`；
- 其他 `rs2_addr` 位到 `mem_addr` 位，约 `-1.60 ... -1.35 ns`。

### 早期 C2 load 数据到 AGU

在保留 C1 bypass、但启用“DCache 内部 load 格式化”的实验版本中，最差路径转为：

```text
u_dcache/resp_rdata_q_reg[*]/C
  -> stage_wb / C2 forwarding
  -> C0 AGU
  -> u_reg_id_c1/o_mem_addr_reg[*]/D
```

该版本 routed WNS 为 `-1.708 ns`，说明把 formatter 前移并没有解决 AGU 反馈的结构性问题，且由于综合布局变化结果变差。该实验版本已回退，不作为当前功能基线。

### 分支重定向路径

在加入预测方向 bit 之前，最差路径曾是：

```text
C2 load mask / stage_m2 / WB bypass
  -> branch comparator
  -> right_pc mux
  -> 32-bit predicted-PC compare
  -> IF/ID flush CE
```

该路径约 18 个逻辑级、路由占比约 72%，WNS 约 `-2.064 ns`。当前 `branch_cmp` 已将方向比较和目标比较并行化，并随流水传递 `predict_taken`；这项修改有效缩短了分支路径，后续报告的主要瓶颈已转移到 AGU 反馈。

## Reset recovery 路径

`async_default` 组的最差路径来自：

```text
student_top_inst/cpu_rst_sync_reg/C
  -> Core_cpu/u_core/u_stage_id/u_regfile/rf_mem_reg[*][*]/CLR
```

- recovery slack 约 `-1.405 ns ... -1.350 ns`
- 典型 reset net fanout: 约 `2788`
- logic delay 很小，route delay 约 `3.1 ns`，本质是高扇出 reset 网络

这不是正常数据 setup 路径，但会使 Vivado 的整体 timing status 失败。当前 reset 在 50 MHz 域生成后作为 CPU 异步复位使用，释放时需要跨到 200 MHz 域，约束和实现方式都不理想。

## 其他路径

- `clk_out1_pll` 50 MHz 域 setup/hold 充裕，没有主导问题。
- hold：`WHS=+0.106 ns`，`0` 个失败端点；不需要用 hold fix 换 setup。
- unconstrained path 表为空；跨 `clk_out1_pll`/`clk_out2_pll` 的异步分组约束已生效。
- MMCM feedback 和 UART/LED 外部路径不是 CPU 200 MHz 主瓶颈。

## 当前工作区状态说明

当前 RTL 已恢复为功能基线：C1-AGU bypass 开启、DCache 仍由 C2 `stage_m2` 做 load 格式化。最近已验证的性能基线是 `srcWithMext` 5M 周期 IPC `0.826767`，`rv32i_pass=37`、`rv32i_fail=0`，`srcSmoke` PASS，RV32 全量 PASS。

最近一次关闭 C1-AGU bypass 的实验功能正确，但 IPC 降至 `0.789894`，低于目标，因此不作为基线。当前工作区的最新 RTL 改动尚未重新 routed，不能把第三次 Vivado 报告直接称为当前 RTL 的签核报告。
