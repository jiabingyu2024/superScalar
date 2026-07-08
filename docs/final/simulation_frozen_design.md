# Verilator 仿真框架当前定型说明

## 1. 入口和构建目标

当前仿真入口：

| 模式 | DUT | filelist | C++ main |
|---|---|---|---|
| `rv32` | `myCPU` | `scripts/filelists/verilator_mycpu.f` | `tb/verilator/main_mycpu.cpp` |
| `src` | `student_top` | `scripts/filelists/verilator_student_top.f` | `tb/verilator/main_student_top.cpp` |

`scripts/filelists/verilator_student_top.f` 内容：

```text
-f scripts/filelists/core.f
-f scripts/filelists/ip_verilator.f
-f scripts/filelists/soc.f
```

也就是 src 仿真会同时编译核心、SoC wrapper 和 `rtl/ip` 行为模型。与 FPGA Tcl 不同，Verilator 必须使用 `rtl/ip/IROM_0.sv`、`DRAM_0.sv`、`MUL_0.sv`、`DIV_0.sv`、`pll.sv`。

## 2. 推荐命令

```sh
make verilator-build-src BUILD_JOBS=1
python3 scripts/run_verilator.py src --test srcSmoke --no-build
python3 scripts/run_verilator.py src --test srcWithMext --max-cycles 2000000000 --no-build
python3 scripts/run_verilator.py src --test srcWithoutMext --max-cycles 2000000000 --no-build
```

Makefile 中 `SRC_MAX_CYCLES ?= 100000000`，`scripts/run_verilator.py` 中 src 默认最大周期也会回退到 `SRC_MAX_CYCLES`，再回退到旧环境变量 `SRC_TEST_MAX_CYCLES`，最后默认 `100000000`。

`srcWithMext` 长程序通常需要显式给更大的 `--max-cycles`，已有结果使用过 `2000000000`。

## 3. src profile 定型

`tb/verilator/src_profiles.json` 是 src 程序判定的事实来源：

| 测试 | checker | 关键字段 |
|---|---|---|
| `src0/src1/src2` | `ledseg` | 对号/错号 LED 签名，RV32I pass/fail counter，期望 pass 37。 |
| `srcSmoke` | `ledonly` | 对号/错号 LED 签名，counter 仅做结果 JSON 诊断。 |
| `srcWithMext` | `lampseg` | 最终对号/错号 marker、右侧 8 灯 mask `0x03030303`、RV32I 37、M 扩展 8。 |
| `srcWithoutMext` | `lampseg` | 最终对号/错号 marker、右侧 8 灯 mask `0x03030303`、RV32I 37，不要求 M 扩展计数。 |

当前关键 marker：

```text
legacy pass LED: 0x01221c08
legacy fail LED: 0x24181824
lampseg pass marker: 0x04887020
lampseg fail marker: 0x90606090
test lamp mask: 0x03030303
pass counter addr: 0x80100000
fail counter addr: 0x80100004
```

## 4. checker 行为

### 4.1 `src_ledonly`

文件：`tb/verilator/checker_src.cpp`

行为：

1. 观察 LED 写 `0x24181824`：立即 FAIL。
2. 观察 LED 写 `0x01221c08`：立即 PASS。
3. pass/fail counter 写入只记录到结果中，不作为 ledonly 的硬性 PASS/FAIL 条件。

适用：`srcSmoke`。它没有右侧 8 灯完整协议，因此不能要求 `0x03030303`。

如果把 fail counter 非零作为所有 src 的立即 FAIL，可能会误判某些程序中间阶段对 `0x80100004` 的诊断写；当前只在需要 counter 判定的 checker 中使用该逻辑。

### 4.2 `src_ledseg`

行为：

1. 先等 legacy pass LED。
2. 再检查 `seg_wdata` 的 BCD counter 格式和 virtual SEG 编码是否匹配。
3. 在 `src_seg_grace` 窗口内未匹配则 FAIL。

适用：`src0/src1/src2` 这类老协议程序。

如果只看 LED，不看 SEG，可能遗漏 SEG 显示链路或 counter 读写相位问题。

### 4.3 `src_lampseg`

行为：

1. 每次 LED 写入时提取 `value & test_lamp_mask` 作为右侧 8 灯状态。
2. 若 LED 低 mask 外字段匹配 fail marker，则 FAIL。
3. 若匹配 pass marker，则继续检查：
   - 右侧 8 灯必须全亮：`(value & 0x03030303) == 0x03030303`
   - 若配置 RV32I 期望计数，SEG 解码出的 RV32I 数必须等于 37。
   - 若配置 M 扩展期望计数，SEG 解码出的 M 数必须等于 8。
4. 全部满足才 PASS。

这解决了“只看某个 LED hex 值不可读，也容易误判”的问题。

如果删掉右侧 8 灯检查，程序可能只画出最终对号但某些右侧测试灯没亮，仍被误判 PASS。如果删掉 SEG 高位计数检查，`33` 与 `37` 这类 RV32I 子测试少通过问题会被掩盖。

## 5. JSON 结果可读字段

`tb/verilator/sim_result.cpp` 已把 src 正确性拆成可读结构：

```json
"correctness": {
  "summary": {
    "final_symbol_cn": "对号",
    "right_8_lamps_all_on": true,
    "right_8_lamps_value": "0x03030303",
    "rv32i_pass_counter": 37,
    "rv32i_fail_counter": 0,
    "rv32i_count_from_seg": 37,
    "mext_count_from_seg": 8
  },
  "right_lamps": {
    "lamps": [
      {"index": 1, "on": true},
      ...
      {"index": 8, "on": true}
    ]
  }
}
```

阅读结果时优先看：

1. `status`
2. `reason`
3. `correctness.summary.final_symbol_cn`
4. `correctness.summary.right_8_lamps_all_on`
5. `correctness.summary.rv32i_count_from_seg`
6. `correctness.summary.mext_count_from_seg`
7. `correctness.seg_readable.last_nonzero_raw`

## 6. 已有结果解释

### `srcSmoke`

已有结果：

```text
status: PASS
reason: LED pass signature observed
cycles: 35415550
final_symbol_cn: 对号
rv32i_pass_counter: 37
rv32i_fail_counter: 0
rv32i_count_from_seg: 37
mext_count_from_seg: 0
last_nonzero_seg: 0x37000708
```

`right_8_lamps_all_on=false` 是符合预期的，因为 `srcSmoke` profile 没有右侧 8 灯协议，`right_lamps.available=false`。

### `srcWithMext`

已有结果：

```text
status: PASS
reason: SRC final pass lamp marker and counters observed
cycles: 734122286
final_symbol_cn: 对号
right_8_lamps_all_on: true
right_8_lamps_value: 0x03030303
rv32i_count_from_seg: 37
mext_count_from_seg: 8
last_nonzero_seg: 0x37814682
```

其中 `0x378xxxxx` 的高位含义是：RV32I 计数 37，M 扩展计数 8，低位是 counter BCD。

## 7. 仿真时钟模型

`main_student_top.cpp` 同时推进 CPU clock 和 50 MHz SoC clock：

```text
cpu_half_period_ps = 500000 / cpu_freq_mhz
soc_half_period_ps = 500000 / DEFAULT_SOC_FREQ_MHZ
```

每个 CPU 上升沿：

```text
capture request
toggle clocks/eval/dump
checker.pre_tick
mirror.tick_request
checker.post_tick
perf.observe_state
```

这意味着 checker 看到的是 CPU 上升沿附近的请求和 mirror 更新后的外设状态。若以后改 RTL 的 MMIO 返回相位，必须同步审查 mirror 和 checker 的采样点，否则可能出现仿真模型与 RTL 相位不一致。

## 8. 当前误判边界

1. `srcSmoke` 是快速冒烟，不要求右侧 8 灯。
2. `srcWithMext/srcWithoutMext` 以最终 marker 为收敛条件；如果程序永远不写最终 marker，会 TIMEOUT。
3. JSON 中 `perf` 的部分乱序字段当前为 0 或残留字段，不代表当前 CPU 真有 ROB/IssueQueue。
4. `summary.json` 会被每次运行覆盖，不是长期累计数据库。
5. `srcWithMext` 若最大周期太小会 TIMEOUT，但 TIMEOUT 时可能已经看到部分正确 SEG/LED；不能把短窗口 TIMEOUT 当功能 FAIL。

## 9. 自检清单

1. 修改 CPU load/store 后，必须看 `LB/LH/LBU/LHU/SB/SH/SW` 和 `srcSmoke` 的 `rv32i_count_from_seg`。
2. 修改 LED/SEG/counter 地址后，必须同步改 `sim_common.h`、`src_profiles.json` 和 `SocMemBridge.sv`。
3. 修改 final marker 后，必须同步改 profile，不要在 checker 里硬编码。
4. 修改 `student_top` 调试口时，确保都包在 `VERILATOR_TB` 内。
5. 修改 DCache miss/resp 相位后，必须检查 `main_student_top.cpp` mirror 是否仍与 RTL 对齐。
6. 跑 `srcWithMext` 时显式给足 `--max-cycles`，避免把短周期 TIMEOUT 误判为功能问题。
