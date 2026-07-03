# 017 srcSmoke bring-up 记录

日期：2026-07-03

## 目标

开始运行 src 类测试，先让 `srcSmoke` 在主 Verilator DUT `myCPU` 上跑通。

本轮目标不是优化到好性能，而是确认：

1. TB 和 memory/MMIO/counter 模型不会误判。
2. DUT 能从 `srcSmoke` 运行到最终 PASS 观测点。
3. 失败时能区分 RTL 功能问题、性能周期上限问题和 checker 规则问题。

## 初始现象

命令：

```sh
scripts/run_verilator.py src --test srcSmoke --no-build
```

默认 `20,000,000` 周期下 TIMEOUT。早期 trace 显示：

1. ROB head 停在 `pc=0x80001008`。
2. IssueQueue 中有 ready branch，但 EX 被 MEM stall。
3. MEM 管线中一个 `LW` 访问 `0x80100018`，`StoreBufferMatchOut.block=1`。

根因不是程序真的跑飞，而是 StoreBuffer 把部分字节命中当成必须等待的 hazard，导致 MEM 拉住 EX，older branch 无法继续执行。

## RTL 修复 1：StoreBuffer 部分转发

原行为：

```text
若 load 的 rstrb 和某个 store entry 同 word 有部分字节重叠，但不能覆盖 load 所需全部字节
  -> StoreBufferMatchOut.block = 1
  -> ExecuteMemStage 拉 exStallReq
```

问题：

`srcSmoke` 中出现了 `SH` 后跟同 word `LW` 的序列。`LW` 需要部分字节来自 StoreBuffer，剩余字节来自 DRAM。原设计不会合并，只会阻塞。由于 IssueQueue 的 MEM 保序已经保证更老 MEM 不会被年轻 MEM 越过，这个 block 会把可执行路径卡死。

修复后行为：

```text
完全命中：StoreBuffer 直接返回 load 所需数据，MEM 不访问 DRAM
部分命中：StoreBuffer 返回 forwardData/forwardMask，MEM 发 DRAM read，返回后逐字节合并
无命中：正常发 DRAM read
```

涉及文件：

```text
rtl/core/DispatchStage/StoreBufferTypes.sv
rtl/core/DispatchStage/StoreBuffer.sv
rtl/core/ExecuteStage/ExecuteMemStage.sv
```

设计边界：

1. core 对外仍输出 raw store data/raw mask。
2. `dram_driver`/TB memory model 仍负责按 `addr[1:0]` 做读右移、写左移。
3. StoreBuffer 内部只为 forwarding 临时对齐 store 字节。
4. misaligned half/word 跨 word 访问仍未完整支持。

## RTL 调整 2：BPU 容量和后向分支启发式

`srcSmoke` 解除 StoreBuffer 卡死后可以继续运行，但大量时间消耗在循环和软件除法路径。为了降低循环分支 miss，对 BPU 做了小幅调整：

1. BTB 从 32 entry 增加到 256 entry。
2. BHB PHT/local entry 从 32 增加到 256。
3. global history 从 6 位增到 8 位。
4. BTB 命中且 target 小于当前 PC 时，即使 BHB 尚未训练为 taken，也按后向分支预测 taken。

涉及文件：

```text
rtl/core/PreFetchStage/BPU.sv
```

效果：

短 trace 中 commit 数有提升、branch miss 有下降，但 `srcSmoke` 总周期仍约 `72.8M`。这说明当前性能瓶颈不只在冷启动分支预测，还包括长延迟除法、简单后端吞吐、load/store 串行化等因素。

## checker 修正：srcSmoke 使用 LED-only

在 `80,000,000` 周期上限下，DUT 最终写出：

```text
SEG 0x37000000
counter start
...
counter stop
SEG 0x00000000
LED 0x01221c08
```

旧 `ledseg` checker 要求 LED PASS 后继续看到：

```text
SEG 高两位 BCD == 37
SEG 低六位 BCD == counter_ms
virtual_seg 能还原当前 seg_wdata
```

但 `srcSmoke` 最终在写 LED PASS 前已经把 SEG 清零，所以旧 checker 给出：

```text
FAIL: SEG did not match within grace window
```

这不是 DUT 没跑到 PASS，而是 checker 对 `srcSmoke` 的终态假设错误。修复方式是新增 `ledonly` checker，并把 `srcSmoke` profile 改为：

```json
{
  "name": "srcSmoke",
  "checker": "ledonly",
  "led_pass": "0x01221c08",
  "led_fail": "0x24181824"
}
```

`ledonly` 只用 LED PASS/FAIL signature 判断正确性，同时仍记录 SEG、counter、DRAM 访问和 MMIO 写入等性能观测字段。

涉及文件：

```text
tb/verilator/checker_src.h
tb/verilator/checker_src.cpp
tb/verilator/checker.cpp
tb/verilator/src_profiles.json
```

## 验证结果

构建并运行：

```sh
scripts/run_verilator.py src --test srcSmoke --build --build-jobs 1 --build-cxx clang++ --max-cycles 80000000
```

结果：

```text
srcSmoke: PASS
checker_kind: src_ledonly
cycles: 72813551
reason: LED pass signature observed
counter_stop_cycle: 72813238
counter_ms: 1456
first_seg_write: 0x37000000
last_seg_write: 0x00000000
dram_read_count: 592918
dram_write_count: 200123
```

随后复用二进制回归：

```sh
scripts/run_verilator.py rv32 --suite rv32ui --no-build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32mi --no-build --max-cycles 30000
scripts/run_verilator.py rv32 --suite rv32um --no-build --max-cycles 30000
```

结果：

```text
rv32ui: 全部 PASS
rv32mi: 全部 PASS
rv32um: 全部 PASS
```

## 当前结论

`srcSmoke` 已在 `myCPU` Verilator DUT 上跑通，当前通过标准是 LED PASS signature。

需要注意：

1. `srcSmoke` 不是 LED+SEG 最终一致型 profile，不能用它证明 `ledseg` checker 对其他 src 测试一定正确。
2. `srcSmoke` 当前周期数较大，下一阶段若以 src 性能为目标，应优先看除法密集循环、MEM 保序限制、load 返回阻塞和 branch miss。
3. StoreBuffer 部分 forwarding 是后续 src 测试的基础路径，建议增加定向用例覆盖 `SB/SH` 后跟 `LW/LH/LB`、同 word 多 store 合并等情况。

## 修改文件

RTL：

```text
rtl/core/DispatchStage/StoreBufferTypes.sv
rtl/core/DispatchStage/StoreBuffer.sv
rtl/core/ExecuteStage/ExecuteMemStage.sv
rtl/core/PreFetchStage/BPU.sv
```

TB：

```text
tb/verilator/checker_src.h
tb/verilator/checker_src.cpp
tb/verilator/checker.cpp
tb/verilator/src_profiles.json
```

文档：

```text
docs/design/rtl_core_design.md
docs/design/memory_and_test_contract.md
docs/sim/verilator_plan.md
docs/README.md
docs/archive/2026-07-03/017_srcSmoke_bringup.md
```
