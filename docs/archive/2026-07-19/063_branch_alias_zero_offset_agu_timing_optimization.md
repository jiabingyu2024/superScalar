# 分支、move alias 与零偏移 AGU 时序切分

## 结论

本轮在不显著降低 `srcWithMext` IPC 的约束下，针对当前 200 MHz
布局布线报告中最差的三类组合链进行了局部微架构切分：

1. 条件分支不再经过“分支比较 -> actual next-PC 选择 -> 32 位 next-PC
   比较”后才生成 miss，而是使用随 uop 保存的 predictor 元数据直接比较
   predicted-taken 与 actual-taken。
2. fused move 的 producer transaction 到 alias transaction 的
   `producer_tid` 重定向，从 fixed/load/slow completion 当拍移到 producer
   顺序提交时。
3. 依赖 fixed completion 的零偏移 load/store 直接使用 completion result
   作为地址；非零偏移依赖跨一拍后再进入 AGU，避免同周期串联两个 carry
   chain。

最终 `srcWithMext` 20M IPC 为 `0.944961`，相对修改前 `0.947182`
下降约 `0.235%`。唯一一次 Vivado synthesis-only 结果为 WNS
`-1.236 ns`、TNS `-2041.110 ns`、负 setup endpoint `3665`。原 routed
前三类目标路径均已从最差路径中移除，但 200 MHz 尚未收敛；新的主瓶颈
转移到 `FetchQueue head -> decode/dispatch -> Scoreboard payload S/R/CE`。

## 输入证据与分析边界

修改前最新完整布局布线结果：

- WNS `-1.073 ns`
- TNS `-1217.186 ns`
- setup failing endpoint `4165`
- hold WNS `+0.065 ns`，hold TNS `0`

当前 routed 报告的十条最差 setup 路径分成两族：

- 5 条 `exec_q.op1 -> branch_outcome_q[*].miss`，最差 `-1.073 ns`，
  17 级逻辑；
- 5 条 `LoadQueue entries.addr -> Scoreboard producer_tid`，最差约
  `-1.042 ns`，11 级逻辑。

同时，用户提供的 post-route physopt 日志反复处理
`fixed_completion.result -> IQ src1 wakeup -> memory address`，说明分支和
producer map 被切断后，fixed ALU 与 AGU 串联会成为下一瓶颈。

`v42_batch8_small_predictor_high_ipc` 的全量 synthesis CSV 来自 7 月 18 日
的一版临时 shadow-tag DCache，不能作为当前 DCache 的严格同版本基线。
本轮只用它识别共享旁路结构，不依据其中已经不存在的 `fast_tag_mem`
路径修改当前 DCache。

## RTL 修改

### 1. 分支 miss 快路径

文件：`rtl/core/core_top.sv`

- 条件分支：
  `miss = actual_taken XOR (pred_hit && pred_kind==COND && counter[1])`。
- 直接 JAL：IROM 中目标不可变，命中且类型为 JUMP 即认为预测目标正确。
- JALR：目标由寄存器动态产生，为避免重新引入 add-plus-compare 长链，
  保守地按 miss 处理并使用精确 actual target 恢复。
- 异常分支仍强制 `miss=0`，由原异常恢复路径处理。

该改动不改变条件分支的执行/提交拍数。代价集中在 JALR 密集代码；目标
`srcWithMext` 的稳态热循环基本不含 JALR。

### 2. fused move alias 在提交时重定向

文件：`rtl/core/issue/scoreboard.sv`

原实现会在 fixed/load/slow completion 时读取 alias entry 的 rd，并更新
32 项 `producer_tid_q`。load completion 的 valid 又受 LoadQueue forwarding
metadata 影响，形成 `LoadQueue addr -> producer_tid` 的大范围组合锥。

新实现保持 completion 当拍填写 alias entry 的 done/result，但直到 producer
顺序提交时才把 alias rd 的映射从 producer transaction 改到 alias
transaction。这样 producer slot 在提交后可以安全复用，年轻同名 writer 的
映射仍由 transaction-ID 比较保护，同时 completion 不再驱动 producer map。

### 3. 零偏移 completion-to-address 快通路

文件：`rtl/core/issue/inorder_issue_queue.sv`

第一次尝试把所有 fixed-result memory dependency 统一延后一拍。它能切断
双 carry chain，但 `srcWithMext` 20M IPC 降到 `0.901587`，相对基线下降
`4.81%`，因此拒绝。

最终方案按地址形式区分：

- `imm == 0`：匹配的 fixed completion result 直接作为 memory address，
  同拍仍可选择/发射；
- `imm != 0`：base result 先写入 IQ，下一拍开放 `mem_addr_ready` 后只经过
  一个 AGU 加法器；
- load-address registered wakeup 和 slow completion 保留各自明确的数据源，
  不再借用被 fixed completion 同拍改写的 `entries_d.src1_value` 做地址加法。

`srcWithMext` 热循环的两个关键内存访问均为地址 ADD 后的 `lw 0(base)`，
因此可走无气泡快通路。

## 验证

### 构建与正确性

- `verilator-build`：通过。
- `verilator-build-src`：通过。
- RV32I/MI/M：`40 + 4 + 8 = 52/52 PASS`。
- `srcWithMext` 500k：RV32I `37/0`、M `8`，IPC `0.896248`。
- `srcWithMext` 20M：RV32I `37/0`、M `8`，IPC `0.944961`。
- `srcSmoke` 500k：RV32I `37/0`，IPC `0.668484`。

修改前相同窗口：

| profile | 窗口 | 修改前 IPC | 修改后 IPC | 变化 |
|---|---:|---:|---:|---:|
| srcWithMext | 500k | 0.896398 | 0.896248 | -0.017% |
| srcWithMext | 20M | 0.947182 | 0.944961 | -0.235% |
| srcSmoke | 500k | 0.688324 | 0.668484 | -2.882% |

`srcSmoke` 的下降来自 JALR 密集调用/返回被保守恢复；比赛目标
`srcWithMext` 的稳态损失低于本轮设置的 2% 门槛。

### 唯一一次 Vivado synthesis-only

命令：

```text
vivado.bat -mode batch -source fpga/run_synthesis.tcl -tclargs srcWithMext 8 200 1 v42_branch_alias_zeroimm_agu 100000 0 0
```

结果：

- `synth_design`：成功，0 error；
- WNS：`-1.236 ns`；
- timing-summary TNS：`-2041.110 ns`；
- 全量 CSV slack 累加：`-2039.576 ns`；
- 负 setup endpoint：`3665`；
- synthesis 估算等效 Fmax：约 `160.36 MHz`。

日志有 4 条 `set_clock_groups` critical warning，来源是工程复用时 XDC 在
generated clock 建立前的一次早期解析；最终 timing summary 的 User Ignored
Path Table 已列出 `clk_out1_pll <-> clk_out2_pll` 两个方向，且本文使用的
WNS/TNS 均为 `clk_out2_pll` 同时钟域路径。另有 BTB `ram_style=block`
无法满足、回退到 LUTRAM 的 warning，它与新的 predictor feedback 次瓶颈一致。

7 月 18 日临时 batch8 synthesis 的 WNS 为 `-1.572 ns`。两者 DCache
实现并不完全相同，因此 `+0.336 ns` 只能作为趋势参考，不能替代同版本
place/route 对比。

## 路径迁移结果

本次全量 CSV 中：

| 目标族 | 修改前证据 | 修改后 synthesis |
|---|---|---|
| branch outcome | routed 最差 `-1.073 ns` | 负路径 `0` 条 |
| producer map | LoadQueue 起点，约 `-1.042 ns` routed / `-1.206 ns` batch8 synth | 96 条均改由 frontend/dispatch 起始，最差 `-0.276 ns` |
| exec memory address | fixed-result 双加法链 | 仅 6 条 MDU 相关，最差 `-0.256 ns`；fixed-result 双加法族消失 |

新瓶颈：

1. `FetchQueue head -> Scoreboard payload S/R`：最差 `-1.236 ns`，
   11 级逻辑，data path `5.725 ns`，其中 route 占 `86.45%`；
2. 同类 frontend -> scoreboard payload/CE：共约 2663 条，是当前 TNS 主体；
3. predictor `read_entry_q` feedback：95 条，最差 `-1.033 ns`；
4. DCache tag response -> scoreboard/execute：最差约 `-0.448/-0.431 ns`。

## 后续建议

下一轮不应再围绕 branch/producer-map/zero-offset AGU 做细碎修改。优先考虑
在 fetch/decode 与 Scoreboard allocation 之间增加可保持每拍一条吞吐的
dispatch payload register，并把 Scoreboard payload 写入与 allocate-pointer、
commit-reuse 选择解耦。该结构预计只增加启动/恢复延迟，不降低稳态单发射
吞吐，但必须重新验证 macro move 的双 allocation、同拍 commit+allocate
以及异常/serialize 边界。

根据本轮约束，没有运行第二次 Vivado，也没有运行 place/route。
