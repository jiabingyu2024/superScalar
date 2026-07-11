# NOP-Core 对齐、LSU 时序切分与 IPC 优化执行记录

日期：2026-07-10 至 2026-07-11

参考文档：

- `vs/NOP-Core_vs_superScalar_current_microarchitecture_timing_review.md`
- `058_fpga_timing_improvement_plan.md`
- `059_ipc_optimization_plan.md`

## 1. 结论

本轮完成了计划中的 Phase 0、Phase 1、Phase 2、Phase 3 和满足进入条件的 Phase 5：

1. 性能计数绑定真实 RTL 状态，不再用 `!int_issue_ready[0]` 猜测 load pending。
2. pending load 不再全局关闭两路 INT issue。
3. 在 MEM IQ/PRF/AGU 与 StoreBuffer/DCache 之间加入单项 registered request stage。
4. cacheable load 在 StoreBuffer 非空但无同 word alias 时可访问 DCache；完整覆盖仍转发，部分覆盖仍等待。
5. `MUL_0` 的 3 拍 DSP pipeline 改为 II=1，并用等长 metadata valid/uop/op pipeline 对齐结果；DIV/REM 仍保持单 active 状态机。

`srcWithMext` 同一 200,000-cycle 窗口 IPC 从 `0.640525` 提高到 `0.836345`，提升 `30.57%`，超过计划的 20% 进取目标。未调用 Vivado，因此这里只能确认结构上切断了原长路径，不能声明 routed WNS/Fmax 已经通过。

## 2. 基线与最终结果

| 指标 | 修改前 | Phase 1-3 | 最终（含 Phase 5） |
| --- | ---: | ---: | ---: |
| cycles | 200,000 | 200,000 | 200,000 |
| commit | 128,105 | 155,271 | 167,269 |
| IPC | 0.640525 | 0.776355 | 0.836345 |
| 相对基线 | - | +21.21% | +30.57% |
| INT blocked by load | 20,189 | 78 | 83 |
| MEM IQ backpressure | 82,159 | 53,572 | 46,724 |
| ROB head wait MUL | 20,227 | 28,582 | 15,922 |
| MulDiv busy | 未独立计数 | 57,995 | 502 |

Phase 1-3 后 load/MEM 活动数随有效吞吐提高，所以 `load_pending` 等绝对周期不适合单独与基线比较；更可信的结果是 commit/IPC、MEM IQ backpressure、INT 全局封锁和完成正确性同时改善。

## 3. 微架构变更

### 3.1 NOP-Core stage contract 对齐

旧路径：

```text
MEM IQ head
  -> PRF combinational read
  -> AGU
  -> StoreBuffer 8-entry CAM/byte merge
  -> DCache/DRAM arbitration
  -> combinational mem_issue_ready
  -> MEM IQ pop/compact
```

新路径：

```text
MEM IQ head + PRF read + AGU
  -> edge: mem_req_q(valid/uop/address/store_data/mask)
  -> StoreBuffer CAM / DCache request
  -> load pending metadata
  -> completion register
  -> ROB/Busy/IQ wakeup
```

`mem_issue_ready` 现在只依赖 `!clear_i && !mem_req_valid_q`。StoreBuffer CAM、DCache 接收和 DRAM 状态只能阻塞本地 `mem_req_q`，不会同拍反馈到 MEM IQ select/pop/compact。这对应 NOP-Core 的 ISS/RRD/EXE ownership 分界思想。

如果该寄存边界删掉或把 downstream ready 重新接回 `mem_issue_ready`，原 35 级 `IQ -> PRF -> AGU -> SB -> DCache -> DRAM` 路径会重新出现。

### 3.2 request 接受与 payload 稳定

`DramAccessIF` 新增 `exReadAccept`，表示 load request 真正被共享读写通道接受。`mem_req_q` 只有以下情况才能释放：

- misaligned load/store 已生成异常 completion；
- store 已被 StoreBuffer 接受；
- load 已获得完整 StoreBuffer forwarding；
- load request 的 `exReadAccept` 为 1。

request/load payload 位于无 reset 的 `always_ff @(posedge clk)` 中，异步 reset/flush 只清 `valid/pending/state`。这既保证 backpressure 时 payload 稳定，也避免宽 uop/address/data 进入高扇出 reset tree。

如果把 `exReadEn` 当作 accept，store drain 正占共享通道时 load token 会被错误建立，而实际请求没有发出，最终 ROB 永久等待或把后续响应配给错误 uop。

### 3.3 StoreBuffer disambiguation

已寄存 load 地址驱动 StoreBuffer CAM，规则如下：

| 查询结果 | 行为 |
| --- | --- |
| 完整覆盖所需 byte | 直接 forwarding 并完成 |
| 同 word 但只有部分覆盖 | 等待相关 store drain 后重查 |
| 无同 word alias，且地址在 `0x8010_0000..0x8013_ffff` | 可访问 DCache，即使 StoreBuffer 非空 |
| uncached/device 地址 | 继续等待 StoreBuffer 全空和 drain token 清除 |

StoreBuffer 仍按老到年轻扫描，后扫描的年轻 store 覆盖同 byte 的老 store。没有实现 partial-forward + memory merge，也没有放开 MEM IQ 越序。

如果把 partial alias 当 no-alias，`SB/SH -> LW` 会混入旧内存字节；如果 uncached/MMIO load 使用 cacheable 放行规则，会破坏设备访问顺序。

### 3.4 INT/load 解耦

两路 INT completion 使用 slot 0/1，load return 使用 MEM slot，MulDiv 使用独立 slot，因此 pending load 不再关闭 INT issue：

```systemverilog
int_issue_ready_o[i] = !clear_i;
```

MEM 仍保持单 outstanding load，依赖 load 仍由 BusyTable/IQ ready 位自然阻塞。错误路径 response 由 recovery 清除 pending token 后丢弃。

如果 completion slot 或 PRF 写口映射被改成重叠，这个解耦会造成 completion 覆盖；仿真专用 PRF 多写冲突断言用于捕获该类错误。

### 3.5 MUL II=1

旧 `MulDivPipe` 在 `MD_MUL_WAIT` 中锁住整个单元，3 拍乘法实际每 4~5 拍才能接受下一条。新设计直接把当前 MUL 操作数送入已有 `MUL_0`，并同步移动：

```text
mul_valid_q[2:0]
mul_uop_q[2:0]
mul_op_q[2:0]
```

第三拍用相同位置的 metadata 选择 `MUL/MULH/MULHSU/MULHU` 结果。DIV/REM 只在 MUL metadata pipeline 为空时启动，避免共享 completion slot 冲突；divider recovery 仍使用 `div_drain_q` 吞掉错误路径迟到响应。

一度把已和 ready 相与的 fire 回送为 `MulDivPipe.valid_i`，Verilator 报出 `UNOPTFLAT`；最终改为 raw queue valid 输入、单元内部形成 `valid && ready` fire，最终构建中 `UNOPTFLAT/MULTIDRIVEN/LATCH` 均为 0。

如果 metadata 延迟与 `MUL_0` 的 3 拍配置不一致，会把正确乘积写入错误 ROB/PRD；completion collision 断言覆盖 MUL 与 DIV/REM 同拍返回。

## 4. Phase 0 可观测性

新增 JSON 事件均来自真实 RTL 状态，并只在 `VERILATOR_TB` 下累加：

- request stage valid；
- partial alias block；
- StoreBuffer nonempty/no-alias；
- full forwarding；
- MEM IQ head source not ready；
- younger ready behind head；
- MUL/DIV/REM issue count；
- MulDiv busy cycles。

`srcWithMext` 最终 200k 窗口观测到：partial alias 3 cycles、nonempty/no-alias 31,316 cycles、full forward 6,649 cycles、MUL 15,495、DIV 10、REM 10。该数据证明 no-alias 放行和 MUL pipeline 都命中了真实高频路径。

## 5. 未实施阶段及原因

### Phase 4：MEM IQ bounded lookahead

未实施。虽然 `younger_ready_behind_head` 很高，但计划要求同时满足“ROB-head MEM wait 仍为前三瓶颈”。最终排名中它是第 4，且实现 lookahead 必须增加 memory sequence/ROB age、只匹配 older store 的 forwarding 和定向 memory-order scoreboard。当前收益证据不足以承担该正确性风险。

### Phase 6：前端优化

未实施。IROM wait 为 0，FetchBuffer/decode backpressure 仍是后端压力传播，不是取指供给不足。当前不扩大 fetch width、不加入 I-cache，也不把后端状态组合反馈到 PC 路径。

### 更深 PRF/IQ 重构

未实施。P1 request register 已切断已知最差 MEM 路径；在没有新 routed timing report 前，不重写 PRF registered read 或 INT IQ payload/selection。

## 6. 验证结果

| 验证 | 结果 |
| --- | --- |
| Verilator `myCPU`/`student_top` 重建 | PASS；0 `UNOPTFLAT/MULTIDRIVEN/LATCH` |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |
| `srcWithMext`, 200k | 预期 TIMEOUT；37/37、fail 0、M 8/8；IPC 0.836345 |
| `srcSmoke`, full | PASS at 33,398,179 cycles；IPC 0.920966；SEG `0x37000667` |
| `srcWithMext` difftest, 50k | 预期 TIMEOUT；41,262 commits、MMIO skip 4、last PC `0x80000e78`；无 selfcheck 错误 |
| 仿真专用断言 | 全部回归中 0 failure |

当前 difftest harness 是 commit-trace selfcheck，`reference_enabled=false`；因此它证明 trace 自洽和程序正常推进，不等价于外部 Spike/NEMU 参考模型逐条比对。

## 7. Vivado 待验收项

按用户要求没有运行 Vivado。后续生成新工程时必须验证：

1. 最差路径不再完整穿过 `MemIssueQueue -> PRF -> AGU -> StoreBuffer -> DCache -> SocMemBridge -> DRAM WEA`。
2. `mem_issue_ready` 的扇入只来自 request valid/clear，不重新出现 StoreBuffer/DCache/DRAM 信号。
3. `MUL_0` 仍为 3-stage、II=1 的 DSP pipeline，metadata pipeline 与 IP latency 一致。
4. 50 MHz WNS >= +0.5 ns、WHS >= 0；再评估 55/60 MHz。
5. LUT/FF 单阶段增幅 <= 5%，setup/hold/TNS/THS、DRC/CDC/methodology 均无 blocker。
6. 不用 false path、虚假 multicycle 或 `ALLOW_COMBINATORIAL_LOOPS` 掩盖问题。

## 8. 后续优先级

最终短窗前三个压力项是 INT IQ backpressure、MEM issue block、load pending。下一轮应先用新的计数拆分 request-stage 空转与 DCache miss/refill/共享端口等待，再决定是否增加 load response queue/tag；不要直接设置 `MemIssueQueue.HEAD_ONLY=0`。只有新 routed timing report 指向 PRF/IQ 或 DCache array，才进入对应结构优化。

