# RV32 CPU 项目技术报告（Markdown 初稿）

> 本文依据当前分支 RTL、仿真结果 JSON、Vivado Tcl 和设计文档编写，日期为 2026-07-15。
>
> 文中“待补图”位置需要后续在 Word/PPT 中补充架构图、时序图、波形或工具截图；“待最终回归填写”表示仓库中尚无足以支持最终结论的证据，不应在正式提交前直接删除。
>
> 原目录中的 `3.2 基于 Scoreboard 的有限乱序执行与顺序提交`在正文中按真实设计改为“有限乱序完成与顺序提交”；重复的`6.4 特权指令与异常测试结果`改为“DiffTest 回归结果”。

# 快速预览简介

本项目设计并实现了一款面向 FPGA 教学、竞赛和体系结构实验的 32 位 RISC-V CPU。处理器以 RV32I 为基础指令集，支持 RV32M 乘除法扩展、机器模式 CSR 与异常返回，并提供 Zba、Zbb、Zbc、Zbkb、Zbkx 和 Zbs 六组可配置位操作扩展。设计采用单发射、不同功能单元可乱序完成、Scoreboard 顺序提交的微架构，在保持控制复杂度和 FPGA 资源开销可控的前提下，允许普通整数、Load/Store、乘除法和位操作指令具有不同执行延迟。

处理器前端采用由 BTB、PHT、全局历史寄存器和返回地址栈组成的 GShare 分支预测器。后端使用 8 项 Scoreboard 保存所有在途指令的目的寄存器、完成状态、结果、异常和提交信息，并使用 transaction ID 将 Fixed Execute、Load 和 MDU/Bitmanip 三类完成端口与对应指令关联。架构寄存器只在顺序提交后写入，年轻指令即使先完成，也不能越过更老指令产生架构副作用，由此建立精确提交和精确异常边界。

访存系统包含 2 项 Load Queue、4 项 Store Buffer、Store-to-Load forwarding、访存请求仲裁器、32 KiB 直接映射 DCache 和外部 DMEM register slice。Store 在执行阶段进入 Store Buffer，但只有到达 Scoreboard head 并提交后才允许写出；Load 可以合并更老 Store 的字节数据，也可以在条件允许时绕过 Load Queue 直接启动缓存访问。Cacheable DRAM、Uncached 访问与 MMIO 共用统一请求接口，并在仲裁和提交条件中保持必要的顺序约束。

验证平台基于 Verilator。RV32 指令测试以 `myCPU` 为 DUT，SRC 类测试以完整 `student_top` 为 DUT；DiffTest 使用 OpenXiangShan difftest 子模块提供的标准探针和 DPI 数据通路，并接入独立 RV32 参考执行器，在提交边界逐条比较 PC、指令、寄存器写回和异常状态。当前证据表明 RV32I 40 项、RV32M 8 项和机器模式/CSR 4 项测试均通过；`srcWithMext` 的 500000 周期 DiffTest 窗口比较了 344974 次参考提交，未报告架构分歧，但该窗口以 TIMEOUT 结束，不能替代应用级最终 PASS。

FPGA 工程面向 Xilinx Kintex-7 `xc7k325tffg900-2`，输入差分时钟为 200 MHz，默认 SoC 与 CPU 时钟均为 50 MHz。Vivado 工程通过 Tcl 生成，并根据测试 profile 自动选择 IROM/DRAM 初始化文件。设计在性能优化过程中同步考虑同步 BRAM 推断、地址生成重定时、DCache 数据返回隔离、外部存储寄存切片和 reset 扇出控制，使功能正确性、IPC 和 implementation 可实现性共同参与设计取舍。

> **待补图 0-1：项目成果快速预览图。** 建议将“CPU架构图、Verilator测试通过截图、Vivado Device视图、上板LED/SEG照片”四张图组成 2×2 拼图，并在下方标出 RV32I/M 测试数量、当前 SRC IPC 和目标 FPGA。

---

# 目录

1. 项目概述
2. CPU设计
3. CPU性能优化设计
4. RV32 CPU关键机制与特色功能设计
5. 仿真平台介绍
6. 仿真结果
7. 上板验证
8. 总结展望
9. 参考文献

> 正式排版时建议由 Word 根据标题样式自动生成目录和页码，不要在 Markdown 中手工维护页码。

---

# 1. 项目概述

## 1.1 项目背景

RISC-V 采用开放、模块化的指令集体系，基础整数指令集与乘除法、位操作、压缩指令和特权架构之间具有清晰的扩展边界，适合用于处理器体系结构教学和 FPGA 原型验证。与只实现指令语义的简单多周期 CPU 相比，一个能够运行完整测试程序并在 FPGA 上稳定工作的处理器，还需要解决流水控制、数据相关、分支预测、可变延迟执行、存储顺序、精确异常、缓存、时序收敛和验证可观测性等工程问题。

本项目的目标不是堆叠尽可能多的乱序结构，而是在资源、频率和实现复杂度之间建立可解释的平衡。处理器保持单发射和单提交，使前端和提交控制相对清晰；同时使用 Scoreboard 保存多条在途指令，允许 Fixed Execute、Load 和长延迟执行单元在不同周期返回结果。该方式比传统固定五级流水能够更自然地容纳 DCache miss、乘除法和位操作延迟，又比具有物理寄存器重命名、Issue Queue 和多发射选择的完整乱序核更适合当前 FPGA 规模和项目周期。

项目同时面向两类工作负载：第一类是 `riscv-tests` 中的 RV32 指令定向测试，用于验证单条指令和异常语义；第二类是赛事 SRC 程序，用于覆盖完整 SoC、存储、外设、计时器和持续运行性能。仅依靠第一类测试无法发现 DCache/DRAM 拍数不匹配、MMIO 顺序和板级 IP 行为差异；仅依靠 SRC 最终灯图案又难以定位第一条错误指令。因此工程中同时建设了提交级 DiffTest、波形调试和结构化 JSON 性能统计。

## 1.2 设计目标

项目设计目标分为功能、微架构、性能、实现和验证五个层次。

### 1.2.1 功能目标

1. 正确执行 RV32I 基础整数指令，包括算术逻辑、移位、比较、分支跳转和字节/半字/字访存。
2. 支持 RV32M 的乘法、除法和余数指令，并覆盖除零和有符号溢出等边界情况。
3. 支持机器模式 CSR、ECALL、EBREAK、MRET、FENCE 和 FENCE.I 等系统指令子集。
4. 支持指令地址不对齐、Load/Store 地址不对齐、非法指令和系统异常的精确提交。
5. 通过配置开关选择六组 Zb 扩展之一或组合，关闭时不让无关位操作逻辑污染基线关键路径。

### 1.2.2 微架构目标

1. 保持按程序顺序发射，降低恢复和资源分配复杂度。
2. 允许不同功能单元乱序完成，避免长延迟操作强制冻结所有已发射指令。
3. 使用 Scoreboard 保证顺序提交和架构状态精确性。
4. 建立 RF、Commit-WB、Scoreboard 和 Completion 多级旁路，减少不必要的 RAW 停顿。
5. 通过 Store Buffer、Load Queue 和 Store forwarding 支持投机访存，同时阻止错误路径 Store 产生外部副作用。

### 1.2.3 性能目标

1. 在无相关、无资源冲突时保持每周期一条指令的发射和提交能力。
2. 降低条件分支和函数调用/返回产生的前端损失。
3. 提升缓存命中工作负载下的 Load 吞吐，避免所有 Load 固定经过长队列路径。
4. 通过同步存储、流水边界和局部旁路控制改善 FPGA 关键路径。
5. 使用 IPC、分支命中率、DCache 命中率和 stall 分类评价优化，而不是只观察程序总周期。

### 1.2.4 工程目标

1. RTL 采用模块化 SystemVerilog，package、filelist、仿真模型和 Vivado IP 合同明确。
2. 相同 CPU 可通过 `myCPU` 接入最小 RV32 测试平台，也可通过 `student_top` 接入完整 SoC。
3. Verilator 行为模型与 Vivado 真实 IP 在请求接受、输出寄存和返回 valid 拍数上保持一致。
4. Debug/DiffTest 逻辑仅在仿真宏下存在，不进入 FPGA 综合。
5. 工程能够由 Makefile 和 Tcl 复现构建、仿真、工程生成和结果归档过程。

## 1.3 项目平台说明

### 1.3.1 FPGA平台

主 FPGA 目标器件为 Xilinx Kintex-7 `xc7k325tffg900-2`。板级顶层接收 200 MHz 差分输入时钟，经 Clock Wizard 产生 50 MHz SoC 时钟和独立 CPU 时钟。默认 CPU 时钟同样为 50 MHz，以保证与赛事模板、UART 参数和 counter 时基一致；提高 CPU 频率时只修改 `FPGA_CPU_CLK_MHZ`，SoC 计时和串口域继续保持 50 MHz。

FPGA 工程不直接综合 `rtl/ip` 下的 Verilator 行为模型，而由 `fpga/create_vivado_project.tcl` 生成 IROM、DRAM、乘法器、除法器和 PLL IP。该划分避免行为模型被误当成板级真实实现，同时要求两者遵守相同 latency 合同。

### 1.3.2 软件与仿真平台

项目主要工具包括：

| 工具 | 用途 |
|---|---|
| SystemVerilog | CPU、SoC 和仿真 IP 行为模型描述 |
| Verilator | 将 RTL 编译为 C++ 周期模型，执行 RV32/SRC 回归 |
| C++ | Testbench、Memory Model、Checker、DiffTest 适配和结果统计 |
| Python/Make | 测试发现、构建调度、profile 选择和批量运行 |
| Vivado 2023.2 | IP 生成、综合、布局布线、时序分析和 bitstream 生成 |
| OpenXiangShan difftest | 标准 DiffExt 探针、DPI 数据包与状态传输框架 |

### 1.3.3 SoC集成层次

```text
top
└── student_top
    ├── myCPU
    │   └── core_top
    ├── IROM_0
    └── SocMemBridge
        ├── DramBramAdapter / DRAM_0
        ├── LED / SEG / SW / KEY
        └── counter
```

`myCPU` 是 CPU 对赛事接口的适配层；`student_top` 组合 CPU、指令 ROM、数据 RAM 和外设；`top` 进一步加入 PLL、UART 和 Digital Twin 控制器。RV32 定向测试使用 `myCPU`，SRC 测试使用 `student_top`，上板使用 `top`。

> **待补图 1-1：软硬件平台组成图。** 左侧画 Verilator/Cpp/DiffTest，右侧画 Vivado/Kintex-7，中间放共享 RTL 和测试数据，体现同一套 RTL 的两条验证路径。

## 1.4 主要设计指标与成果

### 1.4.1 静态设计指标

| 指标 | 当前配置 |
|---|---:|
| 数据宽度 | 32 bit |
| Reset PC | `0x8000_0000` |
| 发射宽度 | 1 instruction/cycle |
| 提交宽度 | 1 instruction/cycle |
| Fetch Queue | 4 entries |
| Scoreboard | 8 entries |
| Store Buffer | 4 entries |
| Load Queue | 2 entries |
| BTB | 128 entries |
| GShare history | 8 bit |
| PHT | 256 × 2 bit |
| RAS | 8 entries |
| DCache | 2048 lines × 16 B = 32 KiB |
| DRAM窗口 | `0x8010_0000`～`0x8013_FFFF`，256 KiB |
| 默认CPU时钟 | 50 MHz |
| FPGA器件 | `xc7k325tffg900-2` |

### 1.4.2 当前验证成果

截至本文编写日期，基础有效配置的回归结果如下：

| 测试类别 | 数量 | 当前结果 |
|---|---:|---|
| RV32I | 40 | 40 PASS |
| RV32M | 8 | 8 PASS |
| Machine/CSR/Zicntr | 4 | 4 PASS |
| Zb | 六组选配 | 必须按启用配置分别重编 DUT 与参考模型后统计 |
| `srcWithMext` DiffTest窗口 | 500000 cycles | 344974 次参考提交无 mismatch；应用状态为 TIMEOUT |

当前同口径 20M 周期优化记录显示，`srcWithMext` IPC 从 0.613611 提升到 0.764203，提升约 24.5%；DCache 命中率由 97.2825% 提升到 99.7246%。这些数字用于说明优化趋势，最终提交版仍应以最后一次全量回归和最终 RTL 对应的 JSON 为准。

> **待补图 1-2：主要指标与成果信息图。** 建议用四个大数字展示“32-bit、8-entry Scoreboard、32 KiB DCache、IPC +24.5%”，并在图注中写清测试窗口。

---

# 2. CPU设计

## 2.1 指令集的支持情况

处理器以 RV32I 为基本架构，使用 `uop_t` 将不同指令统一译码为功能单元类型、操作类型、源/目的寄存器、立即数、访存尺寸和异常信息。当前支持情况如下。

| 类别 | 指令/能力 | 实现单元 |
|---|---|---|
| 整数运算 | ADD/SUB、AND/OR/XOR、SLT/SLTU | Fixed Execute ALU |
| 移位 | SLL/SRL/SRA 及立即数形式 | Fixed Execute ALU |
| 高位立即数 | LUI、AUIPC | Decoder + ALU |
| 跳转 | JAL、JALR | Fixed Execute Branch |
| 条件分支 | BEQ/BNE/BLT/BGE/BLTU/BGEU | Branch Comparator |
| Load | LB/LBU/LH/LHU/LW | AGU + Load Queue + DCache + Load Data Path |
| Store | SB/SH/SW | AGU + Store Buffer |
| RV32M乘法 | MUL/MULH/MULHSU/MULHU | MUL IP + metadata pipeline |
| RV32M除法 | DIV/DIVU/REM/REMU | DIV IP + MDU control |
| CSR | CSRRW/CSRRS/CSRRC及立即数形式 | Commit + CSR File |
| 系统 | ECALL、EBREAK、MRET、FENCE、FENCE.I | Scoreboard serialize + Recovery |
| 计数CSR | cycle/cycleh、instret/instreth | Perf counters + CSR File |

### 2.1.1 位操作扩展

`core_config_pkg.sv` 提供六个综合期配置：

```text
CFG_ZBA  CFG_ZBB  CFG_ZBC  CFG_ZBKB  CFG_ZBKX  CFG_ZBS
```

Zba 提供移位加法，Zbb 提供基础位操作、计数、旋转和符号扩展，Zbc 提供 carry-less multiplication，Zbkb/Zbkx 提供密码算法常用的 pack、zip/unzip、byte reverse 和 crossbar permutation，Zbs 提供单 bit 设置、清除、取反和提取。简单 Zb 操作在 `bitmanip_unit` 中快速完成；CLMUL 类操作使用迭代状态机，避免把大规模组合异或网络放入主 ALU 关键路径。

配置关闭时，Decoder 不应把对应编码识别为有效扩展指令，Bitmanip 请求口也不应进入活动状态。修改配置后必须重建普通 Verilator 和 DiffTest 二进制，保证 DUT 与参考模型使用相同扩展集合。

### 2.1.2 异常支持边界

当前实现覆盖：

- 指令地址不对齐；
- 非法指令；
- Load 地址不对齐；
- Store 地址不对齐；
- ECALL from M-mode；
- Breakpoint；
- Trap 进入 `mtvec`；
- MRET 返回 `mepc`。

处理器只实现 Machine-mode 必需子集，不声明 U/S 模式、中断控制器、页表、原子扩展或浮点扩展。报告中应把“通过当前机器模式测试子集”与“实现完整 RISC-V Privileged Architecture”区分开。

> **待补图 2-1：指令集支持矩阵。** 横轴使用 RV32I、M、CSR/System、Zba/Zbb/Zbc/Zbkb/Zbkx/Zbs，纵轴使用算术、控制流、访存、异常和可配置状态，以颜色区分固定支持与选配支持。

## 2.2 处理器总体架构

当前处理器的准确描述为：**单发射、单提交、按序发射、允许不同功能单元乱序完成、Scoreboard 顺序提交的 RV32 Core**。

```text
Frontend -> Decode/ID -> Issue/Read -> Execute/FU
                                      | fixed completion
                                      | load completion
                                      | slow completion
                                      v
                                  Scoreboard
                                      |
                                in-order Commit
```

Frontend 负责 PC、GShare 预测、IROM 返回对齐和 Fetch Queue；Decode 将指令转换为统一 uop；ID holding register 保存唯一一条等待发射的指令。Issue 阶段同时读取 RegFile 和 Scoreboard producer map，通过 Operand Resolver 选择最新版本，再由 Issue Control 检查源操作数、功能单元、队列 credit 和恢复条件。

指令发射时获得一个 Scoreboard transaction ID，并与 uop 和操作数一起进入 `exec_q`。Fixed Execute 可以完成 ALU、Branch、地址生成和 Store metadata；Load 进入访存系统等待 DCache 或 Store forwarding；MUL/DIV 和 Bitmanip 走长延迟单元。三类结果均按 transaction ID 回写 Scoreboard，而不是直接写架构 RegFile。

Commit 只观察 Scoreboard head。只有最老 entry 已完成并满足 Store/Fence 等附加条件时才提交。普通结果写入 Commit-WB bridge，随后写 RegFile；Store 在提交时只设置 Store Buffer 中对应 slot 的 committed 标志；CSR 和 Trap 状态也只在 Commit 边界更新。

该架构不包含物理寄存器重命名、Reservation Station 或可跳过阻塞 ID 的 Issue Queue。因此，如果当前 ID 指令等待 RAW 或资源，年轻指令不能从它后面绕过；“乱序”仅指已经发射到不同执行单元的指令可能以不同顺序完成。

> **待补图 2-2：CPU Core总体架构图。** 可直接按照[`one_page_cpu_core_architecture_ppt_guide.md`](one_page_cpu_core_architecture_ppt_guide.md)绘制，必须标出七个逻辑阶段、Scoreboard主干、三类Completion、旁路和Recovery。

## 2.3 流水线与总体数据通路设计

为便于描述，处理器划分为七个逻辑阶段。可变延迟指令并不固定每阶段一拍，因此该划分表达的是职责和寄存边界，不是传统等长七级流水。

### 2.3.1 IF/PRED阶段

Frontend 根据当前 PC 同步读取 BTB 和 PHT。预测未命中时默认选择 `PC+4`；条件分支命中时由 PHT 饱和计数器最高位决定是否选择 BTB target；JAL/JALR 类无条件跳转直接选择 target；Return 优先使用 RAS 栈顶。预测结果与请求 PC 被寄存，并与一拍 IROM 返回配对后进入 Fetch Queue。

Fetch Queue 深度为 4，用于隔离同步预测/IROM延迟和后端短暂停顿。Redirect 时队列被清空，并从 Recovery Control 提供的新 PC 重新取指。

### 2.3.2 ID阶段

Decoder 组合解析 opcode、funct3、funct7、寄存器号和立即数，生成 `uop_t`。ID holding register `id_uop_q` 只保存一条指令；当 Issue 条件不成立时保持不变，当指令成功发射时清空，当前端同时有新指令时可以同拍替换。

非法编码在 Decode 阶段生成 exception metadata。该 uop 仍分配 Scoreboard entry，但 entry 在分配时直接标记 done，等待它成为 head 后精确触发异常，而不是在 Decode 立即冲刷流水线。

### 2.3.3 IS/RD阶段

RegFile 提供两个组合读端口。Scoreboard 根据 rs1/rs2 查询 youngest producer transaction ID、done 和 result。Operand Resolver 依次考虑 x0/RF、Commit-WB、Scoreboard producer 和本周期 Completion，从而输出最终操作数和 ready。

Issue Control 进一步检查：

- 当前 ID valid；
- rs1/rs2 ready；
- Load/Store 地址源满足独立 memory-ready；
- Scoreboard 有空项或本周期 Commit 可释放一项；
- Load Queue/Store Buffer 有 credit；
- MDU/Bitmanip 请求端可接受且共享资源不冲突；
- Serial 指令前后顺序满足；
- 当前无 Branch resolve 或 Redirect。

`issue_fire` 是一个原子事件，同时驱动 ID 消费、Scoreboard allocate 和 `exec_q` 捕获，避免出现“已执行但未分配”或“已分配但未执行”的半事务。

### 2.3.4 EX阶段

`exec_q` 保存 transaction ID、uop 和两个操作数。Fixed Execute 在组合路径中完成普通 ALU、分支比较、JAL/JALR target、访存地址检查和 Store slot metadata。有效地址在发射边沿直接计算并保存到 `exec_mem_addr_q`，使后续 Load/Store 和 DCache 控制不再串联 32 位地址加法器。

MUL/DIV 与 Bitmanip 从 `exec_q` 发起请求。Fixed 指令可以快速产生 completion；长延迟单元内部保存 owner transaction ID，直到结果 valid 后再返回。

### 2.3.5 MEM/LONG阶段

Load/Store 在该阶段进入 Store Buffer、Load Queue、Store Forwarding 和 DCache。乘除法和迭代 CLMUL 也在逻辑上处于长延迟执行阶段。它们不会阻止更早已经发射的其他功能单元产生 Completion，但当前 ID 仍可能因共享资源 busy 或 RAW 而停顿。

### 2.3.6 COMPLETE阶段

Fixed、Load 和 Slow 三类 Completion 使用 transaction ID 定位 Scoreboard entry，将 `done` 置位并写入 result；Fixed Completion 还携带异常、Store slot 等信息。Completion 不更新架构寄存器，因此年轻指令先完成不会破坏程序顺序。

### 2.3.7 COMMIT/WB阶段

Scoreboard head 为 occupied 且 done 时具备基本提交条件。Store 还要求对应 Store Buffer slot 有效；FENCE/FENCE.I 要求 Load、Store、DCache 和 MDU 静止。提交后，普通目的寄存器结果进入 WB bridge，CSR、Trap、MRET、Store committed 标志和分支调用/返回信息在各自架构状态模块更新。

> **待补图 2-3：七个逻辑阶段流水图。** 用不同颜色区分固定一拍阶段和可变延迟阶段，并用三条箭头表示 Fixed/Load/Slow Completion 汇合到 Scoreboard。

> **待补图 2-4：典型指令时序图。** 至少画独立 ALU 连续发射、ALU RAW 同拍旁路、Load-to-ALU 和 Load-to-address 四种情况。

## 2.4 数据通路关键模块详细设计

### 2.4.1 Frontend与Fetch Queue

Frontend 将 PC 生成、预测器同步读、IROM 请求/返回 metadata 和 Fetch Queue 组合为一个可反压前端。Fetch Queue 满时停止新的预测请求；后端取走 head 后释放 credit。Redirect 的优先级高于正常入队/出队，保证错误路径返回不会重新进入队列。

同步存储的关键是 PC、预测 next PC、PHT index/counter 与 IROM 指令必须属于同一请求。设计为每个请求保存 metadata，避免仅靠“当前 PC”解释一拍后的指令返回。

### 2.4.2 Decoder

Decoder 输出统一 `uop_t`，主要字段包括：

- `pc/instr/pred_next_pc`：控制流和提交信息；
- `rs1/rs2/rd/uses_rs*/writes_rd`：依赖和写回；
- `fu/alu_op/branch_op/muldiv_op/bitmanip_op`：功能单元选择；
- `imm/mem_size/load_unsigned`：执行与访存控制；
- `sys_op/csr_op/csr_addr/serialize`：系统指令；
- `exception_valid/cause/tval`：早期异常。

把依赖语义显式编码为 `uses_rs1/uses_rs2` 十分重要。没有该字段时，LUI、JAL 等指令编码中的伪寄存器位可能被误识别为 RAW 依赖。

### 2.4.3 RegFile

RegFile 是 32×32 bit 架构整数寄存器阵列，具有两个异步读端口和一个时序写端口。x0 在读端组合钳位为零，写端屏蔽 rd=0，并每周期物理维持 `regs_q[0]=0`。x1～x31 不进行 reset，从而减少 1024 bit 数据阵列的全局复位扇出。

RegFile 只接受 Commit-WB 结果，不接受 Completion。这样 flush 时无需回滚寄存器；尚未提交的最新值由 Scoreboard 或旁路网络提供。

### 2.4.4 Scoreboard

Scoreboard 深度为 8，使用 allocate pointer、commit pointer 和 count 构成环形在途窗口。每个 entry 保存 occupied、done、PC、instruction、rd、result、功能单元、异常、CSR、Store slot 以及 call/return 信息。

`producer_valid[32]`和`producer_tid[32]`直接记录每个架构寄存器的 youngest writer。由于指令按序发射，新写者分配时覆盖旧映射即可；Consumer 查询只需一次寄存器号索引，不必扫描全部 8 个 entry。

Scoreboard 的同周期更新顺序是：

```text
Completion write -> Commit clear -> Younger allocation
```

满窗口同拍 Commit+Issue 时，allocate pointer 与 commit pointer 可能指向同一物理 slot。Nonblocking assignment 的文本顺序保证年轻 allocation 最终覆盖老 entry 的 clear。Commit 清 producer map 时还必须比较 producer tid 是否仍等于 commit pointer，防止老 WAW writer 清除年轻 writer 的映射。

### 2.4.5 Operand Resolver

Operand Resolver 的普通源优先级为：

```text
x0/RF -> Commit-WB -> Scoreboard youngest -> same-cycle Completion
```

Completion 必须同时满足 producer found 和 transaction ID 相等，不能只比较 rd。Fixed、Load 和 Slow Completion 使用确定优先级；正常协议下同一个 transaction 不会从两个端口同时返回。

访存地址 rs1 另有 `src1_memory_value/ready`。Fixed 和 Slow Completion 可以前递到地址路径，Load Completion 只进入普通 consumer，不直达下一条 AGU。这样普通 Load-use 的 ALU/Branch/Store-data 可以无额外等待，而 Load 结果作为下一条 Load/Store 基地址时保留一拍时序隔离。

### 2.4.6 Issue Control

Issue Control 汇总数据和资源条件。Load/Store credit 不只看队列 count，还要加上 `exec_q` 中尚未正式入队的同类指令，否则连续发射可能超订阅最后一个 slot。Scoreboard 满时，如果 head 本周期真正 Commit，则该 Commit 提供同拍 allocation credit。

Serial 指令发射前要求 Scoreboard 为空且无 serial pending；它分配后设置 serial pending，阻止年轻指令继续发射，直到 System/exception 提交或 flush。该机制用于 CSR、FENCE、MRET 等需要简单全序语义的操作。

### 2.4.7 Fixed Execute

Fixed Execute 统一完成 ALU、Branch、AGU 和 Store metadata。Branch 计算 actual next PC，并与 uop 携带的 predicted next PC 比较；若不同则产生 branch miss。JAL/JALR 写回值为 `PC+4`。Load/Store 在该模块完成自然对齐检查，异常时直接生成带 cause/tval 的 Completion，正常 Load 转入 LSU，正常 Store 分配 Store Buffer slot 并完成 Scoreboard entry。

### 2.4.8 MDU与Bitmanip Unit

MDU 使用 33×33 有符号乘法输入覆盖 MUL/MULH/MULHSU/MULHU，并通过 operand 扩展方式选择高低结果。除法对有符号操作先求绝对值，输出后恢复符号，同时显式处理除零和 `0x80000000 / -1` 溢出。

MDU 一次只保存一个 owner transaction；请求接受后 busy，结果 valid 后返回并释放。Flush 时标记 killed，底层 IP 的迟到结果被排空但不产生 Completion。

Bitmanip 简单操作快速计算；CLMUL/CLMULH/CLMULR 使用迭代寄存器保存累加值、被乘数和乘数。MDU 与 Bitmanip 共享 slow completion 端口，因此 Issue Control 强制互斥。

### 2.4.9 Store Buffer

Store Buffer 深度为 4。Store 执行后保存 transaction ID、地址、raw wdata、size、uncached 属性和 sequence，但初始为 speculative。Commit 根据 Scoreboard entry 保存的 store slot 设置 committed；Memory Arbiter 只允许 committed head Store 对外请求。

Full flush 删除未提交 Store，但保留已 committed Store 继续 drain。该规则保证异常或分支恢复不会撤销已经发生架构提交的内存副作用，也不会让错误路径 Store 写到外部。

### 2.4.10 Load Queue与Store Forwarding

Load Queue 深度为 2，head 始终是最老等待 Load，另有唯一 active metadata 表示已经被 DCache 接受、正在等待 response 的事务。Load 进入 LSU 时会扫描所有 older Store，将命中字节合并到 forward mask/data。年轻 Store 不参与，且同一字节由更年轻的 older Store 覆盖更老值。

全字节被 older Store 覆盖时，Load 不访问 DCache，直接产生 forwarding completion。部分覆盖时仍访问 DCache，response 返回后逐字节合并。若 Load Queue 为空且 DCache 可接受，新 Load 可 direct-start，不必先入队再出队。

### 2.4.11 Memory Arbiter

Memory Arbiter 的固定优先级为：

```text
Committed StoreBuffer head
  > EX direct Load candidate
  > LoadQueue head
```

Store 优先保证已经提交的写能够及时 drain，并为 Fence/Uncached 访问释放顺序条件。Uncached Load 只有自身位于 Scoreboard head 且不存在 older Store 时才允许访问，防止具有外部副作用或易变语义的 MMIO 读被投机提前。

### 2.4.12 DCache

DCache 为 32 KiB 直接映射 Cache，包含 2048 行，每行 16 Byte，共四个 32-bit word bank。Tag+valid 使用同步 BRAM，四个 data bank 并行读取。Reset 后进入 `DC_INIT`，逐行清 valid，而不是对整块数据阵列施加复位。

Cacheable Load 在 IDLE 接受请求并启动同步 tag/data lookup，命中时下一逻辑阶段返回 word；miss 时保存请求地址，依次请求四个 word 完成 refill。请求 word 的第一个 response 可以提前返回给 CPU，后续三个 word 继续填充 cache line。Store 采用 write-through：对外写请求被接受，同时若本地 tag hit 则更新对应 data bank 字节。

Uncached Load 被本地锁存后在下一周期从 `DC_UNC_REQ` 发出，避免 Load Queue/仲裁组合锥直接到达 SoC register slice。Flush 对尚未完成的 miss/uncached 请求设置 killed；已经被外部接受的事务继续排空 response，但不向 Scoreboard报告 Completion。

### 2.4.13 Dmem Register Slice

`dmem_regslice` 位于 DCache 和 SoC Memory Bridge 之间，寄存请求 valid、write、address、wdata、wstrb 和 uncached 属性，同时寄存 response data。它切断 Core 内部缓存控制与外部 BRAM/MMIO 大扇出译码之间的长路径，是提高 FPGA 可实现频率的重要边界。

### 2.4.14 CSR File与Recovery Control

CSR File 实现 mstatus、misa、mtvec、mscratch、mepc、mcause、mtval、cycle和instret等机器模式寄存器。Trap 优先于普通 CSR 写和 MRET 状态恢复；mtvec/mepc 低两位强制对齐。

Recovery Control 的重定向优先级为：Exception到 `mtvec`，MRET到 `mepc`，FENCE.I到下一条 PC，最后是 Branch miss的actual next PC。Exception/MRET/FENCE.I产生 full flush；Branch miss只重定向前端并清除错误路径状态边界。

> **待补图 2-5：Issue子系统局部图。** 展示RegFile、Scoreboard producer map、Operand Resolver、三类Completion和Issue Control。

> **待补图 2-6：Load/Store数据通路图。** 展示AGU、Store Buffer、Store Forwarding、Load Queue、Arbiter、DCache、Regslice及三种优先级。

> **待补图 2-7：DCache状态机图。** 画出INIT、IDLE、UNC_REQ/WAIT、REFILL_REQ/WAIT以及kill排空路径。

## 2.5 发射、停顿与旁路控制设计

### 2.5.1 RAW、WAW与WAR处理

当前按序发射，所有消费者进入 Issue 前都按程序顺序到达，因此不存在年轻指令提前读取后又被老指令覆盖的 WAR 问题。WAW 由 producer map 指向 youngest transaction 处理：年轻写者分配时覆盖旧 writer，老 writer Commit 只有在 map 仍指向自己时才清 valid。

RAW 是主要动态相关。Consumer 查询 producer map：未找到在途 writer时使用RF/WB；找到后只等待指定transaction。Entry已done时直接取Scoreboard result；同拍正在Completion时使用transaction ID旁路，从而消除写Scoreboard再读出的一拍等待。

### 2.5.2 旁路矩阵

| Producer来源 | ALU/Branch普通源 | Store数据rs2 | Load/Store地址rs1 | CSR源 |
|---|---:|---:|---:|---:|
| RegFile | 支持 | 支持 | 支持 | 支持 |
| Commit-WB | 支持 | 支持 | 支持 | 支持 |
| Scoreboard done | 支持 | 支持 | 支持 | Serialize后理论无在途producer |
| Fixed Completion | 支持 | 支持 | 支持 | 不接入 |
| Load Completion | 支持 | 支持 | **不支持同拍直达** | 不接入 |
| MDU/Bitmanip Completion | 支持 | 支持 | 支持 | 不接入 |

Load-to-address 有意停一拍，即使 DCache hit 也可能发生。原因不是功能上无法前递，而是 Load数据若同拍经过Completion mux、地址加法和DCache控制，会形成跨越多个大模块的组合路径。下一周期结果已进入Scoreboard后，地址路径可以从稳定entry result读取。

### 2.5.3 资源停顿

主要停顿条件包括：

- Scoreboard满且本周期无Commit credit；
- 源transaction未完成；
- Load Queue或Store Buffer无可用slot；
- MDU/Bitmanip busy或请求口未ready；
- serial pending；
- Branch resolve/Redirect恢复边界；
- Frontend Fetch Queue没有有效指令。

ID停顿时uop保持，不需要replay。已经发射的Load或长延迟请求则由各自队列/FU保存owner和状态，response迟到时按transaction ID完成。

### 2.5.4 控制优先级

处理器状态更新遵循以下全局优先级：

```text
Reset
  > Full flush / Redirect
  > Completion / Commit / Allocate正常更新
```

在Scoreboard内部，正常更新进一步规定Completion、Commit、Allocate的覆盖次序；在Load Queue内部，completion清active后，同拍direct/queued start可以重新设置新的active；在Store Buffer内部，commit mark、enqueue和drain必须按照既定协议处理同拍事件。优先级是跨模块合同的一部分，不能只根据局部代码风格任意调整。

> **待补图 2-8：旁路网络和禁止旁路矩阵。** 使用蓝色实线表示允许，红色叉线表示Load Completion到下一条AGU被隔离。

## 2.6 Commit、异常与恢复控制设计

### 2.6.1 顺序提交

Scoreboard commit pointer始终指向程序顺序最老的在途指令。`commit_fire`要求head occupied且done；Store需要slot有效；FENCE/FENCE.I需要内存和长延迟资源静止。每周期最多提交一条，保证RegFile、CSR、Store committed和预测器RAS更新均按程序顺序发生。

普通写寄存器指令提交时，`rd/result`进入`wb_valid_q/wb_rd_q/wb_data_q`。RegFile在下一上升沿真正写入，因此Operand Resolver保留一条Commit-WB旁路覆盖该可见性间隙。

### 2.6.2 精确异常

异常metadata从Decode或Execute写入对应Scoreboard entry。年轻指令可以在异常指令之后完成，但不能越过它Commit。当异常entry到达head时：

1. `mepc`记录异常指令PC；
2. `mcause`记录异常原因；
3. `mtval`记录非法指令或错误地址；
4. mstatus保存并关闭MIE；
5. Recovery跳转到mtvec；
6. Scoreboard、ID、Execute和投机Load被清除；
7. 未提交Store被删除，已提交Store保留。

RegFile中此前已提交值不被flush，因而异常点之前的架构状态完整保留，异常点及其后的副作用均未进入架构状态。

### 2.6.3 分支恢复

Branch在Fixed Execute计算actual next PC。若与预测next PC不一致，Recovery立即重定向Frontend并清理错误路径。预测器训练使用随该指令保存的`pred_index`和`pred_counter`，不能用分支解析时已经变化的GHR重新计算索引。

GHR采用非投机更新，只在真实条件分支解析后移入actual taken，因此branch miss无需恢复历史寄存器。其代价是分支尚未解析时，后续预测仍使用旧全局历史。

### 2.6.4 System序列化

CSR、MRET、FENCE和FENCE.I使用serialize机制。它们发射前等待所有老指令提交，发射后阻止年轻指令进入Scoreboard。这样CSR source可直接使用RF+Commit-WB，避免接入通用Completion大mux；FENCE也能以简单的quiescent条件建立全序边界。

> **待补图 2-9：异常精确提交与恢复时序。** 画出老异常、年轻已完成ALU、Commit trap、full flush和mtvec重取，强调年轻结果未写RegFile。

---

# 3. CPU性能优化设计

性能优化遵循“先正确、再测量、后修改”的原则。每项优化均从可观测瓶颈出发，修改后同时检查功能回归、IPC、分支/DCache命中率、stall分类和Vivado关键路径，避免只为某一个局部数字牺牲整体可实现性。

## 3.1 基于 GShare 的分支预测优化

### 3.1.1 原始瓶颈

控制流指令会改变顺序取指地址。如果处理器在分支执行完成后才决定下一PC，Frontend必须为每个分支等待多个周期；循环和函数调用密集程序中，分支气泡会成为IPC的主要限制。仅使用PC局部的2-bit计数器可以学习单个分支的偏向，但无法利用不同分支之间的全局相关性。

### 3.1.2 预测器组成

当前预测器由四部分构成：

| 结构 | 配置 | 作用 |
|---|---:|---|
| BTB | 128 entries | 保存PC tag、target和分支类型 |
| PHT | 256×2-bit | 预测条件分支方向 |
| GHR | 8 bit | 保存最近条件分支真实方向 |
| RAS | 8 entries | 预测函数返回地址 |

BTB索引使用PC低位；PHT索引为：

```text
PHT index = PC[9:2] XOR GHR[7:0]
```

PHT计数器采用四态饱和状态。最高位为1时预测taken，未训练项按`01`即weakly not-taken处理。BTB同时保存`PRED_COND`、`PRED_JUMP`和`PRED_RETURN`类型，使Frontend能够区分条件分支、直接/间接跳转和返回。

### 3.1.3 同步读取与训练

BTB和PHT按同步RAM方式读取，预测结果一拍后有效。Frontend为请求PC保存metadata，并与IROM返回对齐。分支执行时，uop已经携带取指时使用的PHT index和counter，训练直接更新原entry。

同周期预测读和训练写若命中同一BTB/PHT entry，模块使用collision bypass选择新写入值。否则FPGA BRAM的read-during-write模式差异可能导致仿真和综合结果不一致。

### 3.1.4 GHR与RAS策略

GHR只在条件分支真实解析后更新，不在预测时投机移位。该策略不需要在mispredict时恢复GHR，显著简化控制；代价是同一时间窗口内尚未解析的分支不会贡献最新历史。

RAS只在Commit边界处理call和return。Call的link address入栈，Return出栈。该方式保证错误路径调用不会污染RAS，但比投机RAS更晚更新；对于当前单发射、较浅前端，这是合理的复杂度取舍。

### 3.1.5 效果评价

分支优化应使用动态分支数、命中数和miss rate评价。当前`srcWithMext` 500K窗口记录11368次分支、11073次命中，命中率97.405%。`srcSmoke`同窗口分支结构不同，命中率80.899%，说明命中率与程序控制流特征有关，不能只用单一测试概括预测器能力。

> **待补图 3-1：GShare结构图。** 画出PC到BTB索引、PC XOR GHR到PHT索引、RAS和next-PC mux。

> **待补图 3-2：2-bit饱和计数器状态转移图。** 标出strong/weak taken和not-taken。

> **待补图 3-3：不同SRC profile分支命中率柱状图。** 使用同一仿真窗口，避免直接比较不同cycles的原始miss数量。

## 3.2 基于 Scoreboard 的有限乱序完成与顺序提交

### 3.2.1 原始瓶颈

固定五级流水通常假设执行或访存延迟较稳定。加入DIV、CLMUL和DCache miss后，如果所有指令共享一个固定EX/MEM流水寄存器，长延迟操作会冻结后续所有阶段；如果各功能单元直接写RegFile，又会破坏WAW、异常和提交顺序。

### 3.2.2 优化方案

Scoreboard提供8个在途entry。指令按ID顺序分配transaction ID，执行单元保存该ID，完成时回写对应entry。Commit pointer始终从最老entry开始推进，因此形成：

```text
In-order Issue
Out-of-order Completion
In-order Commit
```

例如：

```asm
I0: div x5, x1, x2
I1: add x6, x3, x4
```

I0先发射并占用MDU，I1随后发射到Fixed Execute并可能更早完成。I1结果先保存在自己的Scoreboard entry，仍必须等待I0完成并提交后才能写架构RegFile。

### 3.2.3 Producer map降低查询复杂度

每个架构寄存器只保存youngest producer transaction ID，Consumer无需并行比较全部entry的rd。对于顺序发射，这是一个低成本的版本跟踪方法。它不是完整寄存器重命名：多个版本的结果仍在Scoreboard中，但架构名字只有一个直接映射，且ID阻塞时年轻指令不能绕过。

### 3.2.4 满窗口同拍复用

Scoreboard满时，若head本周期提交，Issue Control将Commit视为allocation credit。Scoreboard在同一边沿先清老head、后写年轻allocation，count保持不变。该优化避免窗口长期满载时每次Commit后固定浪费一拍。

### 3.2.5 性能收益与局限

收益包括：

- 可变延迟结果不再要求固定写回拍数；
- 独立Fixed指令可在更老长延迟指令尚未完成时先产生结果；
- Completion bypass可直接唤醒紧随Consumer；
- 异常和Store副作用仍保持精确。

局限包括：

- 只有一个ID候选，RAW或FU busy会阻塞所有年轻指令；
- 每周期最多发射/提交一条，峰值IPC不超过1；
- producer map不等价于PRF和Rename，不能消除所有名字相关；
- Scoreboard query和Completion mux仍可能形成Issue关键路径。

因此报告使用“有限乱序完成”而不是“完整乱序执行”。

> **待补图 3-4：DIV与独立ALU乱序完成时序。** 横轴为周期，纵轴为ID、EX、MDU、Scoreboard和Commit，突出ALU先done但后Commit。

## 3.3 数据相关检测与多级旁路优化

### 3.3.1 旁路层次

若所有Consumer都等待Producer Commit并写入RegFile，普通ALU链会产生大量空泡。当前设计建立四层数据来源：

1. RegFile提供已提交基线值；
2. Commit-WB覆盖Commit到RF真实写入的一拍间隙；
3. Scoreboard done提供已完成、未提交结果；
4. Same-cycle Completion直接提供本周期刚产生的结果。

Scoreboard决定“Consumer应该等待哪个版本”，Completion bypass决定“这个版本是否正好本周期完成”。只做其中一层都会产生错误：没有producer版本比较会在WAW后读到老值；没有同拍Completion会多等待一拍。

### 3.3.2 典型RAW优化

```asm
add x5, x1, x2
xor x6, x5, x3
```

第二条在查询Scoreboard时发现x5由tid0生成且entry尚未done；同周期Fixed Execute返回tid0 Completion，Resolver匹配ID并直接前递result，第二条可以在该边沿发射。与等待Scoreboard写入后再查询相比节省一拍。

Load结果也可同拍前递给ALU、Branch和Store data，从而减少典型Load-use penalty。Store data使用普通rs2路径，因此：

```asm
lw x5, 0(x1)
sw x5, 0(x2)
```

可以在Load Completion周期使用最新x5数据，只要Store地址x2已经ready。

### 3.3.3 时序隔离取舍

Load Completion不前递到下一条访存地址rs1：

```asm
lw x5, 0(x1)
lw x6, 0(x5)
```

第二条等待一拍，下一周期从Scoreboard done/result读取。该限制牺牲少量IPC，换取切断DCache response→Completion mux→地址加法→DCache metadata/control的长组合路径。

### 3.3.4 WAW正确性

```asm
add x5, x1, x2   # tid0
div x5, x3, x4   # tid1
xor x6, x5, x7
```

第二条分配后producer[x5]指向tid1。即使tid0先Commit并进入WB，第三条也必须等待tid1。Resolver中Scoreboard found覆盖RF/WB老版本；tid0 Commit也不能清除已经指向tid1的producer map。

> **待补图 3-5：四层操作数选择优先级图。** 用从低到高的mux层级表示RF、WB、Scoreboard和Completion。

> **待补图 3-6：Load旁路允许/禁止矩阵。** 突出Load→ALU允许、Load→Store data允许、Load→Load/Store address隔离一拍。

## 3.4 Load/Store 数据通路优化

### 3.4.1 Store Buffer解耦执行与外部写

如果Store只能在Commit阶段才计算地址和数据，提交会承担过长组合路径；如果Store在EX立即写外部存储，错误路径和异常后的Store又无法撤销。当前Store在EX完成地址与数据准备并写入Store Buffer，Scoreboard保存slot；Commit只将slot标记为committed，真正对外写由Store Buffer head随后drain。

这将“计算完成”“架构提交”和“外部请求接受”分成三个事件，既保留精确副作用，又让Store不长期占用执行流水。

### 3.4.2 Store-to-Load Forwarding

Load扫描所有older Store的字节覆盖。Store Buffer内保存raw data和size，forwarding模块按地址offset生成对齐byte mask/data。对同一字节，程序顺序更年轻但仍older的Store覆盖更老值。

三种情况分别处理：

| 场景 | 动作 |
|---|---|
| 全字节覆盖 | 不访问DCache，直接Load Completion |
| 部分覆盖 | 发DCache读，response后按字节merge |
| 无覆盖 | 正常DCache访问 |

该设计避免了“只要存在older Store就阻塞所有Load”的保守策略，并正确处理SB/SH对后续LW的部分覆盖。

### 3.4.3 Load Direct-start

传统路径是Load先入Load Queue，下一周期由head发起DCache请求。当前在Load Queue为空、DCache可接受且顺序条件满足时，EX Load作为direct candidate直接进入Memory Arbiter。如果DCache握手成功，该Load不写入等待队列，只设置active metadata；若不能直接启动，再回退到Load Queue。

同口径20M周期记录中，加入32KiB DCache后IPC为0.647277，进一步加入direct-load路径后提升到0.764202，说明减少Load固定排队对当前工作负载具有明显收益。该比较只说明该历史迭代的变化，不能将全部差值简单归因于一条RTL语句。

### 3.4.4 Uncached顺序

Uncached Load可能读取计时器、按键等具有实时语义的外设，因此要求自身位于Scoreboard head且不存在older Store。Uncached Store仍进入Store Buffer，并在Commit后按序drain。这样MMIO不会被投机提前，也不会被DCache命中数据替代。

> **待补图 3-7：Store/Load生命周期图。** Store画出EX enqueue、Commit mark、Memory drain；Load画出Forward、Direct-start、Queue和DCache response四条路径。

## 3.5 DCache 与访存请求调度优化

### 3.5.1 容量优化

历史优化记录对同一`srcWithMext` 20M窗口逐步增加DCache容量：

| 配置阶段 | IPC | DCache hit rate |
|---|---:|---:|
| 8KiB | 0.613611 | 97.2825% |
| 16KiB | 0.625688 | 98.1519% |
| 32KiB | 0.647277 | 99.6579% |

容量增加减少冲突miss，但会消耗更多BRAM并扩大索引/布线范围。当前选择32KiB，是IPC收益与Kintex-7 BRAM资源之间的折中。

### 3.5.2 同步Tag/Data Bank

Tag/valid和data array分别封装为单一写端口同步RAM模板，便于Vivado推断Block RAM。DCache INIT只逐行写valid=0，避免大规模异步reset。Load请求在tag比较前投机启动data bank读取，命中后直接选择已返回word，减少tag compare串入data RAM address的延迟。

### 3.5.3 Refill与关键字优先返回

Cache line包含4个word。Miss后从请求word开始依次读取外部存储；第一个response既写data bank，也立即返回给Load，剩余word继续refill。这样Load不必等整条16Byte cache line全部填完才完成。

### 3.5.4 请求仲裁

Committed Store优先于Load，避免Store Buffer长期占满并保证Fence可前进；Direct Load优先于Queued Load，使新Load在空队列时减少一拍；Queued Load保持FIFO head顺序。固定优先级简单可证明，但在极端连续Store流量下可能推迟Load，后续可根据计数器评估是否需要公平机制。

### 3.5.5 Write-through策略

Store每次都向外部DMEM写，同时在本地hit时更新data bank。Write-through无需dirty bit和writeback状态机，便于上板和异常分析；代价是Store外部带宽更高。Store Buffer与Memory Arbiter吸收了部分写延迟，因此当前阶段优先选择可验证性更高的策略。

> **待补图 3-8：DCache容量与IPC/命中率双轴图。** 三个点必须注明相同20M仿真窗口。

> **待补图 3-9：DCache miss refill时序。** 标出lookup miss、四次word请求、关键word提前response和最终tag valid写入。

## 3.6 面向 FPGA 时序收敛的关键路径优化

### 3.6.1 时序优化方法

FPGA性能不能只依赖RTL仿真。项目使用Vivado routed timing report按起点/终点聚类全部setup违例，识别DCache→SoC memory、Execute→Scoreboard、DCache→Scoreboard、Store forwarding和reset等路径族，再决定增加寄存边界还是缩小组合锥。

历史200MHz实验中，早期实现WNS达到-3.616 ns至-4.310 ns，说明5 ns周期下存在大量严重违例。该结果不能作为最终可上板频率，但揭示了关键路径来源，为后续结构调整提供依据。

### 3.6.2 Early AGU

访存地址由`src1_mem_value + imm`计算。若该加法放在DCache或Store forwarding输入前，路径会继续穿过地址译码、tag/index生成、队列扫描和RAM控制。当前在Issue进入`exec_q`的边沿同步保存`exec_mem_addr_q`，使MEM阶段从寄存地址开始。

### 3.6.3 Load-to-address旁路隔离

Load response通常来自BRAM/DCache远端。阻止它同拍进入下一条AGU，可避免形成跨越DCache、Scoreboard Resolver、地址加法和新DCache请求的环路式长路径。这是一项明确的IPC/Fmax折中，应在性能报告中同时记录`load_access_block_cycles`和实现slack。

### 3.6.4 Dmem Register Slice

DCache的外部请求要到达SoC地址译码、MMIO寄存器和BRAM控制。Register slice寄存完整请求payload和response，切断Core/SoC边界。即使增加一个外部访问拍数，也能显著降低跨层级高扇出路径，并使DCache只依赖ready/valid合同。

### 3.6.5 同步RAM与单写端口模板

Tag、Data、BTB等大数组使用同步读取和明确单写端口，避免综合为大量distributed RAM或LUT mux。写地址/数据mux放在RAM模板外，使Vivado更容易识别Block RAM。Read-during-write通过显式collision bypass保证行为一致。

### 3.6.6 Reset与层级策略

RegFile数据、Scoreboard无效payload和DCache data不做无意义复位，只复位valid/occupied、pointer和控制状态。这样减少全局reset网络和寄存器CE/R扇出。

Vivado默认`flatten_hierarchy=rebuilt`，允许跨层级优化并在综合后重建可观察层次；调试时可以临时使用`none`，但不能把保留层级当成性能优化。关键调试探针受`VERILATOR_TB`保护，不进入综合。

### 3.6.7 时序结果使用原则

正式报告必须同时给出目标周期、WNS、TNS、失败端点数、hold/pulse-width状态和资源利用率。只截一条最差路径不足以证明设计可上板；只看到bitstream生成也不等于满足时序。

> **待补图 3-10：优化前后关键路径示意图。** 左侧画Load response直达AGU/DCache，右侧画Scoreboard稳定结果和Early AGU寄存边界。

> **待补图 3-11：Vivado违例路径聚类图。** 使用模块级路径族，而不是粘贴数百行Timing Report。

## 3.7 性能测试与优化效果分析

### 3.7.1 评价指标

核心指标定义如下：

```text
IPC = Commit instruction count / Core cycles
Branch hit rate = Branch hit count / Branch count
DCache hit rate = Cache hit count / Cache access count
```

此外还记录Frontend空闲、RAW、Load访问、Load返回、Store Buffer、serial和长延迟执行等stall。不同版本比较必须使用同一测试profile、相同初始化文件、相同周期窗口和相同CPU频率口径。

### 3.7.2 历史同口径优化结果

`srcWithMext` 20M周期记录如下：

| 迭代 | 主要变化 | Commit数 | IPC | Branch hit | DCache hit |
|---|---|---:|---:|---:|---:|
| Iteration 1 | 8KiB DCache基线 | 12,272,212 | 0.613611 | 98.7357% | 97.2825% |
| Iteration 2 | 16KiB DCache | 12,513,762 | 0.625688 | 98.7366% | 98.1519% |
| Iteration 3 | 32KiB DCache | 12,945,533 | 0.647277 | 98.7381% | 99.6579% |
| Iteration 4 | Direct Load | 15,284,038 | 0.764202 | 98.7447% | 99.7246% |
| Iteration 5 | Store timing整理 | 15,284,050 | 0.764203 | 98.7460% | 99.7246% |
| Iteration 7 | 注册边界版本 | 15,267,208 | 0.763360 | 98.7446% | 99.7243% |

从8KiB基线到Direct Load版本，IPC提升约24.5%。Iteration 7略降约0.11%，说明为时序增加边界通常会带来小幅吞吐代价，但如果显著改善Fmax，实际每秒指令数仍可能提高。

### 3.7.3 当前短窗口快照

当前`build/result/src`中的500K周期快照：

| Profile | Commit | IPC | Branch hit | DCache hit | 状态 |
|---|---:|---:|---:|---:|---|
| srcSmoke | 285,895 | 0.571790 | 80.8990% | 99.9316% | TIMEOUT窗口 |
| srcWithMext | 345,025 | 0.690050 | 97.4050% | 99.9769% | TIMEOUT窗口 |

`srcWithMext`在500K时已观察到RV32I通过计数37、失败计数0、M扩展计数8，但尚未出现最终PASS marker。该数据适合评估早期进度和IPC，不应写成完整赛事程序已经通过。

### 3.7.4 最终报告需要补充的数据

正式提交前需要在本节替换或补充：

- 最终RTL对应的完整`srcWithMext`运行结果；
- `srcSmoke/srcWithoutMext`统一窗口对比；
- 50MHz与目标高频实现的每秒提交数；
- WNS/TNS和资源利用率；
- 优化前后stall结构堆叠图；
- 若使用CoreMark，给出编译选项、迭代次数和CoreMark/MHz。

> **待补图 3-12：IPC优化折线图。** 横轴为Iteration 1～7，纵轴为IPC，标注DCache容量和Direct Load节点。

> **待补图 3-13：当前stall构成图。** 从最终JSON生成堆叠柱状图，避免使用旧版ROB/IQ字段解释当前单发射Core。

---

# 4. RV32 CPU关键机制与特色功能设计

## 4.1 精确异常、CSR 与系统指令支持

### 4.1.1 设计动机

异常和CSR不是普通ALU结果。它们会改变控制流、特权状态和后续指令可见环境。如果在Decode或Execute发现异常后立即更新CSR，可能越过尚未提交的老Store；如果年轻指令已经完成并写RegFile，又无法恢复到异常点之前的精确状态。

本设计将异常视为Scoreboard entry的一部分。异常指令正常占据程序顺序位置，但在发现异常后标记done，不再产生普通执行副作用。只有它成为commit head时才更新mepc/mcause/mtval和mstatus，并触发full flush。

### 4.1.2 CSR实现

当前主要CSR包括：

| CSR | 地址 | 功能 |
|---|---:|---|
| mstatus | `0x300` | MIE/MPIE/MPP等机器状态 |
| misa | `0x301` | 声明RV32 I/M基础能力 |
| mtvec | `0x305` | Trap入口 |
| mscratch | `0x340` | 机器模式临时寄存器 |
| mepc | `0x341` | Trap返回PC |
| mcause | `0x342` | Trap原因 |
| mtval | `0x343` | 非法指令或错误地址 |
| cycle/cycleh | `0xC00/0xC80` | 周期计数 |
| instret/instreth | `0xC02/0xC82` | 提交指令计数 |
| mhartid | `0xF14` | 当前单核返回0 |

CSR指令被序列化，其source在Issue时捕获到Scoreboard entry，真正的读改写在Commit完成。CSRRW直接写source，CSRRS与旧值OR，CSRRC与旧值AND NOT。rd获得写之前的CSR旧值，保持ISA语义。

### 4.1.3 Trap与MRET

Trap发生时，mepc记录异常PC，mcause记录原因，mtval记录附加值；mstatus把MIE保存到MPIE并关闭MIE。MRET恢复MIE、设置MPIE并跳回mepc。Recovery优先选择异常，其次MRET/FENCE.I，最后Branch miss。

### 4.1.4 精确状态保证

精确性的核心不变量是：

1. RegFile只由Commit写；
2. CSR只在Commit更新；
3. 外部Store只允许committed slot发出；
4. Full flush删除所有未提交Scoreboard/Load/Execute状态；
5. 已提交Store不因年轻异常被删除。

> **待补图 4-1：精确异常状态边界图。** 将RegFile/CSR/Committed Store画在边界左侧，将Scoreboard未提交entry、Load和投机Store画在右侧。

## 4.2 投机访存与精确 Store 提交机制

### 4.2.1 三阶段Store生命周期

Store被拆分为：

```text
Execute/enqueue -> Commit/mark committed -> Memory/drain
```

Execute阶段尽早计算地址、数据和mask，使后续Load可以从Store Buffer前递；Commit阶段建立架构顺序；Drain阶段处理DCache/外部总线握手。三者解耦后，Store不会在等待提交期间占用Fixed Execute，也不会在错误路径提前写外部。

### 4.2.2 Flush语义

Full flush扫描Store Buffer并删除所有未committed项，保留committed项。Tail和count根据保留entry重新计算，head保持指向最老已提交Store。若错误地清空整个Store Buffer，已经Commit但尚未被外部接受的Store会丢失；若一个都不清，错误路径Store会在恢复后写出。

### 4.2.3 Load与Store顺序

Load在EX时快照older Store范围，并使用sequence cutoff区分程序顺序。Forwarding只使用older Store，避免从年轻Store读取未来值。Uncached Load还必须等到Scoreboard head并确认older Store不存在，建立MMIO强顺序。

### 4.2.4 精确Store的工程意义

该设计使处理器即使允许Load和ALU在不同时间完成，也能保证：

- 错误预测路径Store不写内存；
- 异常后年轻Store不写内存；
- 已提交Store最终一定drain；
- Load可读取尚未drain但程序顺序更老的Store数据；
- FENCE等待访存子系统quiescent后再提交。

> **待补图 4-2：Store Buffer entry状态图。** 使用Speculative、Committed、Draining/Free三个状态，标出Flush仅删除Speculative。

## 4.3 Cacheable、Uncached 与 MMIO 统一访问

### 4.3.1 地址空间

| 地址 | 目标 | 属性 |
|---|---|---|
| `0x8010_0000`～`0x8013_FFFF` | DRAM | Cacheable |
| `0x8020_0000` | SW低32位 | MMIO/Uncached |
| `0x8020_0004` | SW高32位 | MMIO/Uncached |
| `0x8020_0010` | KEY | MMIO/Uncached |
| `0x8020_0020` | SEG | MMIO/Uncached |
| `0x8020_0040` | LED | MMIO/Uncached |
| `0x8020_0050` | Counter | MMIO/Uncached |

Core通过`dmem_req_valid/ready/write/addr/wdata/wstrb/uncached`发出统一请求，读响应通过独立`dmem_resp_valid/rdata`返回。写请求没有单独response，握手即表示外部已接受。

### 4.3.2 Cacheable访问

DRAM窗口使用固定高位译码进入DCache，避免两个32-bit范围比较器落在Load地址关键路径。Load可命中、miss refill或从Store Forwarding完成；Store采用write-through并在本地hit时更新Cache。

### 4.3.3 Uncached与MMIO访问

MMIO和地址范围外访问设置uncached，不查询或填充DCache。Uncached Load先在DCache内部锁存，再通过DMEM register slice访问SoC；Store在Commit后由Store Buffer发出。该机制保证LED、SEG、Counter等外设读写按程序顺序可见。

### 4.3.4 Byte lane约定

Core输出Store raw data和raw wstrb，DCache/SoC根据`addr[1:0]`对齐到32-bit word byte lane。Load返回word后由Load Data Path根据地址offset选择字节/半字，并完成有符号或零扩展。对齐职责必须唯一，若Core和SoC重复移位会产生SB/SH/LB/LH错误。

### 4.3.5 FPGA IP时序合同

Verilator DRAM行为模型与Vivado Block Memory Generator必须一致区分：请求边沿的`ENA`负责memory read/write，后续output register由`REGCEA`推进，response valid与数据、offset属于同一事务。只延迟valid而不推进真实BRAM输出寄存，会造成连续地址返回错位，仿真可能因过于理想的行为模型而掩盖问题。

> **待补图 4-3：统一存储接口与地址空间图。** 左侧Core统一请求，中央DCache/Regslice，右侧分为DRAM、LED/SEG、SW/KEY和Counter。

> **待补图 4-4：BRAM请求与返回拍数图。** 标出ENA、内部latch、REGCEA、DOUT和resp_valid的上升沿关系。

---

# 5. 仿真平台介绍

## 5.1 仿真环境与工具

### 5.1.1 Verilator双DUT验证策略

项目按照测试目的选择不同DUT：

| 测试类型 | DUT | 可执行文件 | 覆盖范围 |
|---|---|---|---|
| RV32 ISA | `myCPU` | `sim_mycpu` | Core、IROM/DMEM扁平接口、tohost |
| SRC | `student_top` | `sim_student_top` | CPU、IROM、DRAM、MMIO、counter、display |
| RV32 DiffTest | `myCPU`+Diff probes | `sim_mycpu_difftest` | 提交级参考比较 |
| SRC DiffTest | `student_top`+Diff probes | `sim_student_top_difftest` | 完整SoC窗口内提交比较 |

RV32使用最小平台，能够快速运行单条指令测试和生成较小波形；SRC使用完整SoC，能够暴露BRAM读延迟、MMIO、计时器和显示协议问题。两个入口共享Checker、结果JSON、性能计数和命令行配置。

### 5.1.2 构建工具

普通模型构建命令：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

DiffTest模型构建命令：

```bash
git submodule update --init tb/difftest/upstream
make difftest-prepare
make difftest-build BUILD_JOBS=4 BUILD_CXX=g++
make difftest-build-src BUILD_JOBS=4 BUILD_CXX=g++
```

Verilator将SystemVerilog编译为C++模型。`scripts/run_verilator.py`负责解析filelist、检查源码时间戳、选择测试数据、运行可执行文件和生成summary；Makefile作为面向使用者的稳定入口。

### 5.1.3 Filelist与仿真IP

`scripts/filelists/core.f`按package、Decode、Frontend、Issue、Execute、Memory、Commit、Control和Top的依赖顺序列出RTL。`soc.f`加入SoC模块；`ip_verilator.f`加入IROM、DRAM、MUL、DIV和PLL行为模型。

行为模型不是任意简化模型。IROM必须匹配一拍同步读；DRAM必须匹配READ_FIRST、byte write enable和output register enable；MUL/DIV latency与Vivado IP设置一致。否则“Verilator通过、板上失败”并不能说明Core正确。

### 5.1.4 波形与结果文件

设置`TRACE=1`可生成FST波形。每个测试还生成JSON，记录：

- status和reason；
- cycles/max_cycles；
- tohost或LED/SEG正确性状态；
- Commit count和IPC；
- Branch数量与命中率；
- Load/Store/MMIO数量；
- DCache access/hit/miss；
- stall和资源计数；
- DiffTest提交数和最后PC。

结构化结果比仅保存终端日志更适合批量比较和生成报告图表。

> **待补图 5-1：仿真软件栈图。** 从Makefile到Python runner、Verilator executable、Checker/DiffTest和JSON结果逐层画出。

## 5.2 仿真平台总体架构

### 5.2.1 RV32最小平台

RV32平台只实例化`myCPU`。C++ testbench负责：

1. 根据CPU地址提供一拍IROM返回；
2. 模拟DMEM ready/valid和固定延迟读response；
3. 按地址offset处理Load/Store byte lane；
4. 监测tohost写；
5. 驱动reset和clock；
6. 收集性能与Commit trace。

`tohost==1`判定PASS，非零且非1判定FAIL；到达max cycles仍未写tohost则判定TIMEOUT。该标准比“程序跑到某个PC”更严格，也能保存失败码。

### 5.2.2 SRC完整SoC平台

SRC平台的数据流为：

```text
irom.hex / dram.hex
-> RTL IROM_0 / DRAM_0
-> student_top / myCPU
-> SocMemBridge / MMIO / counter / display
-> VERILATOR_TB debug observation
-> SRC checker
-> JSON
```

C++不直接替代RTL内存和外设，而是通过仿真专用debug口采样CPU提交后的外设访问。这样SRC可以覆盖与FPGA相同的SoC桥接路径。

### 5.2.3 双时钟模型

`student_top`同时具有CPU时钟和固定50MHz SoC时钟。`CPU_FREQ_MHZ`控制harness中CPU边沿节奏和性能耗时换算，counter仍由50MHz时钟每50000周期累加1ms。改变CPU频率不能同步改变counter规则，否则SRC显示的毫秒数将失去赛事口径。

### 5.2.4 Checker分层

不同SRC profile使用不同结束协议：

| Profile | Checker | 主要判定 |
|---|---|---|
| src0/src1/src2 | `ledseg` | PASS LED后SEG通过数与counter BCD匹配 |
| srcSmoke | `ledonly` | 观察旧版PASS/FAIL LED marker |
| srcWithMext | `lampseg` | PASS marker、8灯全亮、RV32I=37、M=8 |
| srcWithoutMext | `lampseg` | PASS marker、8灯全亮、RV32I=37 |

同一个TIMEOUT在不同profile下不能只看最后LED数值推断结果，必须结合checker、测试进度计数和是否出现最终marker。

> **待补图 5-2：RV32与SRC双DUT验证架构。** 左边myCPU+Cpp memory+tohost，右边student_top+RTL memory/MMIO+lampseg，共享结果与DiffTest。

## 5.3 riscv-tests功能测试集

### 5.3.1 测试分类

当前测试数据包括：

- `rv32ui`：RV32I基础整数和访存，共40项；
- `rv32um`：M扩展，共8项；
- `rv32mi`：CSR、ECALL/EBREAK、Zicntr等机器模式测试，共4项；
- `rv32uzba/uzbb/uzbc/uzbkb/uzbkx/uzbs`：六组位操作扩展定向测试。

每个测试目录包含hex/coe/dump等输入。Runner根据TEST或SUITE选择文件，必要时通过`prepare_test_data.py`补齐可生成的数据，但不覆盖已有测试资产。

### 5.3.2 常用命令

```bash
# 单项
make sim-rv32 TEST=rv32ui-p-add
make sim-rv32 TEST=rv32um-p-div
make sim-rv32 TEST=rv32mi-p-csr

# 套件
make sim-rv32 SUITE=rv32ui
make sim-rv32 SUITE=rv32um

# 全量发现
make sim-rv32-all
```

调试时可增加`TRACE=1`，修复后应关闭trace运行批量回归，避免波形I/O影响运行速度和磁盘空间。

### 5.3.3 测试结果解释

PASS表示tohost明确写1；FAIL表示写入失败码；TIMEOUT表示在给定周期内未结束。Zb测试必须与当前六个`CFG_ZB*`配置一致：关闭的扩展应在DUT中触发非法指令，不能拿关闭配置去要求扩展测试PASS；启用配置后必须重新编译DUT和DiffTest reference。

> **待补图 5-3：riscv-tests运行终端和JSON截图。** 截取一个PASS测试、一个故障注入DiffTest mismatch以及summary表，不要粘贴全部日志。

## 5.4 SRC类赛事性能测试

### 5.4.1 SRC程序特点

SRC不是单条指令测试，而是完整裸机程序。程序从`0x8000_0000`取指，使用`0x8010_0000` DRAM保存测试计数，通过`0x8020_xxxx`访问LED、SEG和counter。程序完成后通常写最终marker并进入死循环，不会像主机程序一样退出，因此Checker必须监测外设协议。

### 5.4.2 运行命令

```bash
# 500K短窗口，用于进度和IPC
make sim-src TEST=srcWithMext MAX_CYCLES=500000 NO_BUILD=1 OBJCACHE=

# 默认长窗口
make sim-src TEST=srcWithMext NO_BUILD=1 OBJCACHE=

# 指定SRC最大周期
make sim-src TEST=srcSmoke SRC_MAX_CYCLES=50000000 NO_BUILD=1 OBJCACHE=
```

短窗口TIMEOUT通常只是没有到最终marker，但仍需检查失败计数、最后LED/SEG、Commit进度和DiffTest。长窗口TIMEOUT在最终报告中不能算PASS。

### 5.4.3 性能采样

SRC结果记录Core cycles、Commit count、IPC、Branch、DCache和Memory统计。短窗口适合快速比较RTL改动，长窗口用于应用级结论。不同profile的代码结构、初始化数据和终止协议不同，IPC只能在说明测试和窗口后比较。

### 5.4.4 正确性观察点

`srcWithMext`重点观察：

- RV32I pass counter是否达到37；
- fail counter是否保持0；
- M扩展计数是否达到8；
- 右侧8个测试灯是否全部点亮；
- 是否出现PASS或FAIL marker；
- SEG低位计时是否与counter一致。

仅“计数达到37/8”表示前置测试已通过，不等于后续性能矩阵和最终收尾已经完成。

> **待补图 5-4：SRC程序与MMIO结束协议图。** 画出DRAM计数、Counter start/stop、SEG显示和LED最终marker。

## 5.5 DiffTest测试快速调试

### 5.5.1 DiffTest接入结构

当前DiffTest使用固定版本OpenXiangShan/difftest submodule生成的`DiffExt*` RTL探针、DPI-C入口和DiffStateBuffer数据包。提交包进入仓库的RV32 reference executor，参考模型独立执行同一条已提交指令并比较架构状态。

```text
DUT Commit
-> DiffExt probes
-> DPI / DiffStateBuffer
-> RV32 reference step
-> PC/instr/rd/wdata/exception compare
```

该方案不同于把DUT commit trace复制一份再自比较。JSON中的`reference_enabled=true`表示参考执行器确实参与比较。

### 5.5.2 使用命令

```bash
make sim-rv32-difftest TEST=rv32ui-p-lw NO_BUILD=1 DIFFTRACE=1
make sim-rv32-difftest TEST=rv32um-p-div NO_BUILD=1 DIFFTRACE=1
make sim-rv32-difftest SUITE=rv32mi NO_BUILD=1

make sim-src-difftest TEST=srcSmoke MAX_CYCLES=500000 NO_BUILD=1 DIFFTRACE=1
make sim-src-difftest TEST=srcWithMext MAX_CYCLES=500000 NO_BUILD=1 DIFFTRACE=1
```

### 5.5.3 mismatch解释

DiffTest在第一条架构分歧处停止，典型报告包含commit序号、PC、instruction、DUT值和REF值。例如故障注入后：

```text
commit #2: wdata DUT=0x00000001 REF=0x00000000
```

含义是第二条提交指令对同一个架构目的产生了不同写回值。它不一定说明RegFile本身错误，根因还可能是操作数版本、ALU、Load数据、旁路或Commit选择。调试应从该指令PC反汇编，向前追踪它的rs producer和对应transaction ID，而不是继续观察数万周期后的LED。

### 5.5.4 MMIO与非确定性跳过

计时器或外部输入具有非确定性。Reference无法天然得到与DUT同周期的值时，适配层可以对明确标记的MMIO提交进行skip/同步，但必须计数并写入JSON。普通DRAM和寄存器运算不能随意skip，否则DiffTest会失去意义。

### 5.5.5 推荐定位流程

1. 开启DIFFTRACE复现第一条mismatch；
2. 根据PC查看dump中的指令和前后依赖；
3. 确认DUT提交rd/wdata/异常与REF差异类型；
4. 使用transaction ID追踪allocate、producer query、Completion和Commit；
5. 若是Load，继续追踪地址、forward mask、DCache request/response；
6. 修复后先跑单项，再跑同类suite，最后跑SRC窗口；
7. 保留故障注入测试，确认DiffTest能重新准确报错。

DiffTest探针和per-transaction debug metadata只在`VERILATOR_TB`与`ENABLE_DIFFTEST`下存在，Vivado综合不包含这些逻辑。

> **待补图 5-5：DiffTest数据流图。** 必须明确DUT和Reference是两个独立执行状态，而不是两个DUT trace端口。

> **待补图 5-6：第一条mismatch调试截图。** 同屏放DiffTest日志、反汇编和波形中的transaction ID。

---

# 6. 仿真结果

> 本章结果来自当前`build/result`及归档JSON。最终提交前应重新运行目标配置的全量回归并替换日期、commit数和截图。不同Zb配置生成的历史文件不能合并为一次同时通过。

## 6.1 rv32ui测试结果

当前RV32I目录包含40项测试，覆盖整数算术、逻辑、移位、比较、LUI/AUIPC、条件分支、JAL/JALR、LB/LBU/LH/LHU/LW和SB/SH/SW，以及Load/Store组合场景。当前40项均写出`tohost=1`，结果为PASS。

代表性`rv32ui-p-add`结果：2080 cycles，510次Commit，IPC为0.245192。ISA定向测试包含启动、检查循环和tohost收尾，IPC不代表应用性能；其主要作用是验证语义和边界值。

| 测试组 | 数量 | PASS | FAIL | TIMEOUT |
|---|---:|---:|---:|---:|
| rv32ui | 40 | 40 | 0 | 0 |

> **待补图 6-1：RV32I测试结果矩阵。** 按算术、逻辑、控制流、Load、Store分类显示绿色PASS，不需要逐项粘贴40张终端截图。

## 6.2 rv32um测试结果

RV32M包含MUL、MULH、MULHSU、MULHU、DIV、DIVU、REM和REMU共8项，当前全部PASS。测试覆盖有符号/无符号、高半积、除零和溢出语义。

代表性`rv32um-p-div`结果：2080 cycles，141次Commit，IPC为0.0677885。较低IPC主要来自定向测试中连续除法和固定16拍DIV IP延迟，符合当前单owner MDU的预期。

| 测试组 | 数量 | PASS | FAIL | TIMEOUT |
|---|---:|---:|---:|---:|
| rv32um | 8 | 8 | 0 | 0 |

> **待补图 6-2：M扩展测试结果和MDU延迟图。** 左侧8项PASS，右侧画MUL与DIV不同response latency。

## 6.3 特权指令与异常测试结果

当前机器模式测试包括CSR、ECALL/EBREAK和Zicntr相关4项，全部PASS。`rv32mi-p-csr`代表性结果为2080 cycles、172次Commit；测试能够验证CSR读写、旧值返回和基本机器状态。

| 测试组 | 数量 | PASS | FAIL | TIMEOUT |
|---|---:|---:|---:|---:|
| rv32mi/CSR/Zicntr | 4 | 4 | 0 | 0 |

除了官方定向测试，建议最终报告加入自编异常序列：老Store后接非法指令、年轻ALU先完成、Load misaligned、JALR misaligned和MRET返回，以证明精确提交而非仅CSR读写。

> **待补图 6-3：Trap/MRET波形。** 标出commit exception、mepc/mcause/mtval更新、full_flush、redirect_target和mtvec取指。

## 6.4 DiffTest回归结果

当前基础有效配置中，RV32I 40项、RV32M 8项和Machine/CSR 4项均在DiffTest模式通过，即52项提交级比较未发现架构分歧。

`srcWithMext` 500000周期DiffTest窗口结果：

| 指标 | 数值 |
|---|---:|
| 状态 | TIMEOUT |
| DUT cycles | 500000 |
| Reference commits | 344974 |
| Non-deterministic/MMIO skips | 4 |
| Last commit PC | `0x80000e60` |
| Mismatch | 未报告 |

这说明窗口内所有未skip提交均与Reference一致，但程序尚未到达最终PASS marker，所以不能把该结果表述为“srcWithMext最终通过”。

当前六组Zb配置均为关闭状态，仓库中部分历史Zb DiffTest JSON来自不同构建配置，不能纳入当前52项基线统计。正式验证某个Zb组时，需要：启用对应`CFG_ZB*`、重建普通与DiffTest模型、只运行对应suite，并记录启用配置和结果日期。

> **待补图 6-4：DiffTest回归摘要。** 展示52/52基础项通过，以及SRC窗口344974次提交无mismatch；TIMEOUT必须使用中性颜色而不是绿色PASS。

## 6.5 src类赛方测试集结果

当前结果文件中的主要profile如下：

| Profile | Cycles | Commit | IPC | Branch hit | DCache hit | 当前状态 |
|---|---:|---:|---:|---:|---:|---|
| src0 | 50,000,000 | 39,073,706 | 0.781474 | 70.1781% | 98.8800% | TIMEOUT |
| src1 | 5,000,000 | 3,043,194 | 0.608639 | 66.3797% | 99.9964% | TIMEOUT |
| src2 | 500,000 | 335,703 | 0.671406 | 74.3988% | 98.6270% | TIMEOUT |
| srcSmoke | 500,000 | 285,895 | 0.571790 | 80.8990% | 99.9316% | TIMEOUT |
| srcWithMext | 500,000 | 345,025 | 0.690050 | 97.4050% | 99.9769% | TIMEOUT |
| srcWithoutMext | 200,000,000 | 133,804,558 | 0.669023 | 56.2921% | 61.6848% | TIMEOUT |

这些文件的周期窗口不同，只能描述各自运行快照，不能直接按Commit数排序性能。`srcWithoutMext`长窗口的DCache命中率显著低于其他短窗口，说明程序进入了不同工作阶段；也说明短窗口高命中率不能代表全程行为。

当前`srcWithMext`短窗口已经达到RV32I pass counter=37、fail counter=0和Mext count=8，但最终八灯和PASS marker尚未出现。最终提交版应运行足够长窗口，并按`lampseg` checker给出明确PASS/FAIL，而不是以TIMEOUT替代结论。

> **待补图 6-5：SRC结果表截图与进度灯解释图。** 对每个profile注明cycles和checker。

> **待补图 6-6：完整srcWithMext最终结果。** 待最终长回归后补充终端PASS、JSON correctness和LED/SEG最终状态。

## 6.6 IPC、停顿与缓存性能分析

### 6.6.1 IPC差异

当前单发射峰值IPC为1。`srcWithMext`短窗口IPC 0.690050，说明约69%的周期完成一条平均提交；剩余周期来自前端气泡、分支恢复、数据相关、Load/Store等待和长延迟执行。不同profile的IPC差异反映程序结构，而非单纯CPU版本差异。

### 6.6.2 分支影响

`srcWithMext`短窗口分支命中率97.405%，而`srcSmoke`为80.899%。GShare对具有稳定循环和全局相关性的工作负载效果明显；冷启动、间接跳转或短小控制流会降低平均命中。正式分析应按conditional/JAL/JALR分类计数，当前JSON部分breakdown仍为0，需后续完善统计来源。

### 6.6.3 DCache影响

短窗口DCache命中率普遍较高，但历史容量实验说明从8KiB到32KiB仍能提升IPC。`srcWithoutMext`长窗口命中率61.6848%，显示后续阶段可能具有更大工作集或冲突模式，需要结合miss address trace判断是容量、冲突还是访问阶段变化。

### 6.6.4 Stall解释注意事项

当前JSON仍保留部分旧架构字段名，如`rob_full_cycles`、`issue_queue_full_cycles`和宽度统计，但当前Core没有ROB/IQ/2-wide结构，这些字段为兼容输出且常为0，不能据此宣称“ROB从不满”或“2-wide issue利用率为0”。报告应优先使用当前有效的Frontend、Load return、Load access和Core内perf counter，并在后续更新JSON schema。

### 6.6.5 综合评价

当前优化结果表明，DCache容量和Load direct-start对IPC具有主要贡献；GShare对特定SRC阶段提供较高命中；Scoreboard和Completion bypass保证可变延迟结果不破坏精确提交。进一步提升性能的主要方向不是简单增加更多旁路，而是结合长窗口stall结构评估Frontend供给、Load-to-address等待、单owner MDU和单发射上限。

> **待补图 6-7：各profile IPC/Branch hit/DCache hit三联图。** 三张图使用独立纵轴，不要把百分比与IPC强行放到同一轴。

> **待补图 6-8：优化前后20M窗口性能对比。** 对比8KiB基线和32KiB+Direct Load，注明IPC提升24.5%。

---

# 7. 上板验证

## 7.1 平台介绍

### 7.1.1 硬件目标

正式工程目标器件为Kintex-7 `xc7k325tffg900-2`。外部200MHz差分时钟进入PLL，产生50MHz系统时钟和可配置CPU时钟。系统时钟驱动UART、Digital Twin和counter；CPU时钟驱动Core、IROM、DCache和SoC Memory Bridge相关逻辑。

### 7.1.2 工程生成

Vivado工程通过Tcl生成：

```bash
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

Profile决定IROM/DRAM COE。脚本从`fpga/coe/<profile>`优先查找，未找到时回退到`data/<profile>`。这种方式可以为上板保存独立初始化文件，而不修改仿真数据。

CPU频率可以通过环境变量覆盖：

```bash
FPGA_CPU_CLK_MHZ=150.000 \
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

SoC时钟默认保持50MHz，除非同步修改UART、counter和CDC约束。

### 7.1.3 板级接口

UART与Twin Controller实现Digital Twin虚拟输入输出；SW、KEY、LED、SEG和counter通过SocMemBridge映射到`0x8020_xxxx`。CPU程序读写这些地址，与Verilator SRC Checker观察的协议一致。

### 7.1.4 实现前检查

上板前必须检查：

1. `report_blackbox`为空；
2. `Core_cpu`、IROM、DRAM、MUL、DIV和PLL均正确实例化；
3. Vivado IP latency与RTL行为模型一致；
4. generated clock和CDC约束有效；
5. setup、hold和pulse-width满足目标频率；
6. COE profile与待验证程序一致；
7. Debug/DiffTest逻辑未进入综合；
8. Bitstream时间戳晚于最后RTL/IP修改。

> **待补图 7-1：FPGA上板系统框图。** 包含200MHz输入、PLL双时钟、CPU、IROM、DRAM、UART Twin和LED/SEG。

> **待补图 7-2：Vivado工程层次截图。** 展开到`top/student_top/myCPU/core_top`和主要IP，证明没有黑盒或错误裁剪。

## 7.2 验证结果

### 7.2.1 综合与资源结果

当前仓库没有与最终RTL一一对应、可直接引用的最终`report_utilization`。正式提交前请运行最终profile的综合与implementation，并填写下表：

| 资源 | 使用量 | 器件总量 | 利用率 |
|---|---:|---:|---:|
| LUT | `[待填写]` | `[待填写]` | `[待填写]` |
| LUTRAM | `[待填写]` | `[待填写]` | `[待填写]` |
| FF | `[待填写]` | `[待填写]` | `[待填写]` |
| BRAM36/18 | `[待填写]` | `[待填写]` | `[待填写]` |
| DSP | `[待填写]` | `[待填写]` | `[待填写]` |

资源分析应说明DCache、IROM/DRAM和BTB主要消耗BRAM，乘法器消耗DSP，Scoreboard/控制/旁路主要消耗LUT与FF。若资源异常偏低，应先检查黑盒、顶层和综合裁剪，而不是直接宣称资源优化成功。

### 7.2.2 时序结果

历史200MHz实验仍存在setup违例，不能作为最终可上板结论。最终报告应以最终RTL重新route后的结果填写：

| CPU频率 | Period | WNS | TNS | Setup失败端点 | Hold | 结论 |
|---:|---:|---:|---:|---:|---:|---|
| 50MHz | 20.000ns | `[待填写]` | `[待填写]` | `[待填写]` | `[待填写]` | `[待填写]` |
| 目标高频 | `[待填写]` | `[待填写]` | `[待填写]` | `[待填写]` | `[待填写]` | `[待填写]` |

只有WNS≥0、TNS=0且无hold/pulse-width严重问题时，才可以写“满足该频率时序”。如果200MHz不满足，可将50MHz或实测稳定频率作为正式上板频率，并把200MHz实验作为后续优化目标。

### 7.2.3 板级功能验证

建议按以下顺序验证：

1. 下载`srcSmoke` bitstream，确认PLL lock、reset释放和LED/SEG有活动；
2. 观察RV32I通过计数是否达到37；
3. 下载`srcWithMext`，观察M扩展计数是否达到8；
4. 检查八个测试灯和最终PASS/FAIL marker；
5. 对照SEG计时与counter；
6. 使用UART/Digital Twin读取虚拟输出；
7. 必要时运行post-implementation仿真检查BRAM请求/返回配对。

最终板级结论模板：

> 在`[日期]`生成的`[profile]` bitstream上，CPU工作频率为`[频率]`。上电复位后，LED显示`[数值/图案]`，SEG显示`[数值]`，RV32I计数为`[数值]`，M扩展计数为`[数值]`，最终marker为`[PASS/FAIL]`。连续运行`[时长]`未观察到异常复位或显示跳变。

在填写真实观测前，不应把该模板改成肯定语句。

### 7.2.4 仿真与上板一致性

若Verilator通过而上板失败，优先检查：

- IROM/DRAM IP实际read latency；
- BMG ENA与REGCEA；
- response valid、data和offset是否同事务；
- CPU/SoC时钟频率和reset同步释放；
- COE是否重新加载；
- implementation是否使用最新RTL；
- DCache miss refill连续地址返回是否错位。

历史板级调试曾出现连续DRAM读取返回前一地址word的问题，说明最终验证不能只看RTL仿真。建议对初始化为不同非零值的连续地址做post-route trace，逐项比较request address和response data。

> **待补图 7-3：Vivado Timing Summary截图。** 截图中必须同时显示目标clock、WNS/TNS和约束是否满足。

> **待补图 7-4：Vivado资源利用率图。** 使用最终implementation报告，不使用综合早期估算替代。

> **待补图 7-5：上板实物照片。** 照片中标注FPGA板、LED、SEG、UART连接和当前profile。

> **待补图 7-6：板级最终PASS显示。** 需要同时保留日期、bitstream/profile和CPU频率信息。

---

# 8. 总结展望

## 8.1 设计成果总结

本项目完成了从CPU RTL、SoC集成、Verilator验证、DiffTest调试到Vivado工程生成的一体化RV32处理器设计。处理器使用单发射、Scoreboard有限乱序完成和顺序提交架构，在不引入完整Rename/PRF/Issue Queue复杂度的情况下支持Fixed、Load和Slow多类可变延迟结果。

前端实现GShare、BTB和RAS；Issue端建立RegFile、Commit-WB、Scoreboard和Completion多级旁路；执行端支持RV32I、M和六组可配置Zb；访存端实现Store Buffer、Load Queue、Store Forwarding、Direct Load和32KiB DCache；提交端实现CSR、精确异常、MRET和恢复控制。

验证方面，RV32I 40项、RV32M 8项和Machine/CSR 4项定向测试通过。DiffTest已经使用真实参考执行器工作，能够在第一条错误提交处报告PC、instruction和DUT/REF差异。历史同口径优化将`srcWithMext` 20M窗口IPC从0.613611提升到0.764203，验证了DCache容量和Direct Load路径的效果。

工程方面，CPU、SoC和FPGA IP之间建立了filelist、地址映射、ready/valid和latency合同；仿真探针与综合逻辑隔离；Vivado工程可以按profile生成。报告也明确保留了最终SRC应用PASS、最终implementation时序/资源和实板结果的待验证边界。

## 8.2 当前设计限制

1. **单发射上限。** 峰值IPC不超过1，ID RAW或FU busy会阻止年轻独立指令绕过。
2. **不是真正完整乱序核。** 没有物理寄存器重命名、多候选Issue Queue和多提交。
3. **MDU/Bitmanip并发有限。** 单owner MDU及共享slow completion限制长延迟吞吐。
4. **Load-to-address停顿。** 为切断关键路径，Load结果不能同拍直达下一条AGU。
5. **DCache为直接映射、write-through。** 冲突miss和Store外部带宽仍可能成为长窗口瓶颈。
6. **访存outstanding有限。** DCache/SoC接口没有多ID和乱序返回，miss处理串行。
7. **特权能力有限。** 仅Machine-mode子集，没有中断、虚拟存储、用户/监管模式。
8. **Zb为综合期配置。** 现场切换需要修改配置并重新综合，不支持运行时动态开关。
9. **性能JSON存在旧字段。** ROB/IQ/2-wide兼容字段需要迁移到当前Scoreboard架构语义。
10. **最终板级证据待补。** 当前仓库没有与最终RTL完全对应的可信资源、时序和最终PASS照片。

## 8.3 后续优化方向

### 8.3.1 短期工作

1. 完成最终`srcWithMext`长窗口普通与DiffTest回归；
2. 在每个Zb配置下重建DUT/reference并运行对应suite；
3. 重新生成Vivado工程，导出最终utilization和timing summary；
4. 在50MHz完成稳定上板，再逐步提高CPU频率；
5. 清理JSON旧ROB/IQ字段，加入当前Scoreboard、RAW、FU busy和Load-to-address计数；
6. 增加异常、WAW、Store flush和late response定向测试。

### 8.3.2 中期微架构优化

1. 为独立整数指令增加小型解耦Issue buffer，使其可以绕过等待长延迟FU的ID指令；
2. 将MDU和Bitmanip completion端口解耦，或允许多个非迭代操作流水化；
3. 评估2-way set associative DCache降低长窗口冲突miss；
4. 为Store drain和Load仲裁加入公平性/带宽统计；
5. 在不重建Load response长路径的前提下研究两级AGU或地址预测；
6. 进一步缩短Scoreboard dynamic-index result mux和Issue高扇出控制。

### 8.3.3 长期架构演进

若未来目标明确要求IPC超过1，可以在当前精确提交和transaction ID基础上逐步引入：多条Decode/Dispatch、小型Issue Queue、寄存器重命名、物理RegFile、多发射仲裁和多提交。该演进必须同时扩展Store顺序、异常恢复、DiffTest提交宽度和SoC带宽，不应只把前端或ALU复制为两份。

> **待补图 8-1：后续演进路线图。** 从当前单发射Scoreboard Core依次指向解耦Issue、Rename/PRF、2-wide Issue/Commit，并标出每一步新增验证责任。

---

# 参考文献

[1] RISC-V International, *The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA*.

[2] RISC-V International, *The RISC-V Instruction Set Manual, Volume II: Privileged Architecture*.

[3] RISC-V International, *RISC-V Bit-Manipulation ISA Extensions*.

[4] David A. Patterson, John L. Hennessy, *Computer Organization and Design: The Hardware/Software Interface, RISC-V Edition*.

[5] John L. Hennessy, David A. Patterson, *Computer Architecture: A Quantitative Approach*.

[6] James E. Smith, Gurindar S. Sohi, “The Microarchitecture of Superscalar Processors,” *Proceedings of the IEEE*.

[7] AMD/Xilinx, *7 Series FPGAs Data Sheet: Overview (DS180)*.

[8] AMD/Xilinx, *Vivado Design Suite User Guide: Synthesis (UG901)*.

[9] AMD/Xilinx, *Vivado Design Suite User Guide: Design Analysis and Closure Techniques (UG906)*.

[10] AMD/Xilinx, *Block Memory Generator v8.4 Product Guide (PG058)*.

[11] Verilator Project, *Verilator User Guide*.

[12] OpenXiangShan, *difftest*, GitHub open-source project.

[13] RISC-V Software Source, *riscv-tests*, GitHub open-source project.

> 正式提交时请按学校/竞赛指定格式补充版本号、访问日期、URL和引用页码，并在正文对应段落插入编号引用。

---

# 附录建议

正文不建议放入大段日志和完整Timing Report。可在最终文档增加：

- 附录A：完整指令支持与测试矩阵；
- 附录B：Make/Verilator/DiffTest命令速查；
- 附录C：SRC profile与PASS/FAIL协议；
- 附录D：最终Vivado资源和时序报告；
- 附录E：关键SystemVerilog模块清单；
- 附录F：故障注入与第一条DiffTest mismatch案例。
