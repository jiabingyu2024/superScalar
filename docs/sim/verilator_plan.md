# Verilator 仿真说明

当前 Verilator TB 已按 `docs/archive/2026-07-02/008_tb_replan_after_review.md` 拆分为公共 harness、memory model、rv32 checker、src profile checker 和性能统计模块。RTL 当前仍可能 FAIL/TIMEOUT，这类结果只表示 DUT 行为未通过，不表示 TB 链路失败。

## 用户入口

当前 Makefile 是用户可见入口，`scripts/run_verilator.py` 在背后负责 Verilator 编译、测试发现、路径展开、批量执行和结果汇总。

常用命令：

```sh
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=srcSmoke
make sim-src-all
```

直接使用脚本时：

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple
scripts/run_verilator.py rv32 --suite rv32ui
scripts/run_verilator.py src --test srcSmoke
scripts/run_verilator.py src --all
```

可选参数：

| 参数 | 作用 |
| --- | --- |
| `--build` | 强制重编 Verilator。 |
| `--build-only` | 只编译，不运行测试。 |
| `--max-cycles N` | 设置最大 CPU 周期数。 |
| `--trace` | 生成 FST 波形到 `build/wave/<mode>/<test>.fst`。 |
| `--counter-cycles-per-ms N` | src counter 模型每 N 个 CPU 周期加 1ms，默认 50000。 |
| `--src-seg-grace N` | LED PASS 后等待 SEG 匹配的窗口，默认 512 周期。 |

### 重编译判定

默认不加 `--no-build` 时，`scripts/run_verilator.py` 会检查：

1. `tb/verilator/*.cpp/*.h`
2. `scripts/filelists/*.f`
3. `scripts/filelists/verilator_mycpu.f` 递归包含的 RTL/package/header 源文件

只要这些文件比 `build/verilator/mycpu/sim_mycpu` 新，就会自动重编。调试 RTL 时优先使用默认行为或显式 `--build`；只有明确要复用旧二进制时才使用 `--no-build`。

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
| `ip_verilator.f` | 仅 Verilator/仿真使用的 IP 行为模型。 |
| `verilator_mycpu.f` | 主 DUT `myCPU` 的仿真 filelist。 |
| `verilator_student_top.f` | SoC smoke DUT 的仿真 filelist。 |

注意：`core.f` 中 package 顺序必须满足 Verilator 声明依赖。当前 `StoreBufferTypes.sv`、`ROBTypes.sv`、`RecoveryTypes.sv` 放在 `PipelineTypes.sv` 前，避免 `StoreBufferIndexPath` 声明前引用。

## Testbench 结构

主 testbench 位于 `tb/verilator/`：

```text
main.cpp                  # 公共仿真入口：clock/reset/主循环/JSON 输出
sim_config.cpp/.h          # 命令行参数
sim_memory.cpp/.h          # IROM/DRAM/MMIO/counter 行为模型
sim_display.cpp/.h         # seg7/virtual_seg 编码和检查工具
sim_trace.cpp/.h           # FST 波形封装
perf_stats.cpp/.h          # 外部可观测性能统计
checker.cpp/.h             # checker 工厂和公共接口
checker_rv32.cpp/.h        # rv32 tohost checker
checker_src.cpp/.h         # src ledseg/observe/memcnt checker
src_profiles.json          # src profile 到 checker 的映射
```

当前只实例化 `myCPU`，不实例化 `student_top`。TB 负责模拟 `myCPU` 外部环境：

| 通道 | TB 行为 |
| --- | --- |
| IROM | 地址在 CPU 上升沿寄存，随后用寄存地址组合返回指令，匹配 BRAM 风格一拍取指契约。 |
| DRAM/普通内存 | 上升沿采样请求；读返回走两级 pipeline；读数据按 `addr[1:0]` 右移；写数据和 mask 按 `addr[1:0]` 左移，匹配 `dram_driver` 行为。 |
| MMIO | 支持 `SW0/SW1/KEY/SEG/LED/CNT` 地址；写 SEG/LED/CNT 更新 TB 内部寄存器。 |
| counter | 写 `0x80200050 = 0x80000000` 启动，写 `0xffffffff` 停止；默认每 50000 个 CPU 周期加 1ms，可由参数调整。 |
| virtual_seg | 按 `display_seg`/`seg7` 编码模型生成，并在 src 判定中检查能否还原当前 `seg_wdata`。 |

TB 在 CPU 上升沿前捕获 `perip_*` 请求，在上升沿后推进外部模型。日志中会记录关键 MMIO 写：

```text
cycle 299 write addr=0x80001000 data=0xffffffc4 mask=0xf
```

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
| `src0/src1/src2/srcSmoke` | `ledseg` | 暂按参考 LED/SEG 流程判定，后续可按 dump/规则调整。 |
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

## src 性能统计

src 结果需要同时输出正确性和性能信息。

当前第一阶段不改 RTL 端口，已记录外部可观测数据：

| 字段 | 含义 |
| --- | --- |
| `cycles` | 仿真 CPU 周期 |
| `result_cycle` | PASS/FAIL/TIMEOUT 周期 |
| `counter_ms` | TB counter 最终值 |
| `counter_start_cycle/counter_stop_cycle` | 程序控制计数器的周期 |
| `mmio_write_count` | MMIO 写次数 |
| `dram_read_count/dram_write_count` | DRAM 访问次数 |
| `first/last_led_write` | LED 写观测 |
| `first/last_seg_write` | SEG 写观测 |
| `checker_kind` | 本 profile 使用的判定器 |
| `last_src_test_lamps` | `lampseg` checker 观测到的 8 个测试灯 bit。 |
| `last_rv32i_count` | 从 SEG 高两位 BCD 解出的 RV32I 通过条数。 |
| `last_mext_count` | `srcWithMext` 中从 SEG 对应位解出的 M/Z 类测试条数。 |

第二阶段再读取内部 perf/debug 信号，目标包括 `commit_count`、`ipc`、`branch_count`、`branch_miss_count`、访存提交数和恢复/停顿计数。优先通过 Verilator hierarchical/public 信号或薄 SV wrapper 暴露，不先修改 `myCPU` 的综合接口。

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
| `scripts/run_verilator.py rv32 --test rv32ui-p-simple --max-cycles 20000 --no-build` | FAIL，tohost 写 `0xffffffc4` | TB 正确捕获 tohost 非 pass 值；DUT 当前未通过。 |
| `scripts/run_verilator.py src --test srcSmoke --max-cycles 200000 --counter-cycles-per-ms 50 --no-build` | TIMEOUT，`checker_kind=src_ledseg` | TB 正常输出超时和 perf 字段；当前未观察到 LED PASS 写。 |
| `scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build` | TIMEOUT，`checker_kind=src_lampseg` | TB 正常使用新灯位协议；当前未观察到最终 PASS/FAIL 图案。 |
| `scripts/run_verilator.py src --test srcWithoutMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build` | TIMEOUT，`checker_kind=src_lampseg` | TB 正常使用新灯位协议；当前未观察到最终 PASS/FAIL 图案。 |

这些 smoke 只证明 TB 和 Verilator 链路可执行，不代表 RTL 正确。
