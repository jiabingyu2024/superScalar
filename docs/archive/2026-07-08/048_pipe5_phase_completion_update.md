# 042 计划执行状态更新

日期：2026-07-08

## 1. 本轮补齐内容

本轮在已有功能基线、顺序预取、小 BTB 之上，继续按 `042_pipe5_rtl_modification_plan.md` 补齐 RTL 功能边界：

1. RV32M 不再使用 `riscv_cpu.sv` 内的组合 `* / % / /` 主路径，改为 `MulDivUnit` 封装 `MUL_0/DIV_0`。
2. 新增真实 `DCache` 模块并接入 CPU 数据侧 ready/valid 总线。
3. 新增 `StoreWriteBuffer` FIFO 模块，但默认 D-cache 功能路径暂不启用后台 write buffer。
4. `myCPU/student_top/Verilator TB` 增加性能计数：
   - load/store
   - dcache access/miss/hit rate
   - stall_front/stall_mem/stall_muldiv/stall_load_use
5. JSON 结果新增 `perf.dcache` 小节，可直接统计 cache hit rate。

## 2. 当前 D-cache 策略

当前默认 D-cache 是保守 direct-mapped load cache：

```text
capacity: 2 KiB
line:     16 B / 4 words
mapping:  direct-mapped
load hit: 一拍返回给 CPU
load miss: 4-word fill
store:    write-through，直接写 SoC/BRAM，并 invalidate 对应 index
MMIO:     uncached
```

当前没有默认启用后台 write buffer。原因是第一版 write buffer + no-write-allocate line fill 暴露出 store/load/cache-line 一致性风险；为保证正确性和 Vivado 收敛，本轮先采用 store 直写 + invalidate。`StoreWriteBuffer.sv` 已实现，可作为后续优化候选，但不应在没有专项回归前默认接入。

## 3. 当前完成度对照 042

| 042 项目 | 当前状态 | 备注 |
| --- | --- | --- |
| `rtl/core` 重建 | 已完成可运行版本 | 行为仍集中在 `riscv_cpu.sv`，拆分模块逐步实化 |
| 单端口 IROM | 已完成 | `IROM_0` 和 Vivado Tcl 对齐 |
| DRAM 一拍 ready/valid adapter | 已完成 | `DramBramAdapter + SocMemBridge` |
| `MUL_0/DIV_0` 封装 | 已完成 | M 指令多周期等待，避免组合除法主路径 |
| D-cache | 已完成保守版 | load cache + store write-through invalidate |
| Store write buffer | 模块已完成，默认未接入 | 接入前需解决 line fill 一致性和 forwarding 策略 |
| perf 计数 | 已补齐主要项 | JSON 可见 cache hit rate |
| src 性能窗口 | 已重新统计 | 见下表 |

## 4. 回归结果

已通过：

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
make sim-rv32 SUITE=rv32ui NO_BUILD=1 MAX_CYCLES=1000000
make sim-rv32 SUITE=rv32um NO_BUILD=1 MAX_CYCLES=3000000
make sim-rv32 SUITE=rv32mi NO_BUILD=1 MAX_CYCLES=2000000
make sim-src TEST=srcSmoke NO_BUILD=1 MAX_CYCLES=100000000 CPU_FREQ_MHZ=50
```

结果：

| 测试 | 结果 |
| --- | --- |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |
| `srcSmoke` | PASS |

## 5. src 窗口性能与 cache hit rate

`srcSmoke` 完整 PASS：

| 测试 | cycles | commit | IPC | branch miss rate | D-cache hit rate | D-cache access | D-cache miss |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `srcSmoke` | 35,415,550 | 30,758,594 | 0.868505 | 19.8832% | 55.5433% | 900,304 | 400,245 |

100M cycle 窗口：

| 测试 | status | commit | IPC | branch miss rate | D-cache hit rate | D-cache access | D-cache miss |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `src0` | TIMEOUT | 68,912,852 | 0.689129 | 39.8716% | 64.0060% | 11,517,933 | 4,145,770 |
| `src1` | TIMEOUT | 70,694,936 | 0.706949 | 25.8220% | 45.2599% | 10,904,013 | 5,968,867 |
| `src2` | TIMEOUT | 74,165,156 | 0.741652 | 27.4165% | 44.7268% | 7,865,253 | 4,347,380 |
| `srcWithMext` | TIMEOUT | 50,841,845 | 0.508418 | 2.44114% | 61.6900% | 18,080,647 | 6,926,692 |

`srcWithMext` 100M 窗口进度：

```text
rv32i_count = 33
mext_count  = 8
LED         = 0x00020000
SEG         = 0x33800000
```

## 6. 性能判断

当前版本相比前一版 BTB-only 基线：

1. `srcSmoke` 仍能 PASS，但从约 34.01M cycles 变为 35.42M cycles。
2. IPC 下降来自：
   - RV32M 改多周期 IP；
   - D-cache miss 需要 4-word fill；
   - store 直写并 invalidate，降低部分数据局部性。
3. 这属于用 cycle 换 Vivado Fmax 的取舍：组合乘除法主路径已经移除，更适合上板综合。

当前最应该看 Vivado timing：

| 如果 critical path 在 | 下一步 |
| --- | --- |
| `DCache` tag/data/return mux | 降低 line count 或把 hit path 打一拍 |
| `MulDivUnit` 外围 | 检查 IP 约束和 result mux |
| `riscv_cpu` execute case | 拆 decode/execute 或 execute/writeback |
| BTB lookup | 降 entry 或打一拍预测 |

## 7. 不建议立即做的事

1. 不建议立刻重新接入 write buffer 默认路径；先综合当前版本。
2. 不建议继续为了 IPC 压缩阶段；当前应先看 Fmax。
3. 不建议把 D-cache 做成 2-way 或 write-back；验证和时序风险都高。

## 8. 当前交付结论

当前工程已经不是只完成 baseline：MUL/DIV IP 化、D-cache 计数、保守 load-cache、SoC ready/valid、单端口 IROM/DRAM、perf JSON 都已接入并通过基础回归。剩余优化应以 Vivado timing 和目标程序 `program_time = cycles / Fmax` 为准，而不是继续盲目加复杂结构。
