# 顺序单发射 Core 实现与回归报告

> 执行依据：052 CVA6 分析、053 适配架构、054 实施计划。  
> 日期：2026-07-13。基线提交：`82470c38efdb34c8f7a7ae3806bde1798bbe79b2`，分支：`dev-v4.0`。  
> 结论：新 RV32IM/Zicsr 顺序单发射、乱序完成、顺序提交 Core 已完成；基础 52 项、`srcSmoke`、`srcWithMext` 均严格 PASS，两个最终 Vivado profile 工程创建成功。

## 1. 实际执行范围

1. 删除旧 `rtl/core/` 中除 `myCPU.sv` 外的实现，删除 `rtl/include/`。
2. 旧实现分别备份到 `legacy_rtl_core_backup/` 和 `legacy_rtl_include_backup/`；备份不进入 RTL filelist。
3. `myCPU.sv` 保持 SoC、TB、FPGA 外部端口合同，只改内部实例为新 `core_top`。
4. 新实现不使用全局 `.svh` 宏；参数、枚举、packed struct 统一放在两个 package 中。
5. 更新 `core.f`、Verilator include 处理和 Vivado package compile priority。
6. 新增 `sim-rv32-base`，明确区分 RV32IM 基础目标与非目标 Zb suite。

## 2. 最终 RTL 组织

```text
rtl/core/
├── myCPU.sv
├── core_top.sv
├── pkg/{core_config_pkg,core_types_pkg}.sv
├── frontend/{frontend,fetch_queue,branch_predictor}.sv
├── decode/decoder.sv
├── issue/regfile.sv
├── execute/{fixed_execute,muldiv_unit}.sv
├── memory/dcache.sv
├── commit/csr_file.sv
├── control/recovery_ctrl.sv
└── perf/perf_counters.sv
```

物理文件没有机械照搬 CVA6，也没有为每个小组合块建立空壳。Scoreboard、RAW age scan、Load Queue、Store Buffer 和 Commit 原子 next-state 仍集中在 `core_top` 的同一时序域，避免跨模块同时更新 `allocate/completion/commit/flush` 时产生优先级歧义；前端、执行单元、DCache、CSR、恢复和性能状态已独立拥有。

## 3. 六级边界的实际落点

| 逻辑级 | 实际寄存边界 | 本拍主要工作 |
|---|---|---|
| S0 PC/Pred | `frontend.fetch_pc_q` | BTB/BHT/RAS 预测下一 PC，发 IROM request |
| S1 IF Return | `pending_*_q` | 对齐一拍 IROM 返回，redirect 时丢弃旧 metadata |
| S2 ID | `fetch_queue` + `id_uop_q` | 4 项 FQ 解耦取指，完整 decode/illegal 标记 |
| S3 Issue/RO | `exec_q` | 最新 WAW producer 扫描、RF/三类 completion bypass、FU ready、单条分配 |
| S4 EX/Complete | Scoreboard completion、LQ/MDU 状态 | ALU/branch/AGU；load、mul/div 可变延迟完成 |
| S5 Commit | `commit_ptr_q` 头项 | 单条顺序提交 GPR/CSR/store/trap/mret/fence 副作用 |

每拍最多 `issue_fire=1`、`commit_fire=1`。8 项 Scoreboard 允许多个已发射事务在途，结果按 transaction ID 乱序完成，但只有最老 done 项可提交。

## 4. 关键微架构实现

### 4.1 前端与分支预测

- 4 项 Fetch Queue；`pending metadata + queue_count <= 4`。
- 64 项带 tag BTB/BHT，条件跳转使用 2-bit 饱和计数器。
- 8 项 RAS 只在 call/return Commit 后更新，错误路径不污染架构可见预测状态。
- branch 在固定 EX 一拍 resolve；miss 比较统一为 `actual_next_pc != pred_next_pc`。
- miss 同拍以 `redirect_valid` 覆盖 Issue，错误路径 ID uop 不会分配进 Scoreboard。

### 4.2 RAW、窗口与精确提交

- 8 项环形 Scoreboard 保存 `occupied/done/result/exception/store_slot`。
- RAW 从 `issue_ptr-1` 向老方向扫描，命中第一个同名 rd，即最新 producer；支持多个同 rd 和 pointer wrap。
- 同拍旁路优先 fixed completion、load completion、MDU completion，实现相邻 ALU RAW 无额外气泡。
- Scoreboard full 且 head 本拍 Commit 时允许同槽 commit+allocate；新 allocation 具有最终 next-state 优先级。
- GPR 只有 Commit 单写口，x0 硬读 0、写忽略。

### 4.3 LSU、Store Buffer 与精确内存副作用

- 2 项 Load Queue、4 项 Store Buffer，均保存 Scoreboard transaction ID。
- Store 在 EX 入 speculative buffer 后即可 completion；只有其 Scoreboard 项 Commit 后才置 `committed=1`，DCache 只 drain committed head。
- misaligned load/store 在发任何 external request 前生成 cause 4/6。
- Load 入队时冻结 `store_seq_cutoff`，按程序顺序扫描当时所有 older store；逐 byte 合并且 younger older-store 覆盖同 byte。
- full forwarding 时 load 不访问 DCache；partial forwarding 将 memory word 与 frozen byte mask 合并后再做一次 offset/符号扩展。
- 后续年轻 Store 不会被老 Load 动态看到。
- cacheable load 可在 older Store 未 drain 时借助 forwarding 前进；MMIO/uncached load 必须同时满足“位于 commit head、无 older store”。
- full flush 清 speculative Store，但保留 committed Store 继续 drain。

### 4.4 DCache

- 8 KiB，512 行，16 B/行，直接映射，blocking。
- Load miss 顺序发 4 个 aligned word refill；目标 word 返回后最终 response。
- committed Store write-through；hit 时按 byte lane 更新 cache，miss no-write-allocate。
- MMIO/uncached 永不分配 cache line。
- flush 时未握手 refill request 可取消；与 kill 同拍已握手的 request 必须进入 killed wait，等迟到 response 后丢弃，不能遗忘外部 outstanding。
- reset 只清 valid，不清 data array。

### 4.5 RV32M、CSR 与恢复

- 全核只有一个 MDU in-flight；真实 `MUL_0` 为 33x33 signed、3 拍，`DIV_0` 为 unsigned、34 拍。
- DIV 保存符号和原操作数，处理除零、`INT_MIN/-1`，按 `{quotient,remainder}` 解包。
- full flush 只标记 MDU killed，真实 IP valid 到达前不接新请求，旧结果不写复用 ID。
- CSR/System serialize：窗口空才能分配，提交前禁止后继。
- 实现 `mstatus/misa/mtvec/mscratch/mepc/mcause/mtval/mhartid/cycle/instret` 项目子集。
- trap、MRET、FENCE.I 由 `recovery_ctrl` 产生 full flush；优先于 branch miss。FENCE 等待 LSU/MDU/DCache quiescent。

## 5. 断言与静态检查

Verilator 构建启用的关键检查包括：

- FQ/Scoreboard/LQ/Store Buffer count 不越界。
- completion 只能命中 occupied transaction ID。
- `commit<=cycle`、`branch_miss<=branch`、`dcache_miss<=access`、`load+store<=commit`。
- external store 必须来自 valid+committed Store Buffer head。
- uncached load 发出时必须位于 commit head 且无 older Store。
- dmem backpressure 期间 valid、write、addr、wdata、wstrb、uncached 全部稳定。
- branch miss 同拍不得 Issue。
- DCache killed refill 不产生 cache fill/completion，MDU killed result 不产生 completion。

最终 `build_mycpu.log`、`build_student_top.log` 中无 `%Warning`、`%Error`、latch、width、UNOPTFLAT 或 combinational-loop 记录。

## 6. 回归结果

### 6.1 Build 与基础 ISA

| Gate | 结果 |
|---|---:|
| `make verilator-build` | PASS，0 Warning/0 Error |
| `make verilator-build-src` | PASS，0 Warning/0 Error |
| RV32UI | 40/40 PASS |
| RV32MI 项目子集 | 4/4 PASS |
| RV32UM | 8/8 PASS |
| `make sim-rv32-base NO_BUILD=1` | 52/52 PASS |

`sim-rv32-all` 审计为 52 PASS + 39 FAIL。39 FAIL 精确来自非目标 bitmanip：Zba 3、Zbb 18、Zbc 3、Zbkb 5、Zbkx 2、Zbs 8；没有 RV32I/M/MI 失败。

### 6.2 用户要求的 500k 中间窗口

| 测试 | 状态 | 关键证据 |
|---|---|---|
| srcSmoke | 500k TIMEOUT（预期诊断状态） | RV32I=37、fail=0、SEG=`0x37000000`、IPC=0.740682、无 fail marker/assertion |
| srcWithMext | 500k TIMEOUT（预期诊断状态） | RV32I=37、M/Z=8、lamp=`0x00020001`、IPC=0.614302、无 fail marker/assertion |

这里没有把小窗口 TIMEOUT 写成 PASS；它只证明 Core/DRAM/MMIO 持续前进，正式结论来自下节大窗口。

### 6.3 最终大窗口

| 指标 | srcSmoke | srcWithMext |
|---|---:|---:|
| checker | `src_ledonly` | `src_lampseg` |
| 最终状态 | PASS | PASS |
| 完成周期 | 40,248,735 | 604,195,677 |
| commit | 30,758,586 | 380,344,388 |
| IPC | 0.764212 | 0.629505 |
| branch hit rate | 83.6839% | 98.7847% |
| DCache access/miss | 800,263 / 10 | 121,295,570 / 3,200,379 |
| RV32I / M-Z count | 37 / 0 | 37 / 8 |

`srcSmoke` 在 100M 上限内看到 LED `0x01221c08`，fail marker 未出现。  
`srcWithMext` 在 1.2B 上限内看到基础 pass marker 与灯位合并后的 LED `0x078b7323`；lamp mask/value 均为 `0x03030303`，RV32I=37、M/Z=8、fail marker 未出现，因此联合 checker 严格 PASS。

结果文件：`build/result/src/srcSmoke.json`、`build/result/src/srcWithMext.json`。

## 7. FPGA 框架回归

使用 Windows Vivado 2023.2 从 WSL 工作区执行最终 filelist，两次均 exit 0：

- `fpga/build/digital_twin_srcSmoke/digital_twin.xpr`
- `fpga/build/digital_twin_srcWithMext/digital_twin.xpr`

已确认最终新增的 `frontend/fetch_queue/regfile/fixed_execute/recovery_ctrl/perf_counters` 都实际记录在两个 XPR 中；真实 IROM/DRAM/MUL/DIV/PLL IP 生成成功，`rtl/ip/*.sv` 行为模型未进入 FPGA sources。

本轮按 054 的“工程可创建”门槛执行，没有启动耗时的 synth/impl，因此不提供虚构的 LUT/FF/BRAM、WNS/TNS 或最差路径结论。下一轮时序优化应单独跑 implementation 后再决定是否给 DCache lookup、Scoreboard RAW scan 增加物理流水拍。

## 8. 054 最终问题答复

1. 六级逻辑边界与 053 一致，具体寄存器见第 3 节；它不是传统全局冻结五级流水。
2. Issue 只被当前 uop RAW/FU/队列资源约束，不被全局 `load_active` 或 `mdu_busy` 冻结；长测 IPC 和持续 Commit 证明窗口在长延迟期间仍前进。当前 TB 未导出“load/div 在途同时 ALU issue”的专用计数，若需要逐拍证据应增加 cover counter 或波形用例。
3. 最新 WAW producer、pointer wrap 由 age scan 实现，长程序反复绕环且断言无违例；双 completion 使用独立 ID 写入口。尚未单独保存三者的最小定向波形。
4. branch 在固定 EX 一拍 resolve，miss 同拍屏蔽 S3 allocation，因此不会存在已发射的年轻错误 uop；若以后把 branch 拆成多拍，必须增加按年龄 squash。
5. full flush 后 dmem 与 DIV 都 kill-and-drain；旧 response/result 没有 completion 权限，ID 不会被旧结果污染。
6. Store 入 Buffer 时 speculative，Scoreboard Store 在 Commit 时把对应 slot 置 committed；只有 committed head 能发 external write。
7. DCache 为 512x16B 直接映射 blocking cache，load allocate、4-word refill、store write-through/no-write-allocate、uncached bypass。
8. srcSmoke 只以 LED pass/fail signature 判定；srcWithMext 要求 pass marker、完整 lamp mask、RV32I=37、M/Z=8 同时成立。
9. RV32 base 52 项由 `sim-rv32-base` 单独报告；Zb 39 项保留在 all 审计中并明确列为非目标。
10. Verilator `MUL_0/DIV_0` 模型与 Vivado 配置均为 MUL 3 拍、DIV 34 拍及相同 packing；8 个 RV32M 与最终 FPGA IP 创建共同检查合同。
11. 最终性能见第 6.3 节。旧 Core 未保存同口径大窗口数据，所以不伪造“相对旧基线提升”；只能报告新 Core 的绝对 IPC/命中率。
12. Vivado source/IP/compile-order 已通过；资源和时序未跑 synth/impl，不能对 WNS/TNS 下结论。

## 9. 明确非目标与后续建议

- 非目标：Zba/Zbb/Zbc/Zbkb/Zbkx/Zbs、ICache、MMU/S 模式、异步中断、外部 access fault、完整 privileged spec。
- 当前 `core_top` 仍集中保存 Scoreboard/LSU/Commit 原子更新。若下一轮为团队并行开发拆文件，应先冻结内部接口并保持同一 next-state 优先级，不能只为目录好看机械拆分。
- 性能优化优先级：先跑 FPGA synth/impl 获取真实最差路径；再考虑 DCache 同拍 lookup、Scoreboard 全槽 RAW scan、Store byte merge，而不是先增加发射宽度。
- 产物清单见 `stage5_rtl_gen.json`。
