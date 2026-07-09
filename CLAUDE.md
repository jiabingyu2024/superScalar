# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**superScalar** — 面向教学/实验的 RV32 CPU，目标是 2-way 超标量乱序处理器（ROB 精确提交、IssueQueue 乱序发射、物理寄存器重命名、StoreBuffer、分支预测）。FPGA 目标板：Kintex-7 (`xc7k325tffg900-2`)，系统时钟 50 MHz。

> **当前状态（branch `dev-7-standby`）：** 核心 RTL 正处于重构过渡期。`rtl/core/` 下已有文件实现的是一个**5 级顺序流水线**（PC→IF→ID→EX→M1→M2→WB），而非 README/docs 中描述的超标量 OoO 架构。`scripts/filelists/core.f` 和 `soc.f` 引用的大量文件路径**已失效**（旧架构遗留），直接使用会导致编译报错。

---

## Build & Simulation

### 依赖

`python3`, `make`, `g++`, Verilator（必需）；Vivado 可选（FPGA 流程）。

### 构建 Verilator 模型

```bash
# myCPU 入口，用于 RV32 ISA 测试
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=

# student_top/SoC 入口，用于 src profile 测试
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

构建底层调用 `scripts/run_verilator.py`，filelists 通过 `scripts/filelists/` 下的 `.f` 文件指定。

### 运行仿真

```bash
# 单个 RV32 ISA 测试
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 OBJCACHE=

# 全套 RV32 测试
make sim-rv32-all NO_BUILD=1 OBJCACHE=

# src 短窗口性能采样
make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=

# src 长窗口（默认 100M 周期）
make sim-src TEST=srcWithMext NO_BUILD=1 OBJCACHE=

# 覆盖最大周期
make sim-src TEST=srcSmoke SRC_MAX_CYCLES=50000000 NO_BUILD=1 OBJCACHE=
```

结果 JSON 写入 `build/result/rv32/` 和 `build/result/src/`，包含 `correctness`、`perf.ipc`、`perf.stalls`、`perf.resources`、`perf.width` 等字段。

### 补齐测试数据

```bash
python3 scripts/prepare_test_data.py
```

测试数据（`.hex`/`.coe`/`.dump`）位于 `data/`，按 profile 分目录（`rv32ui/`、`rv32um/`、`srcWithMext/` 等）。

### FPGA 工程生成

```bash
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

不存在预构建的 `.xpr`，每次通过 Tcl 生成。IP 使用 Vivado 原语（不是 `rtl/ip/` 下的行为模型），后者仅用于 Verilator 仿真。

---

## RTL 架构

### 层次结构

```
rtl/soc/top.sv              ← FPGA board top（差分时钟输入、PLL、UART、digital-twin）
└── student_top.sv          ← SoC integration top（myCPU + IROM_0 + perip_bridge）
    └── myCPU.sv            ← CPU 封装（rst_n 极性转换，接口适配）
        └── core.sv         ← CPU core top
rtl/ip/                     ← 仿真行为模型（IROM_0、DRAM_0、MUL_0、DIV_0、pll）
```

### 当前 core.sv 流水线

`rtl/core/core.sv` 实现的是顺序流水线，各目录职责：

| 目录 | 内容 |
|---|---|
| `pc/` | PC 寄存器与 next-PC 逻辑（`stage_pc.sv`, `pc_reg.sv`） |
| `if/` | 取指对齐（`stage_if.sv`） |
| `id/` | 译码、立即数扩展、整数寄存器堆（`stage_id.sv`, `control_unit.sv`, `regfile.sv`, `imm_unit.sv`） |
| `ex/` | ALU、分支比较（`stage_ex.sv`, `alu.sv`, `branch_cmp.sv`） |
| `m2/` | 访存返回对齐（`stage_m2.sv`） |
| `wb/` | 写回 mux（`stage_wb.sv`） |
| `pipeline_regs/` | 各级流水寄存器（`reg_pc_if`→`reg_if_id`→`reg_id_ex`→`reg_ex_m1`→`reg_m1_m2`→`reg_m2_wb`） |
| `control/` | `bpu_top.sv`（分支预测）、`hazard_unit.sv`（stall/flush/pc_next）、`forward_unit.sv`（前递选择） |

外部存储接口：`irom_*`（组合读）、`dram_*`（M1 写，M2 读返回）。

### SoC 外设（`rtl/soc/`）

`perip_bridge.sv` 将 CPU 访存路由到 DRAM（`0x8010_0000`–`0x8013_FFFF`）和 MMIO（LED、SEG、SW、KEY、counter）；`dram_driver.sv` 驱动片外 DRAM；`uart.sv` + `twin_controller.sv` 实现 digital-twin 虚拟 I/O 协议（仿真和 FPGA 板级通信）。

---

## 开发约定

- RTL 修改后至少跑对应 RV32 directed 测试；涉及控制路径或宽度时跑 `verilator-build` + `verilator-build-src` + src 短窗口。
- 性能分析同时看 `perf.stalls`、`perf.resources`、`perf.mem_stalls` 和 `perf.width`，不只看 IPC。
- 当前设计事实维护在 `docs/design/`；调试/优化过程记录在 `docs/archive/YYYY-MM-DD/`。
- `build/` 是生成物，`backup/` 是临时备份，均不作为设计依据。
- **更新 filelists 时注意：** `scripts/filelists/core.f` 仍引用旧路径（`rtl/core/front/`、`rtl/core/execute/` 等），修改 RTL 目录结构后需同步更新对应 `.f` 文件。

## 关键文档入口

- 总文档索引：[docs/README.md](docs/README.md)
- Core 设计：[docs/design/rtl_core_design.md](docs/design/rtl_core_design.md)
- 仿真计划：[docs/sim/verilator_plan.md](docs/sim/verilator_plan.md)
- FPGA 工程：[docs/fpga/vivado_project.md](docs/fpga/vivado_project.md)
