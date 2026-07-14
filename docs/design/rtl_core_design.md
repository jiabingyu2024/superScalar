# rtl/core 当前设计

> 本文只描述当前 RTL 实现事实。当前 Core 是 RV32 单发射、允许不同功能单元乱序完成、Scoreboard 顺序提交的实现，不是旧文档中的 2-way Rename/ROB/PRF 架构。

## 1. 顶层定位

```text
student_top
  -> myCPU
       -> core_top
            -> Frontend / Decode
            -> Scoreboard / Issue / RegFile
            -> Fixed Execute / MDU / Bitmanip
            -> LoadQueue / StoreBuffer / DCache
            -> CSR / Recovery / Perf
```

外部接口保持不变：

- IROM：组合/同步模型适配后的单指令取指接口。
- DMEM：valid/ready 请求和独立 read response。
- Commit：每周期最多退休一条，所有架构副作用按程序顺序发生。
- `VERILATOR_TB`：性能和提交调试端口；Vivado 综合不包含这些逻辑。

## 2. 当前流水与执行模型

```text
Frontend -> ID register -> Issue/Read Operands -> EX/FU
                                             -> completion
                                             -> Scoreboard
                                             -> in-order Commit
```

1. Frontend 维护 PC、预测器、IROM pending metadata 和 Fetch Queue。
2. ID 寄存器保存一条 `uop_t`，在 Issue 不能接受时保持。
3. Issue 查询 Scoreboard 的 youngest producer，并结合 RF、Commit-WB 和 completion bypass 形成操作数。
4. Fixed Execute 一拍完成 ALU、Branch 和 AGU；MDU、Bitmanip、DCache 可变延迟返回。
5. 各 completion 按 transaction ID 写回 Scoreboard；年轻独立指令可以先完成。
6. Commit 只观察 Scoreboard head，按程序顺序更新 GPR、CSR、Store commit 状态和恢复控制。

这不是通用 OoO Issue Queue：发射仍按 ID 顺序，乱序只发生在功能单元完成时刻。

## 3. 目录和模块职责

| 目录 | 模块 | 职责 |
|---|---|---|
| `pkg/` | `core_config_pkg`、`core_types_pkg` | 静态配置和跨模块 packed 类型 |
| `frontend/` | `frontend`、`fetch_queue`、`branch_predictor` | 取指、预测、返回 metadata 对齐 |
| `decode/` | `decoder` | RV32I/M/CSR/Zb 配置化译码 |
| `issue/` | `regfile` | 架构整数寄存器 |
| `issue/` | `scoreboard` | entry array、producer map、allocate/complete/commit 指针、serial gate |
| `issue/` | `operand_resolver` | RF、Scoreboard、Commit-WB 和 completion 旁路选择 |
| `issue/` | `issue_control` | 源 ready、资源 credit、serial 和恢复条件汇总 |
| `execute/` | `fixed_execute` | ALU、Branch、AGU、对齐异常 |
| `execute/` | `muldiv_unit`、`bitmanip_unit` | 长延迟 M/Zb 执行 |
| `memory/` | `store_buffer` | 投机 store、commit 标记、按序 drain |
| `memory/` | `load_queue` | 等待 load 和唯一 active memory transaction |
| `memory/` | `store_forwarding` | 按程序顺序合并 older store byte |
| `memory/` | `memory_request_arbiter` | committed store、direct load、queued load 请求优先级 |
| `memory/` | `load_data_path` | forwarding merge、地址移位、符号/零扩展 |
| `memory/` | `dcache*`、`dmem_regslice` | Cache、refill、uncached 和外部请求寄存切片 |
| `commit/` | `csr_file` | Machine CSR、trap 和 mret 状态 |
| `control/` | `recovery_ctrl` | branch miss、trap、mret 重定向和 full flush |
| `perf/` | `perf_counters` | Commit、Branch、Cache 和 stall 计数 |
| `debug/` | `commit_trace_probe` | 仿真提交轨迹和 OpenXiangShan DiffTest probes |
| 根目录 | `core_top`、`myCPU` | 模块互连和赛事接口适配 |

## 4. GShare 分支预测

`branch_predictor` 由三块状态组成：

- 128-entry BTB：用 PC 直接索引，保存 tag、target 和 branch kind。
- 256-entry PHT：用 `PC[9:2] XOR GHR[7:0]` 索引，每项是 2-bit 饱和计数器。
- 8-bit GHR：只在真实条件分支解析后移入 actual taken，不在取指时投机更新。

BTB 与 PHT 同步并行读取，预测延迟仍为一拍。PHT 未训练项按 `2'b01`（weakly not-taken）处理。预测时使用的 PHT index 和 counter 随 `fetch_entry_t -> uop_t -> exec_req_t` 传到 EX，分支解析时按原 index 训练，不能用当时已经变化的 GHR 重新计算。

同拍预测和训练命中相同 BTB/PHT entry 时使用写入值旁路，避免 FPGA RAM read-during-write 模式差异。GHR 采用非投机更新，因此 redirect 不需要历史恢复；代价是分支解析前的后续预测仍使用旧历史。

## 5. Scoreboard 合同

Scoreboard 深度为 `SCOREBOARD_DEPTH=8`，transaction ID 直接等于 entry index。

内部状态：

- `allocate_ptr`：下一条发射指令的 entry。
- `commit_ptr`：最老未提交 entry。
- `count`：当前 occupied 数。
- `producer_valid/tid[32]`：每个架构寄存器的 youngest in-flight producer。
- `serial_pending`：CSR/system/fence 序列化屏障。

同周期更新优先级必须保持：

```text
completion write -> commit clear -> younger allocation
```

所有更新使用 nonblocking assignment；同槽复用时，最后的 allocation 覆盖老 entry 的 completion/clear。producer map 同样由年轻 allocation 覆盖老 commit 的清除。

若改变这个文本优先级，满窗口同拍 commit+issue 时可能清掉新 entry，或 WAW 后错误地取消 youngest producer。

## 6. 操作数与旁路

`operand_resolver` 的优先关系为：

```text
RF / x0
  -> previous Commit-WB
  -> Scoreboard youngest producer
  -> fixed completion
  -> load completion
  -> MDU/Bitmanip completion
```

Memory 地址源有独立的 `src1_memory_value/ready`。Fixed 和 slow completion 可以进入该路径，DCache completion 只进入普通 consumer bypass，不直接驱动地址路径。这是现有时序切分，模块化后仍保持。

CSR 指令已经 serialize，CSR source 继续在 `core_top` 直接取 RF 加 Commit-WB，不经过通用 completion 网络。

## 7. StoreBuffer 合同

Store 在 EX 完成时进入 StoreBuffer，但此时仍是投机状态：

1. Scoreboard entry 保存 `store_slot`。
2. Store 到达 Commit head 后，对对应 slot 设置 committed。
3. Memory arbiter 只允许 committed head store 请求 DCache/外部总线。
4. 请求握手后 head 才释放。

full flush 只删除未提交 store；已提交 store 保留并继续 drain。flush 时重新计算 count/tail，但不改变 head 和 sequence 编号。

同周期内部更新顺序保持 `commit mark -> enqueue -> drain`。

## 8. LoadQueue 和转发合同

Load EX 时先快照当时所有 older store：

- 仅 DRAM/cacheable load 使用 StoreBuffer forwarding。
- StoreBuffer 从 head 向 tail 扫描，后扫描的年轻 store 覆盖相同 byte。
- partial forwarding 在 memory response 返回后逐 byte merge。
- 全部 byte 已被覆盖时，不发 DCache 请求，直接 completion。

LoadQueue slot 0 永远是最老等待 load。只有一个 `active_meta` 记录已经被 DCache 接受、等待 response 的事务。completion 清 active 后，同拍 direct/queued start 可以重新设置 active；该覆盖顺序不能改变。

Uncached load 只有在自身为 Scoreboard head 且 older store 不存在时才允许访问。

## 9. Memory 请求优先级

`memory_request_arbiter` 的固定优先级：

```text
committed StoreBuffer head
  > EX direct load candidate
  > LoadQueue head
```

Direct DRAM load 可在 LoadQueue 为空时直接启动。Uncached direct load 还要求 transaction ID 等于 commit pointer 且没有 older store。

DCache 到外部 DMEM 之间保留 `dmem_regslice`，所以模块化没有改变请求寄存级或 ready/valid 时序。

## 10. Commit、恢复与 flush

Commit 条件：

- head `occupied && done`。
- store entry 对应 slot 仍 valid。
- fence/fence.i 等待 StoreBuffer、LoadQueue、active load、DCache 和 MDU quiescent。

恢复优先级由 `recovery_ctrl` 生成：

1. exception -> `mtvec`
2. mret -> `mepc`
3. branch miss -> actual next PC

full flush 清 Scoreboard、LoadQueue 和 EX valid，StoreBuffer 只清投机项。Branch predictor update 信息仍打一拍，避免 EX 比较结果直接驱动全局 redirect/allocation。

## 11. Debug 和综合隔离

`commit_trace_probe` 只在 `VERILATOR_TB` 下存在，采样与 Commit 相同的 pre-NBA 状态。OpenXiangShan `DiffExt*` probes 进一步受 `ENABLE_DIFFTEST` 保护。

因此普通 Vivado elaboration 不包含：

- commit debug 顶层端口；
- per-transaction debug metadata；
- DiffTest DPI module。

## 12. 维护约束

1. 不得把可变延迟 FU response 直接写 GPR；必须先按 transaction ID 完成 Scoreboard entry。
2. 不得让未 committed store 产生外部写副作用。
3. 不得在 flush 时删除已经 committed 的 store。
4. 不得改变 Scoreboard completion/commit/allocation 的同拍覆盖顺序。
5. 不得让 DCache completion 进入 memory-address ready 旁路。
6. 新增 RTL 文件后同步更新 `scripts/filelists/core.f`；package 必须排在所有消费者之前。
7. GShare 训练必须使用随指令保存的 `pred_index/pred_counter`，不得在 EX 用当前 GHR 重算 index。
7. 改动状态边界后至少运行普通 myCPU/student_top build、RV32 支持集和 src DiffTest 窗口。
