# srcWithMext IPC>1 优化记录

> 日期：2026-07-06  
> 目标：`srcWithMext` 小量/窗口内 IPC 至少超过 1，同时保持 RTL 可综合，避免不可控的长组合路径。

## 基线

最近一次 `srcWithMext` 结果：

| 指标 | 数值 |
| --- | ---: |
| cycles | 20,000,000 |
| commit_count | 10,563,639 |
| IPC | 0.528182 |
| issue_queue_full_cycles | 14,571,499 |
| frontend/id stall cycles | 14,584,060 |
| rn stall cycles | 14,568,553 |
| ds stall cycles | 14,567,782 |
| branch miss cycles | 8,066 |
| mem load return block | 0 |
| mem load access block | 0 |
| store commit blocked by load | 604,459 |

结论：当前 IPC 低的第一主因不是 EX/WB stall，也不是分支恢复；最大项是 IQ 资源反压导致 frontend/RN/DS 长期停住。`issue_queue_full_cycles` 占总周期约 72.9%，必须先拆分 Int/Mem/Mul 队列贡献。

## 观测增强

本轮新增 Verilator perf 字段：

1. `resources.issue_queue_full_breakdown.int_cycles`
2. `resources.issue_queue_full_breakdown.mem_cycles`
3. `resources.issue_queue_full_breakdown.mul_cycles`
4. `width.issue_mix.int_uops`
5. `width.issue_mix.mem_uops`
6. `width.issue_mix.mul_uops`

实现方式：`DispatchStage` 生成 per-queue full 标志，经 `CtrlIF` 传给 `core` 计数；`IssueStage` 输出按 `tubeType` 统计实际发射 uop 数。该观测只增加计数器和 `VERILATOR_TB` debug 端口，不改变核心调度行为。

## 假设队列

| 假设 | 判据 | 后续修复方向 |
| --- | --- | --- |
| MemIssueQueue 太浅/单发导致 backpressure | `mem_cycles` 占主导，`mem_uops` 接近 1/cycle 上限或 head 常等待 | 加深 MEM FIFO、允许同拍 pop+push、必要时做 load/store 分流或更宽 MEM issue。 |
| IntIssueQueue 被依赖链/选择策略填满 | `int_cycles` 占主导，`int_uops` 低于期望 | 优化预计唤醒、选择补选、增加 INT depth 或减少全局 age 仲裁损失。 |
| MulIssueQueue 长延迟堵塞 | `mul_cycles` 占主导，`mul_uops` 很低且 M 类密度高 | MUL/DIV 分队列或增加保守 reservation，避免 DIV/REM 堵住 MUL。 |
| Dispatch 整包阻塞放大局部 full | 单队列 full 时 w0 很高，另两个队列还有空间 | 考虑 partial dispatch 或 lane replay，但要评估复杂度和时序。 |

## 迭代记录

### 0. TB 判定纠偏：`0x37800000` 不是最终 PASS/FAIL LED

用户指出上一轮把 `0x37800000` 的含义判断错了。重新联动查看
`data/srcWithMext/srcWithMext.dump` 后确认：

| 地址 | 行为 | 含义 |
| --- | --- | --- |
| `0x800006f8` | 读取 `0x80100000/0x80100030` 后写 `0x80200020` | 生成 SEG 计数显示。`0x37800000` 表示 RV32I=37、M/Z=8。 |
| `0x80000860` | `0x04887020 | mem[0x80100038]` 写 `0x80200040` | 最终 PASS LED 生成函数。 |
| `0x800008a4` | `0x90606090 | mem[0x80100038]` 写 `0x80200040` | 最终 FAIL LED 生成函数。 |

因此 `srcWithMext` 的最终 PASS LED 不是 `srcSmoke` 的 `0x01221c08`，
而是 `0x04887020 | 0x03030303 = 0x078b7323`。最终 FAIL LED 是
`0x90606090 | 已点亮测试灯`。

修复：

1. 删除 `SrcLampSegChecker::post_tick()` 中“expected counters reached before final lamp marker 即 PASS”的早停逻辑。
2. `0x37800000` 只更新 `rv32i_count=37/mext_count=8` 观测值，不再结束仿真。
3. `src_lampseg` 仍按 dump 反推协议等待最终 LED marker：
   - PASS marker：`0x04887020`
   - FAIL marker：`0x90606090`
   - 全部测试灯 mask：`0x03030303`

验证：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果从错误早停的 `PASS @1247 cycles, IPC=0.874098` 变为真实窗口：

| 指标 | 数值 |
| --- | ---: |
| status | TIMEOUT |
| cycles | 500,000 |
| IPC | 0.778046 |
| SEG | `0x37800000` |
| last LED | `0x00020001` |
| pass/fail marker | 均未出现 |

结论：上一轮 `0.874` 是 TB 早停造成的假结果，不能作为 IPC 优化收益依据。
后续性能优化统一以修复后的窗口数据为基线。

### 1. 观测增强

状态：已实现，并完成 `srcWithMext` 500,000-cycle 窗口测试。

命令：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果：

| 指标 | 数值 |
| --- | ---: |
| IPC | 0.789444 |
| issue_queue_full_cycles | 295,695 |
| int full cycles | 0 |
| mem full cycles | 295,695 |
| mul full cycles | 0 |
| int issued uops | 236,577 |
| mem issued uops | 124,942 |
| mul issued uops | 36,917 |

结论：低 IPC 第一主因已定位为 `MemIssueQueue` 反压。MEM 实际 issue 只有约 0.25 uop/cycle，不是 MEM 执行端口满载，而是 4 项严格 FIFO 在队头未 ready 或访存依赖等待时很快填满，随后 Dispatch 整包阻塞，把 Int/Mul 可执行工作也挡在 RN/DS 前面。

### 2. MemIssueQueue 低风险扩容

执行：

1. `MEM_ISSUE_QUEUE_DEPTH` 从 4 提高到 16。
2. 暂未引入同周期 pop->push freeCount 反馈，避免在同一轮增加跨 issue/dispatch 的组合反馈路径。
3. 不改变 MEM 严格 FIFO/head-ready 语义，不增加 MEM 发射宽度。

结果：

| 指标 | MEM depth=4 | MEM depth=16 |
| --- | ---: | ---: |
| IPC | 0.789444 | 0.789446 |
| issue_queue_full_cycles | 295,695 | 30 |
| mem full cycles | 295,695 | 30 |
| rob_full_cycles | 138 | 293,111 |
| free_list_empty_cycles | 0 | 121,711 |
| issue w2 cycles | 50,684 | 63,329 |

结论：MEM 队列深度 4 是明显表层瓶颈，但不是最终 IPC 根因。加深后 dispatch 不再主要被 MEM IQ full 阻塞，ROB 和 FreeList 很快被占满，说明退休端被 ROB head 未完成或 store commit 顺序卡住。下一步需要按 ROB head 类型拆分。

### 3. ROB head 阻塞观测

新增字段：

1. `resources.rob_head_block.not_done_cycles`
2. `resources.rob_head_block.not_done_int_cycles`
3. `resources.rob_head_block.not_done_mem_cycles`
4. `resources.rob_head_block.not_done_mul_cycles`
5. `resources.rob_head_block.not_done_other_cycles`
6. `resources.rob_head_block.store_commit_wait_cycles`

实现方式：ROB entry 增加 `tubeType` 字段，由 Dispatch 写入；`core` 在 perf 计数阶段观察 `robIF.RobPopRes[0]`，统计 head valid 但未 done 的类型，以及 head store 已 done 但 StoreBuffer 尚不能 commit 的周期。

### 4. 后端有效收益点与错误前端优化回退

接手当前工作区后，先复测当前版本：

| 配置/动作 | IPC | 正确性进度 | 结论 |
| --- | ---: | --- | --- |
| 含 Fetch 级 RAS/早跳转/BPU 强制非顺序 taken | 1.07488 | SEG 始终 `0x00000000`，仅启动 LED | IPC 不可信，前端把 PC 高位跑丢，程序进入低地址镜像路径。 |
| 回退 Fetch 级 RAS/早跳转，回退 BPU 非顺序目标强制 taken | 1.09658 | SEG=`0x37800000`，LED=`0x00020001` | 正确路径恢复，IPC>1 仍成立，说明主要收益来自后端而非错误路径。 |

定位到的前端错误现象：

1. `srcWithMext` 在 `pc=8000085c` 的 `jalr zero,0(ra)` 后，大量 branch miss 日志变成 `pc=0000106c/00001394/...`。
2. 这说明 Fetch 级 speculative redirect/RAS 路径产生了不带 `0x8000_0000` 高位的错误目标，后端恢复后继续在低地址镜像中执行。
3. 因此删除 FetchStage 内部 RAS/early direct redirect 的行为，只保留 `prev.fetchRedirectValid/Pc` 默认拉低，避免 PreFetchStage 的新接口悬空。

保留的后端收益点：

1. 分布式 IssueQueue + 3 INT issue slot / 1 MEM / 1 MUL，使 backend 能从已缓存 uop 中多发射，而不是被 2-wide frontend 每拍限制。
2. `MEM_ISSUE_QUEUE_DEPTH` 从 4 提到 16，解决原始 `mem full cycles=295,695` 的表层反压。
3. `ROB_DEPTH` 从 32 提到 64，给长延迟 load/MUL/DIV 与 2-wide commit 之间留出足够乱序窗口。
4. ROB combin pop view 接入同拍 WB done，使 head entry 本拍完成即可本拍被 commit 观察到，减少无意义的退休空泡。
5. 预测唤醒修正：delay 为 1 的 producer 直接标 ready，MEM/MUL 按实际延迟做 shift 预测，减少 dependent uop 晚醒。
6. MUL 延迟模型从 3-cycle IP wrapper 对齐到 `MUL_LATENCY=2` 的可见 WB 时序；Dispatch 的 MUL dependent delay 仍按保守 3-cycle 发放。

### 5. 不保留的一味扩项尝试

用户明确要求不能靠无限加表项拿 IPC。本轮做了右尺寸化验证：

| 尝试 | 结果 | 决策 |
| --- | --- | --- |
| `ROB_DEPTH=128`, `INT_IQ=48` | IPC 仍 `1.09658`，但压力转成 `free_list_empty=210,615` | 不保留。只是把 ROB/IQ 压力转移到物理寄存器池，面积/时序代价不值。 |
| `PHYREG_NUM=80` | IPC 仍 `1.09658` | 不保留。 |
| `PHYREG_NUM=64` | IPC 仍 `1.09658` | 保留原始 64，避免扩大多端口 PRF。 |
| `MEM_IQ=8` | IPC 仍 `1.09658`，但 `mem full=151,096` | 不保留。长跑/不同代码段风险大。 |
| `MUL_IQ=4` | IPC 仍 `1.09658`，`mul full=0` | 保留原始 4。 |

最终候选资源尺寸：

| 项 | 原始 | 最终候选 | 原因 |
| --- | ---: | ---: | --- |
| PHYREG | 64 | 64 | 扩到 80/96 无 IPC 收益，PRF 代价高。 |
| ROB | 32 | 64 | 需要吸收长延迟 M/MEM head block；128 无收益。 |
| INT IQ | 16 | 32 | 配合 3 INT issue slot，避免 INT ready uop 过早反压。 |
| MEM IQ | 4 | 16 | 4/8 都会产生明显 MEM FIFO head-of-line 反压；16 基本消除 full。 |
| MUL IQ | 4 | 4 | M 队列未 full，瓶颈是长延迟完成/顺序提交，不是队列深度。 |

### 6. 当前最终窗口结果

命令：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果：

| 指标 | 数值 |
| --- | ---: |
| status | TIMEOUT |
| cycles | 500,000 |
| commit_count | 548,290 |
| IPC | 1.09658 |
| SEG | `0x37800000` |
| last LED | `0x00020001` |
| issue_queue_full_cycles | 2 |
| mem full cycles | 2 |
| mul full cycles | 0 |
| rob_full_cycles | 0 |
| free_list_empty_cycles | 214,529 |
| rob_head_not_done_cycles | 146,535 |
| rob_head_not_done_mul_cycles | 76,332 |
| store_commit_wait_cycles | 4,030 |

解释：

1. 500k 窗口 IPC 已超过目标 `>1`，且 src 自检进度正常到 RV32I=37/M=8 的 SEG 显示。
2. 当前剩余大项是 `free_list_empty` 和 ROB head 等长延迟 M/MEM 完成，但扩大 PHYREG/ROB 对 IPC 没有带来收益，因此不保留。
3. 后续若继续优化，应优先考虑结构性降低 M/DIV 对顺序提交的阻塞，例如更准确的 DIV 完成建模、M 类用例局部调度、或 commit/recovery 细化；不应继续简单加大表项。

补充回归：

```bash
make sim-rv32 TEST=rv32ui-p-simple MAX_CYCLES=200000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32um-p-mul MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

| 用例 | 结果 |
| --- | --- |
| `rv32ui-p-simple` | PASS |
| `rv32um-p-mul` | PASS |

### 7. 100MHz 约束下的时序友好优化

新增目标：在 `srcWithMext` IPC 保持 `>1` 的前提下，避免继续依赖大表项，并减少最可疑的组合关键路径，面向 FPGA 100MHz 收敛。

本轮先做两个不增加容量的 RTL 优化：

1. IssueQueue 顶层 grant 从“5 次全局 oldest 迭代选择”改为“固定候选顺序 + 同周期 RAW 防护”。
   - 原路径：`candidate.done/age` -> 5 轮 best age 比较 -> RAW 检查 -> grant -> popGrant/issuedProducers。
   - 新路径：每个候选只检查此前已 grant 的 producer RAW，不再做跨簇 32-bit age 最小值迭代。
   - 子队列内部语义不变：INT 队列仍选 ready oldest，MEM/MUL 仍 FIFO head issue。
   - 设计取舍：放弃跨 INT/MEM/MUL 的全局最老严格排序，换取更短组合路径；跨簇 age 对正确性不是必须，同周期 RAW 防护才是必须。

2. Bypass 网络只对实际使用端口做匹配。
   - ALU/BRC/SYS 使用 `INT_ISSUE_WIDTH*2` 个读口。
   - MEM 使用 `MEM_ISSUE_WIDTH*2` 个读口。
   - MUL 使用 `MUL_ISSUE_WIDTH*2` 个读口。
   - 未使用端口直接清零，避免综合器保留无意义的 `read_port x WB_PORT_NUM` 比较网络。

3. WB/Ready/Wakeup/ROB done 端口从 12 收敛到 6。
   - 原定义：`WB_PORT_NUM = INT_ISSUE_WIDTH*3 + MEM_WB_WIDTH + MUL_WB_WIDTH = 12`。
   - 问题：ALU/BRC/SYS 虽然各有 3 个执行数组，但它们共享同一批 3 个 INT issue slot；同一周期最多只有 3 个 INT uop 完成，不可能 9 个 INT WB 端口同时有效。
   - 新定义：`WB_PORT_NUM = INT_ISSUE_WIDTH + MEM_WB_WIDTH + MUL_WB_WIDTH = 6`。
   - WriteBackStage 将 ALU/BRC/SYS completion 动态压入 3 个 INT WB 端口，MEM/MUL 使用后续固定端口。
   - 收益：PRF 写端口、ReadyTable `markReady`、IssueQueue `IssueWakeup`、ROB `RobDoneReq` 扫描和 Bypass `wbForward` 比较网络全部减半。

待验证：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32ui-p-simple MAX_CYCLES=200000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32um-p-mul MAX_CYCLES=500000 BUILD=1 BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

验证结果：

| 项 | 结果 |
| --- | --- |
| `srcWithMext` 500k IPC | `1.09658` |
| `srcWithMext` SEG/LED 进度 | SEG=`0x37800000`, LED=`0x00020001` |
| `issue_queue_full_cycles` | `2` |
| 结论 | IssueQueue grant 简化和 Bypass 端口剪枝没有降低 IPC，可以保留。 |
| `rv32ui-p-simple` | PASS |
| `rv32um-p-mul` | PASS |

WB 端口压缩后复测：

| 项 | 结果 |
| --- | --- |
| `srcWithMext` 500k IPC | `1.09658` |
| `srcWithMext` SEG/LED 进度 | SEG=`0x37800000`, LED=`0x00020001` |
| `issue_queue_full_cycles` | `2` |
| `rv32ui-p-simple` | PASS |
| `rv32um-p-mul` | PASS |
| `rv32um-p-div` | PASS |

Vivado 工具状态：

1. Linux/WSL 侧 `/mnt/d/AppMajor/xilinx/Vivado/2023.2/bin/vivado` 无法正常启动，报缺少 `unwrapped/lnx64.o/prodversion`。
2. Windows 侧 `D:\AppMajor\xilinx\Vivado\2023.2\bin\vivado.bat` 可启动，但 Windows 可见的 `\\wsl.localhost\Ubuntu\home\jiabingyu` 与当前工程所在 WSL 文件系统不一致，当前 repo 路径不可见，无法直接在本轮生成 100MHz timing report。
3. 因此本轮 100MHz 收敛先按 RTL 关键路径风险处理：减少 WB 端口、减少 bypass 比较器、移除 IssueQueue 顶层全局 age 迭代；后续在可用 Vivado 工程环境中必须跑 `FPGA_CPU_CLK_MHZ=100.000` 的 synth/impl timing report 验证 WNS。

FPGA 约束侧同步修改：

1. `fpga/create_vivado_project.tcl` 默认 `cpu_clk_mhz` 从 50MHz 改为 100MHz；`sys_clk_mhz` 仍保持 50MHz，避免 UART/counter 语义变化。
2. `fpga/digital_twin.xdc` 增加输入差分时钟约束：

```tcl
create_clock -name i_sys_clk -period 5.000 [get_ports { i_sys_clk_p }]
```

这样后续 Vivado 生成工程默认就会按 100MHz CPU 时钟目标和 200MHz 输入时钟约束检查，而不是在 50MHz 或无输入时钟约束下给出过松 timing 结论。
