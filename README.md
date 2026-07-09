# superScalar 当前 CPU 架构说明

本仓库当前 `rtl/core` 实现的是一个 **RV32 双发射、顺序执行、阻塞式长延迟执行** 的 CPU。原先乱序执行相关的 Rename、ROB、物理寄存器、乱序 IssueQueue、Commit 等 RTL 已从当前编译路径中移除。

## 当前核心特性

- ISA 覆盖当前测试使用的 RV32I、RV32M、CSR、部分 Zb 位操作指令。
- 前端每次最多取 2 条 32-bit 指令。
- Decode 与 Issue 分离。
- Issue 阶段维护一个小型顺序发射队列。
- 支持双发射顺序执行，但只允许满足配对条件的两条指令同周期进入 EX。
- 使用 64 项 2-bit 条件分支预测器。
- Load/Store 使用阻塞式访存状态机。
- MUL/DIV/REM 使用独立多拍单元，执行期间暂停前端和 issue，但不清空 issue queue。
- 支持 WB 到 EX 前递，以及 slot0 到 slot1 的同周期前递。

## 当前流水结构

当前设计可按以下阶段理解：

```text
Fetch -> Decode -> IssueQueue/Issue -> Execute -> WriteBack/Memory/MulDiv
```

### Fetch

文件：

- `rtl/core/InOrderFetchStage.sv`

职责：

- 维护取指 PC。
- 访问 IROM，一次取 2 条指令。
- 使用 64 项 2-bit BPU 预测条件分支。
- 在 redirect 时刷新前端并跳转到正确 PC。
- 当后端阻塞时保持当前取指状态。

### Decode

文件：

- `rtl/core/InOrderDecodeStage.sv`

职责：

- 将 fetch packet 拆成最多 2 条 `Uop`。
- 如果第一条是已预测 taken 的条件分支，则第二条不进入 decode 输出。
- 生成 `decodeCount`，供 issue queue 入队使用。

### IssueQueue / Issue

文件：

- `rtl/core/InOrderIssueQueue.sv`

职责：

- 顺序缓存 decode 后的 uop。
- 每周期最多发射 2 条。
- 保持程序顺序，不做乱序选择。
- 判断相邻两条指令是否可以双发。

当前不能双发的情况包括：

- 任意一条是 control 指令。
- 任意一条是 load/store。
- 任意一条是 RV32M 的 mul/div/rem 指令。
- 两条指令存在 WAW。

### Execute

文件：

- `rtl/core/InOrderExecuteStage.sv`

职责：

- 执行 1 拍 ALU、branch、CSR、load/store 地址生成。
- 解析条件分支并产生 redirect。
- 对 load/store 产生访存请求信息。
- 对 MUL/DIV/REM 只产生 `mulDivReq`，不在 EX 内组合计算。
- 提供 WB 到 EX 前递，以及 slot0 到 slot1 同周期前递。

### MulDiv

文件：

- `rtl/core/InOrderMulDivUnit.sv`

职责：

- 执行 RV32M 的 MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU。
- MUL 使用移位加法迭代。
- DIV/REM 使用逐位恢复除法。
- 单元工作期间 core 进入 `M_MULDIV_WAIT`，暂停前端和 issue。
- 完成后进入 `M_MULDIV_WB` 写回泡泡，再恢复正常发射。
- Issue queue 在 MUL/DIV/REM 期间不会被清空。

### Memory

文件：

- `rtl/core/core.sv`

职责：

- Load 使用 `M_LOAD_REQ -> M_LOAD_WAIT0 -> M_LOAD_WAIT1`。
- Store 使用 `M_STORE_REQ`。
- 访存期间暂停前端和 issue。
- 访存完成后写回或提交，再恢复正常执行。

## 分支预测与性能计数

性能计数接口：

- `rtl/core/PerfIF.sv`

主要计数：

- `cycle`：core 周期数。
- `commitCnt`：已完成指令数。
- `branchCnt`：控制流指令总数。
- `branchMissCnt`：控制流 redirect/miss 总数。
- `condBranchCnt`：条件分支总数。
- `condBranchMissCnt`：条件分支预测错误数。

测试结果 JSON 中：

```text
ipc = commit_count / cycles
branch_hit_rate = (branch_count - branch_miss_count) / branch_count
```

注意：`branch_hit_rate` 包含 JAL/JALR 等控制流指令，不是纯条件分支 BPU 准确率。当前条件分支预测准确率应看：

```text
1 - branch_breakdown.conditional.miss_rate
```

## 当前编译 RTL

当前 core filelist：

- `scripts/filelists/core.f`

当前 `rtl/core` 编译文件：

- `BasicTypes.sv`
- `IromAccessIF.sv`
- `DramAccessIF.sv`
- `DebugIF.sv`
- `PerfIF.sv`
- `InOrderTypes.sv`
- `InOrderFetchStage.sv`
- `InOrderDecodeStage.sv`
- `InOrderIssueQueue.sv`
- `InOrderExecuteStage.sv`
- `InOrderMulDivUnit.sv`
- `core.sv`
- `myCPU.sv`

## 验证方法

常用正确性回归：

```bash
env CCACHE_DIR=/tmp/superscalar_ccache python3 scripts/run_verilator.py rv32 --all --build
```

系统级 smoke 测试：

```bash
env CCACHE_DIR=/tmp/superscalar_ccache python3 scripts/run_verilator.py src --test srcSmoke --max-cycles 100000000 --build
```

最近一次确认结果：

```text
rv32 --all: PASS
srcSmoke: PASS

srcSmoke cycles:       49,831,041
srcSmoke commit_count: 30,758,613
srcSmoke IPC:          0.617258
srcSmoke LED pass:     0x01221c08
```

## 维护注意事项

- 不要把旧乱序 RTL 重新加入 `scripts/filelists/core.f`，除非明确要回退到乱序架构。
- 修改 fetch/IROM 时序时，要注意 `InOrderFetchStage` 假设 IROM 返回与上一拍请求 PC 对齐。
- 修改 issue queue 时，要保证 MUL/DIV/REM 阻塞期间队列内容不会被清空或重复出队。
- 修改前递逻辑后必须跑 `rv32 --all`，重点关注 RAW、M 扩展和 branch 测试。
- 修改性能计数逻辑后，需要确认 JSON 中 IPC 和分支统计含义是否仍然一致。
