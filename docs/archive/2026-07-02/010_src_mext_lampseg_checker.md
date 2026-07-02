# srcWithMext/srcWithoutMext 新 LED/SEG 协议分析与 checker 更新

## 1. 背景

用户补充说明：与初赛相比，`srcWithMext/srcWithoutMext` 的 LED 显示做了调整：

1. 左侧 ✅/❎ 图案向左移动两排 LED。
2. 最右边编号 1-8 的 8 个灯分别对应 8 类测试。
3. 左侧 ✅/❎ 只有所有测试完成后才作为总结果点亮。
4. SEG 蓝色框显示 RV32I 指令集测试通过条数，满分 37。
5. SEG 绿色框显示测试时间开销，单位 ms。

因此，这两个 profile 不能继续使用旧的 `0x01221c08/0x24181824` LED signature，也不应只停留在 `observe`。

## 2. dump 反推结论

### 2.1 srcWithMext

关键函数：

| 地址 | 含义 |
| --- | --- |
| `0x800007d8` | 直接向 LED `0x80200040` 写入 `a0`。 |
| `0x80000810` | 将单项测试 bit OR 到 `0x80100038`，再写 LED。 |
| `0x80000860` | 将 PASS/✅ 图案 `0x04887020` OR 到 `0x80100038`，再写 LED。 |
| `0x800008a4` | 将 FAIL/❎ 图案 `0x90606090` OR 到 `0x80100038`，再写 LED。 |
| `0x800006f8` | 从 `0x80100000` 和 `0x80100030` 生成 SEG 高位显示。 |
| `0x80000774` | 将 counter 读数转换为 BCD 后 OR 到 SEG 低位。 |

主流程中先检查：

1. `0x80100000 == 37`：RV32I 测试通过条数。
2. `0x80100030 == 8`：M/Z 类或抽选扩展测试计数。

之后各测试通过时 OR 对应灯位。最终根据总通过状态调用 PASS/FAIL 图案函数。

### 2.2 srcWithoutMext

关键函数：

| 地址 | 含义 |
| --- | --- |
| `0x800001bc` | 直接向 LED `0x80200040` 写入 `a0`。 |
| `0x800001f4` | 将单项测试 bit OR 到 `0x80100030`，再写 LED。 |
| `0x80000244` | 将 PASS/✅ 图案 `0x04887020` OR 到 `0x80100030`，再写 LED。 |
| `0x80000288` | 将 FAIL/❎ 图案 `0x90606090` OR 到 `0x80100030`，再写 LED。 |
| `0x80000104` | 从 `0x80100000` 生成 SEG 高位 RV32I 通过条数。 |
| `0x80000158` | 将 counter 读数转换为 BCD 后 OR 到 SEG 低位。 |

主流程先检查 `0x80100000 == 37`，通过后点亮第 1 个测试灯。后续性能/异常测试继续点亮其余测试灯，最后写总 PASS/FAIL 图案。

## 3. 灯位协议

8 个右侧测试灯不是连续 bit，而是：

| 编号 | bit 值 | 含义 |
| --- | --- | --- |
| 1 | `0x00000001` | RV32I 测试通过。 |
| 2 | `0x00000002` | 抽选 Z/M 扩展或第二类测试通过。 |
| 3 | `0x00000100` | 性能/异常测试之一通过。 |
| 4 | `0x00000200` | 性能/异常测试之一通过。 |
| 5 | `0x00010000` | 性能/异常测试之一通过。 |
| 6 | `0x00020000` | 性能/异常测试之一通过。 |
| 7 | `0x01000000` | 性能/异常测试之一通过。 |
| 8 | `0x02000000` | 性能/异常测试之一通过。 |

测试灯总 mask：

```text
0x03030303
```

最终图案：

| 总结果 | marker | 期望最终 LED |
| --- | --- | --- |
| PASS/✅ | `0x04887020` | `0x04887020 | 0x03030303 = 0x078b7323` |
| FAIL/❎ | `0x90606090` | `0x90606090 | 已通过测试灯` |

## 4. checker 更新

新增 `src_lampseg` checker：

1. 观察 LED 写 `0x80200040`。
2. 记录 `last_src_test_lamps = led & 0x03030303`。
3. 观察到 `0x90606090` marker 时判 FAIL。
4. 观察到 `0x04887020` marker 时，严格检查：
   - 8 个测试灯是否全亮。
   - `last_rv32i_count == 37`。
   - `srcWithMext` 额外检查 `last_mext_count == 8`。
5. 检查通过后判 PASS，否则判 FAIL。
6. 若最大周期内未观察到最终 marker，则 TIMEOUT。

`src_profiles.json` 已更新：

| profile | checker | 关键配置 |
| --- | --- | --- |
| `srcWithMext` | `lampseg` | `test_lamp_mask=0x03030303`，`pass_marker=0x04887020`，`fail_marker=0x90606090`，`expected_rv32i_count=37`，`expected_mext_count=8`。 |
| `srcWithoutMext` | `lampseg` | `test_lamp_mask=0x03030303`，`pass_marker=0x04887020`，`fail_marker=0x90606090`，`expected_rv32i_count=37`。 |

## 5. smoke 结果

已验证：

```sh
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
scripts/run_verilator.py src --test srcWithMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
scripts/run_verilator.py src --test srcWithoutMext --max-cycles 200000 --counter-cycles-per-ms 50 --no-build
```

当前两个 src profile 仍 TIMEOUT，原因是 DUT 当前没有跑到最终 LED/SEG 写；但 JSON 中已显示：

1. `checker_kind = src_lampseg`
2. `last_src_test_lamps`
3. `last_rv32i_count`
4. `last_mext_count`
5. `saw_src_pass_marker/saw_src_fail_marker`

因此 TB 侧已经按新协议等待和记录结果，后续 RTL 修复后可以直接用于判定。
