# 本轮 IPC × Fmax 优化里程碑与 Zb 可扩展性审查

## 结论

本轮性能迭代在提交 `ebedcba` 后停止。正在运行的全量 Vivado
布局布线已按要求终止，因此 `ebedcba` 只有综合结果，没有最终 routed
结果。

本轮最有代表性的四个性能版本是：

1. `0faf8ec`：三项 oldest-ready IssueQueue。
2. `e9330e2`：提前执行 branch、提交时恢复，并将乘法缩短为两拍。
3. `6b9b214`：双端口 IROM 加相邻 move 宏融合。
4. `ebedcba`：近期 Store L0 前递、FetchQueue/预测器/分支比较时序重构。

静态审查没有发现上述版本在打开 Zb 配置后必然发生的功能错误，也没有
发现 Zb 配置、译码或执行单元在后续提交中被删除。四个版本的
`bitmanip_unit.sv` 与最初加入 Zb 的 `1d81adc` 完全相同；从
`0faf8ec` 到 `ebedcba`，`decoder.sv` 和 `core_config_pkg.sv` 的 Zb
内容也完全相同。

但是，当前不能把任何一个版本称为“Zb 已签核版本”：

- 六组 `CFG_ZB*` 当前全部为 0。
- 本轮所有 RV32IM、src 性能和 Vivado 数据都来自 Zb 关闭配置。
- 现有 `build/result/rv32/rv32uzb*.json` 中的 FAIL 来自关闭扩展后执行
  Zb 测试，不是启用 Zb 后的失败证据。
- 本轮没有逐组打开 Zba/Zbb/Zbc/Zbkb/Zbkx/Zbs 后重新构建并执行 39
  项 Zb directed test。

因此当前判断是：**RTL 接口和控制结构具备 Zb 可扩展性，未发现静态
阻断项；动态正确性和启用后的 Fmax 仍需单独签核。**

## Zb 配置和数据流现状

编译期配置位于 `rtl/core/pkg/core_config_pkg.sv`：

```systemverilog
CFG_ZBA
CFG_ZBB
CFG_ZBC
CFG_ZBKB
CFG_ZBKX
CFG_ZBS
```

译码路径位于 `rtl/core/decode/decoder.sv`。被启用的 Zb 指令产生
`FU_BITMANIP` uop；被关闭的 Zb 编码保留 illegal-instruction
exception，并被改送普通异常路径，避免等待一个被裁剪掉的执行单元。

执行路径位于 `rtl/core/execute/bitmanip_unit.sv`：

- Zba、Zbb、Zbkb、Zbkx、Zbs 的简单操作为一拍注册完成。
- Zbc 的 CLMUL/CLMULH/CLMULR 使用 32 次迭代。
- Bitmanip 与 MDU 共用 `slow_resp` 完成和唤醒端口。
- IssueQueue 对 `FU_BITMANIP` 有独立 ready 条件。
- branch full flush 会 kill 正在运行的 CLMUL。

DiffTest 的 RV32 参考模型覆盖六组配置，并从
`core_config_pkg.sv` 自动生成对应的 `REF_ZB*` 宏。单项 Zb 测试在对应
配置关闭时会被标记为 UNSUPPORTED；启用后才进入真正的提交级比较。

## 本轮性能版本

所有性能数字均为六组 Zb 关闭的 RV32IM 配置。

| 提交 | 核心变化 | 20M srcWithMext IPC | 时序阶段 | Fmax | IPC × Fmax |
|---|---|---:|---|---:|---:|
| `0faf8ec` | 三项 oldest-ready IQ，memory 保序，顺序提交 | 0.795558 | routed | 173.02 MHz | 137.65 |
| `e9330e2` | branch 提前执行、提交恢复；真实两拍 MUL | 0.856137 | routed | 164.86 MHz | 141.14 |
| `6b9b214` | 双端口 IROM；producer + `addi rd2,rd1,0` 宏融合 | 0.947182 | routed | 164.69 MHz | 约 156.0 |
| `ebedcba` | 近期 Store L0；前端和分支时序重构 | 0.950644 | synthesis | 158.55 MHz | 150.73 |

`6b9b214` 是本轮完成全量布局布线的最高性能版本。
`ebedcba` 是当前源码和综合乘积最好的版本，但其 full P&R 被停止，不能
用综合乘积和 `6b9b214` 的 routed 乘积直接下最终结论。

`bf4e2e1` 也属于本轮提交，但它只加强 Vivado IP/时序结果有效性检查，
没有形成新的 CPU 性能版本。

### `0faf8ec`：真正的 oldest-ready IssueQueue

这个版本把原来的一项 `id_uop` 改成三项固定槽 IssueQueue。ready
的年轻非 memory 指令可以绕过未 ready 的老指令，memory 仍按程序顺序
发射，所有指令仍按 scoreboard 头顺序提交。

对 Zb 的正面影响：

- `FU_BITMANIP` 是正式的 IQ 资源类型，不再依赖单项 ID 停顿。
- fixed、load、slow 三种完成都能唤醒 Zb 的两个源操作数。
- Zba/Zbb 等结果可继续唤醒普通 ALU、load/store 地址和 branch。
- CLMUL 可在后台迭代，年轻的独立普通指令仍可执行。

需要验证的风险：

- MDU 与 Bitmanip 共用一个 `slow_resp` 端口。当前 ready/busy 互锁从
  结构上阻止两者同拍返回，但没有专门的“两个 response 不得同时
  valid”断言。
- 必须覆盖 `Zb -> load/store address`、`load -> Zb`、`Zb -> branch`
  和多个 transaction ID 环绕时的唤醒。
- CLMUL 被更老 branch mispredict 或 exception flush 时，需要确认旧
  response 不会在新 transaction ID 周期中重新出现。

风险等级：低到中。未发现静态错误，主要缺口是启用配置后的动态覆盖。

### `e9330e2`：提前 branch 与两拍 MUL

branch 在操作数 ready 后可以提前执行，但 redirect/full flush 仍在该
branch 到达提交头时发生。这样保留顺序精确状态，同时减少 branch 在
提交头等待执行的空泡。

对 Zb 的交叉影响：

- branch 可以等待 Zb 或 CLMUL 结果后提前执行。
- 更老的 CLMUL 未完成时，年轻 branch 可以先产生 outcome，但不能提前
  改变架构 PC。
- branch mispredict 到提交头后，full flush 会同时清 IQ、scoreboard、
  execute 和 Bitmanip 迭代状态。
- 两拍 MUL 没有改变 Bitmanip 数据格式，但提高了 MDU/Bitmanip 共用
  完成端口的交互密度。

需要验证的风险：

- 更老 CLMUL、年轻 branch，以及更老 branch、年轻 CLMUL 两种顺序都
  应有定向测试。
- MDU response、简单 Zb response、CLMUL response 的相邻周期组合必须
  检查，防止共享 `slow_resp` 选择遗漏。
- 当前 predictor 可在 branch 执行时训练，即使该 branch 后来被更老
  异常冲掉也可能留下预测器状态。这不改变架构正确性，但会影响可重复
  的性能结果。

风险等级：中等验证风险，未发现架构状态错误。

### `6b9b214`：双端口取指与相邻 move 宏融合

该版本识别：

```text
任意合法、非控制、写 rd1 的 producer
addi rd2, rd1, 0
```

两个架构指令获得两个连续 scoreboard 项，但只有 producer 进入 IQ。
producer 完成时，move 项复制同一结果，然后两条指令仍逐条顺序提交。

这是与 Zb 交叉最多的版本：

- 前端的 producer 粗分类包括 OP 和 OP-IMM，因此合法 Zb 可以成为
  producer。
- dispatch 端再次检查 `decoded_uop.exception_valid`。被关闭的 Zb
  编码虽然可能通过前端粗分类，但不会真正触发宏融合。
- fixed、load、slow 三类 completion 都实现了 move alias；简单 Zb 和
  CLMUL 都走 slow completion，因此结构上已经覆盖。
- `addi rd2,rd1,0` 是精确复制，不依赖 producer 的运算类别，Zb 结果
  复制在语义上成立。

需要验证的高价值边界：

1. 每个 Zb 组至少选一条 producer，后接 move。
2. CLMUL producer 后接 move。
3. producer 的 rd 与 move 的 rd 相同。
4. producer/move 跨 scoreboard transaction ID 末尾环绕。
5. move 后立刻有消费者，并分别覆盖 fixed/load/branch/Zb 消费者。
6. move 的 rd 随后又被更年轻指令覆盖，确保 producer map 不被旧
   completion 错误改回。

静态审查未发现宏融合对 Zb 的必然错误。这里是本轮最需要新增 directed
test 的位置，因为普通 Zb directed test 通常不会自然生成这种相邻序列。

风险等级：中等。风险来自新快路径覆盖不足，不是已发现的功能缺陷。

### `ebedcba`：近期 Store L0 和时序重构

该版本的近期 Store L0 只记录已经提交并被接受 drain 的 cacheable
store；pending StoreBuffer 字节始终覆盖 L0 字节。预测器 collision
forwarding、固定头 FetchQueue 和 branch miss 比较重构保持原有行为。

与 Zb 的直接耦合很小：

- L0 位于 load forwarding 元数据路径，与指令编码无关。
- Zba 计算出的 load/store 地址仍通过 IQ slow wakeup 和 AGU，未绕开
  地址依赖。
- FetchQueue 搬运完整 `fetch_entry_t`，包括宏融合字段，没有按 opcode
  裁剪 Zb。
- branch 比较重构只使用 branch uop，不改变 Zb 结果的产生和旁路。

需要验证：

- Zba/Zbb 结果作为近期 Store L0 load 的地址或 store data。
- Zb -> branch 和 load -> Zb -> branch 依赖链。
- Zb producer + move 宏融合与 recent-store load 同时活跃。

风险等级：低。新增 L0 和时序重构没有发现 Zb 特有的正确性风险。

## 全局风险清单

### 1. 当前最大风险是“未启用实测”，不是已知 RTL bug

所有六组开关仍为 0。关闭配置下 RV32IM 52/52 PASS 只能证明 Zb 逻辑被
裁剪时不破坏基线，不能证明打开后的行为。

### 2. 性能和时序结果不能直接外推

Bitmanip 简单操作包含 CLZ/CTZ/CPOP、rotate、xperm 和较宽的结果选择。
打开不同组后，综合器会保留不同组合逻辑。即使功能正确，新的最坏路径
也可能转移到：

```text
IQ operand -> bitmanip simple_result -> response register
```

因此每个计划使用的配置都必须重新综合；只打开实际需要的组，不能用
RV32IM 的 Fmax 代替 Zb 配置的 Fmax。

### 3. 共享 slow completion 依赖结构互斥

当前 MDU 和 Bitmanip response 用 OR/优先选择合并。控制逻辑按 busy、
当前 exec 类型和 CLMUL start 互锁，静态上没有看到冲突窗口，但建议增加
仿真断言：

```systemverilog
assert (!(mdu_resp_valid && bm_resp_valid));
```

同时覆盖连续的简单 Zb、MUL、简单 Zb，以及 CLMUL 前后紧邻 M 指令。

### 4. Zbb 与 Zbkb 的重叠编码

`pack rd,rs1,x0` 与 `zext.h` 结果相同。当前同时打开 Zbb/Zbkb 时 decoder
优先选择 PACK，结果语义仍一致，不构成功能错误。仍应把
`CFG_ZBB=1, CFG_ZBKB=1` 作为组合配置单独测试，避免未来增加侧带分类后
出现差异。

### 5. 配置结果需要可追溯

当前配置是 package 内 localparam，不是顶层 parameter。切换配置后必须
重新构建仿真模型，并在结果中记录六个开关值。否则很容易把关闭配置的
旧二进制或旧报告误认为启用配置结果。这是结果可信度风险，不是编译策略
优化方向。

## 建议的 Zb 签核矩阵

若后续需要正式启用 Zb，最低签核顺序如下：

1. 分别单开 Zba、Zbb、Zbc、Zbkb、Zbkx、Zbs，运行对应 directed test。
2. 单开配置下同时运行 RV32IM 52 项，证明扩展不会破坏基线。
3. 运行 `Zbb + Zbkb` 和“实际比赛所需全部组”的组合配置。
4. 对实际组合运行提交级 DiffTest，而不只检查 tohost。
5. 增加本轮架构专用序列：
   - Zb producer + move；
   - CLMUL producer + move；
   - load -> Zb；
   - Zb -> load/store address；
   - Zb -> branch；
   - branch flush 正在运行的 CLMUL；
   - MDU 与 Bitmanip response 相邻周期；
   - transaction ID 环绕。
6. 完成 srcSmoke/srcWithMext 回归，确认实际软件打开 Zb 后没有意外改变
   trap 或控制流。
7. 对实际 Zb 组合重新综合并导出全部负时序路径。

## 最终版本选择建议

- 需要已完成 routed 证据时，使用 `6b9b214` 作为本轮最强、最完整的
  性能基线。
- 需要继续开发时，使用 `ebedcba`。它包含更高 IPC 和更好的综合乘积，
  但必须补做 full P&R。
- 需要启用 Zb 时，不应直接宣称上述任一提交已经签核。建议从
  `ebedcba` 开始，先完成上述 Zb 动态矩阵，再评估启用后的实际
  IPC × Fmax。

本轮停止时，没有继续进行编译策略或 Vivado directive 搜索；后续若恢复
工作，优先级应是 Zb 动态正确性签核和真实结构时序，而不是工具参数微调。
