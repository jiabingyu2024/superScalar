# RTL 当前定型说明

## 1. 顶层职责划分

当前 RTL 主路径：

```text
top
  -> pll                 Vivado clk_wiz IP，输入差分 200 MHz，输出 50 MHz SoC clock 和 CPU clock
  -> uart                50 MHz UART
  -> twin_controller     UART 与 virtual_sw/key/seg/led 的数字孪生控制
  -> student_top
       -> myCPU
            -> riscv_cpu
                 -> DCache
                 -> MulDivUnit
       -> IROM_0         指令 ROM IP
       -> SocMemBridge
            -> DramBramAdapter -> DRAM_0
            -> display_seg
            -> counter
```

`top.sv` 中 `student_top_inst` 带：

```systemverilog
(* keep_hierarchy = "yes", dont_touch = "true" *)
student_top student_top_inst(...)
```

设计意图是避免综合/实现把学生 CPU 子树完全拍平或优化到难以定位。Tcl 的 post-synth/post-impl sanity 脚本也会查 `student_top_inst`、`Core_cpu` 相关层级。

如果去掉这些属性，功能不一定错，但综合后层级名可能消失，后续 sanity report 和资源归因会变差，甚至在输出未被充分观察时增加被优化掉的误判风险。

## 2. 时钟与复位

| 信号 | 所属层级 | 语义 |
|---|---|---|
| `i_sys_clk_p/n` | `top` | 板级差分输入时钟，Tcl 默认按 `FPGA_INPUT_CLK_MHZ=200.000` 配置 PLL。 |
| `w_clk_50Mhz` | `top/student_top` | SoC/外设/counter/UART 时钟，默认 50 MHz。 |
| `cpu_clk` | `top/student_top` | CPU 时钟，Tcl 默认 50 MHz；Verilator 默认按 `CPU_FREQ_MHZ=50` 建模。 |
| `pll.locked` | `top` | 命名为 `w_clk_rst`，高表示 PLL locked。 |
| `student_top.w_clk_rst` | `student_top` | `top` 传入 `~pll.locked`，因此在 `student_top` 内是高有效 reset。 |
| `uart/twin_controller.rst_n` | `top` | 直接接 `pll.locked`，是低有效复位释放。 |

关键点：`top.sv` 中同一个 `w_clk_rst` 对不同模块含义不同：

```systemverilog
.rst_n(w_clk_rst)      // UART/twin_controller：locked 后释放复位
.w_clk_rst(~w_clk_rst) // student_top：高有效 reset
```

如果把 `student_top` 也接成 `w_clk_rst`，CPU 会在 PLL locked 后一直处于复位，程序不会执行。如果把 UART/twin 反接，数字孪生控制链路会在正常工作时复位。

## 3. CPU 接口契约

`myCPU.sv` 对外提供两个接口：

| 接口 | 信号 | 时序语义 |
|---|---|---|
| IROM | `irom_addr/irom_ena/irom_data` | CPU 给出取指地址和 enable，`IROM_0` 返回 32-bit instruction。当前核心在 `ST_EXEC/WAIT` 可提前给出预测下一 PC。 |
| DMEM | `dmem_req_* / dmem_resp_*` | valid/ready 请求，resp_valid 返回读数据。写请求在 ready 时被接受，读请求在后续 resp_valid 完成。 |

`student_top.sv` 把 `irom_addr[13:2]` 作为 4096 深度 IROM word 地址：

```systemverilog
assign irom_word_addr = irom_addr[13:2];
```

如果 IROM COE 超过 4096 words，当前顶层会截断高地址；如果程序入口不是 `0x8000_0000` 附近的低 16 KB 区间，也需要同步调整 IROM 深度和地址截取。

## 4. 当前 CPU 微架构

`riscv_cpu.sv` 是阻塞式单发射核心，关键状态如下：

| 状态 | 职责 | 退出条件 |
|---|---|---|
| `ST_FETCH` | 复位或 redirect 后补一个取指周期。 | 下一拍进入 `ST_EXEC`。 |
| `ST_EXEC` | 组合译码并执行普通 ALU/branch/store/CSR，发起 load 和 mul/div。 | 普通指令留在 `ST_EXEC`；load 进入 `ST_WAIT_MEM`；M 扩展进入 `ST_WAIT_MULDIV`；redirect 进入 `ST_FETCH`。 |
| `ST_WAIT_MEM` | 等待 DCache/load 返回。 | `cache_resp_valid` 后写回 rd，PC+4，commit+1。 |
| `ST_WAIT_MULDIV` | 等待 `MulDivUnit.done`。 | done 后写回 rd，PC+4，commit+1。 |

主数据流：

```text
IROM -> exec_inst_c -> decode opcode/funct/rs/rd
     -> regs_q 读 rs1/rs2
     -> ALU/branch/CSR/load-store/MulDiv
     -> write_gpr 或等待子模块响应
     -> pc_q 更新
     -> perf counters 更新
```

控制流优先级：

```text
reset
  > 当前状态机 case
  > load/muldiv 阻塞等待
  > branch/JAL/JALR/ECALL/EBREAK/MRET redirect
  > 普通 commit 后连续执行
```

当前没有真正的 ready/valid 流水线级间 backpressure，也没有乱序恢复。所有恢复都体现在单个 `pc_q` redirect 和 `ST_FETCH` 补拍上。

## 5. 分支预测与 redirect

BTB 结构：

```systemverilog
logic        btb_valid_q [0:63];
logic [23:0] btb_tag_q [0:63];
logic [31:0] btb_target_q [0:63];
assign btb_index_c = pc_q[7:2];
assign btb_tag_c   = pc_q[31:8];
assign pred_next_pc_c = btb_hit_c ? btb_target_q[btb_index_c] : (pc_q + 32'd4);
```

设计意图：让 `ST_EXEC` 期间 IROM 地址可以指向预测下一条，从而在预测正确时连续 `ST_EXEC`，减少显式 fetch 气泡。

如果删掉 BTB 或总是 `pc+4`，功能仍可能正确，但循环和跳转密集程序 IPC 会明显下降。如果 BTB 更新条件写错，例如 not-taken 时不清 valid，旧 target 会导致反复误预测。

## 6. Load/Store 与字节对齐

store 在 CPU 端生成未左移的原始数据和 mask：

```systemverilog
SB: mem_req_wdata_c = {24'd0, rs2[7:0]};  mem_req_wstrb_c = 4'b0001;
SH: mem_req_wdata_c = {16'd0, rs2[15:0]}; mem_req_wstrb_c = 4'b0011;
SW: mem_req_wdata_c = rs2;                mem_req_wstrb_c = 4'b1111;
```

实际 byte lane 对齐在 `DramBramAdapter.sv` 完成：

```systemverilog
assign dram_wdata = req_wdata << {req_addr[1:0], 3'b000};
assign dram_we = (req_valid && req_write) ? ((req_wstrb << req_addr[1:0]) & 4'hf) : 4'h0;
assign resp_rdata = dram_rdata_raw >> {read_offset_q, 3'b000};
```

`DRAM_0` 实例化必须保持无参数形式：

```systemverilog
DRAM_0 dram (...);
```

原因是 FPGA 里的 `DRAM_0` 是 Vivado blk_mem_gen 生成的 IP wrapper，深度和宽度由 Tcl 配置，不暴露 `ADDR_WIDTH/DATA_WIDTH` 参数。Verilator 行为模型里虽然有这些参数，但主 RTL 不能依赖它们，否则综合会在 Vivado stub 上报 parameter override 不存在。

load 的符号/零扩展在 CPU 端按 `load_addr_q[1:0]` 再次选择：

```systemverilog
shifted = rdata >> {addr_offset, 3'b000};
LB/LBU/LH/LHU 从 shifted 取低 8/16 bit
```

如果 CPU 端和 SoC 端同时对 store 数据做左移，会发生双重移位；如果 SoC 端读返回已经右移但 CPU load_extend 不看 offset，byte/half load 会在部分地址上错。当前版本的边界是：SoC 端负责 BRAM lane 对齐，CPU 端负责按原始 load 地址做最终扩展。

## 7. DCache 行为

`DCache.sv` 是 128 line、每行 4 word 的直接映射缓存：

```text
cacheable: 0x8010_0000 <= addr < 0x8014_0000
read hit:  当前周期 ready，下一状态直接给 cpu_resp_valid
read miss: 从 line base 开始连续读 4 word 填充
write:     直接写下游 memory；若 cacheable，则 invalidate 对应 line
uncached:  单 word 访问下游 memory，不填充 cache
```

设计取舍：

1. 写请求不做 write-allocate，只 invalidate，避免 store 后 cache line 与 BRAM 不一致。
2. miss 填充固定从 word0 到 word3，逻辑简单，但对只读单 word 的 miss 有额外读放大。
3. `cpu_req_ready` 在 `DC_IDLE` 且下游 ready 时拉高，CPU load/store 不会在 cache busy 时继续推进。

如果写命中不 invalidate，后续 load 可能读到旧 cache data。如果 miss 填充没有保存 `miss_target_word_q`，返回给 CPU 的 word 可能不是原请求地址对应 word。

## 8. MulDivUnit 与 FPGA IP 契约

`MulDivPipe.sv` 实例化：

| IP | 端口契约 | Tcl 生成 |
|---|---|---|
| `MUL_0` | `.CLK/.A[32:0]/.B[32:0]/.P[65:0]` | `mult_gen`，33x33 signed，DSP multiplier、speed goal、2-stage pipeline，输出 66 bit。 |
| `DIV_0` | AXI-stream dividend/divisor 输入，`m_axis_dout_tdata[63:32]` 为 quotient、`[31:0]` 为 remainder。 | `div_gen`，Radix2，32-bit，unsigned，blocking flow，manual latency 16。 |

有符号除法通过先取绝对值、使用 unsigned divider、再恢复符号实现。除 0 和 `INT_MIN / -1` 在 `MD_SPECIAL` 中旁路，不启动 divider。

如果删掉 special path，除 0 行为会依赖 IP，不能满足 RISC-V M 扩展规则。如果 signed 除法直接把负数送入 unsigned divider，`DIV/REM` 会错，但 `DIVU/REMU` 可能仍然看起来正常。

## 9. SoC 内存映射

| 地址 | 作用 | 读写 |
|---|---|---|
| `0x8010_0000` 到 `0x8013_FFFF` | DRAM 数据区 | 读写 |
| `0x8020_0000` | `virtual_sw[31:0]` | 读 |
| `0x8020_0004` | `virtual_sw[63:32]` | 读 |
| `0x8020_0010` | `virtual_key[7:0]` | 读 |
| `0x8020_0020` | SEG 写入寄存器/读回 | 读写 |
| `0x8020_0040` | LED 写入寄存器 | 写 |
| `0x8020_0050` | counter | 读写 start/stop command |

`SocMemBridge.sv` 对非 DRAM 读固定 1 拍返回：

```systemverilog
mmio_resp_valid_q <= req_valid && !dram_sel && !req_write;
```

如果将未知地址读也返回 valid，CPU 不会挂死，但软件错误地址会被静默读 0；这是当前 SRC 兼容优先的取舍。正式 SoC 可考虑加入 bus error 或非法地址 trap。

## 10. FPGA 与仿真 IP 边界

`rtl/ip/*.sv` 是 Verilator 行为模型。FPGA Tcl 创建真实 Vivado IP，并且不应把这些仿真模型加入 FPGA sources。

如果 FPGA 工程同时加入 `rtl/ip/MUL_0.sv` 和 Vivado 生成的 `MUL_0`，会出现模块重复定义或错误地综合行为模型。当前 Tcl 没有加入 `rtl/ip`，这个边界是正确的。

## 11. 当前 RTL 风险点

1. `rtl/core` 中 `Alu/BranchUnit/FetchStage/...` 多个文件是空 module，占位但未被主路径实例化。综合可接受，但容易误导读者以为它们参与执行。
2. Tcl 递归加入 `rtl/soc/dram_driver.sv` 和 `rtl/soc/perip_bridge.sv`，它们是旧桥接路径，主路径不用。若后续修改 IP 端口，旧文件也可能因解析失败影响 Vivado 工程。
3. `DCache.sv` 和 `riscv_cpu.sv` 使用 SystemVerilog block-scope declaration、数组等写法，属于 Vivado 2023.2 支持范围内的常见 SV 写法，但最终仍需 synth 验证。
4. 当前 CPU 功能覆盖以 SRC/RV32 测试为导向，不是完整异常/中断/特权架构实现。
