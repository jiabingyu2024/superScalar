# srcWithMext.dump 目标下的 RISC-V CPU 架构与微架构建议

> 约束：本文件只基于 `data/srcWithMext/srcWithMext.dump` 做静态分析和热点推断，没有查看其他源码。  
> 目标：在 Kintex FPGA 上实现 RV32 CPU，并让该测评程序跑得尽量快。  
> 结论先行：对这个 dump，最优解不是“大而全乱序核”，而是 **高频、低延迟乘法、片上数据存储、强前端预测、2 发射顺序超标量、扎实的 load/use 与 store-forwarding**。

## 1. dump 静态特征

程序规模：

- 指令数：2216 条。
- ISA 需求：RV32I + M + Zicsr/M-mode 基本异常返回。
- 明确出现：`ecall`、`mret`、`mtvec/mscratch/mcause/mstatus/mepc`。
- 没看到压缩指令，前端可以按 32-bit 定长指令设计。

静态指令 mix：

| 类别 | 典型指令 | 静态数量 | 对设计的含义 |
|---|---:|---:|---|
| 整数立即数/地址生成 | `addi/lui/auipc/slli/add` | 很多，`addi` 701 | 地址生成和小 ALU 必须 1 cycle，高旁路质量比复杂 ALU 更重要 |
| 访存 | `lw/sw` | `lw` 328, `sw` 295 | 数据通路瓶颈之一；栈变量和矩阵数组访问都很多 |
| 调用/返回 | `jal/jalr` | `jal` 131, `jalr` 118 | RAS 对返回预测很关键 |
| 条件分支 | `bne/beq/bge/...` | 150 | 热循环为后跳分支，BTFNT/2-bit BHT 收益大 |
| M 扩展 | `mul/mulh/.../div/rem` | 静态几十条 | 静态少，但动态热点里 `mul/mulh` 极重 |
| CSR/异常 | `csrr*`, `ecall`, `mret` | 少量 | 正确性必须过，但不应为它牺牲主频 |

控制流特征：

- 后跳条件分支主要集中在 `0x80000980` 到 `0x80000f5c`。
- `jalr` 多数是函数返回，返回地址栈 RAS 比大容量通用 BTB 更划算。
- 前向 `bne/beq` 多数像正确性检查的失败出口，正常路径大多“不跳”。

## 2. 动态热点推断

核心热点不是静态 M 指令测试，而是矩阵/数组循环：

- `0x80000eac` 外层循环约 10 次。
- 每次调用两次 `0x80000dd4` 初始化 80x80 矩阵。
- 每次调用 `0x80000980` 做一次 80x80x80 矩阵乘。
- 每次调用 `0x80000abc` 先转置/搬运，再做一次 80x80x80 矩阵乘。
- 每次调用 `0x80000cf8` 比较两个 80x80 结果矩阵。

粗略动态乘法量：

| 来源 | 估算 |
|---|---:|
| `0x80000980` 矩阵乘 | `80*80*80*10 = 5,120,000` 次 `mul` |
| `0x80000abc` 矩阵乘 | `80*80*80*10 = 5,120,000` 次 `mul` |
| 两个初始化矩阵，含 `%100` 魔数除法展开 | `2*80*80*10*3 = 384,000` 次 M 类乘法 |
| M 扩展正确性小测试 | 可忽略 |

因此，动态最热路径是：

```text
取循环指令 -> 地址计算 -> 2 个数组 load -> mul -> 累加 add -> store 累加值/循环变量 -> 后跳分支
```

关键结论：

- `mul` 吞吐必须做到 1/cycle，延迟最好 <= 2 cycle。
- 数据存储必须片上，不能让外部 DDR 成为主路径。
- branch miss、load-use stall、乘法等待，每项都会被百万级循环放大。
- dump 像 `-O0`/低优化生成，有大量栈上局部变量 `lw/sw`，所以 store-to-load forwarding 和栈访问快路径很值。

## 3. 推荐总体架构

推荐做一个 **RV32IMZicsr、M-mode only、Harvard、2 发射顺序超标量、片上 TCM/D-cache 化数据存储** 的 CPU。

不要一开始做完整乱序核。这个 benchmark 的控制流简单、循环固定、数据集可放片上；在 Kintex 上，复杂乱序核很容易降低 Fmax、增加验证风险，最终反而慢。

推荐架构边界：

| 模块 | 推荐设计 |
|---|---|
| ISA | RV32IM + 必要 CSR/异常：`mtvec/mscratch/mcause/mepc/mstatus/ecall/mret` |
| 前端 | 64-bit 取指，每拍最多取 2 条 32-bit 指令 |
| 分支预测 | BTFNT fallback + 2-bit BHT + 小 BTB + 8/16-entry RAS |
| 发射 | 2-wide in-order issue，slot0 完整，slot1 受限 |
| 执行 | 2 个简单 ALU，1 个 pipelined MUL，1 个 iterative DIV/REM |
| 访存 | 片上 D-TCM，至少 256 KiB；1-cycle hit；store buffer + forwarding |
| 提交 | 顺序提交，保证精确异常 |
| 目标主频 | 优先稳定高频，不追求过深复杂结构 |

内存容量建议：

- IROM：dump 约 8.7 KiB，放 BRAM 很轻松。
- D-TCM：建议 256 KiB 起步。
- 数据区大致覆盖 `0x80100000` 到栈顶 `0x80121050` 附近；`0x80000abc` 还会在栈上临时分配约 25 KiB。
- `0x80200050` 出现一次 `lw`，需要按测评环境要求映射成 MMIO 或固定输入寄存器。

## 4. 微架构细化

### 4.1 前端

推荐流水：

```text
IF0: PC 选择 / 分支预测
IF1: IROM 64-bit 取指
ID0: 双指令切分 / 立即数 / 简单预译码
ID1: 相关性检查 / 配对
EX : ALU / branch / addr / MUL pipeline
MEM: D-TCM / store buffer
WB : 双写回
```

分支策略：

- `jal` 在 decode 阶段直接给出目标，尽早 redirect。
- `jalr ra-return` 用 RAS 预测，返回密集时收益明显。
- 条件分支用 2-bit BHT；没有历史时用 BTFNT：后跳预测 taken，前跳预测 not-taken。
- branch resolve 放 EX，mispredict flush IF/ID/issue 中年轻指令。

为什么这样最适合此 dump：

- 热循环后跳分支几乎每轮 taken，最后一轮 not-taken。
- 正确性检查的前向失败分支正常情况下 not-taken。
- 函数测试区有大量 `jal` + `jalr` 返回序列，RAS 能减少返回气泡。

### 4.2 双发射规则

建议先做保守 2 发射：

| 发射槽 | 能发什么 | 原因 |
|---|---|---|
| slot0 | ALU/branch/jal/jalr/load/store/CSR/MUL/DIV | 完整功能，负责有副作用或控制流的老指令 |
| slot1 | ALU/MUL，后续可开放 load | 降低异常、访存顺序、CSR 精确性复杂度 |

配对规则：

- 同包内如果 slot1 读 slot0 写的寄存器，默认不配对，除非你明确实现同周期 bypass。
- 同包 WAW 不配对。
- slot1 不发 branch/CSR/div/rem，先保主频和可验证性。
- 如果实现双 LSU，必须有 bank conflict 检测和同地址顺序规则；否则宁可先单 LSU。

对这个 dump 的收益：

- 地址计算、循环变量更新、常量构造可以和部分访存/MUL 重叠。
- 大量 `lui/addi`、`addi/add`、`lw` 前后的独立 ALU 指令能吃到双发射。
- 即使达不到每拍 2 条，减少热循环里的结构冲突也很有价值。

### 4.3 寄存器堆与旁路

2 发射最低需求：

- 4R2W 寄存器堆。
- EX/MEM/WB 到两个 issue slot 的完整 bypass。
- `x0` 硬连 0，写忽略。
- load-use 检测必须准确。

FPGA 实现建议：

- 32x32 很小，可以先用触发器/分布式 RAM 做多读口。
- 如果 4R2W 影响 Fmax，再考虑寄存器堆复制。
- WB 同周期两个写口冲突时，按指令年龄处理；一般配对规则已避免同 rd WAW。

### 4.4 乘除法单元

这是此 benchmark 的核心。

乘法：

- `mul` 吞吐目标：1/cycle。
- `mul` 延迟目标：1 到 2 cycle；超过 3 cycle 会明显伤害矩阵内层循环。
- `mulh/mulhu/mulhsu` 也要正确，但动态热点中 `mul` 最重，初始化中有 `mulh`。
- 用 DSP48 做 32x32，内部流水化；结果带 `rd/tag/valid` 回写。

为什么延迟很关键：

```text
lw a3, 0(a_addr)
lw a5, 0(b_addr)
mul a5, a3, a5
lw a4, acc_stack
add a5, a4, a5
sw  a5, acc_stack
```

`mul` 后面只有一个独立 `lw` 可以隐藏延迟。若 `mul` 是 2-cycle，通常还能被这条 `lw` 部分覆盖；若是 4/8/多周期，百万级循环会被直接拖慢。

除法：

- `div/divu/rem/remu` 只在 M 扩展正确性测试里少量出现。
- 推荐 iterative divider，32 cycle 左右可接受。
- 分母为 0、`INT_MIN / -1`、有符号余数等边界必须按 RISC-V 规范正确。

### 4.5 数据访存

优先级最高的是把数据放片上。

基础方案：

- 256 KiB D-TCM，32-bit word，1-cycle load hit。
- 支持 byte/half/word load-store，符号扩展正确。
- 地址 decode 覆盖 `0x8010_0000` 数据区、栈区和 `0x8020_0050` MMIO。

必须做：

- store buffer，至少 2 到 4 entry。
- store-to-load forwarding：年轻 load 命中未提交 store 地址时直接取 store 数据。
- load-use interlock：load 结果没到时阻塞依赖指令。

建议做的加速：

- D-TCM 64-bit 或 2-bank，按地址低位分 bank。
- 若开放双 LSU，只允许不同 bank 双访问；同 bank stall。
- 栈访问快路径：最近若干个 `s0/sp + imm` 地址用小型 fully-assoc buffer 缓存/转发，专门吃这个 dump 的局部变量 `lw/sw`。

为什么 stack forwarding 很值：

- dump 热循环中循环变量和累加器经常放在 `-20(s0), -24(s0), -28(s0), -32(s0)`。
- 如果每次都真实打到 BRAM，会占用大量 LSU 带宽。
- forwarding 做错会造成旧值参与计算，矩阵结果会直接不一致。

### 4.6 CSR 与异常

必须支持的行为：

- `csrrw/csrrs/csrrc` 及 immediate 版本。
- `mtvec/mscratch/mcause/mepc/mstatus`。
- `ecall` 进入 `mtvec`，设置 `mepc/mcause`。
- `mret` 从 `mepc` 返回并恢复必要状态。

实现取舍：

- CSR 指令放 slot0，单发射。
- CSR/异常 flush 年轻指令，保持精确异常。
- 不需要为了此 dump 实现完整 OS 级特权系统、MMU、页表、缓存一致性。

## 5. 控制优先级

推荐全局 redirect/flush 优先级：

```text
reset
> trap/exception/ecall
> mret
> branch/jalr mispredict
> predicted taken/jal redirect
> normal pc+4/pc+8
```

stall 优先级：

```text
D-TCM/MMIO wait
> divider busy / CSR serialize
> load-use hazard
> issue packet RAW/WAW hazard
> D-TCM bank conflict
> frontend wait
```

注意：

- flush 必须杀掉 younger 指令的写回、store commit、CSR 写。
- stall 不能重复提交同一条 store。
- branch mispredict 与 load stall 同时发生时，要保证 PC redirect 不丢。

## 6. 设计优先级排序

| 优先级 | 项目 | 性能收益 | 风险 |
|---:|---|---|---|
| P0 | RV32IM/CSR 正确性 + 片上 I/D 存储 | 必须 | 中 |
| P0 | 1-cycle D-TCM hit + 完整 bypass | 极高 | 中 |
| P0 | 1/cycle、<=2-cycle `mul` | 极高 | 中高 |
| P1 | BHT/BTB/RAS 分支预测 | 高 | 中 |
| P1 | store buffer + load forwarding | 高 | 中 |
| P1 | 2-wide in-order issue | 中高 | 高 |
| P2 | D-TCM banking / 可选双 LSU | 中高 | 高 |
| P2 | 栈访问快路径 | 中 | 中高 |
| P3 | 小窗口乱序/寄存器重命名 | 不确定 | 很高 |

对你现在的阶段，建议做到 P1，再根据计数器决定是否上 P2。P3 不建议作为第一版目标。

## 7. 不建议投入的方向

- 完整乱序、多发射 ROB、复杂 LSQ：验证量太大，Kintex 上也可能掉主频。
- 大容量通用 cache：这个程序工作集可片上放下，TCM 更确定。
- 复杂全局历史预测器：热分支模式简单，小 BHT + RAS 足够。
- 高性能 divider：动态上不热，iterative 足够。
- MMU、A 扩展、浮点、压缩指令：此 dump 不需要。
- PC 特化硬连热点循环结果：这不是通用 CPU 设计，竞赛规则下风险很大。

## 8. 最小可落地实施路线

第一阶段：正确跑通。

1. 单发射 5/6 级 RV32IM 核。
2. IROM 加载 `0x80000000` 起始指令。
3. D-TCM 映射 `0x80100000` 数据区和栈。
4. 实现 `ecall/mret` 和必要 CSR。
5. `mul/div/rem` 先正确，divider 可多周期。

第二阶段：让热点不被明显卡住。

1. 把 `mul` 改成 DSP pipelined，吞吐 1/cycle，延迟控制到 1 到 2 cycle。
2. 加 EX/MEM/WB 旁路和 load-use interlock。
3. D-TCM 保证 1-cycle hit。
4. 加 store buffer 与 store-to-load forwarding。

第三阶段：前端和双发射。

1. 64-bit 取指，每拍取两条。
2. 加 BTFNT + BHT + BTB + RAS。
3. 加 2-wide issue：先 `slot0 full + slot1 ALU/MUL`。
4. 用性能计数器统计：
   - 总 cycle / retired inst
   - branch miss 次数
   - load-use stall 次数
   - mul wait 次数
   - D-TCM wait/bank conflict 次数
   - PC 区间热点：`0x80000980-0x80000aa0`、`0x80000abc-0x80000cd4`、`0x80000dd4-0x80000e90`

第四阶段：按瓶颈加 P2。

- 如果 LSU 满：做 D-TCM banking 或栈快路径。
- 如果 mul wait 高：降低乘法延迟或做更 aggressive 的 issue。
- 如果 branch miss 高：调 BHT/BTB/RAS。
- 如果 Fmax 低：砍复杂度，先保主频。

## 9. 自检清单

- `jalr zero,0(ra)` 返回是否能被 RAS 正确预测。
- 后跳循环分支是否预测 taken，最后一次 not-taken 是否正确 flush。
- `mulh/mulhu/mulhsu` 符号扩展是否正确。
- `div/rem` 边界是否符合 RISC-V，尤其除 0 和溢出。
- `ecall` 的 `mepc/mcause/mtvec` 行为是否能通过 `0x800003xx` 附近测试。
- store 后紧跟同地址 load 是否能 forward，且 byte/half mask 正确。
- flush 时 younger store 是否不会写入 D-TCM。
- 双发射同包 RAW/WAW 是否会被禁止或正确旁路。
- `sp/s0` 大负偏移访问是否不会越界，D-TCM 容量是否覆盖栈临时区。
- `0x80200050` MMIO 读是否按测评环境返回正确值。

## 10. 最小实践任务

手写一个简化版 CPU，功能边界如下：

- RV32IM，不做压缩、不做 MMU、不做中断嵌套。
- 单发射、顺序提交、Harvard IROM/D-TCM。
- 支持 `mtvec/mscratch/mcause/mepc/mstatus`、`ecall/mret`。
- `mul` 先 2-cycle pipelined，`div/rem` iterative。
- D-TCM 256 KiB，1-cycle hit，先单 LSU。

步骤：

1. 先让 PC 从 `0x80000000` 顺序取指，支持 `jal/jalr/branch`。
2. 实现 RV32I ALU/load/store，跑到第一个 `ecall` 前。
3. 补 CSR/异常，让 `ecall/mret` 测试通过。
4. 补 M 扩展，先过 `0x80001dxx-0x800021xx` 的乘除测试。
5. 跑完整 dump，记录总 cycle。
6. 只加一个优化：pipelined `mul`，再记录 cycle。
7. 加 BHT/RAS，再记录 cycle。
8. 加 store forwarding，再记录 cycle。
9. 最后再考虑 2-wide issue。

评价标准不要只看“能不能跑”，要看每次优化后的 `cycle` 和 stall counter 是否真的下降。
