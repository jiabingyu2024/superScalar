# TB 结构复盘与重新规划

## 1. 本次复盘结论

当前 `tb/verilator/tb_mycpu.cpp` 能作为第一版链路原型使用，但不适合作为后续长期维护形态。它把命令参数、IROM/DRAM/MMIO 模型、rv32 checker、src checker、trace、日志和结果汇总都放在一个文件里，已经偏离了之前确定的“公共 harness + test profile”方向。

后续 TB 的主要目标应改回：

1. 保持一套公共 Verilator harness。
2. rv32 和 src 不拆成两套完全独立 TB，而是拆成两类 checker/profile。
3. src 判定不能全局硬编码 LED/SEG magic value，必须按 profile 或 dump/配置选择判定逻辑。
4. 性能统计是 src 仿真的一等输出，不是日志附属信息。

## 2. 对本次审查问题的逐项回应

### 2.1 当前 C++ TB 又长又乱的问题

这个判断是正确的。当前 632 行的 `tb_mycpu.cpp` 是为了先打通 Verilator 编译、IROM/DRAM 时序、MMIO 捕获、rv32 `tohost` 和 src 参考流程而形成的原型，不应继续在这个文件里堆功能。

应重构为以下边界：

```text
tb/verilator/
  main.cpp                  # 公共仿真入口：参数、时钟、reset、主循环
  sim_config.h/.cpp          # 命令行参数、路径、profile 配置、结果路径
  sim_memory.h/.cpp          # IROM/DRAM/MMIO/counter/SEG/LED/virtual_seg 行为模型
  sim_trace.h/.cpp           # FST trace、关键事件日志
  checker.h                  # checker 公共接口、事件类型、结果类型
  checker_rv32.h/.cpp        # rv32 tohost 判定
  checker_src.h/.cpp         # src checker dispatcher
  checker_src_ledseg.h/.cpp  # LED/SEG 类 profile 判定
  checker_src_memcnt.h/.cpp  # DRAM pass/fail counter 类 profile 判定
  perf_stats.h/.cpp          # 性能统计采集、JSON 输出
```

这不是为了“文件变多”，而是为了把变化率不同的内容隔离开：memory 模型要稳定，checker 会随测试程序变化，性能统计会持续扩展。

### 2.2 为什么当前只有 Verilator，是否需要 `tb.sv`

主验证链路仍建议以 Verilator C++ harness 为主，不建议现在建立一套完整独立的 `tb.sv`：

1. 当前测试需要批量选择 rv32 suite/src profile、解析 dump、读写 JSON、保存日志和结果，这些更适合 C++/Python 完成。
2. IROM/DRAM/MMIO 行为模型若在 SV 和 C++ 各写一套，后续很容易出现两套模型不一致。
3. 赛事 src 判定和性能统计需要复杂状态、字符串/配置处理、profile 分发，用 C++ 更直接。

但可以保留一个“很薄”的 SV wrapper 作为后续选项：

```text
tb/verilator/tb_top.sv
```

它只做以下事情之一：

1. 包一层 DUT，给 Verilator 暴露内部 perf/debug 信号。
2. 放少量 SVA/断言，检查外部接口协议。
3. 作为 `student_top` smoke 的 SV 顶层壳。

这个 wrapper 不应该复制 memory/checker 逻辑，也不应该形成第二套独立 TB。

### 2.3 src LED/SEG 固定值不是通用规则

这个问题必须修正。用户给出的 LED/SEG 流程只能作为某些 src 程序的参考流程，不能全局套到所有 src。

从现有 dump 能看到几个事实：

1. `src0/src1/src2/srcSmoke/srcWithMext/srcWithoutMext` 都会访问 MMIO：
   - SEG：`0x80200020`
   - LED：`0x80200040`
   - counter：`0x80200050`
2. `src0.dump` 和 `src1.dump` 中能看到 `0x3037` 相关常量，比较接近“SEG 高两位显示 37”的流程。
3. `srcWithMext.dump`、`srcWithoutMext.dump` 中大量出现对 `0x80100000` 和 `0x80100004` 的访问，看起来存在 DRAM 中的 pass/fail counter 或测试计数区；它们不能简单等同于 LED 写 `0x01221c08` PASS、写 `0x24181824` FAIL。
4. `srcWithMext` 还在早期读取 `0x80100000`、`0x80100030` 等数据做检查，说明它的程序结构比固定 LED/SEG 流程复杂。

因此后续 src checker 应改为 profile 化：

```json
{
  "name": "src0",
  "checker": "ledseg",
  "led_pass": "0x01221c08",
  "led_fail": "0x24181824",
  "seg_expect_prefix_bcd": 37,
  "counter_addr": "0x80200050"
}
```

```json
{
  "name": "srcWithMext",
  "checker": "memcnt",
  "pass_counter_addr": "0x80100000",
  "fail_counter_addr": "0x80100004",
  "counter_addr": "0x80200050",
  "finish_rule": "需要继续结合 dump 或用户提供规则确认"
}
```

这些配置可以放在：

```text
tb/verilator/src_profiles.json
```

或：

```text
data/src_profiles.json
```

推荐放在 `tb/verilator/src_profiles.json`，因为它描述的是仿真判定策略，不是原始测试数据。

### 2.4 DUT 选择

主 DUT 仍选择 `myCPU`。

理由：

1. `myCPU` 是当前 CPU 对外集成边界，包含裸 `core` 到 IROM/DRAM/perip 接口的适配关系。
2. rv32/src 的正确性和性能调优主要应先在 `myCPU` 边界完成，避免 `student_top` 的显示、板级 wrapper、赛事外设模板干扰 core bug 定位。
3. `core` 直接作为主 DUT 会绕开 `myCPU` 的真实外部接口时序，尤其是 IROM/DRAM/perip 适配，不利于和 FPGA/SoC 路径统一。
4. `student_top` 后续应作为第二级 smoke DUT，用于检查 SoC shell、`dram_driver`、`counter.sv`、显示链路和 Tcl/filelist 集成，不作为当前主仿真入口。

当前分层建议：

| 层级 | DUT | 用途 |
| --- | --- | --- |
| L1 | `myCPU` | rv32 正确性、src 正确性、src 性能统计主链路 |
| L2 | `student_top` | SoC/赛事模板 smoke、上板前接口一致性检查 |
| 特殊 debug | `core` | 仅在定位内部 bug 时临时使用，不作为标准回归入口 |

### 2.5 src 性能结果必须记录

src 仿真输出必须包含性能数据。性能统计分两层实现。

第一层不依赖 RTL 改口，马上可做：

| 字段 | 含义 |
| --- | --- |
| `cycles` | CPU 仿真周期数 |
| `result_cycle` | PASS/FAIL/TIMEOUT 发生周期 |
| `counter_ms` | TB counter 最终毫秒值 |
| `counter_start_cycle`/`counter_stop_cycle` | 程序控制 counter 的周期 |
| `mmio_write_count` | MMIO 写次数 |
| `dram_read_count`/`dram_write_count` | DRAM 访问次数 |
| `first_led_write`/`last_led_write` | LED 观测结果 |
| `first_seg_write`/`last_seg_write` | SEG 观测结果 |
| `checker_kind` | 使用的 src 判定类型 |

第二层需要读取内部 perf/debug 信号，先不改 `myCPU` 端口，后续确认方式：

1. 优先用 Verilator hierarchical signal/public 标注读取 `PerfIF` 或 commit 计数。
2. 若层级读取不稳定，再讨论是否给 `myCPU` 增加仿真专用输出或 SV wrapper。
3. 不为性能统计先破坏综合边界和板级接口。

第二层目标字段：

| 字段 | 含义 |
| --- | --- |
| `commit_count` | 提交指令数 |
| `ipc` | `commit_count / cycles` |
| `branch_count` | 分支提交或执行次数 |
| `branch_miss_count` | 分支错误恢复次数 |
| `load_store_count` | 访存类提交数 |
| `stall/recovery` 相关计数 | 后续按 RTL 可见性扩展 |

## 3. 推荐执行顺序

如果该规划通过审查，后续执行顺序建议如下：

1. 新增 `tb/verilator/src_profiles.json`，先把现有 src profile 分成 `ledseg`、`memcnt_pending` 两类。
2. 把 `tb_mycpu.cpp` 拆成 `main.cpp + sim_memory + checker_rv32 + checker_src + perf_stats`，保持外部 Makefile/脚本入口不变。
3. `checker_src_ledseg` 只覆盖已经确认适用 LED/SEG 参考流程的 profile。
4. 对 `srcWithMext/srcWithoutMext` 先实现“观测型 memcnt checker”：记录 `0x80100000/0x80100004`、LED/SEG/counter 行为，不先武断给 PASS。
5. 结合用户后续提供的 src 规则或进一步 dump 反推，把 `memcnt_pending` 升级为严格 PASS/FAIL checker。
6. 在 JSON result 中统一输出 correctness result 和 performance result。
7. 可选增加薄 `tb_top.sv`，只用于暴露内部 perf/debug 或少量断言，不复制 C++ 行为模型。

## 4. 对现有文档/实现的修订要求

1. `docs/archive/2026-07-02/007_verilator_tb_mycpu.md` 记录的是已实现原型，不再代表最终规划。
2. `docs/sim/verilator_plan.md` 中 src 固定 LED/SEG 通用判定必须改为“当前原型限制/待 profile 化”。
3. 后续重构前，不应继续向 `tb_mycpu.cpp` 添加新的 src 特判。
4. 后续任何 src checker 规则必须能追溯到 dump、用户提供规则或 profile 配置。
