# NOP-Core → superScalar 适配方案确认

> 日期：2026-07-09
> 目标：将 NOP-Core 的乱序多发射微架构移植到 superScalar 项目的 `rtl/core/`
> 约束：`rtl/ip/`、`rtl/soc/`、TCL 不能重构，只允许有限延迟拍数等接口适配修改

## 2026-07-09 用户已确认决策

| 编号 | 决策 |
|---|---|
| A1 | 不做 ICache；可修改/适配 IROM BRAM IP 为双端口，用双读端口实现 2-way/2 路取指。 |
| A2 | DRAM/DCache 时序按 `docs/fpga/ip_timing_alignment.md`；目标 DRAM 读返回按固定 2 拍合同维护。 |
| A3 | DRAM/cacheable 范围保持 `0x8010_0000 ~ 0x8014_0000`，适配当前 superScalar SoC/MMIO。 |
| B1 | 按建议：第一版 2 宽。 |
| B2 | 按建议：ROB/IQ/StoreBuffer 深度先沿用 NOP-Core 量级，后续按资源和 timing 调参。 |
| B3/B4 | 目标分支预测器为参数化的全局/局部竞争历史预测器：GShare、5-bit 历史、512 项 PHT、256 项 BTB、8 项 RAS。 |
| C1 | 覆盖 `rv32ui/rv32um/rv32mi/ecall/ebreak/fence/mret`，先不做 Zb。 |
| C2 | 不需要虚实地址转换，不做 MMU/TLB。 |
| D1 | MUL 先保持 3 拍，后续可调。 |
| D2 | 按建议：保留 `DIV_0` IP，适配握手。 |
| E1 | 按建议：采用写回写分配 DCache。 |
| F1 | 按建议：保留 StoreBuffer，store 顺序提交后才写内存。 |
| G1 | 手写 SystemVerilog。 |

## 新增待确认项

这些问题来自对 `resource/NOP-Core/` 源码的进一步阅读：

1. BPU 的“512 项 PHT”是总预算，还是 global/local/choice 各 512 项？建议第一版先实现 `GShare 512 + BTB 256 + RAS 8`，local/choice 预留参数，确认资源口径后再打开。
2. DCache line size 是否接受第一版从 16B 起步？NOP-Core 原版是 64B line，但它有 AXI burst；当前 superScalar SoC 是单 DMEM req/resp，16B 更利于上板和时序。
3. load speculative wakeup 是否第一版关闭？建议关闭，按真实 load WB/forwarding 唤醒，等 DCache/StoreBuffer 正确性稳定后再做 NOP-Core 风格提前唤醒与失败恢复。
4. IROM 双读端口实现方式：Vivado 是否直接生成 true dual-port ROM，还是复制两份同内容 ROM？如果 BRAM 资源允许，复制 ROM 的时序和端口适配更简单。

以下原始问题保留为设计讨论记录；当前有效结论以上面的“用户已确认决策”和“新增待确认项”为准。

---

## A. 接口适配（最高优先级，影响 SoC 边界）

### A1. 指令存储器接口：IROM 直连 vs 加 ICache

**现状**：`myCPU.sv` 的 `irom_addr/data/ena` 直连 `IROM_0` IP，单拍延迟，宽度32bit（一次取一条指令）。

**NOP-Core 方案**：有完整 ICache（8KB 2-way SA），通过 AXI4 `iBus` 向外请求填充。

**问题**：你希望如何处理取指端？

- **选项 A**：保留 IROM 直连，不加 ICache。取指每拍固定返回一条指令，fetchWidth 退化为1。这大幅简化前端，但损失了 burst 取指的效益。
- **选项 B**：在 `rtl/core/` 内加 ICache，通过 DMEM 接口（或新增一路接口）向 IROM 做 burst 填充。需确认 IROM_0 是否支持连续地址读或 burst。
- **选项 C**：取指仍单拍取一条，但加 FetchBuffer 解耦，配合分支预测做预取（伪 ICache 效果）。

> **我的建议**：选项 A 或 C。IROM 是片上 BRAM，单拍延迟，miss 不会是瓶颈；加真 ICache 需要改 IROM_0 接口或绕过它用 AXI，代价高。

**历史问题：已确认不做 ICache，改双端口 IROM 支持 2 路取指。**

---

### A2. 数据存储器接口：DMEM req/resp → DRAM 延迟拍数确认

**现状**：`myCPU.sv` 的数据存储器接口为自定义握手：
```
dmem_req_valid, dmem_req_addr, dmem_req_wdata, dmem_req_wstrb, dmem_req_ready
dmem_resp_valid, dmem_resp_rdata
```
`DramBramAdapter.sv` / `dram_driver.sv` 负责对接 `DRAM_0` IP。

**你已说明**：DRAM IP 可以改为 **2拍返回数据**（即发出请求后2拍 `resp_valid` 拉高）。

**问题**：DCache 设计需要精确知道 DRAM 每次 burst 传输的延迟模型：

| 场景 | 延迟 |
|---|---|
| DCache hit（load） | 1拍（MEM2 出结果）|
| DCache miss，DRAM 首个 word 返回 | 2拍（DRAM latency） |
| DCache miss，整行（4 words）填充 | 2 + 3 = 5拍（首word2拍，后续3个+1） |
| Store（写 DRAM，异步写回） | 不阻塞流水线 |

**请确认以下几点**：
1. DRAM_0 是否支持 burst 读（连续地址每拍一个 word）？还是每次只能单 word 请求？
2. 改为2拍后，是 `req→resp` 固定2拍，还是带背压（ready 可拉低）？
3. 你提到 `miss 也是三拍`——具体含义是：DCache miss 时从 DRAM 首次拿到数据用3拍（1拍DRAM req + 2拍DRAM resp），还是 DCache hit latency = 3拍（MEMADDR+MEM1+MEM2）？

> **我的理解**：你的意思是 DCache hit = 1拍（MEM2），DRAM latency = 2拍，miss 首词返回 = 3拍（MEM2触发+2拍DRAM），这与 NOP-Core DCache 设计完全一致，可以直接对应。请确认。

---

### A3. DRAM 地址空间与 Cached/Uncached 划分

**现状**：DCache 的 cacheable 地址窗口硬编码为 `0x8010_0000 ~ 0x8014_0000`（256KB）。

**NOP-Core 方案**：通过 DMW（直接映射窗口）寄存器划分 cached/uncached，软件可配置。

**问题**：
1. 新的 DCache cacheable 范围应覆盖多大的 DRAM？（当前 DRAM 大小是多少？）
2. 是否保留硬编码方式（简单但不灵活），还是用 CSR DMW（需要增加 CSR）？
3. SOC 中外设（UART、计数器、七段显示）的 MMIO 地址范围是什么？需确保它们走 uncached 路径。

> **我的建议**：保留硬编码方式，只需将 cache 范围改为覆盖整个 DRAM。外设 MMIO 地址不在 DRAM 范围内，自然走 uncached。

---

## B. 微架构参数（影响资源与性能，需你确认偏好）

### B1. 流水线宽度（发射宽度）

NOP-Core 的3宽度解码/派遣，加上3个 INT pipeline，是其 IPC 达到1.02的关键。

**问题**：你希望目标实现为几宽度？

- **2宽度**：2路解码/重命名，Int×2 + MulDiv×1 + Mem×1，资源消耗较小，实现复杂度低
- **3宽度**：对齐 NOP-Core，Int×3 + MulDiv×1 + Mem×1，最大 IPC 接近原版

> **我的建议**：从2宽度起步更稳健，关键路径（乱序核本身）比宽度更影响 IPC；NSCSCC 2025 分数主要看绝对频率×IPC，2宽度+高频 vs 3宽度+低频需要取舍。

**历史问题：已确认第一版按建议采用 2 宽。**

---

### B2. ROB 深度与发射队列深度

NOP-Core：ROB=32，Int IQ=7，MulDiv IQ=3，Mem IQ=5，StoreBuffer=8。

这些参数直接影响 BRAM/寄存器资源用量。在 FPGA 上深度越大越消耗 LUT/FF，但过小会降低 IPC。

**问题**：是否沿用 NOP-Core 的参数，还是缩减？（例如 ROB=16，Int IQ=4，StoreBuffer=4）

> **我的建议**：先照搬 NOP-Core 参数，跑通后再根据时序和资源报告调整。这些参数都是 localParam，修改代价低。

---

### B3. 物理寄存器数量

NOP-Core：63个物理寄存器（32架构寄存器 + 31额外）。

额外物理寄存器越多，能同时 in-flight 的重命名指令越多，乱序窗口越大。但 RegFile 读写口数量也随之增加（每条指令需要2个读口、1个写口）。

**问题**：是否沿用63个，或调整？

> **我的建议**：沿用63个，与 ROB 深度（32）匹配（最坏情况每条指令都写1个新寄存器，32条 in-flight 需要32个额外）。

---

### B4. 分支预测器复杂度

NOP-Core 源码事实：global correlating predictor（5bit GHR，8192项PHT，索引用 `GHR @@ PC` 拼接）+ 1024项BTB + 8项RAS；不是 local/global tournament。
当前实现：64项直接映射 BTB，无方向预测。

**问题**：是否需要完整的全局历史预测器？还是只用 BTB（预测"跳/不跳"用静态/2bit计数器）？

- RAS（8项）对 CALL/RET 密集的测试程序有显著效果，建议保留
- GShare 对于 NSCSCC 测试程序可能提升有限（程序规模小，BTB+2bit 计数器足够）

**历史问题：已确认实现参数化 BPU；新增待确认项只剩 512 项 PHT 的资源口径。**

---

## C. ISA 适配（必须确认）

### C1. 指令集

NOP-Core 实现 LA32R，superScalar 实现 **RISC-V RV32IMZB**（从 build/ 目录的测试集可确认）。

所有解码逻辑、ALU操作码、CSR 地址、异常原因码都需要从 LA32R 转换为 RISC-V 规范。

这部分是翻译工作，不影响微架构结构，但工作量最大。

**历史问题：已确认第一版覆盖 RV32I/M/MI 和 ecall/ebreak/fence/mret，先不做 Zb。**

---

### C2. CSR 子集

当前实现有5个 CSR（mstatus, mtvec, mscratch, mepc, mcause），支持 M-mode 陷阱处理。

NOP-Core 支持完整 LA32R 特权，包括 TLB/MMU（用于虚实地址转换，启动 Linux）。

**问题**：我们是否需要 MMU/TLB？

> **我的判断**：NSCSCC 2025（RISC-V赛道）通常不要求 MMU，测试程序使用物理地址。建议只实现 M-mode CSR，省去 TLB 和虚实地址转换逻辑，大幅降低实现复杂度。

**历史问题：已确认不需要 MMU/TLB/虚实地址转换。**

---

## D. MulDiv 单元适配

### D1. 乘法器（MUL_0 IP）

**现状**：Xilinx `MUL_0` IP，33bit×33bit → 66bit，3拍延迟（MulDivUnit.sv 中 `mul_count_q` 从2倒数）。

**NOP-Core**：Xilinx `multiplier.xci`，2拍延迟，`MulDivConfig.multiplyLatency = 2`。

**问题**：你是否可以将 `MUL_0` IP 配置改为2拍延迟？还是保持3拍，在 MulDiv pipeline 中等待3拍？

> **注意**：这是 IP 层的有限修改，完全合理。如果能改为2拍，MulDiv IQ 深度要求可以降低。

**历史问题：已确认 MUL_0 第一版保持 3 拍，后续可调。**

---

### D2. 除法器（DIV_0 IP）

**现状**：Xilinx `DIV_0` AXI-stream IP，可变延迟，32bit÷32bit。

**NOP-Core**：软件实现的早出除法（earlyOut width=16，不依赖 IP）。

**问题**：是否保留 `DIV_0` IP（接口已稳定，改动最小），还是换成软件迭代除法（更灵活，可控延迟）？

> **我的建议**：保留 `DIV_0` IP，仅适配 AXI-stream 握手接口，与 MulDiv pipeline 的握手信号对接即可。

---

## E. DCache 写策略

### E1. 写策略：写穿透 vs 写回写分配

**现状**：DCache 写穿透（store hit 不写 cache，直接写 DRAM，同时 invalidate cacheline）。

**NOP-Core**：写回写分配（store miss 先填充 cache line，写 cache；写回 DRAM 在替换时发生）。

写回写分配需要：
1. dirty bit 管理
2. 替换时先写回脏行（writeback FSM）
3. StoreBuffer + 提交后延迟写

**问题**：是否采用写回写分配策略（与 NOP-Core 一致）？

> **我的判断**：强烈建议写回写分配。写穿透在 store 密集的程序（如矩阵运算）中会频繁向 DRAM 发请求，严重影响性能。而 NSCSCC 性能测试中 store 比例不低。代价是 dirty bit + writeback FSM，约增加 100-200 行 RTL。

---

## F. Store Buffer

### F1. StoreBuffer 与 commit 的关系

NOP-Core 的 StoreBuffer：
- Store 在 MEM2 级入队（`retired=False`）
- Commit 时将对应条目标记 `retired=True`
- StoreBufferPlugin 后台异步将 retired 条目写入 cache 或 uncached 总线
- Load 需要查询 StoreBuffer（地址匹配则前传）

**问题**：是否采用与 NOP-Core 相同的 StoreBuffer 设计（乱序 store 入队，顺序提交后写内存）？

> **我的判断**：必须保留。这是 OoO 处理器实现精确异常的基础：store 在提交前不能改变内存状态。

---

## G. 实现方式

### G1. SpinalHDL 生成 vs 手写 SystemVerilog

NOP-Core 是 Scala/SpinalHDL 项目，生成 `mycpu_top.v`。superScalar 使用 SystemVerilog。

**方案一**：运行 `sbt run` 生成 NOP-Core 的 `mycpu_top.v`，作为架构参考，在 superScalar 中手写 SV 对应模块。
**方案二**（不推荐）：尝试直接移植 SpinalHDL 工具链进来。

> **我的判断**：方案一。手写 SV 是唯一可行路线，既保持与现有项目的一致性，也便于调试和适配。NOP-Core 的 Scala 代码用作设计参考，而非直接复用。

**历史问题：已确认手写 SystemVerilog。**

---

## 总结：需要你回答的关键问题

| # | 问题 | 影响范围 |
|---|---|---|
| A1 | 取指：保留 IROM 直连（选 A/C），还是加 ICache？ | 前端复杂度，取指带宽 |
| A2 | DRAM 2拍延迟确认：burst 支持？背压信号？miss=3拍含义？ | DCache 状态机设计 |
| A3 | DRAM 总大小？外设 MMIO 地址范围？ | Cached/Uncached 地址划分 |
| B1 | 目标发射宽度：2路还是3路？ | 整体资源与 IPC 权衡 |
| B4 | BPU：完整 GShare+BTB+RAS，还是简化 BTB+2bit+RAS？ | 前端复杂度，分支预测率 |
| C1 | 确认指令集：RV32I+M+Zba+Zbb+Zbc+Zbk+Zbs（含 B扩展）？ | 解码器设计 |
| C2 | 是否需要 MMU/TLB？ | 特权实现复杂度 |
| D1 | MUL_0 改为2拍延迟？还是保持3拍？ | MulDiv pipeline 设计 |
| E1 | DCache 写回写分配（推荐）？还是保持写穿透？ | DCache 复杂度，store 性能 |

---

## 附：不需要确认的部分（已有结论）

- ROB 深度、发射队列深度、物理寄存器数量：先照搬 NOP-Core 参数，后续再调
- DIV_0 IP 保留，适配握手接口
- CSR 实现 M-mode（mstatus, mtvec, mscratch, mepc, mcause, mie, mip 等），不实现 TLB（待 C2 确认）
- StoreBuffer 采用乱序入队、顺序提交后写的设计
- 手写 SystemVerilog 实现，以 NOP-Core 为架构参考
- `rtl/ip/`、`rtl/soc/`、TCL 不重构，仅修改延迟相关参数
