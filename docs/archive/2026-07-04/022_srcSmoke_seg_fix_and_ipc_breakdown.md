# srcSmoke SEG 修复与 IPC 分支分类定位

## 背景

本次处理两个问题：

1. `srcSmoke` 最终 SEG 没有保持 `0x37xxxxxx`，之前观测为最后写 `SEG=0`。
2. `srcSmoke` IPC 约 0.42，对二路乱序核来说明显偏低，需要判断是否为 TB 统计问题，若是微架构问题则定位瓶颈。

## SEG 根因

根因在 SoC 读返回相位，不是 TB JSON 截断，也不是 `counter.sv` 本身。

core 的 `ExecuteMemStage` 对 load 的约定是：

```text
T0: 发起 read，load metadata 进入 loadMetaPipe0
T1: load metadata 推进
T2: loadMetaPipe1 使用 perip_rdata
```

DRAM 路径此前已经按两拍对齐：

```text
dram_read_sel -> dram_read_sel_d1 -> dram_read_sel_d2
```

但 `perip_bridge` 对 SEG/SW/KEY/counter 读只打一拍：

```text
mmio_sel_q / cnt_sel_q
```

因此 `srcSmoke` 收尾阶段执行：

```text
stop counter -> read counter -> read SEG -> write SEG
```

时，core 在第二拍实际看到的 `perip_rdata` 已经回到默认 0。结果是：

- counter read 得到 0，而不是 1456。
- SEG read 得到 0，而不是早期写入的 `0x37000000`。
- 最终 OR 后写出 `SEG=0`。

## 修复

修改 `rtl/soc/perip_bridge.sv`：

- 将 `mmio_sel_q/cnt_sel_q/perip_addr_q` 改为两级流水。
- 使用 `mmio_sel_d2/cnt_sel_d2/perip_addr_d2` 选择 `perip_rdata`。
- 保持 `counter.sv` 不修改。

同步修改 `tb/verilator/sim_memory.cpp/.h`：

- rv32/myCPU memory model 的 MMIO/counter 读也按两拍返回。
- 避免 rv32 平台和 student_top 平台在读返回相位上再次分叉。

## 修复后结果

运行：

```text
make sim-src TEST=srcSmoke NO_BUILD=1
```

结果：

```text
status       = PASS
cycles       = 72814875
counter_ms   = 1456
final SEG    = 0x37001456
last LED     = 0x01221c08
```

JSON 关键字段：

```text
expected_counter_value                 = 0x37001456
current_matches_counter_ms             = true
pass_display_matches_counter_ms        = true
value_at_last_led_matches_counter_ms   = true
```

日志末尾：

```text
cycle 72813238 write CNT = 0xffffffff
cycle 72814748 write SEG = 0x37001456
cycle 72814875 write LED = 0x01221c08
```

## IPC 统计口径

IPC 不是 TB wall-clock 统计，而是：

```text
ipc = core PerfIF.commitCnt / cycles
```

本次增加了分支类型分类 perf 计数：

```text
conditional branch count/miss
JAL count/miss
JALR count/miss
```

这些计数从 Dispatch 保存的 `brcSubType` 进入 ROB，在 Commit 退休分支时分类累加，并通过 `VERILATOR_TB` debug 口输出。

## IPC 实测分类

`srcSmoke` 结果：

```text
cycles             = 72814875
commit_count       = 30758700
ipc                = 0.422423
branch_count       = 12855156
branch_miss_count  = 3317770
branch_miss_rate   = 0.258089
```

分类：

| 类型 | count | miss_count | miss_rate |
| --- | --- | --- | --- |
| conditional | 12055013 | 3117626 | 0.258617 |
| JAL | 400076 | 80 | 0.000199962 |
| JALR | 400067 | 200064 | 0.500076 |

结论：

1. `JAL` 基本不是问题。
2. `JALR` miss 率约 50%，说明当前无 RAS、普通 BTB 预测 return 的策略很弱。
3. 最大 miss 来源是条件分支，约 311 万次，占总 miss 的主要部分。

## 低 IPC 定位

`srcSmoke` 的性能循环不是纯算术顺序代码。dump 显示内层循环调用软件除法/取模 helper：

```text
0x800004dc -> 0x800013ac
0x800004f4 -> 0x80001328
```

这些 helper 最终进入 `0x80001330` 的移位减法循环，内部有多条数据相关条件分支：

```text
beq/bgeu/bge/bltu/bne
```

因此当前低 IPC 的主要原因是：

1. 当前 `srcSmoke` 走软件除法/取模 helper，没有使用硬件 M 扩展 DIV/REM，导致分支密度极高。
2. 条件分支预测对这些数据相关分支效果差，miss 率约 25.9%。
3. `JALR` 返回没有 RAS，return miss 率约 50%。
4. 每次 branch miss 都通过 `REC_BRANCH_MISS` 执行 frontend/backend flush。
5. CommitStage 对 branch/store 采取保守策略，遇到 branch 或 store 后 `stopCommit=1`，同周期不继续提交后续 ROB 项。

所以 IPC 低是当前 workload 与微架构共同导致的真实问题，不是 TB 统计错误。

## 后续优化建议

优先级建议：

1. 对 `srcWithMext` 跑同样分类计数，确认使用硬件 M 扩展后软件除法 helper 是否消失。
2. 增加 RAS，专门预测 `JALR x0, 0(x1)` 这类 return。
3. 针对条件分支，增加更细的 PC 级 miss 热点统计，找出 `0x80001330` helper 中最差分支。
4. 在保证恢复精确性的前提下，评估正确预测 branch 提交时是否必须 `stopCommit=1`。
5. 后续再加 `fetch/dispatch/issue/commit_width/rob_head_not_done/store_commit_stall/recovery_cycles` 计数，进一步拆分 IPC 损失来源。

## 验证

已运行：

```text
make verilator-build-src
make sim-src TEST=srcSmoke NO_BUILD=1
make verilator-build
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1
```

结果：

```text
srcSmoke PASS
rv32ui-p-simple PASS
```
