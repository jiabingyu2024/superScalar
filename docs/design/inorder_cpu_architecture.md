# 双发射顺序执行 CPU 架构与数据流

本文档描述当前 `dev-v0` 分支下 `rtl/core` 中的 in-order 双发射 CPU。该版本从原先的乱序超标量结构收敛为顺序执行结构，保留双发射能力、简单 2-bit BPU、DCache、M 扩展乘除法 IP 封装，并保持当前 SoC 的 IROM/DMEM 时序契约。

## 顶层结构

当前 CPU 顶层仍然是 `rtl/core/myCPU.sv`，对外端口不变：

- IROM：单口 32-bit 指令接口，`irom_addr/irom_ena` 在本周期发出，`irom_data` 在下一周期返回。
- DMEM：ready-valid 请求/响应接口，SoC 侧只支持 single outstanding transaction。
- Verilator 性能计数：通过 `dbg_perf_*` 输出给测试框架。

`myCPU` 内部例化 `core`，`core` 再例化各级模块：

- `InOrderFetchStage`：PC 生成、IROM 请求、简单 2-bit BPU、取指包生成。
- `InOrderDecodeStage`：把取指包转换成 uop。
- `InOrderIssueQueue`：顺序发射队列，支持跨取指包配对双发。
- `InOrderExecuteStage`：组合执行 ALU、branch、CSR、load/store 地址生成和 M 扩展请求生成。
- `InOrderMulDivUnit`：封装当前分支已有的 `MulDivUnit`，内部使用 `MUL_0`/`DIV_0` 时序模型。
- `DCache`：cacheable DRAM 访问走缓存，MMIO/counter 等地址走 uncached。

## 流水与状态

这个 CPU 是顺序流水结构，但不是传统固定 5 级每拍全速推进的流水线。它有明确的前端、队列、执行、访存/写回数据流；同时 load/store/mul/div 会通过 `memState` 阻塞后续发射，直到当前长延迟操作完成。

主要状态由 `MemState` 管理：

- `M_NORMAL`：正常取指、入队、发射、执行。
- `M_LOAD_REQ`：发出 load 请求；cache hit 可以在该状态同周期返回。
- `M_LOAD_WAIT0`：等待 load miss 或 uncached load 返回。
- `M_STORE_REQ`：发出 store 请求，握手成功后提交。
- `M_MULDIV_WAIT`：等待乘除法单元完成。
- `M_MULDIV_WB`：乘除法结果写回后的恢复周期。

## 前端数据流

当前 SoC 只有单口 IROM，因此前端每次只取一条 32-bit 指令：

1. `InOrderFetchStage` 维护 `reqPc`。
2. 当 `run && !stall` 时，输出 `iromEna=1` 和 `iromAddr=reqPc`。
3. 同一周期根据 BPU 计算下一次请求 PC：
   - 命中且计数器高位为 1：跳到预测目标。
   - 否则：顺序 `PC+4`。
4. 下一周期 IROM 返回 `iromData`，fetch 生成 `FetchPacket`：
   - `ifPkt.pc = reqPcPipe0`
   - `ifPkt.inst0 = iromData`
   - `ifPkt.inst1 = 0`
   - `ifPkt.predTaken/predTarget` 保存当时预测结果。

分支预测器是 64 项 direct-mapped 2-bit counter 表，并保存 tag 和 target。条件分支在 execute 阶段解析后训练 BPU；预测错误时 `core` 拉高 `fetchFlush`，把前端 PC 重定向到真实目标。

## Decode 与 Issue Queue

`InOrderDecodeStage` 当前每个有效取指包只产生一个有效 uop：

- `decodeUop[0]` 有效，携带 PC、inst、预测信息。
- `decodeUop[1]` 固定无效，因为当前 IROM 单口不能同拍返回第二条指令。

双发射能力不依赖同一取指包内有两条指令，而是由 `InOrderIssueQueue` 跨周期缓存指令实现。队列深度为 6：

- decode 每周期最多入队 1 条。
- issue 每周期最多从队首发射 2 条。
- 队列只按程序顺序弹出，不能绕过队首指令。

当队首两条指令满足 `can_pair(a, b)` 时可以双发，否则只发第一条。当前不能双发的情况包括：

- 任一条是控制流指令：`JAL/JALR/BRANCH/SYSTEM`。
- 任一条是访存指令：`LOAD/STORE`。
- 任一条是 M 扩展乘除法指令。
- 两条都写同一个非零 `rd`，即 WAW。
- 指令为 `0` 或队列中不足两条。

这样设计保证了顺序语义简单清楚：可以双发的主要是普通整数 ALU/位操作/部分 Zb 扩展指令。

## Execute 数据流

`InOrderExecuteStage` 对两个发射槽组合执行：

- slot0 执行较老指令。
- slot1 执行较新指令。
- slot1 读寄存器时可以看到 slot0 当周期产生的写回结果。

寄存器读取通过 `read_reg_forwarded` 完成，前递来源包括：

- 上一周期或长延迟操作完成时形成的 `wbPkt[0]`/`wbPkt[1]`。
- 同周期更老 slot 的 `olderSlotWb`。

因此普通 ALU 指令之间可以通过前递减少 RAW 停顿。例如两条可双发 ALU 指令中，slot1 依赖 slot0 的结果时，可以直接用 slot0 的组合写回值。

执行结果统一输出 `ExecuteResult`：

- 普通 ALU/CSR/control 指令直接给出 `wb`、`commit`、branch 统计和 redirect 信息。
- load/store 不在 execute 直接提交，而是生成 `loadInfo/storeInfo`，交给 `core` 的访存状态机处理。
- M 扩展生成 `mulDivInfo`，交给 `InOrderMulDivUnit`。

## 访存路径

load/store 的地址和数据在 execute 阶段生成，但真正访存在 `core` 的状态机中完成：

1. execute 发现 slot0 是 load/store。
2. `core` 保存 `loadInfo` 或 `storeInfo`。
3. 状态切到 `M_LOAD_REQ` 或 `M_STORE_REQ`。
4. 前端和 issue 暂停，issue queue 内容保留，不清空。
5. 操作完成后恢复 `M_NORMAL`。

访存请求先进入 `DCache`：

- `0x8010_0000` 到 `0x8013_ffff` 为 cacheable DRAM。
- 其他地址为 uncached，用于 MMIO/counter 等。
- DCache 对外仍使用当前 SoC 的 ready-valid DMEM 接口。
- store 采用写穿透；store hit 同时更新 cache line，避免后续 load 被无谓 miss 拖慢。
- load hit 可以组合返回，`M_LOAD_REQ` 同周期完成写回和提交。
- load miss 或 uncached load 进入等待状态，直到 `cacheRespValid`。

数据对齐规则保持当前 SoC 文档约定：

- core/DCache 发出的 store data/mask 是低位未移位形式。
- SoC/adapter 根据地址低位移位写入。
- cacheable load 从 cache line 读出 aligned word 后，core 根据地址低位右移，再按 `funct3` 做符号/零扩展。
- uncached load 使用 SoC 已经按地址低位对齐后的返回数据。

## M 扩展路径

M 扩展指令在 execute 阶段只生成请求，不在当周期提交：

1. `InOrderExecuteStage` 识别 `OP_OP && funct7 == 7'b0000001`。
2. `core` 在 `M_NORMAL` 下启动 `InOrderMulDivUnit`。
3. `memState` 切到 `M_MULDIV_WAIT`，暂停前端和发射。
4. `InOrderMulDivUnit` 等待 `MulDivUnit.done`。
5. 完成后通过 `mulDivWb` 写回并提交。

底层 `MulDivUnit` 复用当前分支的 IP 时序模型：

- MUL 使用 `MUL_0`，固定注册流水延迟。
- DIV 使用 `DIV_0`，固定多周期输出。

当前 M 扩展是阻塞式：乘除法执行期间不会继续发射后续指令。

## 分支与冲刷

条件分支在 execute 阶段解析真实方向和真实 next PC：

- 如果真实 next PC 等于预测 next PC，则命中。
- 如果不同，则 `redirect=1`，`core` 触发：
  - `queueFlush=1` 清空 issue queue。
  - `fetchFlush=1` 清空 fetch 当前包并把 `reqPc` 改为真实目标。

`JAL/JALR/SYSTEM` 当前总是作为控制流重定向处理，并且不能与其他指令双发。BPU 训练目前主要针对条件分支。

## 周期级示例

以一条普通 ALU 指令为例，在无阻塞、无 redirect 的情况下：

- 周期 0：fetch 输出 `iromAddr=PC`，IROM 接收请求。
- 周期 1：IROM 返回指令，fetch 形成 `ifPkt`，同时请求 `PC+4`。
- 周期 2：decode 把 `ifPkt` 转成 uop，入 issue queue。
- 周期 3：issue queue 发射该 uop 到 `exUop`。
- 周期 4：execute 组合计算结果，`wbPkt` 在时钟沿更新。
- 周期 5：寄存器堆数组写入结果；后续指令也可通过 `wbPkt` 前递提前看到结果。

如果队列中有两条可配对普通 ALU 指令，则周期 3 会同时发射 slot0/slot1，周期 4 同时执行，周期 5 同时写回。

以 load hit 为例：

- 周期 N：load 被发射到 execute。
- 周期 N+1：execute 产生 load 地址，`core` 进入 `M_LOAD_REQ`。
- 周期 N+2：DCache hit 时同周期返回数据，core 完成 load 写回和提交，恢复 `M_NORMAL`。

以 load miss 或 uncached load 为例：

- 周期 N+2：请求被 DCache/SoC 接收，但没有同周期返回。
- 后续周期：停在 `M_LOAD_WAIT0`。
- 响应到达周期：写回 load 数据并恢复正常发射。

## 与原乱序超标量结构的主要区别

当前版本不是乱序 CPU：

- 没有 rename。
- 没有 ROB。
- 没有物理寄存器堆/free list。
- 没有乱序 issue。
- 没有按功能单元分布式唤醒选择。
- 没有 store buffer 乱序提交。

当前版本的顺序性体现在：

- issue queue 只从队首发射。
- 不允许绕过队首等待的 load/store/mul/div。
- load/store/mul/div 阻塞前端和发射，但不清空 issue queue。
- commit 由当前执行/访存/乘除法完成点顺序推进。

这样牺牲了乱序隐藏长延迟的能力，但 RTL 边界、控制逻辑和可验证性更简单。

## 性能计数

当前 core 输出的主要计数包括：

- `perf_cycle`：核心周期数。
- `perf_commit`：提交指令数。
- `perf_branch/perf_branch_miss`：分支总数和预测失败数。
- `perf_load/perf_store`：load/store 提交数。
- `perf_dcache_access/perf_dcache_miss`：DCache 访问和 miss。
- `perf_stall_front/perf_stall_mem/perf_stall_muldiv/perf_stall_load_use`：主要阻塞来源。

测试框架会根据这些计数生成 IPC、分支命中率、DCache 命中率等指标。需要注意的是，当前 branch breakdown 中 conditional/jal/jalr 细分项没有完整接出，可信的是总 branch count 和总 miss count。

## 已知限制

- IROM 只有单口，所以当前取指宽度是 1；双发主要依靠 issue queue 积累相邻指令。
- load/store/mul/div 都会阻塞流水，无法和后续独立指令重叠执行。
- 控制流指令不能双发。
- DCache 参数当前在 `core` 中设为 `LINE_COUNT=16384`，适配当前仿真/测试工作集；若面向 FPGA 资源，需要重新评估容量。
- 分支预测器较简单，没有 RAS、BTB 多路组相联或间接跳转预测。
