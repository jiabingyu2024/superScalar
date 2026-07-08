# 当前版本总览

## 1. 版本边界

当前版本的目标是让 SRC 类程序在 SoC 顶层环境下稳定运行，并让 Verilator 判定逻辑能够正确识别最终对号/错号、右侧 8 灯和 SEG 计数。

本轮审查只读文件并写文档，没有调用 Vivado。已有仿真结果来自 `build/result/src/*.json`，不是本轮重新跑出的新结果。

## 2. 主设计入口

| 层级 | 文件 | 作用 |
|---|---|---|
| FPGA 顶层 | `rtl/soc/top.sv` | 板级顶层，接差分输入时钟、UART、虚拟 LED/SEG，实例化 PLL、UART、twin controller、student_top。 |
| SRC DUT 顶层 | `rtl/soc/student_top.sv` | SRC 程序运行环境，连接 CPU、IROM、SoC 内存桥、LED/SEG/SW/KEY/CNT。 |
| CPU wrapper | `rtl/core/myCPU.sv` | 对外保持课程/SoC 期望的 CPU 接口，内部实例化 `riscv_cpu`，并在 `VERILATOR_TB` 下导出性能计数。 |
| CPU 实体 | `rtl/core/riscv_cpu.sv` | 当前实际执行核心。单发射、阻塞式状态机，支持 RV32I、CSR 子集、M 扩展乘除。 |
| 数据缓存 | `rtl/core/memory/DCache.sv` | 直接映射 4-word line DCache，写穿/写绕到 SoC memory bridge，miss 时按 4 word 填充。 |
| SoC 内存桥 | `rtl/soc/SocMemBridge.sv` | 地址译码到 DRAM、SW、KEY、SEG、LED、counter。 |

## 3. 当前架构事实

当前仓库名虽然是 `superScalar`，但当前主路径 RTL 不是超标量/乱序实现。实际运行核心是 `riscv_cpu.sv` 中的阻塞式单发射状态机：

```text
ST_FETCH -> ST_EXEC
ST_EXEC  -> ST_WAIT_MEM    load 等待 DCache 响应
ST_EXEC  -> ST_WAIT_MULDIV M 扩展等待 MulDivUnit
ST_EXEC  -> ST_FETCH       分支预测错误或 redirect
ST_EXEC  -> ST_EXEC        普通指令/预测正确路径连续执行
```

这意味着当前 IPC 和性能计数应按单发射阻塞核理解，不能用乱序核的 ROB、IssueQueue、rename 等指标解释最终正确性。`sim_common.h` 里仍保留了一批面向更复杂核心的性能字段，但当前 `riscv_cpu` 不驱动那些乱序专用分桶。

## 4. 已有仿真结果证据

已有 JSON 结果显示：

| 测试 | JSON | 状态 | 关键正确性 |
|---|---|---|---|
| `srcSmoke` | `build/result/src/srcSmoke.json` | `PASS` | `final_symbol_cn=对号`，`rv32i_pass_counter=37`，`rv32i_fail_counter=0`，`SEG=0x37000708`。 |
| `srcWithMext` | `build/result/src/srcWithMext.json` | `PASS` | `final_symbol_cn=对号`，右侧 8 灯全亮 `0x03030303`，`rv32i_count_from_seg=37`，`mext_count_from_seg=8`，`SEG=0x37814682`。 |

`build/result/src/summary.json` 只代表最近一次批量/单测运行摘要，当前文件中只列了 `srcWithMext`，不能当作完整历史汇总。

## 5. 最近关键修复进入当前定型版本

`rtl/core/riscv_cpu.sv` 的 load 扩展逻辑已按地址低两位选择 byte/halfword：

```systemverilog
shifted = rdata >> {addr_offset, 3'b000};
3'b000: load_extend = {{24{shifted[7]}}, shifted[7:0]};
3'b001: load_extend = {{16{shifted[15]}}, shifted[15:0]};
3'b100: load_extend = {24'd0, shifted[7:0]};
3'b101: load_extend = {16'd0, shifted[15:0]};
```

这个修复解释了之前 `srcSmoke/srcWithMext` 的 SEG 高位显示 `33` 而不是 `37` 的根因：`LB/LH/LBU/LHU` 对非 0 byte offset 的读数错误，导致 RV32I 子测试计数少 4 个。

如果删掉这个低位 offset 处理，byte/halfword load 会只看 `rdata[7:0]` 或 `rdata[15:0]`，非对齐到 word 低位的 load 测试会失败，SRC 最终 SEG 计数会回退到错误值。

## 6. 当前文件组织定型

| 类别 | 文件 |
|---|---|
| 核心 filelist | `scripts/filelists/core.f` |
| SoC filelist | `scripts/filelists/soc.f` |
| Verilator IP 模型 | `scripts/filelists/ip_verilator.f` |
| Verilator student_top filelist | `scripts/filelists/verilator_student_top.f` |
| Vivado 工程 Tcl | `fpga/create_vivado_project.tcl` |
| FPGA 约束 | `fpga/digital_twin.xdc` |
| src profile | `tb/verilator/src_profiles.json` |

仿真 filelist 显式加入 `rtl/ip/*.sv` 行为模型。FPGA Tcl 不加入 `rtl/ip/*.sv`，而是创建真实 Vivado IP。这是当前版本必须保持的边界。

## 7. 当前已知缺口

1. `fpga/create_vivado_project.tcl` 当前不自动跑 `synth_1/impl_1`。
2. `fpga/digital_twin.xdc` 当前只有 pin/IOSTANDARD，没有 `create_clock`。
3. Tcl 递归加入 `rtl/core` 和 `rtl/soc` 下所有 `.sv`，因此会把未在仿真 filelist 使用的 `dram_driver.sv/perip_bridge.sv` 也加入工程。它们当前语法上是普通 RTL，但不属于主路径。
4. 若要正式确认可综合，仍需用 Vivado 实际跑 `synth_1` 并检查 blackbox、utilization、timing warning。
