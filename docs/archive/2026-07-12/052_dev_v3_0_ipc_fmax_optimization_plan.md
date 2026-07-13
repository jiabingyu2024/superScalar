# dev-v3.0：顺序单发 RV32 核的 IPC/Fmax 优化方案

## 1. 文档目的

本文档定义 `dev-v3.0` 的优化方向。基线是当前分支 `dev-7-standby` 的顺序单发实现，以及工作树中已有的 ID-AGU、LS sidecar 和 DCache 重构改动。目标是在 Kintex-7 `xc7k325tffg900-2` 上取得：

- CPU 主频：250 MHz（4.000 ns 周期，最终 routed signoff 需要正裕量）；
- `srcWithMext` IPC：至少 0.80；
- RV32 directed tests、`srcSmoke`、`srcWithMext` 正确性不退化；
- 不引入没有精确顺序定义的通用乱序提交。

本文档只描述架构和实现计划，不把尚未对最新 RTL 重新实现的旧 routed 报告当作签核结果。

## 2. 当前证据与问题定位

### 2.1 性能证据

当前工作树中的 `build/result/src/srcWithMext.json` 给出 5M 周期采样：

| 指标 | 数值 | 解释 |
|---|---:|---|
| 周期 | 4,999,998 | 采样窗口 |
| commit | 3,724,895 | 动态退休指令数 |
| IPC | 0.744979 | 当前采样，不代表最终 routed 版本 |
| frontend stall | 1,419,637 | 前端/后端阻塞合计桶 |
| load return block | 396,524 | load 返回阻塞 |
| load access block | 447,247 | 访存入口阻塞 |
| Mul/Div busy | 741,540 | 可能与内存 stall 重叠 |
| DCache miss | 77,012 / 1,811,614 | miss rate 约 4.25% |
| branch miss | 2,827 / 109,119 | miss rate 约 2.59% |

从 IPC 0.744979 到 0.8，只需减少约 344k 个周期。分支预测不是首要收益点；即使每次 branch miss 少一拍，理论上也只节省约 2.8k 周期。

### 2.2 时序证据

旧的 200 MHz routed 报告 `fpga/build/digital_twin_srcWithMext_200.000MHz/reports/timing_summary_200.000MHz.rpt` 中：

- `clk_out2_pll` WNS：`-1.708 ns`；
- 最差路径数据延迟：`6.655 ns`；
- 逻辑延迟：`2.166 ns`；
- 布线延迟：`4.489 ns`，占 67.45%；
- 路径是 C1 结果/操作数到 C0 AGU 的反馈，23 个逻辑级。

因此 250 MHz 不能靠少几个 LUT 完成，必须消除跨物理区域的反馈、宽前递总线和异步分散 RAM。

## 3. dev-v3.0 目标微架构

保持单发射，但把后端明确拆成局部数据通道：

```text
       C0: decode/RF/AGU
              |
       +------+----------------+
       |                       |
 C1-EX: ALU/branch/M        C1-LS: BRAM cache/LSU
       |                       |
       +----------+------------+
                  v
       ordered completion gearbox (2 entries)
                  |
       C2: one architectural RF write per cycle
```

关键原则：

1. C1-EX 不能把通用 ALU 结果组合反馈到 C0 AGU；
2. C1-EX 和 C1-LS 可以同拍完成，但通过有序结果队列解决单写口冲突；
3. miss、store 和 Mul/Div 等长延迟操作使用局部 holding register，不把 busy 信号扩散到整个核心；
4. 所有可能改变架构状态的结果仍按程序顺序进入 C2。

## 4. P0：必须优先实现的结构改动

### 4.1 两入口 ordered completion gearbox

当前 `core.sv` 在 `ls_wb_valid` 时冻结 C1，以避免 load 和 EX 结果同时争用单个写回口。这会把本来可以重叠的后端工作变成结构停顿。

新增 2-entry 有序完成队列，每项至少包含：

```text
{valid, age/order, rd, data, write_enable, side_effect_kind}
```

设计要求：

- C1-EX/C1-LS 最多同时各写入一项；
- 队列按指令年龄出队，每拍最多写 RF 一次；
- branch kill 只能清除尚未提交且年龄更大的项；
- store、CSR、trap 不得绕过完成顺序；
- 队列满时才冻结前端。

预期收益是消除 load 后紧邻普通 ALU 的单拍写回冲突。它只增加少量寄存器和局部 mux，通常比双写 RF 更适合 FPGA 布线。

### 4.2 正沿寄存器堆与数据免复位

当前 `rtl/core/id/regfile.sv` 在下降沿写入，并对全部 32 个寄存器异步清零。这同时造成半周期时序、RAM 推断受限和高扇出 reset。

改造要求：

- 改为正沿写入；
- 用现有 WB-to-ID 显式旁路解决同拍读写；
- rs1/rs2 使用两份复制的 32x32 LUTRAM 或等价分布式结构；
- 只复位控制/valid，不清零数据阵列；
- x0 由读端 mux 固定为零。

验收重点是 RF 到 C0 AGU 的 routed 路径，以及 reset recovery 违规是否消失。

### 4.3 同步 BRAM sector DCache

当前 DCache 数据阵列采用分散的 byte-bank LUTRAM，并按 4-word line refill。dev-v3.0 改为：

- `1024 x 32` 数据 RAM，优先推断 `RAMB36E1`；
- tag 与 valid 独立存放；
- 每个 word 一个 valid bit，采用 word/sector valid；
- miss 只请求 critical word；
- 其余 word 只做非阻塞预取，不阻塞下一次合法访存；
- hit 路径为 C0 地址寄存、C1 BRAM 输出、C2 格式化/写回；
- store hit 使用 BRAM byte write-enable。

这项改动同时降低 LUTRAM 布线、cache hit 的组合路径和整行 refill 的访问阻塞。必须明确外部 DRAM 的 single-outstanding ready/valid 契约，不能用“背景填充”掩盖请求重复或丢失。

### 4.4 语义化 AGU 旁路

不恢复全宽 `EX -> AGU` 旁路。只对可证明的地址生成模式开放短旁路：

- `ADDI rd, rs1, imm1` 后紧邻 `load/store ..., imm2(rd)`；
- `LUI/AUIPC` 生成地址基值；
- 必要时加入编译器常见的指针递增模式。

旁路计算应使用保存的基值和立即数合并，避免经过通用 ALU 结果 mux。路径目标是“一条本地 CARRY4 链 + 地址寄存器”，不是把 32-bit ALU、前递 mux、AGU 串起来。

## 5. P1：IPC 和资源的定向优化

### 5.1 2-entry write-through StoreBuffer

Store 先写入 `{addr, data, mask, uncached, age}`，由独立小队列等待外部 ready。load 必须检查队列中的同地址/同字节覆盖并完成 store-to-load forwarding；MMIO 和 fence 仍按顺序排空。

StoreBuffer 满或存在未解决的顺序冲突时才阻塞 C0。不要让每个普通 store 都把 C1/前端冻结。

### 5.2 DIV/REM 配对结果缓存

现有除法器一次计算并输出 quotient 和 remainder。增加一个最近结果项：

```text
{valid, rs1, rs2, signed_mode, quotient, remainder}
```

当相邻或短距离的 `DIV/REM` 使用相同操作数时，第二条直接一拍返回。必须在 flush、异常和操作数符号模式变化时使缓存失效。该优化对通用 ISA 不改变结果，只减少重复 34 拍等待。

### 5.3 单乘法器覆盖四种 RV32M 乘法

当前 `m_unit` 实例化 signed/signed、signed/unsigned、unsigned/unsigned 三套乘法器。用带可选符号扩展的单个 33x33 signed multiplier 覆盖 `MUL/MULH/MULHSU/MULHU`，再按操作选择低/高 32 位。目标是减少 DSP 列周围的拥塞和乘法结果的长距离 mux；延迟保持 3 拍不变。

### 5.4 Mul shadow window

若 3 拍 MUL 占据全局 front stall，可增加 2-entry 的有序完成窗口，让独立整数指令继续执行；DIV 仍保持冻结或使用更深的结果队列。不得在没有年龄/异常规则的情况下直接允许结果乱序写架构 RF。

## 6. Fmax 专项实现

### 6.1 物理分区

- IROM、PC、BTB 放在相邻的 BRAM/CLB 区域；
- RF、AGU、整数 EX 放在同一时钟区域；
- DCache 紧邻 BRAM 列和 DRAM bridge；
- Mul 单元紧邻 DSP 列；
- 跨区域只传寄存后的窄接口，不传全宽组合 WB/bypass 网络。

Pblock 只约束大模块边界并保留约 20% 空白，不做逐 cell LOC。让 `phys_opt_design` 负责高扇出复制和局部重布线。

### 6.2 控制和复位

- 统一使用正沿时钟；
- 采用同步 reset release；
- 数据阵列不复位；
- valid、kill、hold 使用局部寄存副本；
- 避免同一寄存器同时拥有多种 reset/CE control set；
- 不用 false path 掩盖真实 CPU 数据路径，只对 CDC/reset recovery 进行明确约束。

### 6.3 预测器

BPU 主要为 Fmax 服务，而不是 IPC 主收益。可把 BTB/tag/counter 改为同步读，预测元数据与 IROM 请求同拍索引，下一拍与指令对齐。这样可切断 `BPU -> PC mux -> IROM address` 的组合环；branch miss 率变化必须单独测量。

## 7. 实施顺序

1. 建立当前 RTL 的 RV32、`srcSmoke`、`srcWithMext` 基线和 perf counter 快照；
2. 修改 RF 为正沿写、数据免复位，跑 directed tests 和 200/250 MHz 综合；
3. 加 ordered completion gearbox，验证 load/EX 同拍完成、flush 和 CSR 顺序；
4. 实现 sector DCache，先关闭预取，仅验证 critical-word miss；
5. 加 StoreBuffer 和 store-to-load forwarding；
6. 加语义 AGU 旁路，按动态命中次数决定是否扩大模式集合；
7. 优化 M 单元和 DIV/REM cache；
8. 最后做 BPU 同步化、pblock 和 phys-opt 探索。

每个阶段都必须保留前一阶段可回退的配置开关，避免 IPC、功能和时序问题混在一次提交中。

## 8. 验收门槛

### 功能

- `make sim-rv32-all NO_BUILD=1` 全部通过；
- `srcSmoke` 完成预期 checker，不以 timeout 作为通过；
- `srcWithMext` 的 RV32I/MEXT 计数、LED/SEG 结果一致；
- 随机覆盖 load-use、store forwarding、DCache miss/replay、branch kill、CSR/trap、DIV/REM 配对。

### 性能

- 5M 和长窗口分别记录 commit、IPC、frontend stall、DCache hit/miss、load/store 阻塞、Mul/Div busy；
- IPC 目标为 `>= 0.80`，并说明收益来自哪类 stall；
- DCache hit 请求不能因同步 BRAM 退化成每条 load 一个额外 bubble；
- StoreBuffer 不得改变 MMIO 顺序。

### 时序

- 250 MHz routed WNS `>= 0.0 ns`，建议保留至少 0.15 ns 裕量；
- setup、hold、pulse width、reset recovery 均通过；
- 报告最差 20 条路径，确认不再出现 C1-ALU/C2-WB 到 C0-AGU 的长反馈；
- 统计高扇出网络、RAM/DSP 位置和关键路径 route/logic 比例。

## 9. 明确不采用的方向

- 不用大规模通用 forwarding crossbar；
- 不用双边沿时钟作为 250 MHz 的主要手段；
- 不用 multicycle/false-path 约束隐藏真实数据依赖；
- 不为 branch miss 率约 2.6% 的小收益牺牲 EX 时序；
- 不直接扩展成完整 OoO/ROB，除非上述局部 elastic 结构仍无法达到目标。

## 10. 当前状态说明

`dev-v3.0` 是从 `dev-7-standby` 当前工作树创建的本地分支。工作树原有未提交修改被保留。现有 200 MHz routed 报告对应历史实现；在完成本计划的 P0 改动后，必须重新生成 synthesis/place/route 报告，才能判断 250 MHz 是否真正达标。

## 11. 2026-07-12 第一轮实施结果

### 11.1 已实施 RTL

- `regfile.sv` 改为正沿单写，两个异步读端使用镜像 distributed RAM，payload 不复位，x0 继续由读端固定为零；
- `stage_id.sv` 删除第二写口，恢复单一架构写回接口；
- `core.sv` 增加两项 ordered completion gearbox，按 `pending -> LS -> EX` 的年龄顺序每拍写回一个结果；
- C0、C1 和 LS pending operand 都能从当前 EX、当前 LS、gearbox 新旧项中选择最新匹配值；
- 增加 Verilator-only gearbox overflow 检查；
- DCache store-hit 更新先写入本地 update register，下一拍驱动 LUTRAM WE；
- 连续 store 可每拍滚动更新，load 与 pending store 同 word 时按 byte mask 前递合并，避免为 cache update 插入固定 bubble。

### 11.2 仿真回归

最终 RTL 的 Verilator 结果：

| 回归 | 结果 |
|---|---|
| myCPU model build | PASS |
| student_top/src model build | PASS |
| RV32 directed 全套 | 全部 PASS，覆盖 RV32I/M/Zb/CSR/trap/load/store/branch |
| `srcWithMext`, 5M cycles | RV32I=37，MEXT=8，fail=0 |
| `srcWithMext` IPC | `0.826769` |
| commit | 4,133,844 / 5,000,000 cycles |
| frontend stall | 856,415 cycles |
| load access block | 268,431 cycles |
| Mul/Div busy bucket | 587,984 cycles |

5M `srcWithMext` 以固定窗口结束，因此 JSON status 为 `TIMEOUT`；功能计数和 IPC 均达到本轮短窗口验收条件。

### 11.3 250 MHz routed 结果

最终报告：

```text
fpga/build/digital_twin_srcWithMext_250.000MHz/reports/
  timing_summary_250.000MHz.rpt
  utilization_routed_250.000MHz.rpt
  clock_utilization_250.000MHz.rpt
```

结果：

| 指标 | 数值 |
|---|---:|
| CPU clock | 250.000 MHz / 4.000 ns |
| routed WNS | `-3.892 ns` |
| routed TNS | `-19,995.914 ns` |
| setup failing endpoints | 11,278 / 19,688 |
| async reset/recovery WNS | `-3.157 ns` |
| async reset/recovery TNS | `-564.167 ns` |

store-hit `DCache RAM WE` 已不再是最差路径，证明 update register 成功切断旧路径。但 250 MHz 仍未签核，新瓶颈是：

1. `LS valid/依赖解析 -> DCache/SoC memory control -> external DRAM BRAM`，约 20/21 logic levels，数据路径约 7.35--7.50 ns；
2. `wbq1 rd tag -> LSU dependency/front stall -> IF/ID or LS register CE`，约 17 logic levels，数据路径约 7.45--7.69 ns；
3. DCache 仍映射为约 258 个 `RAM64M`，异步 tag/data lookup 和分散布线尚未消除；
4. CPU reset/recovery 网络仍未完成分域同步化。

### 11.4 阶段结论

第一轮已经达到 `IPC >= 0.8` 和全套 directed correctness，但未达到 250 MHz。下一轮不能继续做局部 LUT 化简，应直接实施：

- LSU pending operand 只在寄存边界解析，禁止 queue tag 同拍穿过 AGU/DCache/前端 CE；
- DCache/SoC request 增加 registered request slot 或 StoreBuffer，外部 BRAM enable/address 只由寄存器驱动；
- DCache 数据阵列改为同步 BRAM，并增加相应 load metadata stage；
- reset assertion/deassertion 按 CPU 时钟域同步化；
- 重新定义 load-use/LSU backpressure 后再跑一次完整回归和 routed signoff。
