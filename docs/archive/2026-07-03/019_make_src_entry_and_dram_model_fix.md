# 019 Makefile src 入口与 DRAM_0 行为模型修复

日期：2026-07-03

## 目标

按项目约定把仿真用户入口固定为 `make`，并确认 `srcSmoke` 在 src/student_top DUT 下能通过。

要求：

1. 日常不直接指导用户运行 `scripts/run_verilator.py`。
2. src 类测试能通过 make 设置仿真上限。
3. src 默认上限足够大，避免 `srcSmoke` 被短上限截断。
4. 确认此前 `srcSmoke` 在 student_top 下 TIMEOUT 是否由 TB/IP 行为模型问题导致。

## Makefile 更新

新增/维护的入口：

```sh
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=srcSmoke
make sim-src-all
make verilator-build
make verilator-build-src
```

常用变量：

```text
MAX_CYCLES      # 覆盖本次最大周期
SRC_MAX_CYCLES  # src 默认最大周期，默认 100000000
TRACE           # 非空则生成 FST
BUILD           # 非空则强制重编
NO_BUILD        # 非空则跳过重编
BUILD_JOBS      # Verilator build 并行度
BUILD_CXX       # Verilator C++ 编译器
SRC_SEG_GRACE   # ledseg checker 宽限周期
```

因此：

```sh
make sim-src TEST=srcSmoke
```

默认等价于给 src 使用 `100000000` 周期上限。

## timeout 根因

切到 `student_top` 后，`srcSmoke` 曾经 1M 周期内只有 DRAM 访问，没有 SEG/LED/CNT 写。

对比同一数据的 `myCPU` harness：

```text
cycle 2496 write SEG 0x37000000
cycle 2569 write counter start 0x80000000
```

而 student_top 早期波形显示程序反复读到旧值，长时间只写 DRAM。进一步对比发现 `rtl/ip/DRAM_0.sv` 行为模型有两个问题：

1. write 周期也推进了读地址/valid 管线，会让 store 地址污染后续 load 返回。
2. 读数据相对 `perip_bridge.dram_read_sel_d2` 和 core `loadMetaPipe1` 晚一拍，导致 core 取到旧 load 数据。

## 修复

`DRAM_0` 现在按如下规则建模：

```text
read_en = ena && (wea == 0)

read 周期:
  rd_addr_q <= addra
  下一拍 douta <= mem[rd_addr_q]

write 周期:
  只按 byte enable 更新 mem[addra]
  不推进读返回管线
```

该模型与当前 `perip_bridge` 的 `dram_read_sel_d2`、`dram_driver.offset_d2` 和 core `ExecuteMemStage.loadMetaPipe1` 对齐。

## 验证结果

短 smoke：

```sh
make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1
```

结果：

```text
srcSmoke: TIMEOUT
cycle 2496 write addr=0x80200020 data=0x37000000
cycle 2569 write addr=0x80200050 data=0x80000000
```

该结果说明早期 SEG/counter 行为已恢复。

完整 smoke：

```sh
make sim-src TEST=srcSmoke NO_BUILD=1
```

结果：

```text
srcSmoke: PASS
cycles: 72813551
reason: LED pass signature observed
counter_stop_cycle: 72813238
counter_ms: 1456
first_seg_write: 0x37000000
last_seg_write: 0x00000000
last_led: 0x01221c08
dram_read_count: 592918
dram_write_count: 200123
```

## 当前结论

此前 `srcSmoke` 在 student_top 下 timeout 的直接原因是 TB/IP 行为模型问题，不是 src checker 本身，也不是 core 必然跑不到结果。

当前推荐入口：

```sh
make sim-src TEST=srcSmoke
```

默认不生成波形；只有设置 `TRACE=1` 才生成 FST。

## 修改文件

```text
Makefile
rtl/ip/DRAM_0.sv
docs/sim/verilator_plan.md
docs/design/memory_and_test_contract.md
docs/archive/2026-07-03/018_src_student_top_harness.md
docs/archive/2026-07-03/019_make_src_entry_and_dram_model_fix.md
docs/README.md
```
