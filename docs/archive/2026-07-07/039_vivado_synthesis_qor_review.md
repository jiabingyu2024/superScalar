# Vivado 综合/实现困难的 RTL 结构审查

日期：2026-07-07

## 结论

当前设计不是简单的 Vivado 工具慢，而是有多处 ASIC/仿真友好、但 FPGA/Vivado 不友好的 RTL 结构。综合半小时、实现一个半小时是可以解释的：综合后 CPU core 已经达到约 `117703 LUT / 44928 FF`，其中 `IssueQueue + ROB + RegFile + BPU + Payload` 占了绝大多数 LUT。

这不一定代表功能设计错误，但代表 FPGA 映射方式成本过高。首要问题不是是否把所有队列换成 IP，而是要把“全表组合扫描、全表异步清零、结构体数组随机读写、多端口寄存器堆、宽 wakeup/select CAM”这些逻辑拆成 FPGA 友好的 RAM、valid bit、分层比较和流水化选择。

## 资源热点证据

来自 `synth_util_hier.rpt`：

| 模块 | LUT | FF | 判断 |
| --- | ---: | ---: | --- |
| `issueQueue` | 44889 | 7076 | 最大热点，占全设计 LUT 约 38%。 |
| `intIssueQueue` | 35155 | 4768 | 乱序选择 + wakeup CAM + oldest select 代价最高。 |
| `memIssueQueue` | 7936 | 1821 | 虽然是 FIFO 语义，但仍用结构体寄存器数组实现，代价偏高。 |
| `rob` | 21317 | 7547 | 64 项结构体数组 + 多写回口随机更新 + commit 旁路。 |
| `regFile` | 12750 | 2016 | 64x32、10 读、6 写，Vivado 基本只能用 LUT/FF/MUX 做。 |
| `bpu` | 10700 | 14088 | BTB/BHB 表没有映射 RAM，全部寄存器化。 |
| `payload` | 8480 | 4680 | payload 表项被做成寄存器阵列和大 MUX。 |

综合 warning 也指向同一类问题：

```text
WARNING: [Synth 8-11357] Potential Runtime issue for 3D-RAM or RAM from Record/Structs for RAM entries_reg with 8960 registers
WARNING: [Synth 8-330] inout connections inferred for interface port 'DramAccessIF' with no modport
WARNING: [Synth 8-3848] ... does not have driver
```

`entries_reg with 8960 registers` 说明 Vivado 看到结构体数组 RAM，但没有顺利推断成 BRAM/LUTRAM，而是展开成寄存器和 MUX。

## 主要 RTL 根因

### 1. IssueQueue 是最大瓶颈

位置：

- `rtl/core/BasicTypes.sv:48-54`
- `rtl/core/DispatchStage/IssueTypes.sv:13-26`
- `rtl/core/DispatchStage/IssueQueue.sv:254-412`
- `rtl/core/DispatchStage/IssueQueue.sv:464-608`

当前参数：

```systemverilog
INT_ISSUE_WIDTH = 3
MEM_ISSUE_WIDTH = 1
MUL_ISSUE_WIDTH = 1
ISSUE_WIDTH = 5
WB_PORT_NUM = 6
INT_ISSUE_QUEUE_DEPTH = 32
MEM_ISSUE_QUEUE_DEPTH = 16
SHIFT_WIDTH = 36
```

`IntIssueQueue` 每周期做这些事情：

1. 扫 32 项找 free slot。
2. 对 2 路 dispatch 分配空位。
3. 对 3 个 int issue port，每个 port 扫 32 项找 ready oldest。
4. 每个有效 entry 对 6 个 writeback wakeup port 比较 srcA/srcB。
5. 每个 entry 再对 5 个 same-cycle issued producer 做预测唤醒比较。
6. 每个 entry 还保存两个 36-bit shift delay 字段。

这会综合成大量比较器、优先级编码器、大 MUX 和控制扇出。`intIssueQueue` 单独 `35155 LUT` 是合理结果。

建议：

- 不要直接用 FIFO IP 替换 `IntIssueQueue`，因为它需要乱序 oldest-ready select，普通 FIFO 不能表达这个语义。
- 把 issue entry 拆成两部分：小 CAM 状态表和大 payload RAM。
  - CAM 状态表只保留 `valid/src/srcReady/dst/tube/age/robIndex/payloadIndex` 等必要字段。
  - 大字段如 `pc/imm/csr/subtype/predInfo/storeBufferIndex` 已经放在 `Payload`，继续扩大这种拆分。
- 去掉每项两个 36-bit `ShiftType`，改成小宽度 countdown 或 `ready_at_cycle` 比较。
  - 例如 `delay_count[2:0]` 足够表达 ALU 1、MEM 2、MUL 3、DIV 不预测唤醒。
- oldest select 分两级做：
  - 第一级每 8 项生成一个 ready candidate。
  - 第二级从 4 个 group candidate 里选 3 个。
  - 必要时打一拍，牺牲 1 cycle issue latency 换综合和时序。
- 如果目标是 FPGA 优先，先把 `INT_ISSUE_WIDTH` 从 3 降到 2 做对比，通常能明显降低 select 和 bypass 复杂度。

### 2. MEM/MUL in-order queue 可以改成 FIFO/XPM

位置：

- `rtl/core/DispatchStage/IssueQueue.sv:415-608`

`InOrderIssueQueue` 本质是 head-ready FIFO，但当前仍保存完整 `IssueEntryPath entries [DEPTH]`，并对每项做 wakeup/predict update。MEM 深度 16 时已经消耗 `7936 LUT / 1821 FF`，这对一个 FIFO 语义队列来说偏高。

建议：

- 对 MEM/MUL 队列，优先改成“FIFO 指针 + entry RAM + head shadow”。
- 如果保持严格 head issue，可以考虑 Xilinx `xpm_fifo_sync` 或 FIFO Generator。
- 但注意：因为 entry 的 ready 会被 wakeup 更新，不能把整个 entry 完全塞进黑盒 FIFO 后就不管。更 FPGA 友好的做法是：
  - FIFO 只管理顺序和 payload index。
  - head entry 读出到寄存器。
  - 只对 head 或少量前瞻 entry 做 wakeup readiness 更新。
- 如果仍希望任意 entry wakeup，则普通 FIFO IP 不够，需要自写 valid/status RAM。

优先级：MEM queue 比 MUL queue 更值得先改，因为综合资源和性能瓶颈都更明显。

### 3. ROB 是第二大热点，结构体数组随机多写口代价高

位置：

- `rtl/core/DispatchStage/ROB.sv:5-51`
- `rtl/core/DispatchStage/ROB.sv:54-113`

当前 ROB：

- 64 项 `RobEntryPath entries [ROB_DEPTH]`。
- 每周期最多 2 push、2 pop、6 done update。
- commit 读 head/head+1，同时组合旁路 6 个 done port。

这会让 Vivado 生成多写端口寄存器阵列，基本不会推 BRAM。`rob` 资源达到 `21317 LUT / 7547 FF`。

建议：

- ROB entry 拆字段：
  - `valid/done/exception/isMiss/isSerial` 保持 FF bit-vector。
  - `pc/predPc/truePc/phyReg/lgcReg/checkpoint/storeIndex` 等 payload 放 LUTRAM/BRAM 或分布式 RAM。
- done 更新不要写整条 struct，只写独立 bit-vector 和少数字段。
- commit head 需要的 payload 可以提前读入 head shadow register，减少组合读大 MUX。
- 如果只为 FPGA 运行，ROB 深度 64 可以先试 32，对综合时间和实现压力会很敏感。

不建议直接用 FIFO IP 完整替换 ROB。ROB 有随机 done 写回和 head commit 读，普通 FIFO 不支持乱序完成回填。

### 4. RegFile 多读多写端口无法自然映射 BRAM

位置：

- `rtl/core/ReadRegStage/ReadRegTypes.sv:12-16`
- `rtl/core/ReadRegStage/RegFile.sv:4-31`

当前 PRF 是 `64 x 32`，读口 `ISSUE_WIDTH * 2 = 10`，写口 `WB_PORT_NUM = 6`。这对 FPGA 是非常贵的结构。BRAM 原生通常只有 2 个端口，多读多写需要复制和仲裁；Vivado 不会自动把这种数组变成高效多端口 RAM。

建议：

- 把架构目标改成 FPGA 友好端口数，例如 4R2W 或 6R3W。
- 用 banking/replication 明确实现：
  - 多读：复制多份 RAM。
  - 多写：限制同周期写端口数，或做写端口仲裁/分拍。
- 如果继续保留 10R6W，LUT/MUX 实现是预期结果，不应期待 Vivado 自动优化成 IP。
- 当前 `RegFile` 用 negedge 写，虽然功能上可模拟半周期读写，但对 FPGA 时序和工具推断都不友好。建议改成单边沿同步读写，并通过 WB bypass 解决同周期可见性。

### 5. BPU/BTB/BHB 表被寄存器化

位置：

- `rtl/core/PreFetchStage/BPU.sv:9-56`
- `rtl/core/PreFetchStage/BTB.sv:21-60`
- `rtl/core/PreFetchStage/BHB.sv:24-135`

BTB 256 项，每项 `valid + tag + target`，BHB 还有 local/global/chooser 表。当前写法是异步组合读 + reset 时全表清零，因此 Vivado 基本用 FF/LUT/MUX 实现。资源结果是 `bpu 10700 LUT / 14088 FF`。

建议：

- BTB/BHB 不要 reset 全表 payload，只 reset valid bit 或使用初始化文件/初值。
- 如果能接受预测晚一拍，改同步读 RAM，BTB target/tag 可进 BRAM 或 LUTRAM。
- BHB 的 2-bit PHT/chooser 非常适合 LUTRAM/分布式 RAM，避免 reset 全表。
- FPGA 上通常允许预测表 power-up unknown，只要 valid 或 confidence 初始为 not-taken 即可。

### 6. Payload 表也没有推 RAM

位置：

- `rtl/core/DispatchStage/Payload.sv:4-45`

`Payload` 存的是较大的静态字段，理论上比 IssueQueue 更适合 RAM 化。但当前有 5 个组合读口、2 个写口、全表 reset/flush 清零，所以综合成 `8480 LUT / 4680 FF`。

建议：

- payload RAM 改同步读，Issue 先发 `payloadIndex`，下一拍进入 ReadReg/execute 分类。
- flush 只清 valid bit，不清 payload body。
- 读口数量按实际 issue port 拆 bank，或分 tube 建独立 payload RAM：int/mem/mul 各自只服务本类 issue。
- 可以考虑 `xpm_memory_sdpram` 或 `xpm_memory_tdpram`，但要先把读写端口语义改成同步 RAM 能表达的形式。

### 7. 全局异步 reset 和 flush 全表清零放大控制网

典型位置：

- `IssueQueue.sv:304-314`
- `IssueQueue.sv:490-506`
- `ROB.sv:54-72`
- `Payload.sv:21-31`
- `StoreBuffer.sv:88-104`
- `BTB.sv:46-52`
- `BHB.sv:92-102`
- `RegFile.sv:19-23`

综合报告显示大部分 FF 是带异步 reset 的 `FDCE`：

```text
FDCE 42625
FDPE 1565
FDRE 738
```

implementation 中 Vivado 还插入了 BUFG 去驱动高扇出 reset/set/enable，这也解释了 power optimization 崩溃时提到巨大 fanin/fanout cone。

建议：

- FPGA 上优先只 reset 控制状态：valid、head、tail、count、FSM。
- 大 payload、表项 RAM、预测器表、ROB payload、PRF 不要 reset 全体数据。
- flush 队列时只清 valid/count/head/tail，不清 entries。
- 尽量用同步 reset；跨全核 reset/flush 按 stage 或 cluster 分发打一拍。

### 8. Interface/modport 使用不完整，Vivado warning 很多

位置：

- `rtl/core/core.sv:18`
- `rtl/core/core.sv:82`
- `rtl/core/core.sv:94`
- `rtl/core/DramAccessIF.sv:68-109`

`DramAccessIF` 定义了 modport，但 `core` 端口仍写成裸 interface：

```systemverilog
DramAccessIF dromAccess
```

综合日志出现：

```text
inout connections inferred for interface port 'DramAccessIF' with no modport
```

建议：

- `core` 端口改成明确 modport，例如 `DramAccessIF.core dromAccess`，再审查 `StoreBuffer` 和 `ExecuteMemStage` 是否也只用各自 modport。
- 对 `CtrlIF` 这类多 producer interface，当前日志中大量 `no driver` 可能来自 modport 视角下未使用字段，但也可能掩盖真实方向问题。建议按模块拆小 interface，或给每类执行单元独立 control output，最后在 `Ctrl` 中汇总。

### 9. Vivado 工程配置偏调试，不偏 QoR

位置：

- `fpga/create_vivado_project.tcl:158-159`

当前：

```tcl
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $flatten_hierarchy [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]
```

默认 `FPGA_FLATTEN_HIERARCHY=none`，并且 `KEEP_EQUIVALENT_REGISTERS=true`。这对 bring-up 和层级资源定位有价值，但会限制跨层级优化和寄存器合并。

建议建立两个 profile：

- Debug profile：
  - `FLATTEN_HIERARCHY=none`
  - `KEEP_EQUIVALENT_REGISTERS=true`
  - post synth/impl sanity report 保留
- QoR profile：
  - `FLATTEN_HIERARCHY=rebuilt`
  - `KEEP_EQUIVALENT_REGISTERS=false`
  - 关闭 `power_opt_design` 和 `post_place_power_opt_design`
  - 先用 `Performance_Explore` 或默认 strategy 对比

## 是否该用 Vivado IP/XPM

| 结构 | 是否建议 IP/XPM | 原因 |
| --- | --- | --- |
| IROM/DRAM | 已经使用 blk_mem_gen | 正确。 |
| MUL/DIV | 已经使用 Xilinx IP | 正确。 |
| MEM/MUL in-order issue queue | 建议考虑 FIFO/XPM 或 RAM+指针 | 语义接近 FIFO，但 ready 更新要小心。 |
| Payload | 建议 XPM RAM/分 bank RAM | 大字段、多 entry，适合 RAM 化。 |
| BTB/BHB | 建议 LUTRAM/BRAM/XPM RAM | 表结构明显，不应全 FF。 |
| ROB | 不建议直接 FIFO IP | 有随机 done 写回，需拆字段后部分 RAM 化。 |
| IntIssueQueue | 不建议直接 FIFO IP | 本质是 CAM + oldest ready select，不是 FIFO。 |
| RegFile | 不建议期待自动 IP 化 | 多读多写端口太多，需手写 replication/banking。 |

## 优先级改造清单

### P0：立刻能降低 Vivado 压力

1. 关闭 implementation 的 power optimization，避开当前 Vivado 2023.2 崩溃路径。
2. QoR profile 中使用 `FLATTEN_HIERARCHY=rebuilt`，关闭 `KEEP_EQUIVALENT_REGISTERS`。
3. `DramAccessIF` 裸 interface 全部改明确 modport。
4. 所有大数组 flush/reset 改为只清 valid/head/tail/count，不清 payload entries。

### P1：最高收益 RTL 改造

1. `Payload` 改同步 RAM，读出打一拍。
2. `BTB/BHB` 改 valid-only reset + RAM 表。
3. `MEM InOrderIssueQueue` 改 FIFO/RAM+head shadow。
4. `IssueEntryPath` 去掉 36-bit 双 shift 字段，改小宽度 latency counter。

### P2：架构级收敛

1. `IntIssueQueue` 分组选择，32 项拆成 4 组，每组本地 oldest-ready。
2. ROB 拆 field，done/valid bit-vector 与 payload RAM 分离。
3. PRF 降低端口数，或显式 banking/replication。
4. 比较 `INT_ISSUE_WIDTH=2` 与当前 `3` 的 IPC/QoR。如果 IPC 收益不明显，FPGA 版本应降宽。

## 最小实践任务

先不要大改整个后端。建议按下面顺序做一个可验证小改：

1. 新建一个 `PayloadRam`，接口保持 `payloadIndex` 语义不变，但内部只 reset `valid`。
2. 把 payload body 改成同步读：IssueStage 发 index，下一拍得到 payload。
3. 在 `IssueStage -> ReadRegStage` 之间允许多 1 拍 payload latency。
4. 跑 Verilator 对比功能。
5. 跑 Vivado synth，看 `payload` 是否从 `8480 LUT / 4680 FF` 明显下降。
6. 如果下降明显，再用同样模式改 BTB/BHB 和 MEM queue。

这个任务边界小、风险可控，而且能直接验证“同步 RAM + valid-only clear”是否适合你的代码风格。

## 自检清单

- 队列 flush 时是否只清 valid/count，而不是清整条 entry？
- 大数组是否有异步 reset？有则优先移除。
- 数组是否是结构体数组并带多组合读口？这通常不会推 BRAM。
- 每个 RAM 是否能接受同步读 1 拍 latency？
- 是否存在超过 4 个读口或超过 2 个写口的寄存器堆？
- wakeup/select 是否是 `entry_num x wakeup_port x src_num` 全交叉比较？
- oldest select 是否一次性扫完整队列？
- interface 端口是否都用了 modport？
- Vivado warning 里是否还有 `no driver`、`inout inferred`、`Potential Runtime issue for RAM from Record/Structs`？
- debug profile 和 QoR profile 是否分开？

