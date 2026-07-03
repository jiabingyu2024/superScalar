# rv32ui myCPU 定位与修复记录

## 1. 本次目标

定位 `myCPU` 当前“一条 rv32ui 都过不了”的根因，优先让 `rv32ui` 官方整数测试集通过。默认仿真周期上限保持较小，避免把 RTL 死锁误判成慢测试。

## 2. 最终结论

本次修复后：

```sh
scripts/run_verilator.py rv32 --suite rv32ui --max-cycles 30000
```

结果：`rv32ui` 当前仓库内所有测试均 `PASS`。

## 3. 已确认并修复的问题

### 3.1 Store 译码把 rs2 数据当成立即数

现象：

- `rv32ui-p-simple` 写 `tohost=0xffffffc4`。
- 该值正好是 `sw gp,-60(t5)` 的 S-type 立即数 `-60`，说明 store 写数据来自 imm，而不是 rs2/gp。

根因：

- `DecodeSTORE` 中 `opTypeB` 错设为 `OP_TYPE_IMM`。
- `ReadRegStage/ExecuteMemStage` 因此把 store dataB 走成立即数。

修复：

- `DecodeSTORE.opTypeB = OP_TYPE_REG`。
- store 地址仍由 `rs1 + imm` 计算，store 数据来自 rs2。

涉及文件：

- `rtl/core/DecodeStage/DecodeTypes.sv`

### 3.2 Flush 只屏蔽输出，没有清掉级间寄存器

现象：

- `rv32ui-p-lui` 分支恢复后仍提交错误路径 `ecall`，写出失败码。
- 波形显示恢复目标 PC 正确，但 Decode/后端残留旧 uop。

根因：

- 多个 stage 在 `flush` 时只让输出 valid 变 0，没有清内部 `pipeReg`。
- `DecodeStage` 特别危险：flush 时清了 replay 状态，但没有清 `pipeReg`，错误路径指令会在 stall 解除后重新出现。

修复：

- 在 Fetch/Decode/ReadReg/各 Execute/WriteBack 的 `flush` 分支清空内部寄存器。

涉及文件：

- `rtl/core/FetchStage/FetchStage.sv`
- `rtl/core/DecodeStage/DecodeStage.sv`
- `rtl/core/ReadRegStage/ReadRegStage.sv`
- `rtl/core/ExecuteStage/ExecuteAluStage.sv`
- `rtl/core/ExecuteStage/ExecuteBrcStage.sv`
- `rtl/core/ExecuteStage/ExecuteMemStage.sv`
- `rtl/core/WriteBackStage/WriteBackStage.sv`

### 3.3 Recovery PC 没有同步驱动 IROM 请求地址

现象：

- 分支恢复时 PC 寄存器更新为目标地址，但同周期 IROM 地址仍可能使用旧 `pcOut`。
- 若随后前端 stall 让 IROM enable 关闭，IROM 地址寄存器会保持错误路径地址，造成 PC/inst 错配。

修复：

- `PreFetchStage` 在 `recovery.pcUpdateEn` 时强制 `iromAccess.ena=1`。
- `iromAccess.iromAddr` 优先使用 `recovery.pcUpdate`。

涉及文件：

- `rtl/core/PreFetchStage/PreFetchStage.sv`

### 3.4 ReadyTable 缺少 same-cycle markReady bypass

现象：

- rename/dispatch 可能在同周期读取一个正在 WB markReady 的物理寄存器，读到旧 not-ready 状态。

修复：

- `ReadyTable` 组合读时检查同周期 `markReady` 端口，命中则返回 ready。

涉及文件：

- `rtl/core/RenameStage/ReadyTable.sv`

### 3.5 Dispatch 被 stall 时不接收 wakeup

现象：

- `rv32ui-p-add` 早期死锁，ROB full，某些 branch/source 永远 not ready。
- 波形显示生产者 WB wakeup 发生时，依赖 uop 仍停在 Dispatch pipeReg；进入 IssueQueue 时仍带旧 not-ready 位。

根因：

- Dispatch 级被后端 stall 保持时，没有用 `IssueWakeup` 更新 held uop 的源 ready。
- 发往 IssueQueue 的 push entry 也没有吸收 same-cycle wakeup。

修复：

- `IssueQueueIF.DispatchStage` 暴露 `IssueWakeup` 输入。
- `DispatchStage` 在 stall holding 时更新 `pipeReg` 的源 ready。
- 构造 `IssuePushReq` 时合并 same-cycle wakeup。

涉及文件：

- `rtl/core/DispatchStage/IssueQueueIF.sv`
- `rtl/core/DispatchStage/DispatchStage.sv`

### 3.6 MEM uop 乱序导致 load 越过 older store

现象：

- `rv32ui-p-sw/st_ld/ld_st` 曾出现失败或死锁。
- 波形显示 younger load 对同地址发起 DRAM read，而 older store 还没有写入 StoreBuffer。

根因：

- IssueQueue 原本只限制“每周期最多一个 MEM”，但不保证 MEM uop 按程序序发射。
- 单纯在 StoreBuffer 遇到未知 store 时全局阻塞会死锁：load 卡住 EX，older store 反而无法进入 EX 填充 StoreBuffer。

修复：

- IssueQueue 内部增加 `entryAge/ageCounter`，按 dispatch 进入 IQ 的顺序记录本地年龄。
- MEM 候选如果前面还有更老 MEM entry，即使更老 entry 未 ready，也不能发射。
- StoreBuffer 只对已填充 entry 做完整转发或部分字节冲突阻塞，不对任意未填充 entry 做全局 unknown-store 阻塞。

涉及文件：

- `rtl/core/DispatchStage/IssueQueue.sv`
- `rtl/core/DispatchStage/StoreBuffer.sv`

### 3.7 ROB 1-bit position 不能作为 IssueQueue 长期年龄比较依据

现象：

- `rv32ui-p-st_ld` 在 test_21 附近，`sw @0x80000408` 比 `lw @0x8000040c` 更老，但 `lw` 先发射并读到旧值。

根因：

- 原比较依赖 `robIndexPosition + robIndex`。
- ROB 环形队列多次 wrap 后会出现 `rob15,pos1` 比 `rob0,pos0` 更老，但简单 `position` 比较无法判断当前 epoch。

修复：

- IssueQueue 内部所有 oldest 选择和 MEM 保序统一使用本地单调 `entryAge`。
- ROB 的 `robIndex` 仍只用于 WB 回填 done。

涉及文件：

- `rtl/core/DispatchStage/IssueQueue.sv`

### 3.8 IssueStage 在 stall 时错误 pop Payload

现象：

- `rv32ui-p-lh` 超时。
- 末态 ROB full，后端空，ROB head `PC=0x800002ec` 未 done。
- 波形显示 `isPipe.stall=1` 时 IssueQueue 没有 pop，但 Payload 被 pop；下一拍同一 IQ entry 真正发射时 payload 已经丢失，uop 无法进入后端完成。

根因：

- `payload.PayloadPopReq.valid` 只看 `IssuePopRes.done`，没有和 `IssuePopReq.valid` 同步。

修复：

```text
issueFire = !isPipe.stall && !isPipe.flush && IssuePopRes.done
```

只有 `issueFire` 为 1 时才 pop IssueQueue、pop Payload，并让 `IssueStage.nextStage.valid=1`。

涉及文件：

- `rtl/core/IssueStage/IssueStage.sv`

### 3.9 Verilator 自动重编译依赖不完整

现象：

- RTL 修改后如果只看 TB/filelist mtime，可能运行旧二进制，调试结论会被污染。

修复：

- `scripts/run_verilator.py` 递归解析 `-f` filelist，把 RTL/package/header 源文件 mtime 纳入重编译判断。

涉及文件：

- `scripts/run_verilator.py`

## 4. 关键设计事实更新

长期维护时按以下事实理解当前实现：

1. store 解码：地址 `rs1 + imm`，数据必须来自 `rs2`。
2. flush 必须清 stage 内部寄存器，不能只屏蔽输出 valid。
3. recovery redirect 同周期必须驱动 IROM 地址。
4. Dispatch/IssueQueue 都要消费 same-cycle wakeup，避免 uop 在 stall holding 中错过 ready。
5. IssueQueue 使用本地 `entryAge` 判断调度年龄，不依赖 ROB 1-bit position。
6. MEM uop 当前保守按程序序发射，用正确性换取较低实现风险。
7. Payload pop 必须和 IssueQueue pop 同步，统一由 `issueFire` 控制。
8. StoreBuffer 负责 forwarding 和有序提交，不负责 unknown older store 全局阻塞。

## 5. 验证记录

已运行：

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --max-cycles 2000 --trace
scripts/run_verilator.py rv32 --test rv32ui-p-lui --build --max-cycles 5000
scripts/run_verilator.py rv32 --test rv32ui-p-add --build --max-cycles 10000
scripts/run_verilator.py rv32 --test rv32ui-p-sw --build --max-cycles 10000
scripts/run_verilator.py rv32 --test rv32ui-p-st_ld --build --max-cycles 20000
scripts/run_verilator.py rv32 --test rv32ui-p-lh --build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32ui --max-cycles 30000
git diff --check
```

最终结果：

| 项 | 结果 |
| --- | --- |
| `rv32ui` suite | 全部 PASS |
| `git diff --check` | 无 whitespace/error 输出 |

## 6. 后续注意

1. 当前 MEM 保序偏保守，会降低性能；后续若要优化，需要引入 load/store age、store address-ready 和 replay/violation 机制，不能直接放开 load 越过 unknown older store。
2. `entryAge` 是 IssueQueue 内部 32-bit 单调计数，足够当前仿真使用；若未来长时间运行且 IQ entry 生命周期跨越计数回绕，需要改成带环形比较或更宽计数。
3. 本次只证明 rv32ui 通过，不代表 M 扩展、异常、src 性能程序已经全部正确。
