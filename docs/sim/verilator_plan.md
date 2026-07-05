# Verilator 仿真说明

当前 Verilator TB 按测试类型拆成两个 DUT 入口：

| 测试类型 | DUT | 可执行文件 | 定位 |
| --- | --- | --- | --- |
| rv32 | `myCPU` | `build/verilator/mycpu/sim_mycpu` | 最小平台，方便抓 core/接口波形，主打 ISA 正确性定位。 |
| src | `student_top` | `build/verilator/student_top/sim_student_top` | SoC 集成平台，覆盖 IROM/DRAM/perip_bridge/counter/display 路径。 |

公共 checker、性能统计、结果 JSON、参数解析仍复用同一套 C++ 代码。RTL 当前仍可能 FAIL/TIMEOUT，这类结果只表示 DUT 行为未通过，不表示 TB 链路失败。

## 用户入口

当前 Makefile 是用户可见入口，`scripts/run_verilator.py` 只作为 Makefile 背后的实现脚本，负责 Verilator 编译、测试发现、路径展开、批量执行和结果汇总。日常运行仿真默认使用 `make`。

常用命令：

```sh
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=srcSmoke
make sim-src-all
```

常用 make 变量：

| 变量 | 示例 | 作用 |
| --- | --- | --- |
| `TEST` | `make sim-src TEST=srcSmoke` | 选择单个测试。 |
| `SUITE` | `make sim-rv32 SUITE=rv32ui` | 选择 rv32 套件。 |
| `MAX_CYCLES` | `make sim-src TEST=srcSmoke MAX_CYCLES=200000000` | 覆盖仿真最大 CPU 周期数。 |
| `SRC_MAX_CYCLES` | `make sim-src TEST=srcSmoke SRC_MAX_CYCLES=120000000` | 只覆盖 src 默认最大周期；未设置 `MAX_CYCLES` 时生效。 |
| `TRACE` | `make sim-rv32 TEST=rv32ui-p-simple TRACE=1` | 生成 FST 波形。 |
| `BUILD` | `make sim-src TEST=srcSmoke BUILD=1` | 强制重编后运行。 |
| `NO_BUILD` | `make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1` | 跳过重编，复用已有二进制。 |
| `BUILD_JOBS` | `make verilator-build BUILD_JOBS=1` | 设置 Verilator build 并行度。 |
| `BUILD_CXX` | `make verilator-build BUILD_CXX=clang++` | 设置 Verilator 生成 C++ 的编译器。 |
| `SRC_SEG_GRACE` | `make sim-src TEST=src0 SRC_SEG_GRACE=1024` | 设置 ledseg checker 的 SEG 宽限周期。 |
| `CPU_FREQ_MHZ` | `make sim-src TEST=srcSmoke CPU_FREQ_MHZ=150` | 设置 src/student_top 仿真中的 CPU core 频率，用于双时钟推进和性能 ms 换算；SoC counter 时钟仍固定 50MHz。 |

src 默认最大周期：

```sh
SRC_MAX_CYCLES ?= 100000000
```

因此 `make sim-src TEST=srcSmoke` 默认会用 `100000000` 周期上限，避免 src 类长程序被脚本默认短上限过早截断。需要更短 debug 时显式设置 `MAX_CYCLES`。

src/student_top 的频率口径：

```sh
CPU_FREQ_MHZ ?= 50
```

`CPU_FREQ_MHZ` 只改变 Verilator harness 中 `w_cpu_clk` 的节奏，以及结果 JSON 的 `perf.elapsed_ms_by_cpu_freq = cycles / (CPU_FREQ_MHZ * 1000)`。`w_clk_50Mhz` 仍固定按 50MHz 推进，`rtl/soc/counter.sv` 的 50000 cycle/ms 行为不改。因此 JSON 中：

| 字段 | 含义 |
| --- | --- |
| `perf.cpu_freq_mhz` | 本次按 make 参数设置的 CPU 频率。 |
| `perf.elapsed_ms_by_cpu_freq` | 按 CPU 周期和 CPU 频率换算的性能耗时。 |
| `perf.soc_counter_freq_mhz` | SoC/counter 固定频率，当前为 50MHz。 |
| `correctness.counter.ms` / `perf.counter.ms` | `student_top` 内 counter 按 50MHz 时钟得到的显示/测评 counter ms。 |

### 重编译判定

默认不加 `--no-build` 时，`scripts/run_verilator.py` 会检查：

1. `tb/verilator/*.cpp/*.h`
2. `scripts/filelists/*.f`
3. 当前 mode 对应 filelist 递归包含的 RTL/package/header 源文件

rv32 检查 `build/verilator/mycpu/sim_mycpu`，src 检查 `build/verilator/student_top/sim_student_top`。调试 RTL 时优先使用默认行为或显式 `--build`；只有明确要复用旧二进制时才使用 `--no-build`。

当前构建命令默认加入：

```text
--output-split 20000 --output-split-cfuncs 20000
```

目的是拆小 Verilator 生成的 C++ 翻译单元，降低 GCC/clang 编译内存压力。若并行重编中断或编译器 ICE，应先清理对应 `build/verilator/<target>` 后单线程重建：

```sh
make sim-rv32 SUITE=rv32ui BUILD=1 BUILD_JOBS=1 BUILD_CXX=clang++
```

## 测试选择粒度

rv32 测试需要支持：

| 模式 | 示例 |
| --- | --- |
| 单个测试 | `TEST=rv32ui-p-add` |
| 单个套件 | `SUITE=rv32ui` |
| 全部套件 | `sim-rv32-all` |

src 测试需要支持：

| 模式 | 示例 |
| --- | --- |
| 单个 profile | `TEST=src0` |
| 全部 profile | `sim-src-all` |

## 文件列表

稳定 filelist 位于 `scripts/filelists/`：

| 文件 | 用途 |
| --- | --- |
| `core.f` | core package、interface、module、`core` 和 `myCPU`。 |
| `soc.f` | SoC wrapper RTL。 |
| `ip_verilator.f` | 仅 Verilator/仿真使用的 IP 行为模型，当前包含 `IROM_0/DRAM_0/MUL_0/DIV_0/pll`。 |
| `verilator_mycpu.f` | rv32 DUT `myCPU` 的仿真 filelist，包含 `core.f` 和 `ip_verilator.f`，用于解析 core 内实例化的 `MUL_0/DIV_0`。 |
| `verilator_student_top.f` | src DUT `student_top` 的仿真 filelist。 |

注意：`core.f` 中 package 顺序必须满足 Verilator 声明依赖。当前 `StoreBufferTypes.sv`、`ROBTypes.sv`、`RecoveryTypes.sv` 放在 `PipelineTypes.sv` 前，避免 `StoreBufferIndexPath` 声明前引用。

## Testbench 结构

主 testbench 位于 `tb/verilator/`：

```text
main_mycpu.cpp            # rv32/myCPU 仿真入口
main_student_top.cpp      # src/student_top 仿真入口
dut_mycpu_io.cpp/.h       # myCPU 端口驱动和 perip/irom 请求采样
dut_student_top_io.cpp/.h # student_top 的 Verilator-only dbg_perip_* 采样
sim_config.cpp/.h          # 命令行参数
sim_memory.cpp/.h          # IROM/DRAM/MMIO/counter 行为模型
sim_display.cpp/.h         # seg7/virtual_seg 编码和检查工具
sim_trace.cpp/.h           # FST 波形封装
sim_result.cpp/.h          # JSON 输出、关键 MMIO 日志、统一 finish
perf_stats.cpp/.h          # 外部可观测性能统计
checker.cpp/.h             # checker 工厂和公共接口
checker_rv32.cpp/.h        # rv32 tohost checker
checker_src.cpp/.h         # src ledseg/observe/memcnt checker
src_profiles.json          # src profile 到 checker 的映射
```

### rv32/myCPU 平台

rv32 只实例化 `myCPU`。TB 负责模拟 `myCPU` 外部环境：

| 通道 | TB 行为 |
| --- | --- |
| IROM | 地址在 CPU 上升沿寄存，随后用寄存地址组合返回指令，匹配 BRAM 风格一拍取指契约。 |
| DRAM/普通内存 | 上升沿采样请求；读返回走两级 pipeline；读数据按 `addr[1:0]` 右移；写数据和 mask 按 `addr[1:0]` 左移，匹配 `dram_driver` 行为。 |
| MMIO | 支持 `SW0/SW1/KEY/SEG/LED/CNT` 地址；写 SEG/LED/CNT 更新 TB 内部寄存器。 |
| counter | 写 `0x80200050 = 0x80000000` 启动，写 `0xffffffff` 停止；默认每 50000 个 CPU 周期加 1ms，可由参数调整。 |
| virtual_seg | myCPU 平台保留 C++ 编码模型，主要用于早期 src checker 调试；当前正式 src 路径使用 `student_top` 内 RTL `display_seg`。 |

TB 在 CPU 上升沿前捕获 `perip_*` 请求，在上升沿后推进外部模型。日志中会记录关键 MMIO 写：

```text
cycle 299 write addr=0x80001000 data=0xffffffc4 mask=0xf
```

### src/student_top 平台

src 实例化 `student_top`，不再由 C++ 模拟 IROM/DRAM 返回数据：

| 通道 | 行为 |
| --- | --- |
| IROM | 使用 RTL `IROM_0`，通过 Verilator plusarg `+irom_hex=<path>` 在仿真启动时 `$readmemh`。 |
| DRAM | 使用 RTL `perip_bridge/dram_driver/DRAM_0`，通过 `+dram_hex=<path>` 初始化 `DRAM_0.mem[0]` 起始内容。 |
| MMIO/counter/display | 使用 RTL `perip_bridge/counter/display_seg`；`counter.sv` 不修改，固定 50000 个 `w_clk_50Mhz` 周期加 1ms。 |
| checker 采样 | `student_top.sv` 在 `VERILATOR_TB` 下暴露 `dbg_perip_addr/dbg_perip_wdata/dbg_perip_mask/dbg_perip_wen`，只用于 Verilator，不改变 FPGA 接口。 |

src harness 中 `w_cpu_clk` 和 `w_clk_50Mhz` 当前同频同相翻转，因此 counter 的 1ms 对应 50000 个 CPU 周期。`--counter-cycles-per-ms` 对 src/student_top 平台不能改成非 50000，否则 C++ 镜像统计和 RTL `counter.sv` 会不一致。

## rv32 判定

rv32 使用严格 `tohost`：

| 条件 | 结果 |
| --- | --- |
| 写 `tohost == 1` | PASS |
| 写 `tohost != 0 && tohost != 1` | FAIL |
| 超过最大周期 | TIMEOUT |
| dump 中找不到 `tohost` | UNSUPPORTED |

`tohost` 地址由对应 `.dump` 中的 `<tohost>` 符号解析，不全局硬编码。

## src profile 与判定

src profile 配置位于：

```text
tb/verilator/src_profiles.json
```

当前 checker 分类：

| checker | 行为 |
| --- | --- |
| `ledseg` | 使用 LED PASS/FAIL signature，并在 LED PASS 后检查 SEG BCD 和 virtual SEG。 |
| `ledonly` | 只使用 LED PASS/FAIL signature；用于最终不保持 SEG 计数格式的 profile。 |
| `observe` | 不武断给 PASS/FAIL，只记录 LED/SEG/counter/DRAM 结果区行为，直到超时。 |
| `memcnt` | 支持 DRAM pass/fail counter；只有配置 `expected_pass_count` 后才会按 pass counter 给 PASS。 |
| `lampseg` | 面向 `srcWithMext/srcWithoutMext` 的新灯位协议：识别最终 ✅/❎ 图案、8 个测试灯和 SEG 测试条数。 |

`ledseg` 使用用户给出的赛事参考流程：

```text
CPU 运行
  -> testbench 在 CPU 上升沿采样 perip_wen/perip_addr/perip_wdata
  -> 若写 LED 地址 0x80200040
       data == 0x24181824 => FAIL
       data == 0x01221c08 => 记录 saw_led_pass
  -> saw_led_pass 后继续检查 SEG 和 virtual_seg
       SEG 高两位 BCD == 37
       SEG 低六位 BCD == counter_ms
       virtual_seg 编码能还原当前 seg_wdata
  -> LED PASS 且 SEG/virtual SEG 均匹配 => PASS
  -> LED PASS 后 512 个 CPU 周期内 SEG 仍不匹配 => FAIL
  -> 到 SRC_TEST_MAX_CYCLES 仍无最终结果 => TIMEOUT
```

该流程不能作为所有 src profile 的通用判定。当前配置：

| profile | checker | 说明 |
| --- | --- | --- |
| `src0/src1/src2` | `ledseg` | 暂按参考 LED/SEG 流程判定，后续可按 dump/规则调整。 |
| `srcSmoke` | `ledonly` | 实测最终先停止 counter、写 `SEG=0`，再写旧 LED PASS `0x01221c08`；因此用 LED PASS/FAIL 判定，SEG/counter 只作为性能观测字段记录。 |
| `srcWithMext` | `lampseg` | 使用新 LED/SEG 协议：8 个测试灯 mask 为 `0x03030303`，PASS 图案 `0x04887020`，FAIL 图案 `0x90606090`，要求 RV32I 条数 37、M/Z 类条数 8。 |
| `srcWithoutMext` | `lampseg` | 使用新 LED/SEG 协议：8 个测试灯 mask 为 `0x03030303`，PASS 图案 `0x04887020`，FAIL 图案 `0x90606090`，要求 RV32I 条数 37。 |

`srcWithMext/srcWithoutMext` 的 8 个右侧测试灯对应非连续 bit：

```text
1: 0x00000001
2: 0x00000002
3: 0x00000100
4: 0x00000200
5: 0x00010000
6: 0x00020000
7: 0x01000000
8: 0x02000000
```

也就是总 mask `0x03030303`。最终 PASS/FAIL 不是旧的 `0x01221c08/0x24181824`，而是左侧图案移动后的：

| 图案 | marker | 最终 LED 形式 |
| --- | --- | --- |
| PASS/✅ | `0x04887020` | `0x04887020 | test_lamps` |
| FAIL/❎ | `0x90606090` | `0x90606090 | test_lamps` |

因此，当前 `srcWithMext/srcWithoutMext` 若超时，只表示尚未观察到最终 PASS/FAIL 图案，不代表 TB 判定错误。

## 结果 JSON

每个测试会输出：

```text
build/result/<mode>/<test>.json
```

JSON 分为三层：

| 字段 | 含义 |
| --- | --- |
| `test/mode/checker/status/reason/cycles/max_cycles` | 测试名、测试类型、checker、结果、原因、实际周期和上限。 |
| `correctness` | 正确性相关观测，rv32 主要是 `tohost`，src 主要是 LED/SEG/counter/lamp marker。 |
| `perf` | 性能和访存统计，包含 commit、IPC、分支预测、DRAM/MMIO 访问、counter、LED/SEG 写历史。 |

src 的 `correctness` 关键字段：

| 字段 | 含义 |
| --- | --- |
| `correctness.led.pass_seen` | 是否观察到 LED PASS signature。 |
| `correctness.led.pass_cycle` | LED PASS 所在 CPU 周期。 |
| `correctness.led.last_value` | 最后一次 LED 写值。 |
| `correctness.seg.current_value` | 当前/最后一次 SEG 写值；有些程序最终会清零。 |
| `correctness.seg.pass_display_value` | 最后一次非零 SEG 写值，用来保留 `0x37......` 这类通过条数/计时显示。 |
| `correctness.seg.pass_display_cycle` | `pass_display_value` 写入周期。 |
| `correctness.seg.value_at_last_led_write` | 最后一次 LED 写发生时 TB 记录到的 SEG 值。 |
| `correctness.seg.expected_counter_value` | 按 `counter.ms` 重新编码出的期望显示值：高两位固定 `37`，低六位为 counter ms 的 BCD，例如 1456ms 对应 `0x37001456`。 |
| `correctness.seg.current_matches_counter_ms` | 当前/最后 SEG 写值是否等于 `expected_counter_value`。 |
| `correctness.seg.pass_display_matches_counter_ms` | 最后一次非零 SEG 写值是否等于 `expected_counter_value`。 |
| `correctness.seg.value_at_last_led_matches_counter_ms` | 最后一次 LED 写入时 SEG 是否等于 `expected_counter_value`。 |
| `correctness.counter.ms` | counter 当前毫秒值，单位 ms；src/student_top 下来自 RTL counter 的同频镜像。 |
| `correctness.counter.start_cycle/stop_cycle` | 程序写 counter start/stop 的周期。 |
| `correctness.src_lamps.*` | `lampseg` checker 下的新灯位协议观测。 |

`perf` 关键字段：

| 字段 | 含义 |
| --- | --- |
| `perf.core_cycle` | core 内部 perf cycle。 |
| `perf.commit_count` | 已提交指令数。 |
| `perf.ipc` | `commit_count / cycles`。 |
| `perf.branch_count` | 已提交分支数。 |
| `perf.branch_miss_count` | 已提交分支中预测错误数。 |
| `perf.branch_hit_count` | `branch_count - branch_miss_count`。 |
| `perf.branch_hit_rate` | `branch_hit_count / branch_count`；无分支时为 0。 |
| `perf.branch_miss_rate` | `branch_miss_count / branch_count`；无分支时为 0。 |
| `perf.branch_breakdown.conditional` | 条件分支提交数、miss 数和 miss rate。 |
| `perf.branch_breakdown.jal` | `JAL` 提交数、miss 数和 miss rate。 |
| `perf.branch_breakdown.jalr` | `JALR` 提交数、miss 数和 miss rate。 |
| `perf.memory.dram_read_count/dram_write_count` | DUT 对 DRAM 区域的读/写请求数。 |
| `perf.memory.mmio_read_count/mmio_write_count` | DUT 对 MMIO 区域的读/写请求数。 |
| `perf.stalls.frontend_cycles` | PF stall 周期数，可近似看作前端被全局阻塞的周期。 |
| `perf.stalls.id/rn/ds/is/rr/ex/wb_cycles` | 各级 `PipeCtrlPath.stall` 周期数；这些桶不是互斥分类。 |
| `perf.stalls.recovery_cycles` | 发生 recovery 事件的周期数。 |
| `perf.resources.rob_full_cycles` | ROB 满导致或参与阻塞的周期数。 |
| `perf.resources.issue_queue_full_cycles` | IssueQueue 满导致或参与阻塞的周期数。 |
| `perf.resources.free_list_empty_cycles` | FreeList 空导致或参与阻塞的周期数。 |
| `perf.resources.store_buffer_full_cycles` | StoreBuffer 分配不可用导致或参与 Dispatch 阻塞的周期数。 |
| `perf.resources.serial_block_cycles` | serial/system 指令顺序化阻塞周期数。 |
| `perf.mem_stalls.load_return_block_cycles` | `ExecuteMemStage` 因 load 返回和当前 MEM pipe 冲突拉 `exStallReq` 的周期数。 |
| `perf.mem_stalls.load_access_block_cycles` | load 发起阶段被 StoreBuffer/DRAM access ready 阻塞的周期数。 |
| `perf.mem_stalls.store_commit_blocked_by_load_cycles` | StoreBuffer head store 请求提交但同周期 DRAM 被 load 读优先占用的周期数。 |
| `perf.width.dispatch/issue/commit.w0/w1/w2_cycles` | 每周期对应阶段实际宽度为 0/1/2 的分布，用于判断二路是否真正被利用。 |
| `perf.counter` | counter 起停周期和最终 ms。 |
| `perf.led/perf.seg` | LED/SEG 首次、末次、非零写入值和周期。 |

SEG/counter 显示的判断口径：

```text
expected_counter_value = 0x37000000 | bcd6(counter_ms)
```

其中 `bcd6` 只编码低六位十进制数字。若 `counter.ms=1456`，期望显示值为 `0x37001456`。`srcSmoke` 当前 profile 仍使用 `ledonly` checker，因此 LED PASS 可使测试 PASS；但若三个 `*_matches_counter_ms` 字段均为 `false`，说明本次运行没有观察到最终 SEG 保持 `0x37xxxxxx` 且低六位对应 counter ms。这应按“LED-only 通过，完整 SEG/counter 协议未满足”理解，不能当成正式 src 显示协议已经通过。

IPC 的判断口径：

```text
perf.ipc = perf.commit_count / cycles
```

`commit_count` 和 `branch_*` 来自 core 的 `PerfIF` debug 口，不按 TB wall-clock 或 MMIO 访问数估算。`PerfIF` 在每个 core 周期累加 `cycle`，按两路 `commitValid` 累加提交指令数，按 commit 阶段分支更新/branch miss 累加分支统计，并按 `conditional/JAL/JALR` 细分。因此 IPC 低首先表示 core 在该 workload 下实际提交密度低；后续需要结合 `branch_breakdown`、store/mem 阻塞、分支提交停止后续 commit、恢复 flush 代价等 RTL 行为分析。

rv32/myCPU 和 src/student_top 都通过 `VERILATOR_TB` 条件编译读取 core `PerfIF`，不改变 FPGA 正式接口。新增 stall/resource/width 字段来自 RTL 内部计数器，TIMEOUT 结果同样会输出，因此适合用小 `MAX_CYCLES` 做性能瓶颈抽样。

当测试 PASS/FAIL 或跑到 `MAX_CYCLES` 上限时，TB 会输出当前已经累计的 JSON。C++ harness 内部也支持 `SIGINT/SIGTERM` 收尾输出 `INTERRUPTED`，但从 `make -> python -> simulator` 链路按 Ctrl-C 时，信号可能先终止包装层，实际是否留下 JSON 取决于信号传递时机；需要稳定中断结果时，优先用较小 `MAX_CYCLES` 主动结束。

## 生成输出

仿真输出：

```text
build/verilator/   # Verilator obj_dir 和可执行文件
build/log/         # 编译日志和每个测试的运行日志
build/wave/        # --trace 时生成 FST
build/result/      # 每个测试的 JSON 结果和 summary.json
```

`build/` 已被 git 忽略。

## 测试数据准备

使用：

```sh
scripts/prepare_test_data.py
```

该脚本会在 `data/` 原目录下补齐缺失的 `.hex` 和 `.dump`。默认幂等，不覆盖已有文件；需要覆盖时显式使用 `--force`。

当前规则：

| 测试类型 | 输入 | 生成物 |
| --- | --- | --- |
| rv32 | ELF | `<test>.hex`、缺失时生成 `<test>.dump` |
| src | `irom.coe/dram.coe` | `irom.hex/dram.hex`、当目录内没有 `.dump` 时由 `irom.coe` 生成 `<profile>.dump` |

src dump 是基于 `irom.coe` 的 raw RV32 反汇编，不包含 ELF 符号信息。

## 当前 smoke 结果

截至本文更新时，TB/Verilator 编译可通过：

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
```

已运行的短 smoke：

| 命令 | 结果 | 含义 |
| --- | --- | --- |
| `scripts/run_verilator.py rv32 --suite rv32ui --max-cycles 30000 --no-build` | PASS | 当前 `rv32ui` 回归通过。 |
| `scripts/run_verilator.py rv32 --suite rv32mi --max-cycles 30000 --no-build` | PASS | 当前支持的 `rv32mi` SYS/CSR 路径回归通过。 |
| `scripts/run_verilator.py rv32 --suite rv32um --max-cycles 30000 --no-build` | PASS | 当前 RV32M mul/div/rem 回归通过。 |
| `make verilator-build` | PASS | 单实例 `MUL_0/DIV_0` 接入后，rv32/myCPU Verilator 构建通过。 |
| `make verilator-build-src` | PASS | 单实例 `MUL_0/DIV_0` 接入后，src/student_top Verilator 构建通过。 |
| `make sim-src TEST=srcSmoke NO_BUILD=1` | PASS，`checker_kind=src_ledonly` | Makefile 默认 `SRC_MAX_CYCLES=100000000`；在 `72814875` 周期观察到 LED PASS，`counter_ms=1456`，最终 SEG 为 `0x37001456`，三个 SEG/counter match 字段均为 true。 |
| `make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1` | TIMEOUT，但早期 MMIO 正常 | `2496` 周期写 `SEG=0x37000000`，`2569` 周期开始写 counter start，用于快速确认 student_top DRAM 时序未退化。 |
| `make sim-src TEST=srcSmoke MAX_CYCLES=5000 TRACE=1 NO_BUILD=1` | TIMEOUT，生成 FST | 用于确认 student_top 下 PC/commit/perip/DRAM 关键信号可抓取。 |
| `make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1` | 未重新回归 | 已具备 student_top 入口，待后续按 profile 跑长回归。 |
| `make sim-src TEST=srcWithoutMext MAX_CYCLES=200000 NO_BUILD=1` | 未重新回归 | 已具备 student_top 入口，待后续按 profile 跑长回归。 |

这些 smoke 说明 rv32/myCPU harness 保持可用，src/student_top harness 已能完整跑通 `srcSmoke`。此前 `student_top` 下 timeout 的直接原因是 `DRAM_0` 仿真行为模型读返回相位和写周期处理不匹配：write 周期污染读地址管线，且读数据比 `perip_bridge`/core load metadata 期望晚一拍。当前 `DRAM_0` 已改为 read-only 推进读地址寄存，下一拍输出上一拍读地址数据，write 周期只更新 memory。
