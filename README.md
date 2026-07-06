# superScalar

这是一个面向教学/实验的 RV32 超标量乱序 CPU 项目。当前核心是 2-way 前端/后端、物理寄存器重命名、ROB 精确提交、IssueQueue 乱序发射、StoreBuffer、分支预测、Verilator 仿真与 Vivado FPGA 工程生成。

项目当前重点不是“最小可跑 CPU”，而是围绕超标量处理器工程实现进行持续 bring-up、性能定位和 RTL 优化。详细设计事实、调试记录和历史修改说明统一维护在 [docs/README.md](docs/README.md)。

## 快速上手

### 环境依赖

常用流程需要：

- `python3`
- `make`
- `g++`
- Verilator
- 可选：Vivado，用于 FPGA 工程生成
- 可选：RISC-V objdump 工具，用于重新生成缺失的 dump 文件

### 构建 Verilator 模型

构建 `myCPU` 入口，主要用于 RV32 ISA 类测试：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

构建 `student_top`/SoC 入口，主要用于 src profile 测试：

```bash
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

### 运行 RV32 测试

单个测试：

```bash
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lw NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32um-p-mul NO_BUILD=1 OBJCACHE=
```

整套测试：

```bash
make sim-rv32-all NO_BUILD=1 OBJCACHE=
```

结果 JSON 写入：

```text
build/result/rv32/
```

### 运行 src 测试

短窗口性能采样：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=
```

长窗口运行：

```bash
make sim-src TEST=srcWithMext NO_BUILD=1 OBJCACHE=
```

`src` 默认最大周期数由 `SRC_MAX_CYCLES` 控制，当前 Makefile 默认是 `100000000`。可显式覆盖：

```bash
make sim-src TEST=srcSmoke SRC_MAX_CYCLES=50000000 NO_BUILD=1 OBJCACHE=
```

结果 JSON 写入：

```text
build/result/src/
```

注意：`srcWithMext/srcWithoutMext` 等 src 测试在短窗口 TIMEOUT 通常不表示仿真框架错误；应结合结果 JSON 中的 `correctness` 和 `perf` 字段判断进度与性能。

### 生成/补齐测试数据

测试数据位于 `data/`。如果需要补齐缺失的 `.hex` 或 `.dump`：

```bash
python3 scripts/prepare_test_data.py
```

默认脚本尽量幂等，不覆盖已有文件；具体规则见 [docs/sim/verilator_plan.md](docs/sim/verilator_plan.md)。

## 目录结构

| 路径 | 职责 |
|---|---|
| `rtl/core/` | CPU core RTL，包含取指、译码、重命名、分发、发射、读寄存器、执行、写回、提交和恢复路径。 |
| `rtl/core/PreFetchStage/` | PC、BPU、BTB、BHB 等前端预测与预取逻辑。 |
| `rtl/core/FetchStage/` | IROM 取指返回对齐和 IF 级流水。 |
| `rtl/core/DecodeStage/` | 指令译码、packet split、serial/store/branch 分类。 |
| `rtl/core/RenameStage/` | SpecRAT、ArchRAT、FreeList、ReadyTable 相关重命名资源。 |
| `rtl/core/DispatchStage/` | ROB、IssueQueue、Payload、StoreBuffer 分配与分发。 |
| `rtl/core/IssueStage/` | 从 IssueQueue 选择 ready uop，读取 Payload，送往 ReadReg。 |
| `rtl/core/ReadRegStage/` | 物理寄存器堆读端口与 RR->EX 分流。 |
| `rtl/core/ExecuteStage/` | ALU/MEM/MUL/BRC/SYS 执行管线。 |
| `rtl/core/WriteBackStage/` | 多执行管线结果汇总、PRF 写回、ROB done、ReadyTable/IQ wakeup、bypass。 |
| `rtl/core/CommitStage/` | ROB 有序提交、ArchRAT 更新、FreeList 释放、store commit、恢复请求。 |
| `rtl/soc/` | SoC 顶层、student_top、MMIO、UART、七段数码管、DRAM driver 等板级/外设边界。 |
| `rtl/ip/` | 仿真/综合用 IP wrapper 或行为模型，例如 IROM、DRAM、MUL、DIV、PLL。 |
| `tb/verilator/` | Verilator C++ testbench、checker、memory model、结果 JSON、trace/perf 辅助代码。 |
| `scripts/` | 仿真入口和测试数据准备脚本。 |
| `data/` | RV32 ISA 测试和 src profile 的 `.hex/.coe/.dump` 输入数据。 |
| `docs/` | 当前设计事实、仿真规则、FPGA 说明、调试归档和变更记录。 |
| `fpga/` | Vivado 工程生成 Tcl、约束文件和 FPGA 相关配置。 |
| `build/` | Verilator 构建产物、日志和仿真结果。通常不手工编辑。 |
| `backup/` | 针对重要 RTL/文档修改的临时备份。通常不作为设计事实来源。 |
| `archive/` | 根目录级临时/专题归档。主要设计归档应优先放在 `docs/archive/`。 |

## 核心 RTL 分层

当前 core 的主要数据流：

```text
PreFetch -> Fetch -> Decode -> Rename -> Dispatch -> Issue -> ReadReg
        -> Execute(ALU/MEM/MUL/BRC/SYS) -> WriteBack -> Commit
```

关键共享资源：

- ROB：乱序执行到有序提交的精确状态边界。
- IssueQueue：保存等待发射的 uop，是当前性能分析中的关键瓶颈之一。
- Payload：保存较大的静态执行 payload，IssueQueue 只保存调度字段和索引。
- Physical RegFile：物理寄存器堆，当前写端口数为 `WAY_NUM * 5`。
- ReadyTable：记录物理寄存器 ready 状态。
- StoreBuffer：保存已分配 store，按提交顺序写入 DRAM，并支持 load forwarding。
- RecoveryManager：处理 branch miss、exception 等恢复请求。
- Ctrl：汇总 stall/flush/resource 信号并驱动各级流水控制。

更详细的微架构说明见 [docs/design/rtl_core_design.md](docs/design/rtl_core_design.md)。

## 仿真结果与性能分析

仿真完成后，结果 JSON 通常包含：

- `correctness`：PASS/FAIL/TIMEOUT、LED/SEG/tohost 等判定信息。
- `perf.commit_count` / `perf.ipc`：提交数和 IPC。
- `perf.stalls`：各流水级 stall 周期。
- `perf.resources`：ROB/IQ/FreeList/StoreBuffer/serial 等资源瓶颈。
- `perf.mem_stalls`：MEM/load/store 相关阻塞。
- `perf.width`：dispatch/issue/commit 的 0/1/2 宽度分布。

近期 IPC 分析记录：

- [docs/archive/2026-07-05/035_ipc_lt05_root_cause_and_optimization.md](docs/archive/2026-07-05/035_ipc_lt05_root_cause_and_optimization.md)
- [docs/archive/2026-07-05/036_srcWithMext_post_phase12_ipc_root_cause.md](docs/archive/2026-07-05/036_srcWithMext_post_phase12_ipc_root_cause.md)

当前阶段性结论：阶段 1/2 已消除 MEM load return 全局 stall 和 ROB full 主瓶颈；`srcWithMext` 长窗口的新主瓶颈是 IssueQueue 长期接近满且缺少 ready 可发射项。

## FPGA 工程

Vivado 工程入口：

```bash
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

也可以按 profile 生成不同内存初始化工程。详细约束、IP 和 Tcl 使用规则见 [docs/fpga/vivado_project.md](docs/fpga/vivado_project.md)。

## 常用命令速查

| 任务 | 命令 |
|---|---|
| 构建 RV32 仿真模型 | `make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=` |
| 构建 src 仿真模型 | `make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=` |
| 跑单个 RV32 测试 | `make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 OBJCACHE=` |
| 跑 RV32 全套 | `make sim-rv32-all NO_BUILD=1 OBJCACHE=` |
| 跑 src 短窗口 | `make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=` |
| 跑 src 长窗口 | `make sim-src TEST=srcWithMext NO_BUILD=1 OBJCACHE=` |
| 补齐测试数据 | `python3 scripts/prepare_test_data.py` |
| 查看 srcWithMext 结果 | `sed -n '1,220p' build/result/src/srcWithMext.json` |

## 开发约定

1. 修改 RTL 前，先确认相关接口文件、Types package 和当前设计文档。
2. 涉及共享结构的修改，例如 ROB/IQ/RegFile/StoreBuffer/Recovery，应同步检查 `CtrlIF`、`PipelineTypes`、对应 IF 和 top-level 连接。
3. 窄范围 RTL 修改应至少跑对应 RV32 directed 测试；影响后端控制、宽度或恢复路径时，应跑 `verilator-build`、`verilator-build-src` 和相关 src 短窗口。
4. 性能优化不要只看 IPC，要同时看 `perf.stalls`、`perf.resources`、`perf.mem_stalls` 和 `perf.width`。
5. 当前设计事实优先更新 `docs/design/`，调试/优化过程记录到 `docs/archive/YYYY-MM-DD/`。
6. `build/` 是生成物，`backup/` 是临时备份；不要把它们当成最新设计依据。

## 文档入口

- 总文档索引：[docs/README.md](docs/README.md)
- 项目框架：[docs/design/project_framework.md](docs/design/project_framework.md)
- Core 设计：[docs/design/rtl_core_design.md](docs/design/rtl_core_design.md)
- 仿真计划：[docs/sim/verilator_plan.md](docs/sim/verilator_plan.md)
- FPGA 工程：[docs/fpga/vivado_project.md](docs/fpga/vivado_project.md)
