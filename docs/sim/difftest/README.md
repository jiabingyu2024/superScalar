# DiffTest 使用与调试指南

本文说明如何在本项目中使用 `tb/difftest/` 和 `scripts/run_difftest.py` 做提交级验证与调试。

当前状态要先说清楚：本项目已经接入了独立 DiffTest harness，可以采集并自检 CPU commit trace；OpenXiangShan DiffTest 上游仓库也已固定在 `tb/difftest/upstream`。但由于当前环境缺少 `mill`，上游 Chisel 生成接口和 NEMU/Spike reference 差分还没有启用。因此当前结果 JSON 中：

```json
"reference_enabled": false
```

这表示当前模式是本地 commit trace self-check，不是完整 reference-model differential check。

## 1. DUT 边界

DiffTest 比对和调试的对象是 CPU 架构提交点，不是整个板级 SoC 外壳。

| 测试类型 | Verilator 顶层 | CPU 提交点来源 | 用途 |
|---|---|---|---|
| `rv32` | `myCPU` | `myCPU.cpu` / `riscv_cpu` | ISA 小测试、快速定位指令级问题 |
| `src` | `student_top` | `student_top.Core_cpu.cpu` / `riscv_cpu` | 跑完整 src 程序，同时观察 CPU commit |

`student_top` 包含 IROM、SocMemBridge、LED/SEG/counter、双时钟复位等板级逻辑。DiffTest 关注的是内部 `myCPU` 的 PC、指令、写回、CSR、trap 等架构状态。

## 2. 快速开始

推荐显式传 `BUILD_CXX=g++`，避免当前环境中 `ccache` 目录只读导致构建失败。

### 2.1 构建 DiffTest harness

```bash
make difftest-build BUILD_CXX=g++ BUILD_JOBS=2
make difftest-build-src BUILD_CXX=g++ BUILD_JOBS=2
```

生成的二进制：

```text
build/verilator/mycpu_difftest/sim_mycpu_difftest
build/verilator/student_top_difftest/sim_student_top_difftest
```

构建日志：

```text
build/log/difftest/build_mycpu_difftest.log
build/log/difftest/build_student_top_difftest.log
```

### 2.2 跑一个 RV32 ISA 测试

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
```

结果文件：

```text
build/result/difftest/rv32/rv32ui-p-simple.json
```

### 2.3 跑一个 src 测试

```bash
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```

结果文件：

```text
build/result/difftest/src/srcSmoke.json
```

## 3. 常用命令

### 3.1 单个 RV32 测试

```bash
make sim-rv32-difftest TEST=rv32ui-p-add BUILD_CXX=g++ BUILD_JOBS=2
```

适合快速验证某类指令，例如 ALU、branch、load/store、CSR、M 扩展。

### 3.2 某个 RV32 suite

```bash
make sim-rv32-difftest SUITE=rv32ui BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest SUITE=rv32um BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest SUITE=rv32mi BUILD_CXX=g++ BUILD_JOBS=2
```

输出 summary：

```text
build/result/difftest/rv32/summary.json
```

### 3.3 全部 RV32 测试

```bash
python3 scripts/run_difftest.py rv32 --all --build-cxx g++ --build-jobs 2
```

如果只想用 Makefile，可以用：

```bash
make sim-rv32-difftest SUITE=rv32ui BUILD_CXX=g++ BUILD_JOBS=2
```

全量 `--all` 当前建议直接用 `scripts/run_difftest.py`，因为 Makefile 目标没有单独暴露 `--all` 开关。Makefile 当前更适合单测或 suite。

### 3.4 src 测试

```bash
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
make sim-src-difftest TEST=srcWithMext BUILD_CXX=g++ BUILD_JOBS=2
```

如需限制最大周期：

```bash
make sim-src-difftest TEST=srcSmoke MAX_CYCLES=50000000 BUILD_CXX=g++ BUILD_JOBS=2
```

如需调整 CPU 频率用于结果统计：

```bash
make sim-src-difftest TEST=srcSmoke CPU_FREQ_MHZ=100 BUILD_CXX=g++ BUILD_JOBS=2
```

## 4. 打开 commit trace

`DIFFTRACE=1` 会打印每条提交指令的 commit 信息到测试日志。

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple DIFFTRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

日志位置：

```text
build/log/difftest/rv32/rv32ui-p-simple.log
```

典型输出形态：

```text
difftest cycle 12 commit#6 pc=0x80000010 inst=0x00100113 rd=x2 wen=1 wdata=0x00000001 next_pc=0x80000014
```

字段含义：

| 字段 | 含义 | 调试价值 |
|---|---|---|
| `cycle` | testbench CPU 周期 | 对齐波形时间 |
| `commit#` | 第几条退休指令 | 定位第一条错误提交 |
| `pc` | 退休指令 PC | 判断控制流是否跑飞 |
| `inst` | 退休指令编码 | 对照 dump 反汇编 |
| `rd/wen/wdata` | GPR 写回 | 定位执行/访存/旁路错误 |
| `next_pc` | 该指令提交后的下一 PC | 定位 branch/jal/jalr/trap 恢复问题 |
| `load/store/trap` | 指令类别标记 | 快速判断问题路径 |

## 5. 打开波形

DiffTest harness 继承现有 Verilator trace 机制。

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

波形位置：

```text
build/wave/difftest/rv32/rv32ui-p-simple.fst
```

src 测试：

```bash
make sim-src-difftest TEST=srcSmoke TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

波形位置：

```text
build/wave/difftest/src/srcSmoke.fst
```

推荐的波形观察信号：

```text
dbg_commit_valid
dbg_commit_pc
dbg_commit_inst
dbg_commit_wen
dbg_commit_rd
dbg_commit_wdata
dbg_commit_is_load
dbg_commit_is_store
dbg_commit_is_trap
dbg_commit_next_pc
dbg_perf_commit
```

对于 `src` 顶层，这些信号在 `student_top` 顶层已经透出；内部真实来源仍是 `Core_cpu`。

## 6. 结果 JSON 怎么看

DiffTest 结果和普通 Verilator 结果隔离：

```text
build/result/difftest/rv32/<test>.json
build/result/difftest/src/<test>.json
```

关键字段：

```json
{
  "status": "PASS",
  "reason": "tohost wrote 1; difftest commits=85 mmio_skip=0 last_pc=0x80000040",
  "difftest": {
    "mode": "commit_trace_selfcheck",
    "reference_enabled": false,
    "commit_count": 85,
    "mmio_skip_count": 0,
    "last_commit_pc": "0x80000040"
  }
}
```

字段解释：

| 字段 | 含义 |
|---|---|
| `status` | 测试最终状态，`PASS/FAIL/TIMEOUT/CRASH/UNSUPPORTED` |
| `reason` | 结束原因，包含原 checker 原因和 difftest 摘要 |
| `difftest.mode` | 当前 DiffTest 模式，目前是 `commit_trace_selfcheck` |
| `difftest.reference_enabled` | 是否启用 NEMU/Spike reference，目前为 `false` |
| `difftest.commit_count` | DiffTest harness 观察到的提交指令数 |
| `difftest.last_commit_pc` | 最后一条提交指令 PC |

自检规则当前包括：

- `commit_valid` 只在实际退休周期拉高。
- `wen=1` 时 `rd` 不能为 `x0`。
- `commit_pc` 必须 4 字节对齐。
- `next_pc[0]` 必须为 0。

这些规则不能替代 reference 差分，但能很快发现 commit probe 错位、load/muldiv 长延迟提交错误、错误写 x0、PC 跑飞等问题。

## 7. 推荐调试流程

### 7.1 某个 RV32 case 失败

先跑普通日志：

```bash
make sim-rv32-difftest TEST=<case> BUILD_CXX=g++ BUILD_JOBS=2
```

如果失败，打开 commit trace：

```bash
make sim-rv32-difftest TEST=<case> DIFFTRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

看日志：

```bash
less build/log/difftest/rv32/<case>.log
```

定位方法：

1. 找到最后几条 `difftest cycle ... commit#...`。
2. 用 `<case>.dump` 对照 `pc` 和 `inst`。
3. 如果 `pc` 跳到非预期地址，优先查 branch/jal/jalr/trap 路径。
4. 如果 `rd/wdata` 错，按指令类型查 ALU、load_extend、mul/div、CSR。
5. 如果 `commit_count` 和 `dbg_perf_commit` 不一致，优先查 commit probe 生成条件。

### 7.2 load/store 相关失败

建议命令：

```bash
make sim-rv32-difftest TEST=rv32ui-p-lw DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-sw DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

重点看：

- load 的 `commit_pc` 是否是发起 load 的 PC，而不是 load 完成时的新取指 PC。
- load 的 `wdata` 是否和 `load_extend()` 后的值一致。
- store 是否产生 commit，但 `wen=0`。
- `dmem_req_addr/wdata/wstrb` 和 `dbg_commit_pc` 的周期关系。

常见 bug：

- 没有锁存 `load_pc_q/load_inst_q`，导致 load 提交时 PC 错位。
- byte/half load 扩展错误，`wdata` 和期望不一致。
- store 等待 `cache_req_ready` 时错误提交。

### 7.3 mul/div 相关失败

建议命令：

```bash
make sim-rv32-difftest TEST=rv32um-p-mul DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32um-p-div DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

重点看：

- `muldiv_done` 周期是否对应一次 `dbg_commit_valid`。
- `dbg_commit_pc/inst` 是否来自发起 mul/div 的指令。
- `dbg_commit_wdata` 是否等于 `muldiv_result`。

常见 bug：

- 没有锁存 `muldiv_pc_q/muldiv_inst_q`。
- `muldiv_rd_q` 被后续指令覆盖。
- 除零、有符号溢出等 RISC-V M 扩展边界处理错。

### 7.4 branch/jump 路径失败

建议命令：

```bash
make sim-rv32-difftest TEST=rv32ui-p-beq DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-jal DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-jalr DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

重点看：

- `next_pc` 是否等于实际应跳转地址。
- JAL/JALR 的 `rd` 写回是否为 `pc+4`。
- mispredict 或 redirect 后是否提交了错误路径指令。

当前核心是简化多周期状态机，不是完整乱序核；后续做超标量/乱序时，应把 probe 移到 ROB commit 边界，而不是 execute 边界。

### 7.5 src 程序失败

先跑：

```bash
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```

如果失败，再打开 trace：

```bash
make sim-src-difftest TEST=srcSmoke DIFFTRACE=1 TRACE=1 BUILD_CXX=g++ BUILD_JOBS=2
```

结果文件：

```text
build/result/difftest/src/srcSmoke.json
```

日志：

```text
build/log/difftest/src/srcSmoke.log
```

调试分工：

- CPU 指令执行问题：看 commit trace。
- LED/SEG/counter 判定问题：看 `correctness` 和 `perf.led/perf.seg/perf.counter`。
- SoC 外设桥问题：看 `dbg_perip_addr/dbg_perip_wdata/dbg_perip_wen` 和 `SocMemBridge`。

`src` 类测试中，DiffTest 的目标是帮助定位 CPU 提交行为，不是替代 LED/SEG checker。

## 8. 和普通 Verilator 回归的关系

普通回归：

```bash
make sim-rv32 TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
make sim-src TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```

DiffTest harness：

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```

两套路径隔离：

| 项目 | 普通 Verilator | DiffTest harness |
|---|---|---|
| runner | `scripts/run_verilator.py` | `scripts/run_difftest.py` |
| rv32 binary | `build/verilator/mycpu/sim_mycpu` | `build/verilator/mycpu_difftest/sim_mycpu_difftest` |
| src binary | `build/verilator/student_top/sim_student_top` | `build/verilator/student_top_difftest/sim_student_top_difftest` |
| result | `build/result/...` | `build/result/difftest/...` |
| log | `build/log/...` | `build/log/difftest/...` |
| wave | `build/wave/...` | `build/wave/difftest/...` |

建议日常开发流程：

1. 先用普通 `sim-rv32` / `sim-src` 确认功能是否过。
2. 一旦出现难定位问题，切到 `sim-*-difftest DIFFTRACE=1`。
3. 如果需要看周期级控制信号，再加 `TRACE=1`。

## 9. 当前限制

当前没有完整 reference-model 差分，原因是上游 OpenXiangShan DiffTest 生成流程依赖 `mill`：

```bash
make -C tb/difftest/upstream \
  PROFILE=/home/jiabingyu/prj/26_jcs/superScalar/tb/difftest/profiles/rv32_single_commit.json \
  DESIGN_DIR=/home/jiabingyu/prj/26_jcs/superScalar/tb/difftest/generated
```

当前环境执行该命令会失败：

```text
make: mill: Not a directory
```

已准备好的上游信息：

```text
upstream path: tb/difftest/upstream
upstream commit: f65181bf3be2a444669e1a3f83f784e532a92154
profile: tb/difftest/profiles/rv32_single_commit.json
```

要启用完整 NEMU/Spike DiffTest，还需要：

1. 安装或提供 `mill`。
2. 用 RV32 single-commit profile 生成 `tb/difftest/generated`。
3. 构建 reference model，例如 NEMU 或 Spike 的 DiffTest so。
4. 在 `tb/difftest/adapter/difftest_adapter.cpp` 中把当前 self-check 替换/扩展为真实 reference step。
5. 对 MMIO 地址启用 skip，尤其是 `tohost/LED/SEG/counter/switch/key`。

## 10. 常见问题

### 10.1 构建时出现 `ccache: error: Read-only file system`

使用：

```bash
BUILD_CXX=g++
```

例如：

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
```

脚本会把 Verilator make 参数设置为：

```text
CXX=g++ OBJCACHE=
```

从而绕开只读 ccache。

### 10.2 `UNSUPPORTED: tohost symbol not found`

说明对应 rv32 测试的 `.dump` 中没有找到 `tohost` 符号。当前 rv32 checker 依赖 `tohost` 判断 pass/fail。

检查：

```bash
ls data/rv32*/<test>.dump
rg "<tohost>" data/rv32*/<test>.dump
```

### 10.3 `TIMEOUT`

优先看：

```text
build/log/difftest/<mode>/<test>.log
build/result/difftest/<mode>/<test>.json
```

建议重新跑：

```bash
make sim-rv32-difftest TEST=<test> DIFFTRACE=1 TRACE=1 MAX_CYCLES=<larger> BUILD_CXX=g++ BUILD_JOBS=2
```

判断方向：

- `commit_count` 还在增长：可能是程序没写 pass 标志，或 checker 条件不匹配。
- `commit_count` 停住：可能 CPU 卡在取指、访存、mul/div、异常循环。
- `last_commit_pc` 固定在某处：对照 dump 看是否死循环。

### 10.4 DiffTest commit 数和 perf commit 数不一致

这是严重问题，说明 probe 不是严格跟随真实提交条件。

优先检查：

- `ST_EXEC` 的 `commit` 条件。
- `ST_WAIT_MEM && cache_resp_valid`。
- `ST_WAIT_MULDIV && muldiv_done`。
- reset 后 `dbg_commit_valid` 是否清零。
- 是否在 stall/wait 周期错误拉高 `dbg_commit_valid`。

## 11. 推荐检查清单

每次改动 CPU 提交、访存、CSR、分支恢复逻辑后，至少跑：

```bash
make sim-rv32-difftest TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-lw BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-sw BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-beq BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32ui-p-jalr BUILD_CXX=g++ BUILD_JOBS=2
make sim-src-difftest TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```

如果改了 M 扩展：

```bash
make sim-rv32-difftest TEST=rv32um-p-mul BUILD_CXX=g++ BUILD_JOBS=2
make sim-rv32-difftest TEST=rv32um-p-div BUILD_CXX=g++ BUILD_JOBS=2
```

如果改了 CSR/trap：

```bash
make sim-rv32-difftest SUITE=rv32mi BUILD_CXX=g++ BUILD_JOBS=2
```

最终再跑普通回归确认没有破坏原入口：

```bash
make sim-rv32 TEST=rv32ui-p-simple BUILD_CXX=g++ BUILD_JOBS=2
make sim-src TEST=srcSmoke BUILD_CXX=g++ BUILD_JOBS=2
```
