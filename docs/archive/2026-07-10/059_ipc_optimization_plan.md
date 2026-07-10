# FPGA 时序友好的 IPC 优化计划

日期：2026-07-10  
适用基线：当前 `srcWithMext` 200,000-cycle Verilator 构建与 `digital_twin_srcWithMext` routed design  
核心目标：在不牺牲功能正确性、50 MHz 时序收敛和 FPGA 可实现性的前提下，提高持续提交吞吐。

## 1. 目标与边界

本轮优化不以“仿真 IPC 单项变大”为唯一目标，而以实际可上板吞吐为准：

```text
有效吞吐 ~= IPC x routed Fmax
```

当前 `srcWithMext` 短窗基线为：

| 指标 | 当前值 |
| --- | ---: |
| 测量周期 | 199,998 |
| commit | 130,737 |
| IPC | 0.653685 |
| 50 MHz 估算吞吐 | 32.684 MIPS |
| CPU setup WNS @ 50 MHz | +0.923 ns |
| CPU hold WHS | +0.026 ns |

目标分为两档，但不是对单个阶段的硬性收益承诺：

| 目标 | `srcWithMext` 同窗口 IPC | 50 MHz 对应吞吐 |
| --- | ---: | ---: |
| 最低目标：较基线提升 10% | >= 0.719 | >= 35.95 MIPS |
| 进取目标：较基线提升 20% | >= 0.784 | >= 39.20 MIPS |

`srcSmoke` 曾测得 IPC 0.910069，但它与 `srcWithMext` 的程序、动态指令比例和运行区间不同，只能做各自版本间的同负载对照，不能直接用来判断本次 IPC 回退或提升。

本计划明确不做以下事情：

1. 不通过 `ALLOW_COMBINATORIAL_LOOPS`、false path 或虚假 multicycle 掩盖真实时序问题。
2. 不把 `MemIssueQueue.HEAD_ONLY` 直接改为 0；该修改缺少内存年龄和 store/load 顺序证明。
3. 不在同一周期叠加新的 `IQ -> PRF -> AGU -> StoreBuffer CAM -> DCache -> DRAM` 组合反馈路径。
4. 不为性能计数消耗上板 LUT/FF；新增和保留的性能计数必须只存在于 `VERILATOR_TB`。
5. 不同时重写 LSU、Issue Queue、MulDiv 和前端，避免正确性、IPC 与 QoR 结果无法归因。

## 2. 当前瓶颈结论

### 2.1 观测事实

| 压力项 | 周期占比 | 判断 |
| --- | ---: | --- |
| IROM wait | 0.00% | 不是取指存储器带宽问题 |
| FetchBuffer backpressure | 64.07% | 后端压力向前传播的结果 |
| Decode/rename backpressure | 70.27% | 后端无法持续接收，不是根因本身 |
| MEM issue blocked | 44.20% | 第一主瓶颈 |
| MEM IQ backpressure | 39.91% | 内存队列排空速度不足 |
| ROB head waiting for MEM | 36.07% | 内存完成延迟直接阻塞提交 |
| load pending | 28.45% | 单 outstanding load 串行化明显 |
| INT issue blocked by load | 10.29% | 可直接解除的不必要耦合 |
| true DCache stall | 7.54% | 有影响，但不是全部 MEM 阻塞 |
| DCache miss rate | 1.41% | 不能解释 44.20% 的 MEM issue block |
| ROB full | 0.18% | ROB 容量不是当前优先扩展项 |
| FreeList empty | 0.00% | 物理寄存器数量不是当前瓶颈 |
| ROB head waiting for MulDiv | 10.32% | 第二级瓶颈，排在 LSU 之后 |

结论：当前 IPC 主要受 LSU 控制策略和内存操作串行化限制。前端能够供给指令，FetchBuffer 满和 decode backpressure 主要是后端堵塞向上传播；在 LSU 压力下降前扩大 FetchBuffer、ROB 或取指宽度不会解决根因，还可能加重布线。

### 2.2 RTL 根因

1. `rtl/core/execute/ExecuteCluster.sv:247`：`mem_load_pending_q` 为 1 时同时关闭两个 INT issue lane。load 返回实际占用 MEM completion slot，和 INT 两个 completion slot 并不重合。
2. `rtl/core/execute/ExecuteCluster.sv:253-258`：load 只有在完整 StoreBuffer forwarding 或整个 StoreBuffer 为空时才能进入 LSU。即使 StoreBuffer 中的 store 与 load 地址完全无关，也会被全局阻塞。
3. `rtl/core/issue/MemIssueQueue.sv:17-20`：MEM IQ 只允许队头发射。它保证了保守的内存顺序，但也会产生 head-of-line blocking。
4. `rtl/core/execute/StoreBuffer.sv:112-127`：8 项并行地址比较和 byte merge 直接参与 load admission，当前最差路径已经跨越 MEM IQ、PRF、AGU、StoreBuffer、DCache 和 DRAM。
5. `rtl/core/execute/ExecuteCluster.sv:522-546`：只保存一个 `mem_load_pending_q`，在返回前不能接收下一个普通 load。
6. `rtl/core/execute/MulDivPipe.sv:108-175`：MulDiv 整体按单 active uop 工作，乘法即使底层 IP 可流水，也要等待状态机回到 IDLE 才接收下一条。

## 3. 时序与 FPGA 约束红线

每个阶段只接受同时满足功能、IPC 和 QoR 的结果。

### 3.1 结构约束

1. `ready` 优先只依赖本模块寄存状态、单级资源占用或局部小扇入逻辑。
2. StoreBuffer 地址比较、forward mask、DCache 接收和 DRAM ready 不得组合回传到 MEM IQ 的移除/压缩逻辑。
3. 新增 CAM、年龄比较或多路选择时，必须放在寄存边界之后；不能把 MEM IQ 五项选择和 StoreBuffer 八项比较串成同一拍。
4. 跨层级宽 payload 只在握手成功时寄存，reset/flush 只复位 valid/state，避免恢复宽数据异步复位和高扇出控制网。
5. 优先增加 1 项弹性寄存器，而不是扩大队列深度。当前 ROB full 仅 0.18%，盲目增深不能提升根因吞吐。

### 3.2 QoR 验收预算

使用相同 part、时钟、seed、strategy 和约束比较每个阶段：

| 项目 | 阶段验收线 |
| --- | --- |
| 50 MHz setup | WNS >= +0.5 ns，TNS = 0 |
| hold | WHS >= 0，THS = 0 |
| 相对 WNS | 同 seed 相比基线下降不超过 0.2 ns；超出则先查路径再决定是否接受 |
| 55 MHz 阶段目标 | WNS >= +0.3 ns |
| 资源 | 单阶段顶层 LUT/FF 增幅原则上 <= 5% |
| 关键路径 | 不再新增跨 IQ/PRF/SB/DCache/DRAM 的组合链 |
| DRC/CDC | 0 error，0 未解释 critical warning，0 combinational loop |

route 存在 seed 波动，因此“相对下降 0.2 ns”是审查触发线，绝对 setup/hold 通过线仍是最终硬门槛。若 IPC 提高但 routed Fmax 下降导致 `IPC x Fmax` 不增，该方案不合入。

## 4. 分阶段实施计划

### Phase 0：冻结可比较基线并补齐阻塞原因计数

先保持 RTL 行为不变，只完善仿真观测：

1. 固定 `srcWithMext` 200,000 cycles 为快速性能窗口，记录同一 binary、同一 Verilator 参数和测量起止点。
2. 保留现有 dispatch/issue/commit width、ROB head 类型、IQ backpressure 和 LSU pressure。
3. 把真实 `mem_load_pending_q` 作为 simulation-only event 导出。当前 `perf_load_pending_o` 由 `!int_issue_ready[0]` 间接推断；Phase 1 解耦 INT ready 后该语义会失效。
4. 将 MEM issue blocked 分解为互斥或明确可重叠的原因：
   - outstanding load 占用；
   - StoreBuffer full；
   - StoreBuffer 有同地址完整 forwarding；
   - StoreBuffer 有部分覆盖；
   - StoreBuffer 非空但实际无地址 alias；
   - DCache/外存未返回；
   - MEM IQ head source not ready。
5. 增加 `mem_iq_head_not_ready` 与 `younger_ready_behind_head`，量化真正的 MEM head-of-line blocking，再决定是否进入 Phase 4。
6. MulDiv 计数拆成 MUL/DIV/REM issue、busy cycles 和 ROB-head wait，避免把不同优化代价混在一起。

所有信号、累加器和 JSON 字段继续放在 `VERILATOR_TB` 条件编译内；非仿真构建只保留常量连接或完全裁剪。

完成门槛：JSON 字段语义能从 RTL 事件逐项解释，计数不把向前传播的 backpressure 排在根因之前，FPGA synthesis elaboration 中不存在新增性能计数寄存器。

### Phase 1：解除 pending load 对 INT issue 的全局封锁

目标修改：

```systemverilog
int_issue_ready_o[i] = !clear_i;
```

MEM issue 仍受 `mem_load_pending_q` 控制；只允许独立 INT/branch uop 在 load 等待期间继续执行。该修改会删除一条 ready gating，而不是增加组合深度，预期对时序中性或略有帮助。

正确性检查重点：

1. load 返回使用 completion/PRF write port 2，INT 使用 port 0/1，MulDiv 使用 port 3；确认同周期四槽完成不会互相覆盖。
2. 对同一 PRD 的多写必须断言不可能发生；若发生说明 rename/wakeup 或错误路径清除有 bug。
3. branch miss 与 load return 同周期时，ROB completion、recover 和次拍 clear 的优先级必须保持精确状态。
4. recover/clear 后，错误路径 INT completion 和旧 load response 不能再次置 ready 或写 PRF。
5. wakeup 总线接受同周期 INT + MEM + MulDiv completion，不得因为 valid 数增加丢 lane。

如果删错/改错：最典型后果是同周期 load return 覆盖 INT completion，导致 ROB 永远等不到 done，或错误路径结果污染 PRF。

阶段判据：`int_issue_blocked_by_load` 应接近 0；IPC 必须不回退。若该事件明显下降但 IPC 提升很小，说明它主要与更上游的 MEM 阻塞重叠，继续 Phase 2/3，而不是扩大 INT IQ。

### Phase 2：加入单项 registered LSU request stage

该阶段同时服务时序和 IPC，是本计划的核心结构调整。

建议数据流：

```text
MEM IQ head
  -> PRF read + AGU
  -> [mem_req_q: valid/uop/address/store_data/mask]
  -> StoreBuffer hazard/forward 或 DCache request
  -> [load pending metadata]
  -> MEM completion slot
```

实现原则：

1. `mem_issue_ready_o` 只依赖 `!clear_i` 和 `mem_req_q` 是否可接收，不再依赖 StoreBuffer forwarding、DCache 或 DRAM 信号。
2. MEM IQ 出队时一次性锁存 uop、最终地址、store data 和 mask；后级停顿时 payload 必须稳定。
3. 初版仍保持单 outstanding load，先切断关键路径和理顺握手，不同时引入多返回 tag。
4. store 进入 request stage 后再等待 StoreBuffer push；load 进入 request stage 后再查询 StoreBuffer。
5. 若增加一拍使无冲突 load 的 IPC 回退超过 3%，只在 `mem_req_q` 为空且后级明确可接收时增加受控 skid/bypass；不得恢复完整长组合 ready 链。
6. flush/recover 必须清 `mem_req_q.valid`。若 DCache 请求已不可取消，要用 drop/epoch 状态吞掉旧响应，不能把旧响应写给新 uop。

如果删错/改错：request payload 在 backpressure 时变化会把一个 uop 的 ROB/PRD 与另一个地址配对，表现为偶发错写、精确异常失效或恢复后幽灵 completion。

阶段判据：最差路径不再从 MEM IQ/PRF 穿过 StoreBuffer 和 DCache 到 DRAM WEA；50 MHz WNS 不低于 +0.5 ns；同窗口 IPC 回退不超过 3%，并为 Phase 3 提供稳定的寄存地址查询点。

### Phase 3：用地址相关性替代“StoreBuffer 必须全空”

在保持 MEM IQ `HEAD_ONLY=1` 的前提下，队头 load 之前的所有更老 memory uop 都已经离开 MEM IQ；其中未提交 store 位于 StoreBuffer。因此可以基于已寄存 load 地址做保守 disambiguation：

| StoreBuffer 查询结果 | 初版处理 |
| --- | --- |
| 无同 word alias | 允许访问 DCache，即使 StoreBuffer 非空 |
| 覆盖 load 所需全部 byte | 直接完整 forwarding |
| 只有部分 byte 覆盖 | 暂停，等待相关 store drain 后重查 |
| store 地址/状态不确定 | 暂停 |

具体要求：

1. 将 `load_forward_hit` 真正接入 Execute；不能再用 `store_buffer_empty_i` 代表“无地址冲突”。
2. StoreBuffer CAM 只接收 Phase 2 已寄存的地址，查询结果不能组合反馈到 MEM IQ。
3. 初版不做 partial-forward + DCache byte merge，避免增加返回路径 mux 和验证面。只有部分覆盖占比足够高时才单独立项。
4. 保持年轻 store 覆盖老 store的 byte merge优先级；当前 StoreBuffer 从老到年轻迭代，后写 byte 覆盖先写 byte，该语义不能改变。
5. MMIO/uncached load 必须保持保守顺序。若地址属于 device region，至少等待所有更老 store 可见，并按现有提交规则执行，不把普通 cacheable load 的旁路规则直接用于 MMIO。
6. 删除或收窄 `store_drain_pending_q` 的全局阻塞语义前，必须证明它不再承担 recover 或 store 可见性保护。

如果删错/改错：load 可能越过更老的同地址 store 并读到旧值；更隐蔽的错误是 partial store forwarding 丢失未覆盖 byte，只在 SB/SH 后接 LH/LW 时暴露。

阶段判据：`store_buffer_nonempty_no_alias` 不再计入阻塞；MEM issue block、MEM IQ backpressure、ROB-head MEM wait 三项均应下降。若 IPC 收益小于 2% 且 partial-alias 占比很低，停止扩展 forwarding 复杂度。

### Phase 4：仅在计数证明必要时缓解 MEM IQ 队头阻塞

进入条件：Phase 1-3 后，`younger_ready_behind_head` 仍超过测量周期的 5%，且 ROB-head MEM wait 仍是前三瓶颈。

不能直接设置 `HEAD_ONLY=0`，原因是：

1. 年轻 load 不能越过地址未知的老 store。
2. 年轻 store 提前进入 StoreBuffer 后，当前 forwarding CAM 没有按 load/store 年龄过滤，可能错误转发给更老 load。
3. MMIO、异常和 recover 需要比普通 cacheable load 更强的顺序约束。

可接受的实现路线：

1. 为 memory uop 和 StoreBuffer entry 增加可比较的 memory sequence/ROB age 信息。
2. 先做两项 bounded lookahead，而不是五项全 CAM oldest-ready select。
3. 只有候选之前不存在未解析 store，或所有更老 store 地址已知且证明无 alias 时，才允许年轻 load 发射。
4. StoreBuffer forwarding 只匹配比 load 更老的 store，并保持“最年轻的老 store byte 胜出”。
5. 候选选择结果先寄存，再进入 Phase 2 request stage，避免 `5-entry select x 8-entry StoreBuffer CAM` 同拍串联。
6. device/uncached access、fence、异常 uop 继续严格按队头顺序。

如果删错/改错：会出现依赖测试难以稳定复现的内存顺序错误，ISA 单测可能全过，但长程序或中断/恢复场景随机失败。

阶段判据：必须有定向 memory-order scoreboard 和断言证明，且同窗口 IPC 至少提升 3%；否则保留 `HEAD_ONLY=1` 的简单实现。

### Phase 5：优化 MulDiv 吞吐，不拉长 ALU 关键路径

进入条件：LSU 优化后 `rob_head_wait_mul` 仍超过 5%。

1. 先用 Phase 0 计数区分 MUL 与 DIV/REM；不要因 DIV 长延迟去重写乘法路径。
2. 查询 `MUL_0` 的实际 latency 和 initiation interval。如果支持 II=1，将乘法 uop metadata 做与 DSP pipeline 等长的 valid/uop shift register，允许每拍接收一个 MUL。
3. DIV/REM 继续使用独立 busy 状态；不要让 divider busy 阻止可流水的 MUL，除非二者确实共享唯一 completion 端口且会同拍冲突。
4. 对 MUL 与 DIV 可能同拍返回的情况使用一项 response buffer 或静态可证明的仲裁，禁止无 backpressure 地丢 completion。
5. 不减少 DSP 内部 pipeline 级数来追求低 latency；对 FPGA 而言，较高 latency、II=1 通常比一拍大乘法更容易收敛。

如果删错/改错：metadata 与 DSP result 延迟错一拍会把正确乘积写入错误 ROB/PRD，这是比算术结果错误更危险的静默破坏。

阶段判据：RV32UM 全过，MulDiv collision 断言为 0，`rob_head_wait_mul` 明显下降，且 DSP/BRAM/LUT 与 WNS 在预算内。

### Phase 6：后端解除后再复查前端

只有当 MEM/MulDiv 压力下降后，以下任一现象成立才进入前端优化：

- IROM wait 或 fetch starvation 持续出现；
- FetchBuffer 空而 decode 可接收的周期占比明显；
- branch recovery 的真实丢失周期进入前三瓶颈。

当前短窗 branch miss 共 265 次，其中 JAL/JALR miss rate 高但绝对数量较小。可优先评估直接 JAL target 预解码、BTB 命中和 RAS，而不是扩大 fetch width。所有预测改动必须在 fetch stage 内部寄存或使用小表，不能把 decode/ROB 状态直接组合反馈到取指 PC 关键路径。

## 5. 验证与回归矩阵

### 5.1 每阶段快速回归

| 检查 | 通过标准 |
| --- | --- |
| lint/elaboration | 0 error，0 latch，0 multidriven，0 unoptflat/combinational loop |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |
| `srcWithMext` 短窗 | 37/37、fail 0、M 8/8；200k TIMEOUT 属预期 |
| JSON | schema 可解析，counter coverage 完整，字段语义与当前 RTL 一致 |
| FPGA 裁剪 | performance counter 不进入非 `VERILATOR_TB` 网表 |

`srcSmoke` 在阶段收口时使用相同运行范围复测。全量 `srcWithMext` 不作为日常迭代项；只在候选版本正确性和短窗性能稳定后由用户安排。

### 5.2 LSU 必做定向场景

1. load pending 期间双 INT issue，并与 load 同周期完成。
2. load pending 期间 branch miss，随后旧 load response 返回。
3. older SW -> younger LW，同地址完整 forwarding。
4. older SB/SH -> younger LW，partial alias 必须等待或正确 merge。
5. StoreBuffer 非空但 load 无 alias，允许访问 DCache。
6. 两个 store 对同一 word 不同 byte，年轻 store byte 优先。
7. StoreBuffer full 与同周期 drain/push。
8. recover 时 request stage、pending load、未 retire store 同时存在。
9. cache miss/refill 与 store drain 并发。
10. MMIO load/store 顺序与异常路径。

### 5.3 建议断言

```text
accepted request -> payload stable until consumed
load completion -> exactly one matching ROB/PRD
wrong-path request/response -> never writes PRF or completes live ROB entry
load bypass -> no older unresolved or aliasing store
forwarded byte -> comes from youngest older matching store
completion collision -> no valid result silently dropped
clear/recover -> all speculative valid state killed or explicitly quarantined
```

### 5.4 Vivado 阶段报告

每个实际候选版本保留：

- `report_timing_summary`；
- 最差 20 条 setup/hold path；
- `report_utilization -hierarchical`；
- `report_high_fanout_nets`；
- `report_control_sets`；
- DRC、CDC、methodology；
- 同版本 IPC JSON。

重点检查路径是否仍经过：

```text
MemIssueQueue -> PRF -> AGU -> StoreBuffer -> DCache -> SocMemBridge -> DRAM WEA
```

Phase 2 完成后，该整条组合路径必须被 request register 切开。

## 6. 文件范围与实施顺序

预计涉及：

- `rtl/core/execute/ExecuteCluster.sv`
- `rtl/core/execute/StoreBuffer.sv`
- `rtl/core/issue/MemIssueQueue.sv`，仅 Phase 4 才改变选择规则
- `rtl/core/execute/MulDivPipe.sv`，仅 Phase 5
- `rtl/core/backend/CoreBackend.sv`
- `rtl/core/core.sv`
- `tb/verilator/perf_stats.h`
- `tb/verilator/perf_stats.cpp`
- `tb/verilator/dut_student_top_io.cpp`
- 对应 LSU/MulDiv 定向 testbench 与断言文件

严格实施顺序：

```text
P0 计数语义冻结
 -> P1 INT/load 解耦
 -> P2 registered LSU request
 -> P3 StoreBuffer 精确 no-alias 放行
 -> 重新排序瓶颈
 -> P4 MEM IQ bounded lookahead（条件进入）
 -> P5 MulDiv pipeline（条件进入）
 -> P6 前端复查（条件进入）
```

每个 Phase 单独保留基线、diff、回归结果和 QoR。前一阶段没有通过，不叠加后一阶段。

## 7. 停止与回退条件

出现以下任一情况，停止扩大改动并回到最近通过点：

1. RV32 或短窗 difftest 出现任何功能偏差。
2. setup WNS < +0.5 ns、hold violation，或最差路径新增跨模块组合反馈。
3. IPC 提升但 `IPC x routed Fmax` 下降。
4. 单阶段 LUT/FF 增幅超过 5%，且没有相称的吞吐收益。
5. 新增 combinational loop、CDC critical、unconstrained endpoint 或依赖 false-path 才能过时序。
6. Phase 3 后某类优化收益低于 2%，却显著增加 memory ordering 验证面。
7. Phase 4 无法给出“load 不越过老未知 store、forward 只来自老 store”的形式化或 scoreboard 证据。

## 8. 第一轮建议执行内容

第一轮只实施 Phase 0 和 Phase 1：先把真实 load pending 计数从 `int_issue_ready` 解耦，再允许 load pending 期间继续 INT issue。它直接针对已测得的 10.29% 全局阻塞，几乎不增加组合逻辑，也不会触碰 StoreBuffer 顺序规则。

第一轮通过后实施 Phase 2，用单项 request register 切断当前 35 级 LSU 长路径；随后 Phase 3 才利用寄存地址做 no-alias load 放行。这一组合比直接开放 MEM IQ 乱序更符合 FPGA：增加少量 FF，减少跨层级组合依赖，并把最复杂的 memory-order 变更推迟到计数确实证明必要之后。
