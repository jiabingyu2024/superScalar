# DiffTest integration plan

Date: 2026-07-09

## Implementation update

Status after implementation on 2026-07-09:

- Added `VERILATOR_TB` commit/GPR/CSR probes in `riscv_cpu.sv`.
- Forwarded probes through `myCPU.sv` and `student_top.sv`.
- Added isolated `tb/difftest/` adapter and harness.
- Added independent `scripts/run_difftest.py`.
- Added Makefile targets:
  - `difftest-build`
  - `difftest-build-src`
  - `sim-rv32-difftest`
  - `sim-src-difftest`
- Cloned OpenXiangShan DiffTest into `tb/difftest/upstream`.
- Fixed upstream version at commit `f65181bf3be2a444669e1a3f83f784e532a92154`.
- Added upstream-profile-compatible RV32 single-commit profile at `tb/difftest/profiles/rv32_single_commit.json`.

Verified:

```text
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2  PASS
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2          PASS
make sim-rv32 TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2           PASS
make sim-src TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2                   PASS
```

Current limitation:

- The runnable local path is commit-trace self-check, not full reference-model differential checking yet.
- Upstream interface generation command was attempted and failed because `mill` is not installed:

```text
make -C tb/difftest/upstream PROFILE=... DESIGN_DIR=...
make: mill: Not a directory
```

Next required step for full OpenXiangShan/NEMU DiffTest:

1. Install/provide `mill` for the version in `tb/difftest/upstream/.mill-version`.
2. Run the profile generation command to populate `tb/difftest/generated`.
3. Link generated C++ and reference model library into `run_difftest.py`.
4. Replace `reference_enabled=false` adapter mode with real reference step/check calls.

## 目标

在 `tb/difftest/` 下引入 OpenXiangShan DiffTest 能力，把当前 Verilator 测试从“tohost/LED/结果检查”扩展为“提交级架构状态差分检查”。

本计划只描述接入方案，不立即修改 RTL/C++。待审查确认后再分阶段实现。

## DUT 边界结论

本工程当前没有 `student_cpu` 模块。

实际 DUT 分两层：

| 测试类别 | Verilator 顶层 | 真正 CPU DUT | 说明 |
|---|---|---|---|
| `rv32` 类 ISA 测试 | `myCPU` | `myCPU` / 内部 `riscv_cpu` | 直接对 CPU 核和 testbench memory model 做仿真 |
| `src` 类 SoC 测试 | `student_top` | `student_top.Core_cpu`，类型仍是 `myCPU` | 顶层包含 IROM、SocMemBridge、LED/SEG/counter 等外设 |

因此 DiffTest 的架构状态比对对象应统一定义为 `myCPU` 内部的 `riscv_cpu` 提交点，而不是 `student_top` 这个 SoC 壳。`student_top` 只是在 `src` 模式下承载外设和双时钟板级接口。

## 背景判断

OpenXiangShan DiffTest 是面向 RISC-V CPU 的协同仿真框架。其 README 明确说明：

- DiffTest 是 RISC-V 处理器现代协同仿真框架。
- 运行镜像默认从 `0x8000_0000` 线性装载，支持 binary/gz/zstd/ELF 等格式。
- 推荐 Chisel 集成，但非 Chisel 设计可以基于配置生成 Verilog/C++ 接口。
- Mandatory probes 包括 `DiffInstrCommit`、`DiffArchEvent`、`DiffTrapEvent`、`DiffCSRState`、整数寄存器状态探针等。

参考仓库：<https://github.com/OpenXiangShan/difftest>

当前项目状态：

- Verilator 入口：`tb/verilator/main_mycpu.cpp`
- SoC/src Verilator 入口：`tb/verilator/main_student_top.cpp`
- 构建脚本：`scripts/run_verilator.py`
- 当前 RV32 checker：`tb/verilator/checker_rv32.cpp`
- DUT 顶层：`rtl/core/myCPU.sv`
- src 顶层：`rtl/soc/student_top.sv`
- 当前核心主体：`rtl/core/riscv_cpu.sv`
- 当前 `myCPU` 只在 `VERILATOR_TB` 下暴露性能计数，没有暴露 commit 明细。
- 当前 `student_top` 只把 `myCPU` 的性能计数和外设写请求透出，没有透出 CPU commit 明细。
- `riscv_cpu.sv` 当前实现是简化多周期状态机，普通指令在 `ST_EXEC` 提交，load 在 `ST_WAIT_MEM` 响应时提交，mul/div 在 `ST_WAIT_MULDIV` 完成时提交。

## 总体策略

不要直接把 DiffTest 大量逻辑混入 `tb/verilator/`，也不要把 DiffTest 作为 `scripts/run_verilator.py --difftest` 的附加模式。建议单独建立 `scripts/run_difftest.py`，构建目录、main harness、adapter、结果目录都和现有 Verilator 回归隔离。

建议在 `tb/difftest/` 下形成独立边界：

```text
tb/difftest/
  README.md
  upstream/                  # OpenXiangShan/difftest 子模块或固定版本源码
  generated/                 # 由 DiffTest profile 生成的 Verilog/C++ 接口
  adapter/
    difftest_adapter.h
    difftest_adapter.cpp     # 项目本地 wrapper，屏蔽上游 API 变化
    commit_trace.h           # DUT commit bundle 的 C++ 表示
    dut_commit_io.h
    dut_commit_io.cpp        # myCPU/student_top 两种 Verilated 顶层的 commit 采集
  harness/
    main_difftest_mycpu.cpp
    main_difftest_student_top.cpp
  profiles/
    rv32_single_commit.json  # 本项目第一阶段 DiffTest probe 配置
  scripts/
    build_difftest.py        # 可选：生成接口、检查依赖、构建 reference
```

设计原则：

1. RTL 只增加 `VERILATOR_TB` 下的调试/差分测试输出，不影响 FPGA 综合接口。
2. 当前先支持 RV32I/M/Zicsr 的单提交路径，不一次性追求乱序/多提交完整形态。
3. C++ testbench 通过本地 adapter 调 DiffTest，不让普通 `tb/verilator/main_*.cpp` 直接依赖上游内部头文件。
4. 现有 `checker_rv32`/`checker_src` 保留在普通 Verilator 回归中；DiffTest 使用独立 harness，可复用现有 memory/checker 公共库，但不改变普通仿真路径。
5. 所有外部依赖固定版本，避免上游 master 漂移导致本地构建不稳定。

## Phase 0: 固定上游版本与目录边界

目标：只引入目录和构建边界，不改 DUT 行为。

计划动作：

1. 在 `tb/difftest/upstream` 以 git submodule 或固定源码目录引入 `https://github.com/OpenXiangShan/difftest.git`。
2. 记录上游 commit hash 到 `tb/difftest/README.md`。
3. 明确依赖：
   - Verilator
   - C++17 编译器
   - DiffTest 自身构建工具链
   - 参考模型：优先 NEMU，Spike 可作为后续选项
4. 新增独立入口，不修改 `run_verilator.py` 的常规行为：
   - `scripts/run_difftest.py rv32 ...`
   - `scripts/run_difftest.py src ...`

审查点：

- 是否接受把第三方仓库放在 `tb/difftest/upstream`。
- 是否使用 submodule。我的建议是 submodule，因为后续更新和版本固定更清晰。
- 是否接受 DiffTest 完全独立 runner。我的建议是接受，这样普通 Verilator 回归不承担 DiffTest 的依赖和链接复杂度。

## Phase 1: 增加 DUT commit probe

目标：先让 RTL 明确输出“本周期退休了什么”，这是 DiffTest 的核心前提。

拟新增 `VERILATOR_TB` 信号：

```systemverilog
output logic        dbg_commit_valid,
output logic [31:0] dbg_commit_pc,
output logic [31:0] dbg_commit_inst,
output logic        dbg_commit_wen,
output logic [4:0]  dbg_commit_rd,
output logic [31:0] dbg_commit_wdata,
output logic        dbg_commit_is_load,
output logic        dbg_commit_is_store,
output logic        dbg_commit_is_mmio,
output logic        dbg_commit_is_trap,
output logic [31:0] dbg_commit_cause,
output logic [31:0] dbg_commit_next_pc
```

信号添加层级：

1. `riscv_cpu.sv` 产生真实 commit bundle。
2. `myCPU.sv` 在 `VERILATOR_TB` 下把 commit bundle 透出。
3. `student_top.sv` 在 `VERILATOR_TB` 下继续把 `Core_cpu` 的 commit bundle 透出，供 `src` DiffTest harness 使用。

初始映射：

| 场景 | valid | pc/inst 来源 | 写回来源 | next_pc |
|---|---:|---|---|---|
| 普通 ALU/branch/jal/csr | `ST_EXEC && commit` | `pc_q` / `exec_inst_c` | decode 后实际写回结果 | `next_pc` |
| store | `ST_EXEC && commit && store accepted` | `pc_q` / `exec_inst_c` | no rf write | `pc_q + 4` 或 branch target |
| load | `ST_WAIT_MEM && cache_resp_valid` | 需要锁存 load 发起时的 pc/inst | load_extend 结果 | `pc_q + 4` |
| mul/div | `ST_WAIT_MULDIV && muldiv_done` | 需要锁存 mul/div 发起时的 pc/inst | `muldiv_result` | `pc_q + 4` |
| ecall/ebreak/mret | `ST_EXEC && commit` | `pc_q` / `exec_inst_c` | CSR/trap 状态 | trap target 或 `mepc` |

需要新增的内部锁存：

- `load_pc_q`
- `load_inst_q`
- `muldiv_pc_q`
- `muldiv_inst_q`

原因：load 和 mul/div 的提交晚于发起周期。如果只用当前 `pc_q`/`inst_q`，DiffTest 会看到错误退休指令。

如果删掉或做错：load/mul/div 会和参考模型在第一条长延迟指令处错位，后续全部提交都可能假失败。

审查点：

- 当前 `riscv_cpu.sv` 的写回通过 task `write_gpr()` 直接非阻塞赋值，commit probe 需要同步得到同一个写回值。实现时建议先在 `ST_EXEC` 内部计算 `wb_wen/wb_rd/wb_data`，再统一写 GPR 和 probe，避免 probe 与真实写回分叉。
- `x0` 写回必须输出 `rfwen=0`，即使指令写 `rd=x0`。

## Phase 2: 增加 CSR 与 GPR 状态 probe

目标：满足 DiffTest mandatory probes 的最小集合。

拟新增信号：

```systemverilog
output logic [31:0] dbg_gpr [0:31],
output logic [31:0] dbg_csr_mstatus,
output logic [31:0] dbg_csr_mtvec,
output logic [31:0] dbg_csr_mepc,
output logic [31:0] dbg_csr_mcause,
output logic [31:0] dbg_csr_mscratch
```

第一阶段先不暴露物理寄存器/rename table，因为当前核心没有 rename。DiffTest 的整数寄存器 probe 可以按 `numPhyRegs=32` 处理为架构寄存器状态。

如果删掉或做错：只比较 commit 写回值可能漏掉 CSR 副作用、异常恢复、寄存器历史污染；遇到 trap/mret 时定位能力不足。

审查点：

- 当前 CSR 实现很小，只支持 `mstatus/mtvec/mscratch/mepc/mcause/misa=0`。DiffTest 参考模型可能默认 CSR 集更完整，需要配置或屏蔽未实现 CSR。
- `mcycle/minstret` 目前不是 architectural CSR 暴露路径，需要确认是否让参考模型检查这些 CSR。

## Phase 3: 本地 C++ adapter

目标：把 DUT 输出转换为 DiffTest probe 调用。

拟新增结构：

```cpp
struct CommitTrace {
    bool valid;
    uint32_t pc;
    uint32_t instr;
    bool rfwen;
    uint8_t wdest;
    uint32_t wdata;
    bool skip;
    bool is_trap;
    uint32_t cause;
    uint32_t next_pc;
};
```

adapter 职责：

1. 初始化 DiffTest reference model。
2. 装载测试镜像或把当前 `MemoryModel` 内容同步给 reference。
3. 每个 DUT 周期采集 commit probe。
4. 调用 `DiffInstrCommit`。
5. 周期性或每条提交后同步 `DiffCSRState` 与 GPR state。
6. 处理 `skip`：
   - 普通内存访问：不 skip。
   - MMIO/tohost/LED/seg/counter：skip 或使用特殊设备同步策略。
7. 在 mismatch 时设置 `SimResult.status = "FAIL"`，输出 DUT/REF 关键信息。

关键设计：

- `main_difftest_mycpu.cpp` 和 `main_difftest_student_top.cpp` 调用 `difftest->tick(cycle, commit, mem, result)`。
- `difftest_adapter.cpp` 内部包含上游 DiffTest 头文件。
- 普通 `main_mycpu.cpp` / `main_student_top.cpp` 不包含 DiffTest adapter。

如果删掉或做错：testbench 会被上游 DiffTest API 强耦合；上游更新或 reference 切换时需要大范围改 `tb/verilator`。

## Phase 4: 独立 runner 与构建系统接入

目标：保留当前 `make sim-rv32` / `make sim-src` 行为，新增完全隔离的 DiffTest 路径。

拟改动：

1. `scripts/run_difftest.py`
   - 独立解析 `rv32` / `src` 两类测试。
   - 可复用 `run_verilator.py` 中的 testcase 发现逻辑，但建议后续抽到公共模块，避免复制过多代码。
   - 使用独立 BuildTarget：
     - `mycpu_difftest`
     - `student_top_difftest`
   - 编译时定义：
     - `VERILATOR_TB`
     - `ENABLE_DIFFTEST`
   - 链接：
     - `tb/difftest/adapter/*.cpp`
     - `tb/difftest/harness/main_difftest_*.cpp`
     - DiffTest generated C++/library
     - reference model library

2. `Makefile`
   - 新增：

```makefile
sim-rv32-difftest:
	$(PYTHON) scripts/run_difftest.py rv32 $(if $(TEST),--test $(TEST),) $(COMMON_SIM_ARGS)

sim-src-difftest:
	$(PYTHON) scripts/run_difftest.py src $(if $(TEST),--test $(TEST),) $(SRC_SIM_ARGS)
```

3. 构建产物：

```text
build/difftest/
build/verilator/mycpu_difftest/
build/verilator/student_top_difftest/
build/log/build_mycpu_difftest.log
build/log/build_student_top_difftest.log
```

审查点：

- `run_difftest.py` 是否允许调用/复用 `run_verilator.py` 的测试发现函数。我的建议是先复制少量发现逻辑，跑通后再抽公共模块，降低首版改动风险。
- 是否接受 `src` DiffTest 用 `student_top` 顶层，但采集 `Core_cpu` 的内部 commit bundle。

## src 类测试是否可以做 DiffTest

可以做，但约束比 `rv32` 直接 ISA 测试多。

`src` 测试的 Verilator 顶层是 `student_top`，程序分为：

- `irom.hex`：指令 ROM。
- `dram.hex`：数据 DRAM 初始内容。
- LED/SEG/counter 等 MMIO：由 `SocMemBridge` 和 testbench mirror 处理。

DiffTest 参考模型需要看到与 DUT 一致的程序和数据初值：

1. reference PC 仍从 `0x8000_0000` 启动。
2. `irom.hex` 对应指令/只读区域。
3. `dram.hex` 对应 `SRC_DRAM_BASE = 0x8010_0000` 的数据区域。
4. `0x8020_0000` 附近外设地址统一标记 skip，避免 reference model 因没有板级外设而误报。

`src` DiffTest 第一版目标不是验证 LED/SEG 显示协议，而是验证 CPU 执行 `src` 大程序时的架构提交状态。LED/SEG/pass marker 仍由原有 `checker_src` 或独立 harness 里的轻量结果检查负责。

如果删掉或做错：

- 不透出 `student_top.Core_cpu` commit bundle：只能看到 SoC 外设写，无法做指令级差分。
- 不同步 `dram.hex`：reference 从错误数据开始执行，第一批 load 后就会 mismatch。
- 不 skip MMIO：DUT 访问 LED/counter/switch 时 reference 没有等价设备，容易假失败。

## Phase 5: 验收路径

分三档验收。

### 5.1 commit trace 自检

不启用上游 DiffTest，只打开本地 trace：

- 每条提交打印 `pc/instr/rd/wdata`。
- `dbg_perf_commit` 增量必须等于 `dbg_commit_valid` 次数。
- load/mul/div 的 `pc/instr` 必须是发起指令，不是完成周期的下一条取指。

通过标准：

```text
make sim-rv32-difftest TEST=rv32ui-p-simple DIFFTRACE=1
```

无 trace 错位，原有 checker PASS。

### 5.2 小程序 DiffTest

启用 DiffTest，先跑不含 CSR/trap 的 RV32UI 子集：

- `rv32ui-p-simple`
- `rv32ui-p-add`
- `rv32ui-p-addi`
- `rv32ui-p-lw`
- `rv32ui-p-sw`
- `rv32ui-p-beq`
- `rv32ui-p-jal`

通过标准：

- 原有 tohost PASS。
- DiffTest 无 mismatch。

### 5.3 扩展到 M/CSR/trap

逐步打开：

- `rv32um`
- `rv32mi`
- CSR 指令
- ecall/ebreak/mret

通过标准：

```text
make sim-rv32-difftest TEST=rv32ui-p-simple
```

所有已支持 ISA case PASS；未支持 CSR/异常行为必须明确列入 skip/known limitation，不允许静默通过。

### 5.4 src DiffTest

启用 `student_top_difftest`，先跑：

- `srcSmoke`
- 再跑 `srcWithMext`

通过标准：

- DiffTest 无架构状态 mismatch。
- 原有 src 通过条件仍成立：LED/SEG/pass marker/counter 结果由 harness 记录。
- MMIO skip 次数、最后一次 skip PC/addr 进入结果 JSON，便于审查是否过度 skip。

## 关键风险

1. 上游 DiffTest 偏向 RV64/大型核，RV32 配置需要确认。
   - 缓解：先生成最小 RV32 profile，只启用必要 probe。

2. 当前 core 没有完整异常模型。
   - 缓解：Phase 2 只检查已实现 CSR；Phase 5 再逐步打开 trap 对比。

3. 内存模型不同步。
   - 缓解：优先让 reference 从同一个测试镜像启动；MMIO/tohost 地址设置 skip。

4. commit probe 与真实写回不一致。
   - 缓解：重构为“计算一次 wb bundle，同时喂 GPR 和 probe”。

5. load-hit fast return 可能导致同周期提交路径更复杂。
   - 缓解：commit valid 只以最终实际写回/提交条件为准，不以 request valid 为准。

6. store 的架构可见性不好定义。
   - 缓解：第一阶段只通过 commit instr + reference memory 对齐；必要时增加 `DiffStoreEvent`。

7. 多提交扩展。
   - 缓解：接口命名预留 `COMMIT_WIDTH`，当前设为 1；未来超标量改成数组，不改 adapter 总体结构。

8. `src` 顶层存在 CPU clock 和 50 MHz counter clock。
   - 缓解：DiffTest tick 只绑定 CPU posedge；counter/外设仍由 harness mirror 维护，不进入 reference architectural state。

9. 普通 Verilator runner 和 DiffTest runner 代码重复。
   - 缓解：首版接受少量重复，稳定后把 testcase discovery/build common 抽到 `scripts/sim_common.py`。

## 推荐实现顺序

1. `tb/difftest/README.md` 和目录骨架。
2. `scripts/run_difftest.py` 骨架，只支持 build-only/trace 自检，不接上游。
3. `CommitTrace` 空 adapter 和 `main_difftest_mycpu.cpp`。
4. RTL `VERILATOR_TB` commit probe：`riscv_cpu -> myCPU`。
5. `main_difftest_mycpu.cpp` 本地 commit trace 自检。
6. 将 commit probe 从 `myCPU` 继续透到 `student_top`。
7. `main_difftest_student_top.cpp` 跑 `srcSmoke` commit trace 自检。
8. 引入上游 DiffTest 固定版本。
9. 生成 RV32 单提交 DiffTest 接口。
10. 接入 reference model，跑最小 RV32UI。
11. 扩展 CSR/trap/M-extension。
12. 接入 `srcSmoke` / `srcWithMext`，完成 MMIO skip 统计。
13. 文档化 known limitations 和 debug 使用方法。

## 审查需要你确认的问题

1. `tb/difftest/upstream` 是否使用 git submodule？
2. 是否接受 DiffTest 和普通 Verilator runner 隔离，新增 `scripts/run_difftest.py`？
3. 第一阶段是否先接 `myCPU` 的 rv32 DiffTest，再接 `student_top` 的 src DiffTest？
4. 是否接受先以 RV32 单提交为目标，不立即支持未来双提交数组接口？
5. reference model 优先 NEMU 是否可以？如果你更想用 Spike，需要调整构建和设备模型策略。
6. 对 MMIO/tohost/LED/seg/counter，是否统一 `skip`，还是要做 reference 侧设备同步？

我的建议答案：

- 使用 submodule。
- 使用独立 `run_difftest.py`，不把 DiffTest 塞进 `run_verilator.py`。
- 先接 `myCPU` 的 rv32，再接 `student_top` 的 src；二者都比较同一个 CPU commit bundle。
- 第一版单提交，接口命名预留 width。
- 参考模型先 NEMU。
- MMIO 第一版全部 skip，保证 CPU 核心 ISA 对账先跑通；src 的 LED/SEG/pass 结果仍由本地 checker 判断。
