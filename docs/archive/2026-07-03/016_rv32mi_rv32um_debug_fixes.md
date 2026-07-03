# 016 rv32mi/rv32um 定位与修复记录

日期：2026-07-03

## 目标

在 `rv32ui` 已通过的基础上，完成当前 RTL 支持范围内的 `rv32mi` SYS/CSR 测试和 `rv32um` M 扩展测试。

本轮不扩大到完整 privileged 架构，只修复项目当前承诺和 riscv-tests 当前用例实际依赖的行为。

## 失败基线

命令：

```sh
scripts/run_verilator.py rv32 --suite rv32mi --build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32um --build --max-cycles 30000
```

结果：

```text
rv32mi-p-csr: FAIL, tohost = 0x0000002d
rv32mi-p-sbreak: PASS
rv32mi-p-scall: PASS
rv32mi-p-zicntr: PASS

rv32um-p-div:  FAIL, tohost = 0x00000005
rv32um-p-divu: FAIL, tohost = 0x00000005
rv32um-p-mul: PASS
rv32um-p-mulh/mulhsu/mulhu: PASS
rv32um-p-rem:  FAIL, tohost = 0x00000005
rv32um-p-remu: FAIL, tohost = 0x00000005
```

`rv32mi-p-csr` 的失败码 `0x2d = 45 = 22 * 2 + 1`，对应 dump 中 `gp=22`：

```text
csrsi mscratch,16
csrr  a0,mscratch
li    t2,31
bne   a0,t2,fail
```

`rv32um-p-div/rem` 的失败码 `0x5 = 2 * 2 + 1`，对应第一个普通除法断言：

```text
li  a1,20
li  a2,6
div a4,a1,a2
li  t2,3
bne a4,t2,fail
```

## 根因 1：`mscratch` 未实现

`ExecuteSysStage` 原 CSR 白名单只有：

```text
mstatus 0x300
mtvec   0x305
mepc    0x341
mcause  0x342
```

因此对 `mscratch(0x340)` 的读返回 0、写被忽略。`rv32mi-p-csr` 前面的 `csrrwi mscratch,15` 实际没有保存 15，后续 `csrsi mscratch,16` 读到 0 并写回 16，最终 `csrr mscratch` 得到 0 或非 31，导致 `gp=22` 失败。

修复：

1. 在 `ExecuteSysStage` 增加 `CSR_MSCRATCH = 12'h340`。
2. 增加 `mscratch` 寄存器，reset 清 0。
3. `csr_read` 支持读取 `mscratch`。
4. CSR 写回 case 中支持 `mscratch <= newValue`。

边界说明：

`misa` 仍读 0，不声明未实现的 U/S/F 能力；非白名单 CSR 仍读 0、写忽略。`rv32mi-p-zicntr` 通过不表示实现了真实 `cycle/instret` 计数器。

## 根因 2：DIV/REM 有效迭代次数错误

`ExecuteMulStage` 的除法路径使用恢复除法：

```text
trial = {remainder[31:0], dividend[31]}
dividend <<= 1
quotient = {quotient[30:0], bit}
```

这个算法对 RV32 只应做 32 次有效迭代。原实现把 `DIV_LATENCY = 36` 直接作为流水深度，并且每一级都继续调用 `div_step`，导致同一个除法事务被迭代 36 次。

对 `20 / 6` 这类普通除法，前 32 次已经得到正确商和余数；继续 4 次会继续左移商和处理余数，最终结果被破坏，所以第一个普通除法断言就失败。

修复：

1. 在 `DivPipeEntry` 增加 `iterCount`。
2. `divLaunch.iterCount = 0`。
3. `div_step` 只在 `iterCount < 32` 时执行恢复除法步骤，并递增 `iterCount`。
4. `DIV_LATENCY` 对外仍保持 36 拍，后 4 拍只是固定延迟余量，不再改变商/余数。

除零和有符号溢出路径保持原语义：

```text
DIV/DIVU 除零 -> 0xffffffff
REM/REMU 除零 -> dividend
DIV 溢出 -2^31 / -1 -> 0x80000000
REM 溢出 -> 0
```

## 仿真构建修正

调试过程中发现同时启动多个 `--build` 会复用同一个 `build/verilator/mycpu` 目录，容易触发 GCC 进程被杀或中间文件污染。随后即使单线程重建，GCC 13 在 `VmyCPU_vm_classes_0.cpp` 上仍可能 internal compiler error。

脚本修正：

1. 增加 `--build-jobs N`，透传 Verilator build 并行度。
2. 增加 `--build-cxx CXX`，通过 `-MAKEFLAGS CXX=...` 指定 C++ 编译器。
3. Verilator 命令加入 `--output-split 20000 --output-split-cfuncs 20000`，拆小生成的 C++ 文件。

当前环境推荐：

```sh
scripts/run_verilator.py rv32 --suite rv32mi --build --build-jobs 1 --build-cxx clang++
```

## 验证结果

首次干净构建使用：

```sh
scripts/run_verilator.py rv32 --test rv32mi-p-csr --build --build-jobs 1 --build-cxx clang++ --max-cycles 30000
```

结果：

```text
rv32mi-p-csr: PASS
```

随后复用同一二进制回归：

```sh
scripts/run_verilator.py rv32 --suite rv32mi --no-build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32um --no-build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32ui --no-build --max-cycles 30000
```

结果：

```text
rv32mi: 全部 PASS
rv32um: 全部 PASS
rv32ui: 全部 PASS
```

## 修改文件

RTL：

```text
rtl/core/ExecuteStage/ExecuteSysStage.sv
rtl/core/ExecuteStage/ExecuteMulStage.sv
```

脚本：

```text
scripts/run_verilator.py
```

文档：

```text
docs/design/rtl_core_design.md
docs/sim/verilator_plan.md
docs/README.md
docs/archive/2026-07-03/016_rv32mi_rv32um_debug_fixes.md
```
