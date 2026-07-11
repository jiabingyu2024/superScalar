# MEM probe II=1 与全窗口安全 lookahead 优化记录

> 日期：2026-07-12  
> 工作树基线：`a971785`  
> 性能口径：`srcWithMext`，固定 500,000 cycles  
> 约束：本轮不运行 Vivado；用户取消 50M，后续以 500k 为迭代标准

## 1. 结论

本轮将 MEM IQ 的年轻 load address probe 从“两拍串行、probe pending 期间完全停选”
改为可在旧 probe resolve 的同一边沿装入下一项，稳态 initiation interval 为 1。
同时把安全 lookahead 从最老 3 项扩展到整个 5-entry MEM IQ。

最终 500k `srcWithMext`：

| 指标 | 修改前 | 最终版本 | 变化 |
| --- | ---: | ---: | ---: |
| commits | 615,984 | 617,609 | +1,625 |
| IPC | 1.23197 | 1.23522 | +0.00325 / +0.264% |
| MEM head not ready | 172,857 | 164,955 | -4.57% |
| younger ready behind head | 151,703 | 143,037 | -5.71% |
| probe launch | 23,685 | 23,973 | +1.22% |
| probe accept | 23,648 | 23,971 | +1.37% |
| probe reject | 0 | 0 | 保持全接受 |

收益是正向但有限。剩余 HOL 主要来自地址尚未解析的 older store；当前设计没有
store-set、load replay 或 memory-order violation recovery，不能安全允许年轻 load
越过未知地址的 older store。

## 2. 修改文件

- `rtl/core/issue/MemIssueQueue.sv`
- `rtl/core/execute/ExecuteCluster.sv`

没有修改 DCache、StoreBuffer、ROB、PRF、接口端口或 filelist。

## 3. 修改前的串行合同

修改前：

```text
cycle N   : MEM IQ select younger load
edge N    : Execute capture probe owner/address
cycle N+1 : probe resolve
edge N+1  : IQ remove or mark denied
cycle N+2 : MEM IQ 才能选择下一项
```

原因有两处：

1. MEM IQ 在 `probe_pending_q=1` 时完全禁止 selection；
2. Execute 的 `mem_issue_ready_o` 在 `mem_probe_valid_q=1` 时恒为 0。

因此即使 probe 每次都接受，也只能隔拍启动。

## 4. 修改后的 II=1 合同

修改后：

```text
cycle N   : old probe resolve，同时选择另一个安全 younger load
edge N    : old owner 从 MEM IQ 移除；new probe owner/address 原子装入
cycle N+1 : new probe resolve，同时可继续 replacement
```

关键条件：

```systemverilog
mem_issue_ready_o =
    (!mem_probe_valid_q || mem_probe_resolve_valid_o) &&
    (mem_req_count_q < MEM_REQ_DEPTH);
```

该 ready 只观察 registered probe valid、registered request occupancy 和本地 resolve，
不观察 DCache ready，因此没有重新形成 DCache→MEM IQ combinational ready 环。

## 5. 同拍 remove+replace 的年龄修正

MEM IQ payload 使用 stable slot，但 `age_q` 在任意 entry 移除后会压缩。若旧 probe
在本拍接受，而 replacement candidate 比它年轻，则 candidate 下一拍看到的年龄应减 1。

因此 launch 时保存的是 post-remove age：

```systemverilog
if (replacement && old_probe_accept &&
    (new_issue_age > old_probe_age)) begin
    new_tracking_age = new_issue_age - 1;
end
```

如果漏掉该修正，下一拍 resolve 的 `{slot, age, rob_idx}` 与 IQ 中 owner 不匹配，
表现为 probe 已发出但 entry 无法被合法移除。

## 6. 为什么 replacement 周期不允许直接 issue head

当前 MEM IQ 每周期只支持一次 owner removal。旧 probe accept 已经占用该 removal，
如果同拍又直接 issue age-0 head，会出现两个 entry 都进入下游但只移除一个，导致重复执行。

因此 resolving cycle 只允许选择另一个 lookahead load；head issue 延后一拍。该限制不影响
持续 HOL 场景的 probe II=1，也避免为了双 remove 扩大 valid/age next-state 逻辑。

## 7. denied 状态从单项改为 slot bitmap

原实现只保存一个 denied slot。II=1 后连续 probe 可能产生多个 reject，因此改为
`denied_q[MEM_IQ_DEPTH-1:0]`：

- reject 时设置对应 stable slot；
- slot remove 或复用 push 时清除；
- denied 只禁止年轻 lookahead；entry 成为 head 后仍可按顺序执行。

本轮 workload 的 reject 仍为 0，但 bitmap 保证流水化后不会因两个不可提前执行的
load 相互覆盖 denied owner。

## 8. 安全顺序边界

lookahead 仍必须满足：

1. candidate 是普通 load；
2. candidate 之前所有 MEM IQ entry 都是 load；
3. candidate 未被 denied；
4. Execute 注册计算地址后确认 cacheable；
5. misaligned、uncached/device load 不得提前；
6. 任意 older store/fence/serial 都阻止 bypass；
7. 只有 probe accept 后才从 IQ 移除并进入 request queue。

本轮没有增加 speculative memory ordering、replay 或 violation recovery。

## 9. 参数 A/B

### 9.1 Request queue 2→4

曾将 AGU request queue 泛化并扩到 4。500k 中：

- `mem_issue_block` 从 80,468 降到 33,795；
- commits、IPC、probe launch/accept 完全不变；
- 下游仍是单 outstanding/replacement DCache 合同。

结论：更深 queue 只把等待从 MEM IQ 搬到 request queue，没有提高完成吞吐，还增加动态
tail write、payload storage 和 recovery 验证面，已回退到深度 2。

### 9.2 MEM IQ depth 4/5/6

| Depth | 500k IPC | MEM IQ backpressure | 判断 |
| ---: | ---: | ---: | --- |
| 4 | 1.23522 | 147,357 | 容量压力明显上升，Fmax收益无 routed 证据 |
| 5 | 1.23522 | 83,719 | 最终选择 |
| 6 | 1.23522 | 36,923 | 无提交收益，只增加窗口与扫描 |

最终保持 depth=5。深度4虽然IPC相同，但 backpressure 增加 76%，可能在更长阶段传播；
深度6没有IPC收益。由于本轮不运行 Vivado，不能把结构大小推断冒充实际Fmax结果。

## 10. 最终回归

| 测试 | 结果 |
| --- | --- |
| Verilator src build | PASS |
| RV32MI | 4/4 PASS |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| `srcSmoke` DiffTest 500k | 318,165 commits；无 mismatch；RV32I=37 |
| `srcWithMext` normal 500k | 617,609 commits；IPC=1.23522；37+8；fail=0 |
| `srcWithMext` DiffTest 500k | 617,611 difftest commits；MMIO skip=4；无 mismatch |

固定窗口达到上限显示 `TIMEOUT` 是预期终态，不是功能失败。

## 11. 时序影响与待验收项

正向因素：

- 没有增加 DCache→IQ ready feedback；
- probe payload 和 owner 仍终止在 Execute register；
- request queue 保持深度2；
- denied 使用窄 bitmap，不进入宽 payload CE；
- MEM IQ 保持 stable payload slot。

风险：

- selection 从 oldest-three 扩到 5-entry 全窗口，增加两级 age/candidate 检查范围；
- replacement ready 引入本地 `probe_resolve_valid` 条件；
- 必须用新 routed report 检查路径是否终止在 `mem_issue_*_q`，不能仅凭 RTL 宣称Fmax提升。

## 12. 后续真正的大收益方向

当前安全 lookahead 只能跨 older load。若目标从 IPC 1.23 继续显著提升，需要解决 older
store 地址未知造成的 HOL。可选方案是 store-address queue + load queue + violation
detection/replay；在没有 replay 前，不允许年轻 load 猜测越过 older store。

该阶段属于新的内存消歧微架构，不再是简单增加队列深度或 probe 数量，必须单独设计
epoch、recovery、forwarding年龄过滤和 directed memory-order tests。
