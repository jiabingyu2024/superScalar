# ID-AGU + 一拍同步 DCache 微架构评价

## 1. 结论

建议采用该方向，但应把它定义为**单发射、双后端通道、统一 C2 写回/完成点**，而不是简单删除 M1/M2 两级：

- 普通整数/分支/CSR：`C0 ID -> C1 EX -> C2 WB`
- Load：`C0 ID+AGU -> C1 DCache -> C2 WB`
- Store：`C0 ID+AGU -> C1 DCache/提交完成`，C2 只传完成元数据，不写寄存器
- MUL/DIV：进入 C1 EX 后锁存操作数并冻结前端，分别等待固定 3/34 拍，再进入 C2

该方案的主要价值是结构更清晰、分支恢复可提前约一拍、同步 RAM 更容易映射到 FPGA BRAM。它不会改变单发射理论上限 `IPC <= 1`。实际 IPC 是否提高，主要取决于 DCache miss、MUL/DIV 阻塞和地址相关停顿，而不是流水级数本身。

推荐的第一版采用“稳时序策略”：普通 ALU 相关允许旁路；当 load/store 的基址依赖当前 C1 结果且无法在 C0 安全取得时停 1 拍。不要在第一版同时引入 `Cache -> ID/AGU` 超长旁路。

## 2. 分析范围与现状依据

本评价只覆盖当前 `rtl/core/` 的顺序单发射实现及 `myCPU.sv` 外挂的 blocking DCache，不评价 README 中历史上的 2-way OoO 方案。

已确认的当前实现事实：

- 当前后端为 `ID -> EX -> M1 -> M2 -> WB`，load/store 地址在 EX 的通用 ALU 中计算。
- 分支在 EX 产生结果，但 `hazard_unit` 使用 EX/M1 寄存后的 `branch_error_m` 恢复，恢复点比 EX 晚一拍。
- DCache 位于 `myCPU.sv`，当前数据阵列为异步读 LUTRAM；命中数据在 DCache 内寄存，以适配 core 的 M1/M2 契约。
- DCache 为 direct-mapped、blocking、write-through；一次只允许一个 miss/uncached 事务推进。
- 当前 RV32M 固定延迟为 MUL=3 拍、DIV/REM=34 拍，EX busy 时冻结上游。
- FPGA 目标为 Kintex-7、50 MHz，单周期预算约 20 ns。

最近已有结果仅用作基线，不代表改造后结果：

| 测试 | 周期 | commit | IPC | DCache access | miss | DCache stall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `srcWithMext` | 100,000,000 | 51,647,686 | 0.516477 | 18,389,187 | 499,923 | 23,792,191 |
| `srcSmoke` | 37,382,995 | 30,758,597 | 0.822796 | 900,305 | 29 | 900,466 |

限制：现有计数器未可靠拆分 DCache 命中固定代价、refill、uncached、store backpressure、load-use 和 MUL/DIV busy，因此不能由这些数字直接推出精确增益。

## 3. 建议的数据通路

```text
                           +------------------+
RF/decode/imm ---> C0 ID --| 普通指令元数据    |--> C1 EX ------> C2 WB
       |                   +------------------+       |
       +--> base + imm --> [ID/AGU request] ---------+
                                                   C1 DCache ---> C2 WB(load)
                                                       |
                                                       +--------> store done
```

同步 DCache 的推荐时序是：C0 末沿锁存 `{addr, op, mask, rd, store_data, valid}`；C1 并行读取 tag/data 并比较命中；C1 末沿将 load 数据和写回元数据送入 C2。miss 或 uncached 访问则保持 C1 请求槽并对上游施加 backpressure，直至 replay 完成。

普通路径和访存路径必须在 C2 前有明确仲裁。单发射保证同一条指令只走一条路径，但多周期 EX 完成与旧的 DCache 返回可能在同拍到达，控制上仍应断言“最多一个 C2 producer 有效”，或提供一深度 result buffer。

## 4. IPC 评价

### 4.1 理论模型

单发射顺序核可用下式近似：

```text
CPI ~= 1
     + f_branch * miss_rate * redirect_penalty
     + memory_extra_cycles / retired_instructions
     + address_dependency_stalls / retired_instructions
     + f_mul * (Lmul - 1)
     + f_divrem * (Ldiv - 1)
     + other_backpressure

IPC ~= 1 / CPI
```

缩短流水线主要改变启动/排空和分支错误恢复代价；长稳态下，如果没有减少 stall，IPC 几乎不变。

### 4.2 可预期收益

1. **分支恢复**：将 redirect 直接从 C1 EX 送给 hazard/PC，而不是先经过 EX/M1，可减少约 1 个错误路径周期。按当前 `srcWithMext` 的 55,148 次 miss/100M 周期计，单独这一项只改善约 0.055% 总周期，收益很小。
2. **DCache 命中吞吐**：若同步 DCache 支持每拍接受一个命中请求，且 C1 是流水化 lookup，则连续独立 load/store 可保持 1 request/cycle，不应因为“一拍同步读”自动产生每条 load 一拍 stall。
3. **减少寄存器级和旁路源**：删除 M1/M2 的普通 ALU 传递，可简化控制和前递选择；面积、动态功耗和验证复杂度会下降，但 IPC 收益间接。
4. **更高 Fmax 潜力**：BRAM 同步读通常优于异步 LUTRAM 大阵列。即使 IPC 不变，MIPS 仍可能因频率提高而增加。

### 4.3 主要损失项

- **AGU 基址相关**：前一条 ALU 在 C1 产生结果、后一条 load/store 同拍处于 C0。若使用 `EX -> ID/AGU` 旁路，可零气泡但形成 `ALU -> bypass mux -> AGU adder -> C0/C1 register` 长路径；若不使用，则每次此类相关停 1 拍。
- **load 到下一条访存基址**：同步 Cache 的 load 数据在 C1 末才稳定。`Cache -> ID/AGU` 同拍旁路会串起 BRAM 输出、tag compare、数据选择/扩展、AGU，时序风险最高。推荐第一版停 1 拍。
- **MUL/DIV 全局冻结**：固定 3/34 拍且冻结前端时，额外 CPI 仍近似为 `f_mul*2 + f_divrem*33`。少量 DIV 就可能吞掉流水级缩短的全部收益。
- **blocking miss**：当前一次 miss 填整条 4-word cache line，miss 期间全核冻结。`srcWithMext` 当前 DCache stall 占 23.8% 周期，是比流水深度更大的优化对象。
- **write-through store**：连续 store 受外部 ready 限制；若外部端口不能每拍接受，C1 将成为全局背压点。

### 4.4 条件化 IPC 预估

以 `srcWithMext` 当前 `CPI=1/0.516477≈1.936` 为基准：

- 只做级数重排和分支提前：IPC 约仍为 `0.516~0.518`。
- 若额外消除每条指令 `0.05~0.15` 的真实结构性停顿：IPC 约为 `0.53~0.56`。
- 只有在当前 DCache stall 中确实存在约 `0.3 CPI` 可由流水化命中路径消除时，才可能接近 `0.61`；现有计数器不足以证明这一前提。
- 长期理论上限仍是 IPC=1；在 blocking miss、34 拍 DIV 和全局冻结不变时，不应把 0.8+ 作为这次重排的承诺目标。

因此，本次改造更合理的验收目标是：**正确性不退化、命中吞吐达到 1 request/cycle、分支恢复少 1 拍、Fmax 不下降，并通过新计数器确认 IPC 变化来源**。

## 5. 时序评价

### 5.1 C0 ID/AGU

潜在路径为 `IF/ID Q -> decode/RF read -> bypass select -> 32-bit add -> ID/Cache Q`。在 50 MHz 下大概率有余量，但这只是工程推断，必须用 Vivado post-synth/post-route 报告确认。若目标未来提高到 100 MHz 以上，RF/bypass/AGU 组合深度可能取代 DCache 成为关键路径。

控制建议：

- AGU 使用独立加法器，不复用 EX ALU。
- 先用 RF/WB 稳定来源计算地址；对 C1 新结果的同周期旁路做成可参数化或可关闭策略。
- decode 只生成紧凑的 `mem_op`，避免大范围控制扇出直接进入地址加法器。

### 5.2 C1 DCache

推荐 tag 和 data 并行同步读。C1 的组合逻辑只保留 tag compare、word/byte 选择、符号扩展和小 mux，然后在 C1/C2 边界寄存。不要把 miss FSM、外部 ready 链或 SoC 地址译码反向串入命中关键路径。

当前 `DCacheDataByteBank` 明确采用异步读 distributed RAM，不能只改注释或多加一个输出寄存器就视为同步 Cache；需要改写 RAM inference 模板及请求/响应契约。

### 5.3 C1 EX 与 C2 WB

普通 ALU 路径更短，但分支比较、JALR target、CSR 读改写和 redirect 若全部堆在 C1，仍可能形成高扇出路径。redirect 应直达 PC/hazard，同时只在一个位置生成 kill mask。

C2 写回 mux 至少包含 `ALU/CSR/link`、`load`、`MUL/DIV`。若 mux 输入在地理位置上分散，应先各自寄存，再做窄选择；不要把 DCache RAM 输出直接跨层级送到 regfile 写口。

## 6. 冒险、顺序和精确性

| 场景 | 推荐处理 | 代价/理由 |
| --- | --- | --- |
| ALU -> 普通 ALU/branch | C2/WB -> C1 EX 前递 | 可无气泡，路径短且标准 |
| ALU -> load/store base | 第一版停 1 拍；时序充足后试 EX -> AGU | 避免同周期跨级长路径 |
| load -> 普通 ALU/branch | C2/WB -> C1 EX 前递 | 流水位置允许时可无气泡 |
| load -> load/store base | 停 1 拍 | 避免 Cache -> AGU 超长旁路 |
| ALU/load -> store data | 在 C1 store 槽前递，不要求 C0 得到最终值 | 地址和 store data 分开处理 |
| DCache miss/uncached | 保持 C1 请求及元数据，冻结 C0/前端 | 请求不得重复发射或丢失 |
| 分支/异常 kill store | `store_fire` 必须受 valid 且未被 kill 控制 | 禁止错误路径外部副作用 |
| MUL/DIV busy | 锁存操作数和元数据，冻结前端，done 后只前进一次 | 防重复启动和结果错配 |

特别注意：如果 branch 在 C1 EX 发现错误，而更年轻的 store 同拍位于 C0，store 不能在该边沿进入有效的 C1 Cache 请求。`redirect/kill` 必须高于 `C0->C1 accept`。当前恢复使用 `branch_error_m`，改造时必须一起前移，不能只移动数据路径。

## 7. 低功耗和资源影响

- 使用同步 BRAM 可显著减少当前按 byte lane 拆分的 LUTRAM/分布式存储资源，但具体 BRAM 数量取决于 4 byte write-enable 和 tag 存储映射。
- ID 独立 AGU 增加一个 32-bit adder；删除普通指令跨 M1/M2 的宽寄存器可部分抵消。
- 对流水寄存器、Cache RAM 和 MUL/DIV 输入加 clock-enable；stall 时保持，不要每拍重写相同值。
- valid bit 复位即可，数据 RAM 不需要清零；这与当前 DCache 的做法一致。

## 8. 验证敏感点与决策门

编码前必须冻结以下契约：

1. 同步 DCache 是“每拍可接受一个 hit”的流水接口，还是单请求 handshake 接口。
2. store 在 C1 被视为完成，还是必须等 write-through 外部握手完成。
3. misaligned load/store 是 trap、拆分访问，还是维持当前测试约束下的行为。
4. MMIO/uncached 的顺序和响应延迟，尤其是读副作用与 store 不可重放。
5. C2 多来源是否保证互斥；若不能保证，result buffer/仲裁优先级是什么。
6. MUL/DIV 的“3/34 拍”从 start 到 done 如何计数，并用断言固定。

若这六项没有明确，模块虽然可以连通，但 stall/flush 边界会反复返工。
