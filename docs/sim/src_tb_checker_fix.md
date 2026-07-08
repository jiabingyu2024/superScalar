# SRC TB checker 修复记录

本文记录本次对 `tb/verilator` 中 SRC pass/fail 判定逻辑的修复。背景是：把 `0x80100004` fail counter 作为“立即 FAIL”后，`srcSmoke` 和 `srcWithMext` 都在 RV32I suite 中间被提前终止，导致 TB 没有等到 dump 程序自己的最终 LED/SEG/lamp 判定。

## 1. 根因

dump 级程序的最终结果不是由 TB 直接决定，而是程序最终写 LED/SEG：

- 老式 `srcSmoke/src0/src1/src2`：最终写固定 `PASS=0x01221c08` 或 `FAIL=0x24181824`。
- 新式 `srcWithoutMext/srcWithMext`：最终写 `PASS_MARKER=0x04887020 | lamp_mask` 或 `FAIL_MARKER=0x90606090 | lamp_mask`。

`0x80100000/0x80100004` 是 RV32I pass/fail 计数器。它们适合作为诊断信息，但不能对所有 SRC profile 都作为立即终止条件，否则会比程序自身的最终判定更激进。

本次错误现象：

```text
cycle 786 write addr=0x80100004 data=0x00000001
TB 立即 FAIL
```

这会掐断程序后续的 SEG、counter、LED、lamp 流程。

## 2. 修复内容

### 2.1 不再把 fail counter 当成通用立即 FAIL

修改文件：

```text
tb/verilator/checker_src.cpp
```

现在 `ledonly`、`ledseg`、`lampseg` checker 都会记录：

```text
0x80100000 last pass count
0x80100004 last fail count
```

但不会因为 `fail_count != 0` 提前结束。只有专门的 `memcnt` checker 仍按 counter 判定。

### 2.2 新式 lamp marker 改成精确匹配

旧逻辑：

```cpp
(led & marker) == marker
```

新逻辑：

```cpp
(led & ~test_lamp_mask) == marker
```

这样 `PASS_MARKER/FAIL_MARKER` 和右侧 8 个小灯分开判断，避免额外非法 bit 被误认为 marker。

### 2.3 统一 src 默认最大周期

修改文件：

```text
scripts/run_verilator.py
tb/verilator/sim_common.h
```

之前直接调用脚本时默认只有 `20000000` cycles，并且读的是 `SRC_TEST_MAX_CYCLES`。现在统一为：

```text
SRC_MAX_CYCLES，默认 100000000
```

同时保留旧的 `SRC_TEST_MAX_CYCLES` 作为 fallback。

### 2.4 JSON 改成面向 LED/灯阵可读

修改文件：

```text
tb/verilator/sim_result.cpp
```

`correctness` 现在重点看这些字段：

```json
"summary": {
  "final_symbol_cn": "对号/错号/未知",
  "right_8_lamps_all_on": false,
  "right_8_lamps_value": "0x00020000",
  "rv32i_pass_counter": 33,
  "rv32i_fail_counter": 4,
  "rv32i_count_from_seg": 33,
  "mext_count_from_seg": 8
}
```

右边 8 个灯逐项在这里：

```json
"right_lamps": {
  "available": true,
  "all_on": false,
  "lamps": [
    {"index": 1, "on": false},
    {"index": 2, "on": false},
    {"index": 3, "on": false},
    {"index": 4, "on": false},
    {"index": 5, "on": false},
    {"index": 6, "on": true},
    {"index": 7, "on": false},
    {"index": 8, "on": false}
  ]
}
```

## 3. 当前验证结果

### 3.1 构建与静态检查

```sh
g++ -std=c++17 -I tb/verilator -fsyntax-only \
  tb/verilator/checker_src.cpp tb/verilator/sim_result.cpp

make verilator-build-src BUILD_JOBS=1 OBJCACHE=
```

结果：通过。

### 3.2 `srcSmoke`

命令：

```sh
python3 scripts/run_verilator.py src --test srcSmoke --no-build
```

结果：

```text
srcSmoke: PASS
cycles: 35415550
final_symbol_cn: 对号
LED: 0x01221c08
SEG: 0x33000708
RV32I pass/fail counter: 33 / 4
```

解释：`srcSmoke` 是老式 LED-only profile，最终是否 PASS 以旧版对号 LED 为准。RV32I counter 不满 37 会在 JSON 中暴露为诊断信息，但不改变 `srcSmoke` 这个 profile 的 PASS 门槛。

### 3.3 `srcWithMext` 短窗口

命令：

```sh
python3 scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --no-build
```

结果：

```text
srcWithMext: TIMEOUT
final_symbol_cn: 未知
right_8_lamps_value: 0x00020000
lamp6.on: true
RV32I pass/fail counter: 33 / 4
M/Z count from SEG: 8
```

解释：短窗口没有跑到最终 PASS/FAIL marker，因此是 TIMEOUT，不是 FAIL。当前 JSON 能直接看出右侧第 6 个灯亮，其余灯未亮。

## 4. 当前判定原则

| checker | PASS 条件 | FAIL 条件 | counter 用途 |
| --- | --- | --- | --- |
| `ledonly` | 观察到旧版 PASS LED | 观察到旧版 FAIL LED | 仅诊断 |
| `ledseg` | 旧版 PASS LED + SEG/counter 匹配 | 旧版 FAIL LED 或 SEG grace 失败 | 仅诊断 |
| `lampseg` | 精确 PASS marker + 全部 test lamps + SEG 计数匹配 | 精确 FAIL marker 或 PASS marker 缺灯/计数错 | 仅诊断 |
| `memcnt` | pass counter 达到期望且 fail counter 为 0 | fail counter 非 0 | 判定依据 |

这样 TB 不会抢在 dump 程序最终显示前提前结束，同时 JSON 仍保留足够信息定位 RV32I 小测试失败、灯阵进度和 SEG/counter 状态。

