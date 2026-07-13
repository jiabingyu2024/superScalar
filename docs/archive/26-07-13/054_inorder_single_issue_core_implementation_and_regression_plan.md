# 顺序单发射 Core：RTL 重写、框架迁移与回归测试计划

> 配套架构：[`053_superscalar_framework_inorder_single_issue_core_architecture.md`](./053_superscalar_framework_inorder_single_issue_core_architecture.md)。
> 任务范围：后续删除旧 `rtl/core/` 实现和 `rtl/include/`，保留并重写 `rtl/core/myCPU.sv`，按 053 架构实现新 Core；保留现有 SoC、TB、FPGA 框架。
> 本文是执行计划，不代表 RTL 已经删除或新 Core 已经完成。
> 日期：2026-07-13。

## 0. 最终交付物和成功标准

### 0.1 交付物

1. 新的 `rtl/core/` 目录、package、六级顺序单发射 Core、Scoreboard、LSU、Store Buffer、DCache、MDU、CSR/Commit 和性能计数。
2. 保持外部端口兼容但内部已重写的 `rtl/core/myCPU.sv`。
3. 不再存在的旧 `rtl/include/cpu_defines.svh`；新 RTL 不依赖全局宏 include。
4. 更新后的 `scripts/filelists/core.f`、Verilator build 脚本和 Vivado compile-order/include 设置。
5. 两个 Verilator DUT 均可构建：`myCPU` 和 `student_top`。
6. RV32I/RV32M/当前 RV32MI 子集、`srcSmoke`、`srcWithMext` 严格 PASS 的结果 JSON 和日志。
7. 新架构的断言、性能计数和关键波形诊断能力。
8. 最终实现记录：改动文件、回归命令、结果、剩余非目标和 FPGA 时序结果。

### 0.2 功能完成门槛

| 类别 | 必须达到的结果 |
|---|---|
| Verilator build | rv32/myCPU 和 src/student_top 两个 build 均成功 |
| RV32I | `data/rv32ui` 40 项全部 PASS |
| RV32M | `data/rv32um` 8 项全部 PASS |
| RV32MI | `data/rv32mi` 4 项全部 PASS |
| srcSmoke | checker=`ledonly`，观察到 `0x01221c08`，status=PASS |
| srcWithMext | PASS marker + lamp mask `0x03030303` + RV32I count 37 + M/Z count 8 |
| 精确状态 | assertion 无 transaction ID、flush、store commit、late response 违例 |
| 单发架构 | `commit_count <= cycle_count`，稳态 IPC 不可能超过 1 |
| FPGA 集成 | `srcSmoke/srcWithMext` profile 均能创建 Vivado 工程，源文件/IP 端口无失联 |

### 0.3 `sim-rv32-all` 的特殊说明

当前 `make sim-rv32-all` 会扫描所有 `data/rv32*`，除 RV32I/M/MI 外，还包含 Zba/Zbb/Zbc/Zbkb/Zbkx/Zbs 共 39 项。053 第一版明确不实现 bitmanip，所以不能把 91 项 `sim-rv32-all` 全绿作为 RV32IM 的完成门槛。

后续应新增明确目标：

```make
sim-rv32-base:
	$(MAKE) sim-rv32 SUITE=rv32ui ...
	$(MAKE) sim-rv32 SUITE=rv32um ...
	$(MAKE) sim-rv32 SUITE=rv32mi ...
```

`sim-rv32-all` 仍要运行并保存 summary，用来确认预期失败只来自未实现 Zb suite；不能把 Zb FAIL 混入 RV32IM 回归结论，也不能把它们静默过滤成 PASS。

## 1. 执行原则

1. **先记录基线，再删除。** 当前 RTL 即使存在问题，也要保存 build/result/log，避免重写后无法判断是新 bug 还是旧框架问题。
2. **`myCPU` 只保留端口合同，不保留旧内部结构。** 旧 `core + 特殊 DCache index` 连接会被整体替换。
3. **每个阶段保持可构建。** 不把前端、Scoreboard、LSU、CSR、DCache 一次性写完再第一次编译。
4. **先静态/定向，后长回归。** `srcWithMext` 最长可达十亿级周期，不能用于每个小改动的首轮定位。
5. **正确性先于预测和 cache 性能。** 先用 always-not-taken/uncached service 验证架构状态，再打开 predictor/DCache；最终版本必须实现 053 全部结构。
6. **所有 late response 先解决 kill/drain。** 不接受“测试暂时没撞到”的 transaction ID 复用漏洞。
7. **不修改 SoC/TB checker 来迁就 Core bug。** 除 filelist/build 适配外，PASS/FAIL 规则保持不变。
8. **FPGA IP 与 Verilator IP 模型双合同。** 对 MUL/DIV/IROM/DRAM 的任何时序决定都要在两条路径一致。

## 2. 阶段 0：冻结现状和基线

### 2.1 只读清点

执行并归档：

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git ls-files rtl/core rtl/include scripts/filelists
```

单独记录：

- `rtl/core/myCPU.sv` 的正式端口与 `VERILATOR_TB` 条件端口。
- `rtl/soc/student_top.sv` 的实例连接。
- `scripts/run_verilator.py` 中 `+incdir+rtl/include`。
- `fpga/create_vivado_project.tcl` 中 include dir、package 排序和 MUL/DIV IP 配置。
- `SocMemBridge/DramBramAdapter/IROM_0` 的 command/response 时序。

退出标准：可以在不查看旧 Core 内部实现的情况下，完整写出新 `myCPU` 外部合同。

### 2.2 当前版本基线

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=

make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=

make sim-src TEST=srcSmoke SRC_MAX_CYCLES=100000000 NO_BUILD=1 OBJCACHE=
make sim-src TEST=srcWithMext MAX_CYCLES=1200000000 NO_BUILD=1 OBJCACHE=
```

如果当前版本本身不全绿，记录实际 PASS/FAIL/TIMEOUT、首个失败测试和 JSON，不在基线阶段修旧 Core。基线的价值是证据，不是强行制造绿色起点。

需保存的输出：

```text
build/log/build_mycpu.log
build/log/build_student_top.log
build/log/rv32/*.log
build/log/src/*.log
build/result/rv32/*.json
build/result/src/*.json
```

## 3. 阶段 1：目录替换与空框架恢复构建

### 3.1 删除范围

后续实际执行时：

- 删除 `rtl/core/` 下除 `rtl/core/myCPU.sv` 之外的全部旧文件和子目录。
- 删除整个 `rtl/include/`。
- 保留 `rtl/ip/`、`rtl/soc/`、`tb/`、`data/`、`fpga/`。
- `myCPU.sv` 保留文件路径和端口列表，模块体立即重写；不能让它在删除后长期引用不存在的 `core`/`DCache`。

删除前若发现未提交用户修改，先列出并确认范围；不能用 reset/checkout 覆盖用户工作。

### 3.2 首批创建文件

```text
rtl/core/myCPU.sv
rtl/core/core_top.sv
rtl/core/pkg/core_config_pkg.sv
rtl/core/pkg/core_types_pkg.sv
rtl/core/common/fifo.sv
rtl/core/common/skid_buffer.sv
```

`core_config_pkg` 先只放冻结参数和静态宽度；`core_types_pkg` 先放 `fetch_entry_t/uop_t/scoreboard_entry_t/completion_t`。不要为了“以后可能用”一次定义大量无消费者类型。

### 3.3 构建系统同步修改

#### `scripts/filelists/core.f`

按依赖顺序显式列文件：package → common → leaf → subsystem → top → myCPU。禁止使用递归 glob，避免旧备份/实验模块被意外编译。

#### `scripts/run_verilator.py`

删除硬编码 `+incdir+rtl/include`。如果新代码没有 `.svh`，不需要增加新 incdir；package 由 filelist 编译顺序解决。

#### `fpga/create_vivado_project.tcl`

- 将 `core_config_pkg.sv/core_types_pkg.sv` 加入优先 compile-order 名单。
- 删除或改写 `rtl/include` include_dirs。
- 保持真实 `MUL_0/DIV_0/IROM_0/DRAM_0` IP 配置不变。
- 保持 FPGA filelist 禁止加入 `rtl/ip/*.sv` 行为模型的检查。

退出标准：两个 Verilator build 都能解析空框架和端口；允许 Core 暂时只保持 reset/无请求，但不得有 dangling module、重复 package、implicit net 或 latch warning。

## 4. 阶段 2：Frontend、Decode 与最小顺序 ALU 闭环

### 4.1 文件

```text
frontend/frontend.sv
frontend/fetch_queue.sv
decode/decoder.sv
decode/imm_gen.sv
issue/regfile.sv
issue/scoreboard.sv
issue/raw_resolver.sv
issue/issue_stage.sv
execute/alu.sv
execute/branch_unit.sv
execute/fixed_execute.sv
execute/completion_arbiter.sv
commit/commit_stage.sv
control/recovery_ctrl.sv
```

### 4.2 实现顺序

1. Frontend 先做 always-not-taken：固定 `pred_next_pc=pc+4`，实现 IROM pending metadata 和 4 项 Queue。
2. Decode 支持 LUI/AUIPC、OP-IMM、OP、JAL/JALR/Branch 和 illegal exception。
3. Regfile 只接受 Commit 写口。
4. Scoreboard 实现 8 项 allocate/fixed completion/single commit，不接 LSU/MDU。
5. RAW 第一版就支持多个 WAW 和 pointer wrap，不能先写错误的“任意同 rd 就取最低 index”。
6. Fixed Execute 实现 ALU、branch resolve 和 completion bypass。
7. Recovery 实现 reset/trap placeholder/branch miss 的优先级，branch miss 同拍屏蔽 allocation。
8. Commit 实现普通 GPR write 和 branch/JAL/JALR link write。

### 4.3 必写定向场景

- 相邻 `ADD → SUB` RAW 零气泡。
- 两次写 x5 后消费者读取第二个 x5。
- scoreboard pointer 至少绕回两圈。
- branch miss 时 ID 当前 uop 不得 allocate。
- JALR bit0 清零，link 为 `pc+4`。
- x0 读 0、写忽略、无 RAW。

### 4.4 阶段回归

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32ui-p-simple NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-add NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-addi NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-jal NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-jalr NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-beq NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-bne NO_BUILD=1 OBJCACHE=
```

由于 riscv-tests 最终通过通常需要 store tohost，本阶段可能在功能主体正确后仍 TIMEOUT；此时用波形确认控制流到达 test pass 路径，真正 PASS 留到 Store 实现阶段。不能把 TIMEOUT 写成 PASS。

## 5. 阶段 3：LSU、Store Buffer 与无缓存数据通路 bring-up

### 5.1 文件

```text
memory/load_queue.sv
memory/store_buffer.sv
memory/memory_unit.sv
```

这一阶段先通过 `memory_unit` 的 uncached/aligned-word service 接现有 dmem，不打开 DCache array；最终阶段 6 替换为完整 DCache。这样可以把“ISA/顺序/forwarding bug”和“cache refill bug”分开。

### 5.2 实现任务

1. AGU 生成 `rs1+imm`、size、original address、raw store data/mask。
2. misaligned 检测在任何 external request 前完成。
3. 2 项 Load Queue 保存 `{trans_id,addr,size,unsigned,forward_mask/data}`。
4. 4 项 Store Buffer 保存 speculative/committed 状态、scoreboard/store slot 对应关系和 8-bit `store_seq`。
5. Store completion 表示“已入 Store Buffer”，不是“已写外部”。
6. Commit handshake 后 Store 才能 drain；external handshake 后才释放 buffer head。
7. Load 入队时保存 `store_seq_cutoff`，只扫描 cutoff 之前的 older store，实现 full/partial byte forwarding 和 youngest-byte-wins；不得把等待期间后来入队的年轻 store 转发给老 load。
8. External read 一律发 aligned word 地址，load extension 只做一次。
9. MMIO/uncached load 等到自身为 scoreboard head且老 store 排空。
10. 实现 read kill/drain；flush 时清未发 load，已发 read 等 response 后丢弃。
11. Store Buffer forwarding 只用于 cacheable memory；MMIO/uncached load 排序后真实访问设备，不以 forwarding 代替设备读。

### 5.3 定向场景

| 场景 | 预期 |
|---|---|
| SB/SH/SW 后同地址 LB/LH/LW | 从 Store Buffer 获得新值 |
| 两条 store 覆盖一个 load 的不同 byte | 多项 merge 正确 |
| partial forwarding | memory old bytes + store new bytes 合并正确 |
| load 等待时年轻 store 入队 | load 不得看到年轻 store 的 byte |
| store 未 Commit 时发生 trap | 不产生外部 write |
| store 已 Commit、随后 flush | 仍继续 drain，不丢失 |
| load outstanding 时 full flush | 迟到 response 被丢弃，不写新 transaction ID |
| `dmem_req_ready=0` | request payload 全程稳定 |
| LB/LH at nonzero word offset | 不发生双移位 |

### 5.4 阶段回归

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lb NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lbu NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lh NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lhu NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-lw NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-sb NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-sh NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-sw NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-ld_st NO_BUILD=1 OBJCACHE=
make sim-rv32 TEST=rv32ui-p-st_ld NO_BUILD=1 OBJCACHE=
```

完成 Store 后，阶段 2 的 simple/ALU/branch 测试应首次能通过 tohost 正式 PASS。

## 6. 阶段 4：CSR、同步异常、FENCE 与精确恢复

### 6.1 文件

```text
commit/csr_file.sv
commit/commit_stage.sv
control/recovery_ctrl.sv
decode/decoder.sv
```

### 6.2 实现任务

1. 实现 `mstatus/mtvec/mscratch/mepc/mcause/mtval/mhartid`；`misa` 固定为 `0x4000_1100`；`cycle/cycleh/instret/instreth` 为只读真实计数。
2. CSR/System 全部走 serialize gate：scoreboard 空才分配，提交前不发后继。
3. CSR read-modify-write 在 Commit 原子完成，旧值写 rd。
4. 实现 ECALL cause 11、EBREAK cause 3、illegal cause 2、load/store misaligned 4/6。
5. trap 更新 CSR 后 full flush，redirect `mtvec.base`。
6. MRET 更新 mstatus，redirect mepc。
7. FENCE 等 memory quiescent；FENCE.I 再清 frontend。
8. trap/MRET/FENCE.I redirect 覆盖 branch miss。
9. full flush 通知 LSU/MDU kill/drain，并只删除 speculative stores。
10. Decode 已确定的 exception/CSR/System uop 分配时直接成为可提交控制项，不得启动 ALU/LSU/MDU 副作用。

### 6.3 容易误判的 CSR 边界

- `rv32mi-p-zicntr` PASS 只证明当前测试合同，不等于完整 counter CSR。
- 非白名单 CSR 读 0/写忽略是项目子集，不应在注释中宣称 privileged spec 完整。
- 外部无 access-error，不能实现虚假的 load/store access fault。
- `FENCE.I` 无 ICache，只做序列化和前端 flush。

### 6.4 阶段回归

```bash
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
```

失败定位顺序：先看 `mepc/mcause/mtvec`，再看 redirect PC，再看 scoreboard/store flush，最后才看 checker。

## 7. 阶段 5：RV32M 与不可取消 IP 的 drain

### 7.1 文件

```text
execute/muldiv_unit.sv
execute/completion_arbiter.sv
```

### 7.2 实现任务

1. 只例化一个 `MUL_0` 和一个 `DIV_0`；MDU 总体一次一个 in-flight 操作。
2. MUL 使用 33-bit signed extension 覆盖 ss/su/uu，3 拍 metadata 同步。
3. DIV 用 unsigned IP；保存原始符号、绝对值、op、transaction ID。
4. 解包固定为 `div_raw[63:32]=quotient`、`[31:0]=remainder`。
5. 处理除零和 signed overflow。
6. MDU result 进入 hold register，与 LSU result 按 transaction age 仲裁。
7. full flush 将在途 M 请求置 killed；等待真实 output valid 后丢弃，期间 `mdu_ready=0`。
8. branch mispredict 不取消 branch 之前的老 M 请求。

### 7.3 定向场景

- MUL/MULH/MULHSU/MULHU 的符号组合。
- DIV/DIVU/REM/REMU 正负、除零、`0x80000000/-1`。
- DIV 等待期间连续无依赖 ADD 可 Issue/完成。
- 依赖 DIV 的下一条在 Issue stall，后面的独立指令也不能越过。
- DIV 和 load 同拍完成时两者都不丢。
- DIV 在途 full flush，旧结果不得写复用槽。

### 7.4 阶段回归

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
```

只有 8 项 RV32M 全部 PASS，才能进入 srcWithMext；不能用某一个 `mul` PASS 推断 DIV Vivado/Verilator packing 正确。

## 8. 阶段 6：正式 DCache

### 8.1 文件

```text
memory/dcache_data_bank.sv
memory/dcache.sv
memory/memory_unit.sv
```

### 8.2 增量实现顺序

1. 先实现 valid/tag/data lookup 和 read hit，不实现 miss refill。
2. 实现 cacheable miss 的 4-word sequential refill 和 replay。
3. 实现 committed store write-through。
4. 实现 store hit byte-lane update、store miss no-allocate。
5. 接入 uncached load/store path。
6. 接入 flush kill/drain 和 DCache idle。
7. 接入 access/miss/stall counters。
8. 将 tag/data lookup 打拍，检查 FPGA RAM inference；不为 data array 添加 reset。

### 8.3 DCache 必测序列

| 测试 | 检查点 |
|---|---|
| cold load miss | 4 个 refill word 地址连续正确，最后 replay 得到目标 word |
| second load same line | hit，无外部 read |
| conflict line | 相同 index tag 替换，旧 tag 不再 hit |
| store hit | external write-through + cache byte lane 同时更新 |
| store miss | external write，cache valid/tag 不被错误分配 |
| partial byte store | 未写 byte 保持原值 |
| reset after cache used | valid 清、data 不需要清、首次访问重新 miss |
| miss 中 full flush | 后续 response drain，不 fill killed line、不 completion |
| MMIO | 永不分配 cache line，`dmem_req_uncached=1` |

### 8.4 阶段回归

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=

make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=

make sim-src TEST=srcSmoke MAX_CYCLES=5000 TRACE=1 NO_BUILD=1 OBJCACHE=
make sim-src TEST=srcSmoke SRC_MAX_CYCLES=100000000 NO_BUILD=1 OBJCACHE=
```

5000-cycle trace 预期通常只是早期进展，不要求 PASS；用它确认 IROM→DRAM→MMIO 路径和 DCache miss/refill 相位。完整 `srcSmoke` 才作为 PASS gate。

## 9. 阶段 7：Branch Predictor 与性能计数

### 9.1 文件

```text
frontend/branch_predictor.sv
frontend/frontend.sv
perf/perf_counters.sv
```

### 9.2 Predictor 实现步骤

1. 先加带 tag 的 64 项 BTB，JAL/JALR/branch 均由 EX resolve 建表。
2. 每项加 2-bit counter，仅条件 branch 使用。
3. branch miss 的判定统一比较 `actual_next_pc != pred_next_pc`，避免 taken/target 分开漏项。
4. 加 8 项 RAS；只在 call/return Commit 时更新。
5. reset 只清 predictor valid 和 RAS pointer，不清 target RAM 数据。
6. alias、cold miss 只允许影响性能，不得影响 Commit 正确性。

### 9.3 性能计数定义固化

必须确认以下关系：

```text
branch_miss <= branch
dcache_miss <= dcache_access
commit <= cycle
load + store <= commit
```

stall bucket 每周期按固定优先级只归入一个主因，避免总数严重重复：

```text
recovery/serialize
  > load-use RAW
  > LSU resource
  > MDU resource
  > scoreboard full/other RAW
  > frontend empty
```

外部只导出既有 4 个 stall 口，其余内部分类可在波形/assertion 或后续扩展中观察。

### 9.4 A/B 验证

在 predictor 关闭（always-not-taken）和打开时各跑一次 `srcSmoke` 短窗/完整窗：

- architectural commit 结果和 PASS marker 必须一致。
- 打开后 branch miss rate 应下降；若结果不同，predictor 已泄漏到正确性路径。
- IPC 只与 `dbg_perf_commit/dbg_perf_cycle` 比较，不用 wall-clock 或 counter ms 代替。

## 10. 阶段 8：完整回归矩阵

### 10.1 Build gate

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

检查：build log 无 missing module、duplicate definition、width truncation、latch、combinational loop、unoptflat。`-Wno-fatal` 只是不让 warning 中断，不能把关键 warning 当成已解决。

### 10.2 RV32 基础正式 gate

```bash
make sim-rv32 SUITE=rv32ui NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32mi NO_BUILD=1 OBJCACHE=
make sim-rv32 SUITE=rv32um NO_BUILD=1 OBJCACHE=
```

预期：40 + 4 + 8 = 52 项全部 PASS，`build/result/rv32/summary.json` 或分 suite 结果均保存。

建议新增并使用：

```bash
make sim-rv32-base NO_BUILD=1 OBJCACHE=
```

### 10.3 全数据目录审计

```bash
make sim-rv32-all NO_BUILD=1 MAX_CYCLES=2000000 OBJCACHE=
```

预期：RV32I/M/MI 仍 PASS；Zb suite 因明确非目标可 FAIL。审计报告要列出每个失败 suite，确保没有基础 suite 被 Zb 大量输出掩盖。

### 10.4 `srcSmoke`

```bash
make sim-src TEST=srcSmoke SRC_MAX_CYCLES=100000000 NO_BUILD=1 OBJCACHE=
```

严格解释：

- checker kind 必须为 `src_ledonly`。
- LED `0x24181824` 为立即 FAIL。
- LED `0x01221c08` 为当前 profile PASS。
- SEG/counter 字段用于诊断；它们不应反向推翻 ledonly PASS，但 `rv32i_pass_counter` 应作为设计质量检查。

### 10.5 `srcWithMext`

先跑诊断短窗：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=
```

短窗 TIMEOUT 不等于功能 FAIL，只用于确认：PC/commit 前进、DRAM 请求响应、SEG/LED/counter 有合理早期活动、无 assertion。

再跑正式长窗：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=1200000000 NO_BUILD=1 OBJCACHE=
```

如只因周期上限 TIMEOUT、但无 FAIL marker且进展正常，可扩大到已有稳定上限：

```bash
make sim-src TEST=srcWithMext MAX_CYCLES=2000000000 NO_BUILD=1 OBJCACHE=
```

最终 PASS 必须同时满足：

```text
pass marker     = 0x04887020
test lamp mask  = 0x03030303
RV32I count     = 37
M/Z count       = 8
fail marker     未观察到
```

不能因为看到 PASS marker 就提前停止；lamp/count 任一不满足，checker 正确地判 FAIL。

## 11. FPGA 框架回归

SoC/TB 通过并不证明 FPGA IP 时序与 compile-order 正确。最终至少执行：

```bash
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcSmoke
vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs srcWithMext
```

检查：

1. `core_config_pkg/core_types_pkg` 在消费者之前编译。
2. Vivado 工程未加入 `rtl/ip/*.sv` 行为模型，而是生成真实 IP。
3. `MUL_0` pipeline=3，`DIV_0` latency=34，packing 与 RTL wrapper 一致。
4. IROM 仍是一拍地址寄存合同；没有误打开额外 output register。
5. DCache data/tag array 被推断为合理 RAM/LUTRAM，而非因 reset/异步多读口展开成海量 FF。
6. 没有 black box、multi-driven net、unconnected clock/reset。

若资源允许，进一步跑 synth/impl 并归档：utilization、clock summary、WNS/TNS、最差路径。重点观察 Issue RAW、branch redirect、DCache lookup、Store Buffer merge，而不是只看整体 WNS。

## 12. 每阶段必须保持的断言清单

### 12.1 Frontend

- Queue count 不溢出/下溢。
- `pending_valid + queue_count` 不超过深度。
- redirect 后旧 response 不 push。
- `irom_ena` 发出时 metadata 同拍锁存。

### 12.2 Scoreboard/Issue

- occupied/count/pointer 一致。
- completion 只写 occupied ID。
- Commit 只消费 done head。
- mispredict 同拍无 allocation。
- RAW wrap 和 latest producer 唯一。
- x0 永远不写。

### 12.3 Memory

- speculative store 不到 external write port。
- committed store 非 reset flush 不丢。
- 同时最多一个 external read outstanding。
- request stall 时 payload 稳定。
- killed response 不 fill、不 completion。
- MMIO load 只在 head 且 store 已排序时发出。
- Store commit slot/ID 匹配。

### 12.4 MDU/Commit

- killed M result 不 completion。
- variable arbiter 不丢 valid hold。
- trap 不写 faulting rd，不批准 faulting store。
- trap/mret 高于 branch redirect。
- CSR serial 期间不分配年轻指令。

## 13. 失败定位树

### 13.1 Build 失败

```text
missing package/type
  → core.f compile order
duplicate module
  → filelist 是否残留旧文件/FPGA 是否混入 rtl/ip 模型
width/latch
  → package 派生宽度、always_comb 默认赋值
unoptflat/combinational loop
  → valid/ready 是否互相组合依赖
```

### 13.2 rv32ui 首次失败

```text
simple/add 就失败
  → IROM PC/data 相位、Commit RF write、tohost store
branch 类失败
  → actual_next/pred_next、mispredict 同拍 allocation kill
load byte/half 失败
  → aligned read、offset、符号扩展、partial forwarding
store 类失败
  → raw wdata/wstrb 与外部 lane shift
```

### 13.3 rv32mi 失败

```text
csr
  → old CSR value、set/clear、x0/zimm=0 side-effect
scall/sbreak
  → mepc/mcause/mtvec、trap flush、handler return
zicntr
  → 当前测试合同，不先扩大成完整特权实现
```

### 13.4 rv32um/FPGA M 扩展失败

```text
只 high multiply 失败
  → 33-bit signed/unsigned extension
DIV/REM 四项成组失败
  → {quotient,remainder} packing 或符号恢复
Verilator 过、FPGA 不过
  → 行为模型与 Vivado IP latency/packing 不一致
```

### 13.5 src 失败

```text
很早无 MMIO
  → IROM/DRAM 返回相位、DCache refill、PC 跑飞
RV32I count < 37
  → LB/LH/LBU/LHU/SB/SH/SW、CSR/trap
M/Z count < 8
  → RV32M 八类逐项结果
PASS marker 有但 checker FAIL
  → lamp mask/count 未满足，不修改 checker
TIMEOUT
  → 先区分性能不足与无 commit/无 MMIO 进展
```

## 14. 提交/变更批次建议

每个批次必须可 build，建议顺序：

1. `core: replace legacy tree with package-based skeleton`
2. `core: add frontend decode scoreboard and fixed execute`
3. `core: add precise commit and branch recovery`
4. `core: add load queue store buffer and uncached LSU`
5. `core: add machine CSR traps and fence serialization`
6. `core: add single-outstanding muldiv completion path`
7. `core: add blocking write-through dcache`
8. `core: add branch predictor and performance counters`
9. `build: update verilator and vivado compile contracts`
10. `docs: record regressions and FPGA QoR`

实际 commit 前检查用户工作树，按任务范围选择文件；不把无关改动混入。

## 15. 里程碑退出标准

| 里程碑 | 必须满足 | 不允许用什么替代 |
|---|---|---|
| M1 框架 | 两 DUT build | 只跑语法片段 |
| M2 Fixed Core | ALU/branch 控制流到正确 tohost 路径 | “波形看起来差不多” |
| M3 Memory | RV32UI 40 PASS | 只通过 LW/SW |
| M4 Precise State | RV32MI 4 PASS + flush assertions | 只实现 CSR 寄存器读写 |
| M5 M extension | RV32UM 8 PASS | 只通过 MUL |
| M6 DCache | base 52 PASS + srcSmoke PASS | uncached bypass 仍开着 |
| M7 Final | srcWithMext 严格 PASS + predictor/perf + FPGA source build | PASS marker 单字段或短窗 TIMEOUT |

## 16. 最终报告必须回答的问题

1. 最终六级每级具体寄存边界是否与 053 一致？
2. load/div 等待时，是否有波形/计数证明独立 ALU 继续 Issue？
3. scoreboard 同名 `rd`、wrap、双 completion 是否都有断言或定向测试？
4. branch miss 为什么不需要清已发射 scoreboard；这一假设是否仍由单拍 resolve 保证？
5. trap 后迟到 dmem/DIV response 如何被 drain？
6. Store Buffer 的 speculative/committed 分界在哪里？
7. DCache 真实组织、命中延迟、miss refill 次数和写策略是什么？
8. `srcSmoke` 与 `srcWithMext` 使用了什么不同 PASS 规则？
9. RV32 base 52 项和 Zb 非目标如何分开报告？
10. Verilator IP 模型与 Vivado IP 的 latency/packing 如何证明一致？
11. 当前 IPC、branch miss、DCache miss、主 stall 分桶相对基线如何变化？
12. Vivado 资源和最差时序路径是否符合下一轮优化方向？

## 17. 任务完成定义

只有在“新 RTL + base RV32 52 PASS + srcSmoke PASS + srcWithMext 严格 PASS + 两 DUT build + FPGA 工程可创建 + 关键断言无违例”全部成立后，任务才完成。

中间某阶段可临时使用 always-not-taken 或 uncached LSU 做隔离验证，但最终交付不能停在临时实现；053 定义的 scoreboard、精确 Commit、Store Buffer、正式 DCache、预测器和性能计数都必须落地。
