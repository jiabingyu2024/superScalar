# Vivado implementation 与 FPGA 上板优化计划

日期：2026-07-10  
目标器件：`xc7k325tffg900-2`  
工具基线：Vivado 2023.2  
工程：`fpga/build/digital_twin_srcWithMext/digital_twin.xpr`

## 1. 计划目标

本轮先解决综合、约束和 implementation 不稳定问题，获得一份约束可信、可重复完成 route、可生成 bitstream 的基线；随后再围绕资源、时序、复位、CDC 和存储推断做 FPGA 友好优化。

本文件只制定实施方案，不在本阶段修改 RTL、XDC 或 Vivado 工程行为。

## 2. 当前事实与初步根因

### 2.1 `Synth 8-5413` 不是单个寄存器问题

`rtl/core/backend/CoreBackend.sv:367-393` 使用：

```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst || clear_i || recover_i) begin
        ...
```

敏感表只声明 `rst` 为异步控制，但首层复位条件又混入同步的 `clear_i/recover_i`。Vivado 因而对整个 completion bundle 推导出同步/异步控制混用。日志实际包含 `complete_valid`、ROB index、PRD、result、exception、redirect、CSR 信息等全部 completion 寄存器，以及 `serial_inflight_q`，不是只影响报错文本中的 `complete_valid_reg`。

同类结构还存在于 `Rat.sv`、`FreeList.sv`、`BusyTable.sv`、`ROB.sv`、`CompressedQueue.sv` 及多个 common FIFO/pipe 模块。只修 `CoreBackend` 会留下同类综合风险。

### 2.2 输入时钟被重复创建

`pll.xdc`/`pll_in_context.xdc` 已经在 PLL 输入端创建 5 ns 主时钟，并在顶层作用到 `i_sys_clk_p`。`fpga/digital_twin.xdc:12` 又执行：

```tcl
create_clock -name sys_clk_p -period 5.000 [get_ports i_sys_clk_p]
```

后读入的用户时钟覆盖 IP 时钟，导致 `Constraints 18-1055/1056`，并使引用旧时钟对象的派生约束可能失效。当前工程必须明确唯一时钟约束所有者，不能保留两个同周期定义。

### 2.3 CDC 约束在综合阶段引用了尚不存在的生成时钟

`digital_twin_cdc.xdc` 在综合和实现阶段都启用。综合读取顶层时，PLL 仍作为 OOC black box，`clk_out1_pll/clk_out2_pll` 尚未形成有效 clock object，于是 `set_clock_groups` 报 `Vivado 12-4739`。实现 `link_design` 读入 PLL DCP 后，同一约束可以解析。

因此该文件应是 implementation-only、processing order late 的约束，而不是在综合阶段容忍失败。

### 2.4 当前 implementation 的实际致命点是 Vivado 崩溃

当前 `impl_1/runme.log` 显示：

- `link_design` 成功；
- 初始 DRC 为 0 errors；
- `opt_design` 完成；
- 在 `power_opt_design` 的高扇入/高扇出分析后出现 `HACOOException`；
- 随后 Vivado 2023.2 以 `EXCEPTION_ACCESS_VIOLATION` 异常退出。

当前源码 Tcl 已把 `FPGA_ENABLE_POWER_OPT` 默认设为 `false`，但现有 build 明显仍执行了 power optimization，说明构建目录可能来自旧工程配置或 GUI 中的运行属性未同步。必须用全新工程验证配置，而不能继续复用该 run 状态。

### 2.5 资源结构不利于 FPGA

现有综合层次报告的顶层资源为：

| 指标 | 使用量 | 占器件比例 |
| --- | ---: | ---: |
| Slice LUT | 129,023 | 63.31% |
| Slice Register | 111,371 | 27.32% |
| LUTRAM/SRL | 0 | 0% |

主要层次热点：

| 模块 | LUT | FF | 主要风险 |
| --- | ---: | ---: | --- |
| `CoreDCache` | 49,520 | 71,570 | cache data/tag 全部成为 FF/LUT，未推断 BRAM/LUTRAM |
| `CoreROB` | 20,866 | 8,835 | 多端口随机访问、整表复位和宽 entry |
| `CoreBranchPredictor` | 18,938 | 20,489 | BHT/BTB/PHT 全数组异步复位，双 lane 组合读取 |
| `CoreIntIssueQueue` | 10,221 | 2,472 | 全表压缩、全表 wakeup/选择组合网络 |
| `CorePhysRegFile` | 9,276 | 2,016 | 多组合读口、多写口复制/选择网络 |

`CoreDCache` 当前 2 way、128 set、每行 8 word，data array 容量约 32 KiB，但没有推断片上 RAM，这是当前功耗、布局和实现稳定性的首要结构性问题。顶层报告中的 BRAM/DSP 为 0 还受到 OOC IP 作为 black box 的影响，最终资源必须在 link/placed design 后重新统计。

## 3. 实施原则

1. 先修正确性和约束可信度，再比较 QoR；不在错误约束上做时序优化。
2. 每一阶段使用全新 build 名称，禁止旧 DCP/XCI/run 状态污染结论。
3. RTL 优化必须保持 Verilator 功能基线；板级优化不能只以“Vivado 能跑完”为完成标准。
4. CDC false path 只能覆盖已验证的同步器/握手/Gray 路径，不能用来隐藏普通跨域组合采样。
5. 资源优化按“DCache -> BPU/ROB -> Issue Queue/PRF”排序，避免同时重写多个核心结构。
6. WSL 下禁止把全量 `srcWithMext` 作为日常回归：正确性以 RV32 测试集为主，`srcSmoke` 按改动风险跑部分或全量，`srcWithMext` 只跑小窗口 difftest，确认程序仍能正常取指、执行、提交和访问内存。
7. 不由本计划执行者直接启动耗时的 Vivado 综合、布局布线或 bitstream 长任务。执行者负责修改 RTL/Tcl/XDC、生成检查命令和说明预期产物；由用户决定何时启动 Vivado，完成后再读取日志、DCP 和报告继续分析。

### 3.1 仿真分层策略

| 层级 | 使用场景 | 默认范围 |
| --- | --- | --- |
| RTL 定向测试 | reset/clear/recover、CDC wrapper、DCache/BPU/ROB/IQ 等局部改动 | 受影响模块的短测试 |
| RV32 测试集 | 每次 RTL 功能回归的主要判据 | `rv32ui`、`rv32um`、`rv32mi`；按改动影响至少运行相关集合，阶段收口时运行全部 |
| `srcSmoke` | SoC 集成、memory/MMIO、较长控制流检查 | 开发中跑相关片段或短窗口，阶段收口时按需要跑全量 |
| `srcWithMext` difftest | 检查长程序早期是否正常执行 | 只跑小量指令/周期窗口，检查 PC、commit、访存和差分一致性，不等待最终灯码 |
| 全量 `srcWithMext` | 最终候选版本的人工验收 | 默认不运行；仅由用户明确安排 |

小窗口 difftest 的周期数/commit 数不在计划中写死，应根据当前仿真速度选择一个能覆盖启动、IROM/DRAM、分支和 M 扩展早期行为的窗口，并在归档中记录实际参数。

### 3.2 Vivado 长任务协作边界

1. 修改完成后只做快速静态检查、Tcl/XDC 文本检查和已有报告分析，不擅自调用 `launch_runs`、`synth_design`、`place_design`、`route_design` 或 `write_bitstream`。
2. 每个 Vivado 阶段提供一组可复制执行的命令、工程目录、预计产物和停止点；用户运行后提供或保留 `runme.log`、`.dcp`、timing/utilization/CDC/DRC 报告。
3. 优先支持从 checkpoint 分段运行，避免一次失败后重复全部综合和实现。
4. 没有新 Vivado 运行证据时，只能声明“静态修改完成/等待用户运行”，不能声明综合、时序或上板通过。

## 4. 分阶段执行计划

### Phase 0：冻结证据与建立可复现入口

1. 归档当前 `synth_1/impl_1` 日志、XDC 加载顺序、XPR run 属性、崩溃日志和层次利用率报告。
2. 在 Tcl 中打印并归档 `report_clocks`、`report_clock_interaction`、约束文件的 `USED_IN_*`/`PROCESSING_ORDER` 和 impl step enable 状态。
3. 固定输入条件：memory profile、PLL 输入/输出频率、part、Vivado 版本、并行 job 数和环境变量。
4. 为新基线使用独立工程目录，例如 `digital_twin_srcWithMext_implfix_p0`。
5. 准备工程生成、综合、实现和报告导出的分段命令，但不直接启动 Vivado 长任务。

完成门槛：工程生成和分段运行入口明确，命令能打印实际 run 属性；Vivado 执行结果由用户运行后补充。

### Phase 1：修复同步/异步控制混用

1. 将 `CoreBackend` 两个相关时序块改为明确的两级优先级：

```systemverilog
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        ...
    end else if (clear_i || recover_i) begin
        ...
    end else begin
        ...
    end
end
```

2. 扫描全部 `always_ff @(posedge clk or posedge rst)` 中的 `if (rst || clear_i...)`，按信号语义逐个拆分。`clear_i/recover_i/flush` 默认作为同步控制，不加入异步敏感表。
3. 对 completion bundle、ROB/IQ/FIFO 指针和 valid 位补充 recovery/clear 定向测试，确认拆分后优先级与旧仿真意图一致。
4. 第一轮仅做等价结构修复；第二轮再评估把大范围 payload reset 移除，只复位 valid/head/tail/state。未被 valid 标记的数据不要求复位，可减少 FDCE/FDPE、控制集和 reset fanout。
5. 回归先跑相关 RV32 集合，随后按需要跑 `srcSmoke`；`srcWithMext` 仅跑小窗口 difftest，不运行全量。

完成门槛：reset/clear/recover 定向测试和相关 RV32 集合通过，`srcSmoke` 达到本阶段约定范围，`srcWithMext` 小窗口 difftest 无早期偏差；`Synth 8-5413` 是否归零由用户完成下一次 Vivado 综合后确认。

### Phase 2：统一时钟约束所有权

1. 从 `fpga/digital_twin.xdc` 移除重复 `create_clock`，保留引脚和 I/O standard；由 Clocking Wizard 生成的 XDC 作为 `i_sys_clk_p` 唯一主时钟定义。
2. 若后续决定改为用户 XDC 统一拥有主时钟，则必须同时禁用 IP 的重复定义，不能用 `-add` 或改名掩盖冲突。本轮优先采用删除用户重复定义的低风险方案。
3. 在实现 link 后记录真实 clock object、source pin、period 和 waveform，确认 50 MHz/CPU 两个输出频率与 Tcl 参数一致。
4. 加约束回归检查：`check_timing -verbose` 中 no_clock、multiple_clock、unconstrained endpoints 均必须审阅并归零或有明确豁免。

完成门槛：`Constraints 18-1055/1056` 为 0；输入主时钟只有一个；所有预期时序端点均被正确时钟覆盖。

### Phase 3：修正 CDC 约束加载阶段并复核 CDC 设计

1. 对生成的 `digital_twin_cdc.xdc` 设置：
   - `USED_IN_SYNTHESIS false`
   - `USED_IN_IMPLEMENTATION true`
   - `PROCESSING_ORDER LATE`
2. 在 post-link/implementation checkpoint 查询并确认 `clk_out1_pll`、`clk_out2_pll` 存在，再应用 `set_clock_groups -asynchronous`。不要在 XDC 内放 `if/else`；存在性检查和生成逻辑放在项目 Tcl/检查 Tcl 中。
3. 运行 `report_cdc` 和 `report_clock_interaction`，逐条核对：reset deassert 同步、switch/key 双触发器、counter Gray code、LED/SEG snapshot，以及 CPU/50 MHz 域之间所有控制/数据路径。
4. 对多位数据禁止逐 bit 同步后直接拼接；使用 Gray、稳定数据+握手或 snapshot toggle。只有结构已经正确的跨域路径才允许被 async clock group 截断。

完成门槛：综合阶段不再报 `Vivado 12-4739`；实现阶段两个 clock group 均为非空；CDC 报告无未解释的 critical/unknown crossing。

### Phase 4：恢复稳定的 implementation 基线

1. 删除或换名生成工程，准备重新执行 `create_vivado_project.tcl` 的命令，并在新 XPR 中检查两个 power-opt step 应为 disabled。
2. 向用户提供基线运行命令：跳过 `power_opt_design` 和 post-place power opt，按 `opt -> place -> phys_opt -> route -> bitstream` 分段执行。计划执行者不直接启动这些长任务。
3. 用户运行后若仍异常退出，再建议将 job 数降至 4/2，关闭增量结果复用，并从最近成功 checkpoint 分阶段继续，以区分内存压力、工具缺陷与网表问题。
4. 路由后固定生成：timing summary、utilization hierarchical、clock utilization、high fanout nets、control sets、methodology、DRC、CDC、clock interaction 和 power report。
5. 只有无 power-opt 基线稳定后，才在独立 run 中单独重新启用 power opt；若 Vivado 2023.2 稳定复现崩溃，则保持关闭并记录为工具限制，不把它作为 bitstream 门槛。

完成门槛分为两级：修改侧完成门槛是工程配置、分段命令和报告脚本准备完毕；最终门槛由用户运行结果确认，即 clean build 完成 route/bitstream、0 error、0 未豁免 critical warning，且 bitstream 时间戳与当前 RTL/XDC/IP 一致。若需要重复性确认，由用户安排第二次 clean build，不默认执行。

### Phase 5：DCache RAM 化，优先降低 49k LUT/71k FF

1. 将 data/tag/valid/dirty 拆分存储，避免整组数组异步复位。data array 不复位；reset 只清 valid/dirty 或使用初始化扫描 FSM。
2. 把组合命中返回改造成与同步 RAM 读延迟匹配的 pipeline，分别处理 lookup、hit/miss 判定、store byte merge、victim read 和 refill/writeback。
3. 优先验证 2-way banked BRAM：每 way 独立 data bank，tag/metadata 使用 LUTRAM/BRAM 或小寄存器阵列。通过 byte write enable 或 read-modify-write保持 store mask 语义。
4. 保持 `critical-word-first`、uncached 请求、dirty writeback 和现有 memory bridge 协议；若 RAM 化增加 hit latency，必须同步修改性能计数和上游 ready/valid。
5. 用综合报告确认 RAMB36/RAMB18 实际增加、DCache FF/LUT 显著下降，而不是只添加 `ram_style` 属性但仍推断失败。

目标门槛：DCache data 不再以 65k 级 FF 实现；顶层 LUT/FF 显著下降；cache directed tests、RV32I/M/MI 和约定范围的 `srcSmoke` 通过；`srcWithMext` 只要求小窗口 difftest 无偏差。资源结果由用户运行 Vivado 后确认。

### Phase 6：BPU、ROB、Issue Queue 与 PRF 优化

1. **BPU**：去除 table payload 异步复位，只清 valid 或使用 epoch；将大表改为同步读 bank，并通过 fetch pipeline 对齐预测结果。先做容量/端口敏感性分析，再决定是否缩小表项。
2. **ROB**：将 valid/done/exception metadata 与宽 payload 分离；flush 只清有效状态/指针，避免整表清零。评估按 retire/complete 端口分 bank，而不是复制宽 entry 选择网络。
3. **Issue Queue**：减少每周期全表压缩和全表多端口优先选择；优先采用 free-slot bitmap、age/ready bitmap 或分 bank queue，保留多发射正确性。
4. **PRF**：评估 bank/复制 RAM、写冲突仲裁和 bypass；多组合读端口若无法 RAM 化，至少切断 PRF read -> execute -> writeback 的长组合路径。
5. 每次只改一个结构，分别记录 LUT、FF、RAM、WNS、cycles 和 IPC，避免资源下降但性能/正确性不可归因。

完成门槛：每项都有功能回归和 post-route QoR 对照；不接受仅综合前估算的优化结论。

### Phase 7：时序、布局和上板收敛

1. 在约束可信后按真实 worst path 分类：CPU intra-clock、50 MHz intra-clock、reset/high-fanout、RAM boundary、跨层级大 mux、I/O。
2. 优先通过 RTL pipeline、RAM 化和 fanout 降低解决路径；只在结构稳定后尝试 implementation strategy、phys_opt directive 或层次 flatten 参数。
3. 检查 `cpu_rst_sync` 被自动提升 BUFG 的原因。减少大范围异步 reset/payload reset 后，重新评估 reset fanout 和 control-set 数量，不手工强推 BUFG 作为长期方案。
4. 频率采用阶梯收敛：先在当前 50 MHz CPU 域得到可靠 bitstream，再按目标逐档提高；每档都需要用户安排重新生成 PLL、clean build、route 和上板验证，不自动发起长任务。
5. 上板 smoke 顺序：PLL locked/reset release、UART、IROM 启动、LED/SEG 稳定快照、DRAM load/store、RV32I、M 扩展、长程序。为 reset/PC/commit/MMIO progress 保留可观测信号。

完成门槛：用户提供的 routed 报告显示所有时钟域 setup/hold 均通过且无未约束路径；板上重复冷启动/热复位稳定。全量 `srcWithMext` 只在用户安排最终验收时执行，日常阶段以 RV32、`srcSmoke` 和小窗口 difftest 为准。

## 5. 验证矩阵

| 层级 | 必做检查 | 通过标准 |
| --- | --- | --- |
| 静态 RTL | lint、reset pattern 扫描、组合环、多驱动 | 0 blocker |
| 单元仿真 | clear/recover、ROB/IQ、DCache hit/miss/writeback、BPU update | 全部 pass |
| ISA/SoC 仿真 | RV32UI、RV32UM、RV32MI；`srcSmoke` 部分/全量；`srcWithMext` 小窗口 difftest | RV32 为主要正确性门槛，其他范围按阶段记录且无回退 |
| 综合（用户运行） | message audit、层次利用率、RAM/DSP inference、control sets | 0 error，0 未豁免 critical warning |
| 实现（用户运行） | DRC、methodology、CDC、clock interaction、timing、high fanout | 0 blocker，setup/hold met |
| bitstream（用户运行） | clean build 来源、生成时间、配置摘要 | 可追溯；重复运行只在需要时安排 |
| 上板 | reset、UART、LED/SEG、内存、ISA、长程序 | 多次启动结果一致 |

## 6. 建议修改文件范围

P0/P1 预计涉及：

- `rtl/core/backend/CoreBackend.sv`
- `rtl/core/rename/Rat.sv`
- `rtl/core/rename/FreeList.sv`
- `rtl/core/rename/BusyTable.sv`
- `rtl/core/dispatch/ROB.sv`
- `rtl/core/issue/CompressedQueue.sv`
- `rtl/core/common/*.sv` 中同类 reset/clear 结构
- `fpga/digital_twin.xdc`
- `fpga/create_vivado_project.tcl`

后续 QoR 预计涉及：

- `rtl/core/memory/DCache.sv`
- `rtl/core/frontend/BranchPredictor.sv`
- `rtl/core/dispatch/ROB.sv`
- `rtl/core/issue/CompressedQueue.sv`
- `rtl/core/execute/PhysRegFile.sv`
- 必要的上游 pipeline/接口模块与对应 testbench

## 7. 执行优先级与停止条件

1. **P0**：Phase 0-4。先让约束干净、implementation 稳定完成。
2. **P1**：Phase 5。DCache RAM 化是当前最大资源收益点。
3. **P2**：Phase 6-7。按报告驱动 BPU/ROB/IQ/PRF 和 Fmax 优化。

遇到以下任一情况立即停止扩大改动范围并回到最近通过点：

- ISA/SoC 功能回归失败；
- 新增未约束时钟或 CDC critical crossing；
- RAM 化后实际未推断 RAM；
- LUT/FF 降低但 WNS、cycles 或板上稳定性显著恶化；
- 只能依靠 false path、dont_touch 或提高告警限额掩盖问题。

## 8. 第一轮实施建议

第一轮只执行 Phase 1-4：修复全仓同类 reset/clear 写法、删除重复 input clock、把 CDC XDC 改为 implementation-only。修改侧完成 RV32 测试集、约定范围的 `srcSmoke` 和 `srcWithMext` 小窗口 difftest，并准备新的 build 目录及关闭 power-opt 的分段 Vivado 命令；由用户启动 Vivado。收到可信 routed 报告后再进入 DCache RAM 化，否则资源和时序优化缺少可靠基线。
