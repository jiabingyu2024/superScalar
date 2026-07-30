# 存储与测试契约

## 主仿真 DUT

当前 Verilator DUT 按测试类型分流：

| 测试类型 | DUT | 原因 |
| --- | --- | --- |
| rv32 | `myCPU` | 保持最小外部平台，方便生成波形、抓 core/接口信号和定位 ISA 正确性问题。 |
| src | `student_top` | src 目标更接近赛事 SoC 路径，需要覆盖 IROM/DRAM/perip_bridge/counter/display 的真实集成行为。 |

`core` 外部是 SystemVerilog interface，C++ testbench 直接驱动不如扁平端口稳定，并且会绕过真实赛事 CPU 适配层，因此不作为主 Verilator DUT。

## DUT 分层

| 层级 | DUT | 用途 |
| --- | --- | --- |
| L1 | `myCPU` | rv32 正确性仿真的主入口。 |
| L2 | `student_top` | src 类测试和 SoC 集成路径仿真的主入口。 |
| L3 | `top` | FPGA/Vivado 上板入口。 |

## IROM 契约

`myCPU` 暴露一个同步 IROM 取指端口：

```text
irom_addr = 当前取指地址
irom_ena = 取指使能
irom_data = 返回的一条指令
```

取指时序固定为 BRAM 风格的一拍地址寄存、寄存地址组合读：

| 周期 | 行为 |
| --- | --- |
| T0 上升沿前 | `myCPU` 给出 `irom_addr` 和 `irom_ena`。 |
| T0 上升沿 | IROM 行为模型寄存地址；Frontend 同时保存 pending PC/预测 payload。 |
| T0 上升沿后 | `irom_data = mem[addr_q]` 组合有效，并和 Frontend 保存的 payload 同拍绑定。 |

因此主 Verilator TB 不允许把 IROM 简化成“当前地址组合读当前指令”的零延迟模型，也不应额外增加到两拍同步读。否则 IF 阶段 PC 和指令会错位。

IROM 地址映射由 `student_top` 完成：

```text
inst_addr = irom_addr[15:2]
```

当前 IROM 容量是 16384 words = 64 KiB，程序位于
`0x8000_0000..0x8000_ffff`。`student_top` 另实例化一份相同 ROM，作为
CPU 数据口的只读程序存储器视图；因此 C 字符串、`.rodata` 和启动阶段的
`.data` 初值可以通过 load 读取。两份 FPGA ROM 使用同一 COE 初始化文件，
不提供数据口写能力。

## DRAM/MMIO 契约

`DramAccessIF` 明确区分“访问被接受”和“读数据有效”：

```text
accessReady: 本周期地址/命令被接受
readData: 固定延迟后的读返回数据
```

`myCPU` 当前固定 `accessReady=1'b1`，语义是“本周期命令被接收”，不是“读数据本周期有效”。所有 load 读返回，包括 DRAM、SEG/SW/KEY MMIO 和 counter，都必须按 core 的固定两拍 load metadata 对齐：

| 周期 | 行为 |
| --- | --- |
| T0 | `ExecuteMemStage` 发起 load，`readEn=1`，地址被接收；load 的 ROB/Rd/addr/subtype 进入 `loadMetaPipe0`。 |
| T1 | load metadata 从 `loadMetaPipe0` 推进到 `loadMetaPipe1`，外部读选择信号继续推进。 |
| T2 | `readData` 有效，`ExecuteMemStage` 用 `loadMetaPipe1` 的 metadata 做符号/零扩展后生成 WB 结果。 |

store 写入同样在命令被接受的周期生效。当前约定为“core 发 raw data/raw mask，外部 memory model 负责按地址 offset 对齐”：

| 访问 | `myCPU`/core 输出 | `dram_driver`/TB memory model 行为 |
| --- | --- | --- |
| `SB` | `perip_wdata[7:0]` 有效，`perip_mask=4'b0001` | `data << addr[1:0]*8`，`mask << addr[1:0]`。 |
| `SH` | `perip_wdata[15:0]` 有效，`perip_mask=4'b0011` | `data << addr[1:0]*8`，`mask << addr[1:0]`。 |
| `SW` | `perip_wdata[31:0]` 有效，`perip_mask=4'b1111` | word 写入。 |
| load | `readData` 已由外部按 `addr[1:0]` 右移 | `ExecuteMemStage` 只按 load subtype 做符号/零扩展。 |

rv32 的 `myCPU` Verilator memory model 必须保留两拍 load 返回关系，并复刻 `dram_driver` 的读右移、写左移行为；MMIO/counter 读也不能一拍返回，否则 core 会在第二拍看到默认 0。src 使用 `student_top` 时，该职责由 RTL `perip_bridge/dram_driver/DRAM_0/counter` 承担，C++ 侧不再模拟 DRAM 数据返回，只镜像结果用于 checker/perf。

### SoC 地址划分

`perip_bridge` 当前地址表：

| 地址/范围 | 目标 | 说明 |
| --- | --- | --- |
| `0x0200_4000` | `mtimecmp[31:0]` | 机器定时器比较值低 32 位。 |
| `0x0200_4004` | `mtimecmp[63:32]` | 机器定时器比较值高 32 位。 |
| `0x0200_bff8` | `mtime[31:0]` | 机器时间低 32 位。 |
| `0x0200_bffc` | `mtime[63:32]` | 机器时间高 32 位。 |
| `0x8000_0000 <= addr < 0x8001_0000` | IROM data view | 64 KiB，只读；写无效果。 |
| `0x8010_0000 <= addr < 0x8014_0000` | DRAM | 256 KiB，排他上界为 `0x8014_0000`。 |
| `0x8020_0000` | SW0 | 读 `virtual_sw[31:0]`。 |
| `0x8020_0004` | SW1 | 读 `virtual_sw[63:32]`。 |
| `0x8020_0010` | KEY | 读 `{24'd0, virtual_key}`。 |
| `0x8020_0020` | SEG | 读/写 `seg_wdata`；写忽略 mask。 |
| `0x8020_0040` | LED | 写 LED；写忽略 mask。 |
| `0x8020_0050` | counter | 写 start/stop，读 counter。 |
| 其他地址 | 无映射 | 读返回 0，写无效果。 |

注意：`myCPU` 没有单独 read enable 端口，`perip_bridge` 通过 `~perip_wen` 和地址选择推断读；因此 `myCPU` 无访问时必须把 `perip_addr` 置 0。当前 `myCPU.sv` 已满足这一点。

### Mask 和 offset 职责

当前唯一对齐点在 SoC/TB memory model：

```text
dram_data = perip_wdata << {addr[1:0], 3'b000}
dram_we   = perip_mask  << addr[1:0]
readData  = rawWord >> {addr[1:0], 3'b000}
```

core 内部不再对 load data 二次右移，也不对 store data/mask 左移。StoreBuffer 只在内部 forwarding 时临时对齐，用来判断和拼接同 word 的字节覆盖；对外提交仍保持 raw data/raw mask。

StoreBuffer forwarding 的边界：

| 场景 | core 内部行为 | 对外行为 |
| --- | --- | --- |
| load 所需字节全部来自更老 store | StoreBuffer 直接返回右移后的 raw load 数据，MEM 不访问 DRAM。 | 无 DRAM read。 |
| load 所需字节部分来自更老 store | StoreBuffer 返回 `forwardData/forwardMask`，MEM 发 DRAM read，返回后逐字节合并。 | DRAM/TB 仍按地址右移返回 word；core 只覆盖 StoreBuffer 命中字节。 |
| load 与 StoreBuffer 无字节交集 | 正常发 DRAM read。 | 由 DRAM/TB 负责读右移。 |

StoreBuffer 不再把部分命中视为必须等待的 hazard。更老 store 和 load 的程序顺序由 IssueQueue 的 MEM 保序保证；StoreBuffer 的职责是保存已经执行完成的 store 字节并提供 forwarding/提交。

当前不完整支持 misaligned half/word。`SH addr+1/3`、`SW addr+1/2/3` 没有 trap，也不能跨 word 正确写入；测试应避免这些访问，或后续补 misaligned exception。

### 延迟风险

`perip_bridge` 用 `dram_read_sel_d2/mmio_sel_d2/cnt_sel_d2` 选择读返回，`dram_driver` 用 `offset_d2` 对读数据右移。src 已切到 `student_top` 后，这条路径会直接参与 src 结果；若 src 在 `myCPU` 平台通过但在 `student_top` 平台长期无 MMIO 进展，应优先检查 `DRAM_0` 读延迟、`dram_read_sel_d2/mmio_sel_d2/cnt_sel_d2` 和 core load metadata 的相位是否一致。

历史问题：`perip_bridge` 曾经只对 MMIO/counter 读打一拍，导致 `srcSmoke` 收尾阶段读 counter 和读 SEG 时 core 实际采到 0，最终写出 `SEG=0`。当前已统一为两拍选择后，`srcSmoke` 最终显示 `0x37001456`。

当前 Verilator `DRAM_0` 行为模型约束：

1. 只有 `ena && wea == 0` 的 read 周期推进读地址寄存。
2. 下一拍输出上一拍读地址对应的数据，供 `perip_bridge.dram_read_sel_d2` 选择，并与 core `ExecuteMemStage` 的 `loadMetaPipe1` 对齐。
3. write 周期只按 byte enable 更新 memory，不推进读地址/valid 管线，避免 store 污染后续 load 返回地址。

如果把 write 周期也送进读管线，`srcSmoke` 会很早读到错误数据，表现为 `student_top` 下长期只访问 DRAM 而不写 SEG/LED/CNT。

## CSR 和无 cache 约束

当前 core 不实现 I/D cache。`FENCE/FENCE.I` 在项目内定义为 serial NOP：它们需要走 serial 路径保证顺序边界，但不产生 cache flush、取指失效或额外内存副作用。

CSR 当前只承诺测试子集：

| CSR | 地址 | 当前行为 |
| --- | --- | --- |
| `mstatus` | `0x300` | 支持有限 MIE/MPIE 位读写。 |
| `misa` | `0x301` | 只读 `0x40001100`，声明 RV32IM。 |
| `mie` | `0x304` | 当前只实现 `MTIE`（bit 7）。 |
| `mtvec` | `0x305` | 写入时低两位清零；ECALL 跳转使用它。 |
| `mscratch` | `0x340` | 普通可读写 scratch CSR，用于当前 `rv32mi-p-csr`。 |
| `mepc` | `0x341` | ECALL/EBREAK 写入 trap PC，MRET 使用它返回。 |
| `mcause` | `0x342` | ECALL 写入 machine ecall cause 11，EBREAK 写入 breakpoint cause 3。 |
| `mtval` | `0x343` | 保存同步异常附加值；定时器中断写 0。 |
| `mip` | `0x344` | 只读 `MTIP`（bit 7），直接反映 timer IRQ。 |

机器定时器中断在 `mstatus.MIE && mie.MTIE && mip.MTIP` 成立后等待精确提交点，
以内存子系统 quiescent 为附加保守条件接受。接受时写
`mcause=0x8000_0007`、`mtval=0`，`mepc` 保存刚提交指令的架构 next-PC，
再 full flush 并重定向到 `mtvec`。软件把 `mtimecmp` 移到未来后解除 MTIP，
最终通过 `mret` 返回。

非白名单 CSR 当前读 0、写忽略；这仍不是完整 RISC-V privileged 行为。

## rv32 通过标准

采用严格 `tohost` 判定：

| 条件 | 结果 |
| --- | --- |
| 写 `tohost == 1` | PASS |
| 写 `tohost != 0 && tohost != 1` | FAIL，并记录失败码 |
| 超时 | TIMEOUT，失败 |
| 无法定位 `tohost` | UNSUPPORTED，不能算通过 |

当前 riscv-tests 示例中 `tohost` 通常在 `0x80001000`，但 testbench 应优先从 ELF symbol 中解析地址，不应全局硬编码。

## src 测试契约

src 测试有独立通过逻辑，当前通过 `student_top` Verilator harness 运行。框架需要预留：

1. 用户提供的 src pass/fail 规则。
2. 赛事 counter/MMIO 行为；`counter.sv` 不修改，Verilator 中按 RTL 固定 `50000` 个 `w_clk_50Mhz` 周期加 1ms。
3. src harness 通过 `VERILATOR_TB` 条件编译从 `student_top` 暴露 `dbg_perip_*` 观测口，只用于仿真采样，不进入 FPGA 综合接口。
4. 在不修改正式综合端口的前提下，尽量保留内部性能指标观测能力。
