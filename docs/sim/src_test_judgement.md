# SRC 类测试程序入口与 PASS/FAIL 判定说明

本文说明 `data/src*` 这类测试在当前仓库里如何进入、如何运行到结束、Verilator 如何判断通过或失败。重点是避免把不同 profile 的结束协议混在一起，导致误判。

关联文件：

| 文件 | 作用 |
| --- | --- |
| `docs/sim/test.md` | 板级 LED/数码管显示规则原始说明 |
| `scripts/run_verilator.py` | `make sim-src` 的 Python 入口，选择测试、注入 profile 参数 |
| `tb/verilator/src_profiles.json` | 每个 `src*` 测试使用哪种 checker、PASS/FAIL magic、期望计数 |
| `tb/verilator/main_student_top.cpp` | `student_top` Verilator 主循环，负责 reset、采样外设写、调用 checker |
| `tb/verilator/checker_src.cpp` | SRC 类测试 PASS/FAIL 的实际判定逻辑 |
| `tb/verilator/sim_result.cpp` | 结果 JSON 和终端状态输出 |
| `rtl/soc/student_top.sv` | SRC 模式的 DUT 顶层，暴露 Verilator debug 外设请求 |
| `rtl/ip/IROM_0.sv`, `rtl/ip/DRAM_0.sv` | SRC 程序和数据镜像通过 plusargs 加载 |
| `data/src*/irom.hex`, `data/src*/dram.hex`, `data/src*/*.dump` | 测试镜像与反汇编入口/收尾路径 |

## 1. 一句话结论

SRC 类测试不是通过 `tohost` 判断，而是测试程序运行到最后后写 LED、SEG、counter、结果区等 memory-mapped 地址。当前 Verilator 对 `src0/src1/src2/srcSmoke/srcWithMext/srcWithoutMext` 使用不同 checker：旧测试看固定 LED 图案和/或 SEG 计时，新测试看最终灯阵 marker、子测试灯 mask、RV32I/M-Z 计数。判断是否通过时必须先看 `src_profiles.json` 里该测试绑定的 checker。

## 2. 命令入口：从 make 到 DUT

常用命令：

```sh
make sim-src TEST=srcSmoke
make sim-src TEST=srcWithMext MAX_CYCLES=1200000000 CPU_FREQ_MHZ=50
make sim-src-all
```

入口链路：

```text
Makefile
  -> scripts/run_verilator.py src --test <name>
    -> data/<name>/irom.hex + data/<name>/dram.hex
    -> tb/verilator/src_profiles.json 选择 checker 和阈值
    -> build/verilator/student_top/sim_student_top
      +irom_hex=<...> +dram_hex=<...>
      --mode=src --test-name=<name> --src-checker=<...> ...
```

关键点：

1. `src_tests()` 只收集 `data/src*` 目录中同时存在 `irom.hex` 和 `dram.hex` 的测试。
2. `src_profiles.json` 是判定规则的配置源，不同测试不可套用同一 PASS 条件。
3. `+irom_hex`、`+dram_hex` 是给 RTL `IROM_0/DRAM_0` 的 plusargs；`--irom-hex`、`--dram-hex` 是 C++ harness 记录/配置用参数。
4. `student_top` harness 只支持 `--mode=src`。如果误拿 rv32 的 `tohost` 逻辑判断 SRC，会误判。

## 3. SRC 程序的硬件视角

当前 SRC 模式跑的是完整 `student_top`：

```text
test irom.hex/dram.hex
  -> RTL IROM_0/DRAM_0 $readmemh
  -> student_top
  -> myCPU
  -> SocMemBridge
  -> DRAM / SW / KEY / SEG / LED / counter
  -> dbg_perip_* 被 C++ testbench 采样
  -> checker_src.cpp 判定 PASS/FAIL
```

地址约定：

| 地址 | 名称 | 测试程序用途 | checker 用途 |
| --- | --- | --- | --- |
| `0x8000_0000` | IROM 取指基址 | 程序入口从这里开始 | 不直接判定 |
| `0x8010_0000` | DRAM/result base | 子测试通过计数，常见为 RV32I count | `lampseg` 读取 SEG 派生计数；`observe/memcnt` 可观测写 |
| `0x8010_0004` | fail/result 区 | 部分 profile 记录失败数 | `memcnt` 可直接判 FAIL |
| `0x8010_0030` | M/Z 计数 | `srcWithMext` 的 M/Z 类通过计数 | `lampseg` 期望为 8，仅 `srcWithMext` 配置 |
| `0x8010_0038` | test lamp 累积区 | 新版程序累积右侧 8 个测试灯 bit | 最终 LED 与 `test_lamp_mask` 相关 |
| `0x8020_0020` | SEG | 高位显示通过条数，低 6 位显示计时 ms | `ledseg`/`lampseg` 解读 |
| `0x8020_0040` | LED | 写 PASS/FAIL 图案或新版灯阵 marker | 所有 SRC checker 的主要结束观测点 |
| `0x8020_0050` | counter | 写 `0x80000000` start，写 `0xffffffff` stop，读 ms | `ledseg` 校验 SEG 低 6 位 |

注意：C++ `MemoryModel` 在 `student_top` src 模式下不是喂指令/数据的主存模型；实际 IROM/DRAM 在 RTL 内部。C++ mirror 主要镜像外设写入后的 `led/seg_wdata/counter_ms`，用于 checker 和 JSON 诊断。

## 4. 仿真主循环与采样时序

`main_student_top.cpp` 的关键流程：

```text
初始化 top 输入：w_cpu_clk=0, w_clk_50Mhz=0, reset=1
打开 trace，创建 checker
跑 8 个 CPU posedge，reset 仍为 1
拉低 reset

for cycle in 1..max_cycles:
  advance_to_next_cpu_posedge()
    在 CPU 上升沿前采样 dbg_perip_* 为 Request
    推进 w_cpu_clk / w_clk_50Mhz
    eval/dump

  checker->pre_tick(cycle, req, mirror, result)
  mirror.tick_request(req, ...)
  checker->post_tick(cycle, req, mirror, result)

  如果 checker.done():
    写 result json
    终端打印 PASS/FAIL
```

这个顺序有两个实际含义：

1. `pre_tick()` 看到的是 DUT 本周期发出的外设请求，适合第一时间捕捉 LED 写入并立即判定 FAIL/PASS marker。
2. `post_tick()` 看到的是 C++ mirror 已经应用本周期请求后的状态，适合用最新 SEG/counter 状态做组合判断。

如果 debug 外设请求没有准确反映提交后的 store，checker 会误判。对乱序核尤其要注意：MMIO store 必须按程序序提交，不能被投机、合并、缓存或越过更老异常。

## 5. 测试程序入口：dump 里怎么看

SRC 程序没有 ELF 符号名，`.dump` 是从 `irom.coe` 反汇编出来的裸二进制。看入口时用第一条 `0x8000_0000` 附近的启动代码。

旧版 `src0/src1/src2` 入口示例：

```text
data/src0/src0.dump

80000000: auipc sp, ...
80000004: addi  sp, sp, ...
80000008: jal   ra, 0x80001174   ; 初始化/搬运/准备
8000000c: jal   ra, 0x80000fb0   ; 测试主体或收尾主函数
80000010: jal   zero, 0x80000010 ; 结束后原地死循环
```

`srcSmoke` 入口类似：

```text
data/srcSmoke/src_test.dump

80000000: auipc sp, ...
80000004: addi  sp, sp, ...
80000008: jal   ra, 0x800005a8
8000000c: jal   ra, 0x80000540
80000010: jal   zero, 0x80000010
```

新版 `srcWithMext` 入口：

```text
data/srcWithMext/srcWithMext.dump

80000000: auipc sp, ...
80000004: addi  sp, sp, ...
80000008: jal   ra, 0x80000f78
8000000c: jal   ra, 0x80001cf8
80000010: jal   ra, 0x800000e4
80000014: jal   zero, 0x80000014
```

结论：程序结束不是退出仿真，而是写出 LED/SEG 后进入死循环。Verilator 要在死循环前后的外设写中捕捉最终状态。

## 6. 旧版 SRC 收尾协议：`src0/src1/src2`

`src0/src1/src2` 当前 profile：

```json
{
  "checker": "ledseg",
  "led_pass": "0x01221c08",
  "led_fail": "0x24181824"
}
```

典型收尾函数可以在 `data/src0/src0.dump` 看到：

```text
; 读 0x80100000 的通过条数，转 BCD，写到 SEG 高位
80000114: lui   x15,0x80100
80000118: lw    x15,0(x15)        # 0x80100000
...
8000012c: addi  x15,x15,32        # 0x80200020
80000134: slli  x14,x14,0x18
80000138: sw    x14,0(x15)        ; SEG[31:24] = count BCD

; 读 SEG，OR 上低 6 位计时 BCD，再写回 SEG
80000184: addi  x15,x15,32        # 0x80200020
80000188: lw    x13,0(x15)        ; read current SEG
...
80000198: or    x14,x13,x14
8000019c: sw    x14,0(x15)        ; SEG = 0x37 + ms

; 写 LED
800001cc: addi  x15,x15,64        # 0x80200040
800001d4: sw    x14,0(x15)
```

`ledseg` checker 的硬判定：

1. 只要写 LED `0x24181824`，立即 FAIL。
2. 观察到写 LED `0x01221c08` 后，记录 `led_pass_cycle`，但还不立刻 PASS。
3. LED PASS 之后，要求 SEG 满足：
   - `seg_wdata[31:24] == 0x37`，也就是 RV32I 通过条数显示为 37；
   - `seg_wdata[23:0]` 是 6 位 BCD；
   - 该 6 位 BCD 等于 C++ mirror 的 `counter_ms % 1000000`。
4. 还要求虚拟数码管扫描能在 `0xaa/0x55` 两个相位重构出同一个 `seg_wdata`。
5. LED PASS 后超过 `--src-seg-grace`，默认 512 周期，仍未满足 SEG 条件，则 FAIL。

不要误判：

- `src0/src1/src2` 不能只看到 LED PASS 就算 PASS；它们当前使用 `ledseg`，必须连 SEG/counter 也匹配。
- 如果 LED PASS 前 SEG 已经写好并保持，LED PASS 后第一个 `post_tick()` 就可能通过。
- 如果 CPU 最终写了 LED PASS，但 SEG 被清零、读旧值、读相位错，`ledseg` 会 FAIL。

## 7. `srcSmoke` 特例：LED-only

`srcSmoke` 当前 profile：

```json
{
  "checker": "ledonly",
  "led_pass": "0x01221c08",
  "led_fail": "0x24181824"
}
```

`ledonly` checker 的硬判定：

1. 写 LED `0x24181824`：立即 FAIL。
2. 写 LED `0x01221c08`：立即 PASS。
3. SEG/counter 仍写入 JSON 作为诊断信息，但不参与 PASS/FAIL。

为什么它是特例：历史 bring-up 里确认 `srcSmoke` 的程序版本会在 PASS 前后出现 SEG 不保持最终 `0x37xxxxxx` 的情况。如果把它套到 `ledseg`，会把“程序已经写 LED PASS”误判成“SEG 未匹配失败”。所以当前仓库把 `srcSmoke` 切成 `ledonly`，只证明它跑到了旧版 PASS 签名。

不要误判：

- `srcSmoke PASS` 不等价于“SEG/counter 最终显示协议也正确”。
- `result.correctness.seg.*matches_counter_ms=false` 对 `srcSmoke` 通常只是诊断信息，不是该 profile 的失败原因。

## 8. 新版灯阵协议：`srcWithMext/srcWithoutMext`

`srcWithMext/srcWithoutMext` 当前 profile 都使用 `lampseg`：

```json
{
  "checker": "lampseg",
  "pass_counter_addr": "0x80100000",
  "fail_counter_addr": "0x80100004",
  "test_lamp_mask": "0x03030303",
  "pass_marker": "0x04887020",
  "fail_marker": "0x90606090",
  "expected_rv32i_count": 37
}
```

`srcWithMext` 额外有：

```json
{
  "expected_mext_count": 8
}
```

这对应 `docs/sim/test.md` 里的新版板级显示规则：

| 含义 | 值 |
| --- | --- |
| 8 个右侧测试灯总 mask | `0x03030303` |
| 最终 PASS/对号 marker | `0x04887020` |
| 最终 FAIL/错号 marker | `0x90606090` |
| RV32I 满分条数 | 37 |
| `srcWithMext` 的 M/Z 类条数 | 8 |

新版程序的几个关键收尾函数可以从 `data/srcWithMext/srcWithMext.dump` 反推：

```text
; 写 SEG 高位：RV32I count -> [31:24]，M/Z count -> [23:20]
80000708: lui   a5,0x80100
8000070c: lw    a5,0(a5)          # 0x80100000
...
80000728: lw    a5,48(a5)         # 0x80100030
...
80000754: addi  a5,a5,32          # 0x80200020
80000758: or    a4,a3,a4
8000075c: sw    a4,0(a5)

; 更新 SEG 低 6 位计时
800007a8: addi  a5,a5,32          # 0x80200020
800007ac: lw    a3,0(a5)
...
800007bc: or    a4,a3,a4
800007c0: sw    a4,0(a5)

; 累积单个测试灯到 0x80100038，并写 LED 显示阶段进度
80000824: lui   a5,0x80100
80000828: lw    a4,56(a5)         # 0x80100038
80000830: or    a4,a4,a5
80000838: sw    a4,56(a5)         # 0x80100038
80000848: jal   ra,0x800007d8     ; write LED

; PASS: 0x04887020 | test_lamps -> LED
80000870: lui   a5,0x4887
80000874: addi  a4,a5,32          # 0x04887020
8000087c: lw    a5,56(a5)         # 0x80100038
80000880: or    a5,a4,a5
8000088c: jal   ra,0x800007d8     ; write LED

; FAIL: 0x90606090 | test_lamps -> LED
800008b4: lui   a5,0x90606
800008b8: addi  a4,a5,144         # 0x90606090
800008c0: lw    a5,56(a5)         # 0x80100038
800008c4: or    a5,a4,a5
800008d0: jal   ra,0x800007d8     ; write LED
```

counter 函数也能直接看到：

```text
; start counter
800008fc: addi  a5,a5,80          # 0x80200050
80000904: sw    0x80000000,0(a5)

; stop counter
80000930: addi  a5,a5,80          # 0x80200050
80000938: sw    -1,0(a5)          ; 0xffffffff

; read counter
80000964: addi  a5,a5,80          # 0x80200050
80000968: lw    a5,0(a5)
```

`lampseg` checker 的硬判定：

1. 每次写 LED 时，先记录 `last_src_test_lamps = led_value & 0x03030303`。
2. 如果 `(led_value & 0x90606090) == 0x90606090`，立即 FAIL，reason 为 `SRC final fail lamp marker observed`。
3. 如果 `(led_value & 0x04887020) == 0x04887020`，进入 PASS marker 路径，但还要继续检查：
   - `last_src_test_lamps == 0x03030303`，否则 FAIL；
   - 如果配置了 `expected_rv32i_count`，则 `last_rv32i_count == 37`，否则 FAIL；
   - 如果配置了 `expected_mext_count`，则 `last_mext_count == 8`，否则 FAIL；
   - 全部满足才 PASS。
4. `last_rv32i_count` 来自 `seg_wdata[31:24]` 的两位 BCD 译码。
5. `last_mext_count` 来自 `seg_wdata[23:20]` 的一位 BCD 译码。

不要误判：

- 新版 LED 最终值通常不是纯 `0x04887020` 或纯 `0x90606090`，而是 marker OR 上右侧测试灯。例如 fail 时可能是 `0x93636392`，仍然满足 fail marker 位匹配。
- 当前实现的 marker 判断是 `(value & marker) == marker`。这能容忍测试灯混入，但也意味着其他额外 bit 只要包含 marker，就会被接受。更严格的理想判断应是 `(value & ~test_lamp_mask) == marker`；当前文档按现有代码说明，不代表这是最严谨写法。
- `srcWithoutMext` 没有配置 `expected_mext_count`，所以 checker 不会因为 M/Z 数码管位不是 8 而失败；`srcWithMext` 会。

## 9. 当前 profile 速查表

| 测试 | checker | PASS 条件 | FAIL 条件 | 易误判点 |
| --- | --- | --- | --- | --- |
| `src0` | `ledseg` | LED=`0x01221c08` 后 SEG=`0x37 + counter_ms BCD` 且虚拟扫描重构成功 | LED=`0x24181824` 或 PASS 后 512 周期内 SEG 不匹配 | 不能只看 LED PASS |
| `src1` | `ledseg` | 同 `src0` | 同 `src0` | 同 `src0` |
| `src2` | `ledseg` | 同 `src0` | 同 `src0` | 同 `src0` |
| `srcSmoke` | `ledonly` | LED=`0x01221c08` | LED=`0x24181824` | SEG 字段仅诊断，不参与 PASS |
| `srcWithMext` | `lampseg` | PASS marker + `test_lamp_mask` 全亮 + RV32I=37 + M/Z=8 | FAIL marker，或 PASS marker 但灯/计数不满足 | 终态 LED 是 marker OR test lamps |
| `srcWithoutMext` | `lampseg` | PASS marker + `test_lamp_mask` 全亮 + RV32I=37 | FAIL marker，或 PASS marker 但灯/RV32I 不满足 | 不检查 M/Z=8 |

## 10. 结果 JSON 怎么读

结果文件在：

```text
build/result/src/<test>.json
build/result/src/summary.json
```

顶层字段：

| 字段 | 含义 |
| --- | --- |
| `status` | 最终状态：`PASS`、`FAIL`、`TIMEOUT`、`INTERRUPTED`、`CRASH` 等 |
| `reason` | checker 或主循环给出的结束原因 |
| `cycles` | 结束周期 |
| `checker` | 实际使用的 checker，先看这个再解释 correctness |

`correctness.led`：

| 字段 | 含义 |
| --- | --- |
| `pass_seen` | 仅旧 LED checker 使用，表示是否看过旧 PASS LED |
| `last_value` | 最后一次 LED 写值。新版灯阵要按 marker/mask 解读，不要按全字相等 |

`correctness.seg`：

| 字段 | 含义 |
| --- | --- |
| `current_value` | C++ mirror 当前 SEG word |
| `pass_display_value` | 最后一次非零 SEG，防止程序最终清零后丢失诊断 |
| `expected_counter_value` | `0x37000000 | counter_ms 的 6 位 BCD` |
| `*_matches_counter_ms` | SEG 是否匹配旧版 `0x37 + ms` 协议 |

注意：`*_matches_counter_ms=false` 只有对 `ledseg` 是硬失败依据；对 `ledonly/lampseg` 多数时候只是诊断。

`correctness.src_lamps`：

| 字段 | 含义 |
| --- | --- |
| `pass_marker_seen` | 是否看过新版 PASS marker |
| `fail_marker_seen` | 是否看过新版 FAIL marker |
| `test_lamps` | `last_led & test_lamp_mask` |
| `rv32i_count` | 从 SEG `[31:24]` BCD 解出的 RV32I count |
| `mext_count` | 从 SEG `[23:20]` BCD 解出的 M/Z count |

`perf` 字段主要是性能诊断，不决定正确性。比如 IPC、branch miss、dcache miss、stall bucket 都不是 PASS/FAIL 的直接条件。

## 11. 典型判定路径示例

### 示例 A：`srcSmoke` 正常 PASS

```text
程序启动 -> 初始化栈/数据 -> 跑测试主体
  -> 写 SEG/counter 进度，可能最终不保持严格 0x37xxxxxx
  -> 写 LED 0x01221c08
  -> checker=ledonly 立即 PASS
  -> 写 result json，退出仿真
```

判断要点：只要看到 `checker=src_ledonly` 且 reason 是 `LED pass signature observed`，就是当前 profile 的正确 PASS。不要因为 SEG mismatch 字段为 false 推翻它。

### 示例 B：`src0` LED PASS 但 SEG 错

```text
程序启动 -> 跑测试主体
  -> 写 LED 0x01221c08
  -> checker=ledseg 开始 512 周期宽限
  -> SEG 不是 0x37 + counter_ms BCD，或数码管扫描重构失败
  -> FAIL: SEG did not match within grace window
```

判断要点：这不是“已通过但显示有问题”，对 `ledseg` profile 来说这就是正确性 FAIL。

### 示例 C：`srcWithMext` 最终 FAIL marker

已有结果中出现过类似：

```text
last LED = 0x93636392
fail_marker = 0x90606090
(0x93636392 & 0x90606090) == 0x90606090
=> FAIL: SRC final fail lamp marker observed
```

同时 JSON 可能显示：

```text
test_lamps = 0x03030302
rv32i_count = 33
mext_count = 8
```

判断要点：这说明程序写出了新版 FAIL 图案，并且右侧测试灯没有全亮、RV32I 条数也没到 37。不能因为 LED 不是精确等于 `0x90606090` 就说 checker 误判。

### 示例 D：`srcWithMext` PASS marker 但计数不够

```text
写 LED 包含 0x04887020
  -> checker 进入 PASS marker 路径
  -> test_lamps != 0x03030303 或 rv32i_count != 37 或 mext_count != 8
  -> FAIL
```

判断要点：新版 PASS marker 只是“进入最终对号路径”，不是无条件 PASS。灯阵和数码管计数仍是硬门槛。

## 12. 常见误判清单

1. 只看 `last_led` 全字相等。新版灯阵要看 marker 位和 test lamp mask。
2. 把 `srcSmoke` 的 `ledonly` 结果当作 `ledseg` 结果解释。`srcSmoke` 的 SEG mismatch 不一定是失败。
3. 把 `src0/src1/src2` 的 LED PASS 当作最终 PASS。它们还要等 SEG/counter 匹配。
4. 忽略 `checker` 字段。同一个 JSON 结构服务多个 checker，不同字段的硬/软含义不同。
5. 用 rv32 的 `tohost` 规则判断 SRC。SRC 程序没有依赖 `tohost` 退出。
6. 把 `TIMEOUT` 当作 FAIL signature。TIMEOUT 只说明最大周期内 checker 没等到结束条件，原因可能是性能太慢、跑飞、MMIO 不提交、max_cycles 太小。
7. 忽略 `counter` 读写相位。旧版 `ledseg` 要求 SEG 低六位等于 mirror counter ms，MMIO/counter load latency 错会导致显示值错。
8. 让 MMIO store 走 D-cache 或 store buffer 合并。LED/SEG/counter 必须按程序序、非投机、可观测地提交。
9. 忽略 byte mask 对结果区的影响。当前 `lampseg` 的 pass/fail counter 观测保存的是写请求数据，不是最终合并后的 memory word；如果将来启用 `memcnt`，需确认 masked store。
10. 用 `perf.ipc` 判断正确性。性能字段只能说明快慢或瓶颈，不能替代 checker。

## 13. 调试建议：从失败原因反推

| reason | 首先检查 |
| --- | --- |
| `LED wrote fail signature` | 旧版程序主动写了失败图案，查测试主体/异常/结果区 |
| `SEG did not match within grace window` | 查 SEG 写值、counter stop/read、MMIO 读返回延迟、SEG 是否被清零 |
| `SRC final fail lamp marker observed` | 查 `src_lamps.test_lamps`、`rv32i_count`、`mext_count`，定位是哪组没过 |
| `SRC pass marker observed but not all test lamps are set` | PASS marker 写出过早，或某个子测试灯未置位 |
| `SRC pass marker observed but RV32I count is not expected` | RV32I 子测试计数没到 37，优先查 RV32I 指令/分支/load-store |
| `SRC pass marker observed but M/Z test count is not expected` | `srcWithMext` 的 M/Z 计数没到 8，优先查 M 扩展或抽选 Z 扩展 |
| `max cycles reached` | 看早期 SEG/LED/counter 是否有进度；若有进度可能只是慢，若完全没有 MMIO 多半跑飞或启动失败 |

## 14. 修改 checker 或新增测试时的规则

1. 新增 `data/srcX` 后，必须在 `tb/verilator/src_profiles.json` 明确 checker。没有 profile 会默认 `observe`，它不会自动 PASS。
2. 旧版固定图案程序用 `ledonly` 或 `ledseg`，取决于是否能保证最终 SEG 保持 `0x37 + ms`。
3. 新版灯阵程序用 `lampseg`，并配置 `test_lamp_mask/pass_marker/fail_marker/expected_rv32i_count`。
4. 如果程序的 M/Z 计数有硬要求，才配置 `expected_mext_count`。
5. 如果要把 marker 判断改严格，建议从当前：

```cpp
(value & marker) == marker
```

改成：

```cpp
(value & ~test_lamp_mask) == marker
```

同时保留 `test_lamps == test_lamp_mask` 的检查。这样能避免额外非灯位 bit 混入后被误接受。

6. 如果以后 checker 要读取 DRAM 结果区最终值，优先从 memory model 最终 word 读，不要只保存 `req.perip_wdata`，否则 masked store 会误导。

## 15. 最小手工复核流程

当一个 SRC 测试结果可疑时，按下面顺序复核：

```text
1. 打开 build/result/src/<test>.json
2. 看 checker 字段，确认适用规则
3. 看 status/reason，不先看 perf
4. 如果 checker=src_ledonly：
     只用 LED pass/fail signature 判断正确性
5. 如果 checker=src_ledseg：
     检查 LED pass 是否出现
     检查 SEG 是否等于 0x37 + counter_ms BCD
     检查是否超过 src_seg_grace
6. 如果 checker=src_lampseg：
     检查 fail_marker_seen
     检查 pass_marker_seen
     检查 test_lamps == 0x03030303
     检查 rv32i_count == 37
     对 srcWithMext 再检查 mext_count == 8
7. 再看 perf 字段定位慢在哪里
8. 如仍不确定，打开 build/log/src/<test>.log 看关键 MMIO write 序列
```

这套流程优先使用 checker 的硬判定，避免被 JSON 中“对其他 profile 只是诊断”的字段干扰。
