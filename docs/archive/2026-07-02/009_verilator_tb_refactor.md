# Verilator TB 拆分与 smoke 验证

## 1. 本次目标

按 `008_tb_replan_after_review.md` 执行 TB 重构，目标是确保 TB/Verilator 侧能够稳定编译、运行、生成日志和 JSON 结果。由于当前 RTL 仍有内部 bug，rv32/src 测试出现 FAIL/TIMEOUT 不作为本次 TB 失败判据。

## 2. 实现内容

删除旧的单文件 `tb/verilator/tb_mycpu.cpp`，改为拆分结构：

| 文件 | 职责 |
| --- | --- |
| `tb/verilator/main.cpp` | 公共仿真入口，负责 clock/reset、主循环、结果 JSON 输出。 |
| `tb/verilator/sim_common.*` | 常量、公共结构、hex/json 工具。 |
| `tb/verilator/sim_config.*` | C++ TB 命令行参数解析。 |
| `tb/verilator/sim_memory.*` | IROM、DRAM、MMIO、counter 行为模型。 |
| `tb/verilator/sim_display.*` | `seg7`、`virtual_seg` 编码和检查。 |
| `tb/verilator/sim_trace.*` | FST trace 封装。 |
| `tb/verilator/checker.*` | checker 公共接口和工厂。 |
| `tb/verilator/checker_rv32.*` | rv32 `tohost` 严格判定。 |
| `tb/verilator/checker_src.*` | src `ledseg/observe/memcnt` checker。 |
| `tb/verilator/perf_stats.*` | 外部接口可观测性能统计。 |
| `tb/verilator/src_profiles.json` | src profile 到 checker 的映射。 |

`scripts/run_verilator.py` 已改为：

1. 编译多 C++ 源文件。
2. 根据 C++ 源和 filelist 时间戳判断是否需要重编。
3. 读取 `tb/verilator/src_profiles.json`。
4. 向 C++ TB 传入 `--src-checker`、LED signature、pass/fail counter 地址等 profile 参数。

## 3. DUT 与 checker 策略

主 DUT 仍为 `myCPU`。

当前 src profile：

| profile | checker | 当前含义 |
| --- | --- | --- |
| `src0/src1/src2/srcSmoke` | `ledseg` | 暂按 LED PASS/FAIL + SEG/counter 参考流程。 |
| `srcWithMext/srcWithoutMext` | `observe` | 只观测 `0x80100000/0x80100004` 等结果区，不用固定 LED/SEG magic value 判定。 |

`memcnt` checker 已预留，但只有配置 `expected_pass_count` 后才会把 pass counter 达标作为 PASS；否则建议先使用 `observe`，避免错误判定。

## 4. 性能统计

当前 JSON 中新增 `perf` 对象，记录第一阶段外部可观测指标：

1. `cycles`
2. `mmio_read_count/mmio_write_count`
3. `dram_read_count/dram_write_count`
4. `counter_start_cycle/counter_stop_cycle`
5. `counter_ms`
6. `first_led_write/last_led_write`
7. `first_seg_write/last_seg_write`

第二阶段内部 `commit_count/ipc/branch_miss` 等仍待后续通过 Verilator hierarchical/public 信号或薄 SV wrapper 接入。

## 5. 已验证命令

```sh
python3 -m py_compile scripts/run_verilator.py
python3 -m json.tool tb/verilator/src_profiles.json
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
scripts/run_verilator.py rv32 --test rv32ui-p-simple --max-cycles 20000 --no-build
scripts/run_verilator.py src --test srcSmoke --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
```

smoke 结果：

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| `rv32ui-p-simple` | FAIL，`tohost=0xffffffc4` | TB 正确捕获非 pass tohost。 |
| `srcSmoke` | TIMEOUT，`checker_kind=src_ledseg` | TB 正常生成超时结果和 perf 字段。 |
| `srcWithMext` | TIMEOUT，`checker_kind=src_observe` | TB 正常记录 DRAM 结果区写观测，不套用 LED/SEG 固定判定。 |

## 6. 当前限制

> 后续更新：`srcWithMext/srcWithoutMext` 已在 `010_src_mext_lampseg_checker.md` 中从 `observe` 升级为 `lampseg` checker。本节下方 smoke 表保留的是本归档创建时的历史结果。

1. `src0/src1/src2/srcSmoke` 是否全部严格适用 `ledseg` 仍需结合后续规则确认。
2. `srcWithMext/srcWithoutMext` 当前只观测，不给 PASS；需要用户提供或继续反推最终结束条件。
3. 性能统计目前只有外部接口层数据，内部提交数和 IPC 尚未接入。
4. 当前 smoke 的 FAIL/TIMEOUT 来自 DUT 行为或未确认判定规则，不代表 Verilator TB 链路失败。
