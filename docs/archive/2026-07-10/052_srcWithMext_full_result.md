# srcWithMext 全量仿真结果归档

时间：2026-07-10 01:21 CST

命令：

```bash
python3 scripts/run_verilator.py src --test srcWithMext --no-build --max-cycles 2000000000
```

原始文件：

- `docs/archive/2026-07-10/srcWithMext_20260710_0121/srcWithMext.json`
- `docs/archive/2026-07-10/srcWithMext_20260710_0121/srcWithMext.log`
- 原始输出仍保留在 `build/result/src/srcWithMext.json` 和 `build/log/src/srcWithMext.log`

## 结论

这次不是 timeout，而是程序主动写出 final fail lamp marker。

关键结果：

- status: `FAIL`
- reason: `SRC final fail lamp marker observed`
- cycles: `681736299`
- max_cycles: `2000000000`
- final LED raw: `0x93636392`
- final SEG raw: `0x37613634`
- expected SEG high: `0x37800000`
- RV32I pass counter: `37 / 37`
- RV32I fail counter: `0`
- M extension counter from SEG: `6 / 8`
- counter ms: `13634`

## 关键现象

`srcSmoke` 短窗口进入正确程序后，这次 `srcWithMext` 全量跑到了约 681.7M cycles，并最终失败。SEG 高位停在 `0x376...`，而 pass 期望是 `0x378...`。这说明当前不是运行时间上限问题，而是 M 扩展相关检查只推进到 6 个计数，未达到 8 个计数。

log 尾部关键写入：

```text
cycle 681735728 write addr=0x80200040 data=0x03030302 mask=0xf
cycle 681735804 write addr=0x80200050 data=0xffffffff mask=0xf
cycle 681736241 write addr=0x80200020 data=0x37613634 mask=0xf
cycle 681736299 write addr=0x80200040 data=0x93636392 mask=0xf
srcWithMext FAIL after 681736299 cycles: SRC final fail lamp marker observed
```

## 性能快照

来自 result JSON：

- core cycles: `681736297`
- committed instructions/uops count: `380344325`
- IPC: `0.557905`
- branch count: `10958972`
- DRAM reads: `121299058`
- DRAM writes: `21450242`
- frontend stall cycles: `368563460`

注意：这次长跑启动于 IROM `clkb`/Vivado common-clock 修正之前，因此本结果用于判断 aRAT/recovery 修复后的长程序行为；IROM 接口修正本身仍需要后续重新 build 后做短窗口确认。

## 下一步建议

1. 不再重复跑全量 `srcWithMext`，先针对 M 扩展后两项失败做局部定位。
2. 优先看 `MulDivUnit.sv` 的 signed/unsigned、REM/REMU、DIV overflow、除零、结果 lane 写回和 busy/valid 清除路径。
3. 结合 test 程序或 MMIO progress 编号确认 `mext_count_from_seg=6` 对应的具体子测试。
4. 后续小改只跑 RV32UM 单测和 `srcWithMext` 短窗口，除非确认接近最终闭环再跑全量。
