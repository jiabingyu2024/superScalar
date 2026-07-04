# 018 src 切换到 student_top Verilator DUT

日期：2026-07-03

> 后续记录：本文中的 `srcSmoke` student_top TIMEOUT 是当时 `DRAM_0` 仿真行为模型尚未修正时的结果，已由 `019_make_src_entry_and_dram_model_fix.md` 覆盖。当前 `make sim-src TEST=srcSmoke` 已能 PASS。

## 目标

按最新约定重构 TB：

1. rv32 类测试继续使用 `myCPU` 作为 DUT，方便生成波形和抓取 core/接口信号。
2. src 类测试改用 `student_top` 作为 DUT，覆盖 IROM、DRAM、perip_bridge、counter、display 的 SoC 集成路径。
3. 不在原 `tb/verilator/main.cpp` 上继续堆分支，避免 TB 入口变得难维护。

## 结构调整

原单入口：

```text
tb/verilator/main.cpp
  -> VmyCPU
  -> C++ MemoryModel 模拟 IROM/DRAM/MMIO/counter
```

调整后：

```text
tb/verilator/main_mycpu.cpp
  -> VmyCPU
  -> dut_mycpu_io
  -> C++ MemoryModel
  -> rv32 checker

tb/verilator/main_student_top.cpp
  -> Vstudent_top
  -> dut_student_top_io
  -> RTL IROM_0/DRAM_0/perip_bridge/counter/display_seg
  -> src checker

tb/verilator/sim_result.cpp/.h
  -> 公共 JSON 输出、关键 MMIO 日志和 finish
```

公共模块 `checker_*`、`perf_stats`、`sim_config`、`sim_trace` 继续复用。

## Verilator 专用 RTL 钩子

`student_top.sv` 在 `VERILATOR_TB` 条件编译下增加 debug 输出：

```text
dbg_perip_addr
dbg_perip_wdata
dbg_perip_mask
dbg_perip_wen
```

这些端口只在 `scripts/run_verilator.py src` 构建 `student_top` 时启用，不进入 FPGA 正式接口。

`IROM_0.sv` 和 `DRAM_0.sv` 增加 plusargs 初始化：

```text
+irom_hex=<path>
+dram_hex=<path>
```

这样 src 测试切换 profile 时不需要为不同 hex 重新 Verilate。

## 脚本调整

`scripts/run_verilator.py` 现在按 mode 选择 build target：

| mode | top module | binary | filelist |
| --- | --- | --- | --- |
| `rv32` | `myCPU` | `build/verilator/mycpu/sim_mycpu` | `scripts/filelists/verilator_mycpu.f` |
| `src` | `student_top` | `build/verilator/student_top/sim_student_top` | `scripts/filelists/verilator_student_top.f` |

每次运行前会删除旧 result JSON，避免可执行文件崩溃时读到 stale result 误判。

C++ 参数解析会跳过 `+...` plusargs，避免把 Verilator plusargs 当作未知 TB 参数。

## counter 约束

src/student_top 路径使用真实 `rtl/soc/counter.sv`，该模块固定：

```text
50000 个 cnt_clk 周期 = 1 ms
```

当前 harness 让 `w_cpu_clk` 和 `w_clk_50Mhz` 同频同相翻转，因此 src/student_top 下 `counter_ms` 仍等价于每 50000 个 CPU 周期加 1ms。

`--counter-cycles-per-ms` 不能在 src/student_top 路径改成非 50000，否则 C++ 镜像统计和 RTL counter 语义会不一致；当前 `main_student_top.cpp` 会直接报错。

## 验证结果

构建：

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only --build-jobs 1 --build-cxx clang++
scripts/run_verilator.py src --test srcSmoke --build --build-only --build-jobs 1 --build-cxx clang++
```

结果：两个 Verilator 目标均构建通过。

rv32 回归：

```sh
scripts/run_verilator.py rv32 --suite rv32ui --no-build --max-cycles 30000
```

结果：

```text
rv32ui: 全部 PASS
```

src/student_top smoke：

```sh
scripts/run_verilator.py src --test srcSmoke --no-build --max-cycles 1000000
```

结果：

```text
srcSmoke: TIMEOUT
checker_kind: src_ledonly
cycles: 1000000
mmio_write_count: 0
dram_read_count: 50118
dram_write_count: 34116
```

额外生成短波形：

```sh
scripts/run_verilator.py src --test srcSmoke --no-build --max-cycles 2000 --trace
```

波形确认：

1. `student_top` 下 PC 有前进。
2. `commitCnt` 有增长。
3. `dbg_perip_*` 能采样到 DRAM 访问。
4. 2000 周期内没有 LED/SEG/CNT 写。

## 当前结论

TB 的 DUT 分流和 src/student_top harness 已完成。

需要注意：`srcSmoke` 在旧 `myCPU + C++ memory` 平台曾经能跑到 LED PASS；切到 `student_top` 后当前 1M 周期内未观察到 MMIO 写。这不是 stale result 或 TB 崩溃，是真实 `student_top` DUT 运行结果。

后续应优先定位：

1. `student_top/perip_bridge/dram_driver/DRAM_0` 的 DRAM 返回相位是否和 core load metadata 完全一致。
2. `IROM_0/DRAM_0` plusargs 初始化和地址映射是否与原 C++ MemoryModel 完全一致。
3. `student_top` 的 reset、双时钟 counter、perip_bridge 读选择是否引入了原 myCPU 平台没有覆盖的集成差异。

## 修改文件

RTL：

```text
rtl/soc/student_top.sv
rtl/ip/IROM_0.sv
rtl/ip/DRAM_0.sv
```

TB：

```text
tb/verilator/main_mycpu.cpp
tb/verilator/main_student_top.cpp
tb/verilator/dut_mycpu_io.cpp
tb/verilator/dut_mycpu_io.h
tb/verilator/dut_student_top_io.cpp
tb/verilator/dut_student_top_io.h
tb/verilator/sim_result.cpp
tb/verilator/sim_result.h
tb/verilator/sim_memory.cpp
tb/verilator/sim_memory.h
tb/verilator/sim_trace.cpp
tb/verilator/sim_trace.h
tb/verilator/sim_config.cpp
```

脚本与文档：

```text
scripts/run_verilator.py
docs/design/project_framework.md
docs/design/memory_and_test_contract.md
docs/design/rtl_core_design.md
docs/sim/verilator_plan.md
docs/README.md
docs/archive/2026-07-03/018_src_student_top_harness.md
```
