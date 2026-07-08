# 当前 CPU 架构与流水阶段说明

日期：2026-07-08

## 1. 文档范围

本文描述的是当前 RTL 已经实现并通过 Verilator 回归的架构状态，不是最初五级流水计划的理想图。

当前核心已经从超标量/乱序方向收敛为单发射、顺序、精确状态的 RV32 核。它不是完整 IF/ID/EX/MEM/WB 五级流水，而是一个带顺序预取和小 BTB 的流式顺序执行核心：每周期最多提交 1 条指令，正常连续 ALU 指令可以接近 1 IPC，分支错误预测和 load 会插入气泡。

这个实现的优先级是：

1. 保证 RV32I/RV32M/RV32MI 基本正确性。
2. 保持 Verilator 和 Vivado 两边可构建。
3. 在不显著增加复杂度的前提下提高 `srcSmoke` 这类程序的实际运行速度。
4. 暂停继续压缩流水段，等待 Vivado 综合/实现结果再决定是否拆分慢路径。

## 2. 顶层结构

当前工程主路径如下：

```text
student_top
  -> myCPU
       -> riscv_cpu
  -> IROM_0
  -> SocMemBridge
       -> DramBramAdapter
            -> DRAM_0
       -> display_seg
       -> counter
```

关键文件：

| 文件 | 当前职责 |
| --- | --- |
| `rtl/core/riscv_cpu.sv` | CPU 主实现，包含 PC、寄存器堆、CSR、BTB、执行/访存状态机、性能计数器 |
| `rtl/core/myCPU.sv` | CPU wrapper，对外暴露 IROM 和 dmem ready/valid 接口 |
| `rtl/ip/IROM_0.sv` | Vivado 单端口 ROM IP 的 Verilator 平替模型 |
| `rtl/ip/DRAM_0.sv` | Vivado 单端口 byte-write BRAM IP 的 Verilator 平替模型 |
| `rtl/soc/student_top.sv` | 板级/仿真顶层，连接 CPU、IROM、数据总线和外设 |
| `rtl/soc/SocMemBridge.sv` | DRAM/MMIO 地址译码和 ready/valid 响应合并 |
| `rtl/soc/DramBramAdapter.sv` | CPU byte address 访问到 32-bit BRAM word port 的适配 |

`rtl/core/front/decode/execute/memory/regs/control/perf` 下的若干模块目前是结构占位。当前可运行核心没有实例化这些拆分模块，真实行为集中在 `riscv_cpu.sv`。

## 3. 当前微架构概览

### 3.1 执行模型

当前核心是单发射、顺序提交：

```text
取到一条指令 -> 在 ST_EXEC 中解码/执行/写回/提交 -> 更新 PC -> 继续下一条
```

为了避免“每条指令都 FETCH 一拍、EXEC 一拍”导致 IPC 约 0.5，当前实现做了流式预取：

```text
执行当前 pc_q 指令的同时，IROM 请求 pred_next_pc_c
如果预测正确，下一拍继续 ST_EXEC，直接执行下一条 irom_data
如果预测错误，回到 ST_FETCH 重新取真实 next_pc
```

因此，正常 ALU/CSR/分支预测正确路径可以做到每拍提交 1 条。load 需要等待数据存储器响应，store 在请求被接受时提交。

### 3.2 架构状态

`riscv_cpu.sv` 中的主要状态如下：

| 状态 | 作用 | 更新时机 |
| --- | --- | --- |
| `pc_q` | 当前正在执行的指令 PC | 指令提交、load 完成、异常/返回/跳转 |
| `regs_q[0:31]` | RV32 通用寄存器堆 | `write_gpr` 写回，且每拍强制 `x0=0` |
| `csr_mstatus_q` 等 | 简化 M-mode CSR | CSR 指令、ECALL/EBREAK/MRET |
| `load_rd_q/load_funct3_q/load_addr_q` | load 未完成事务上下文 | load 请求被接受后锁存 |
| `btb_valid_q/tag_q/target_q` | 64-entry direct-mapped BTB | branch/JAL/JALR 提交时更新 |
| `perf_cycle/commit/branch/branch_miss` | 性能计数器 | 每拍或提交/分支事件 |

## 4. 流水阶段定义

当前阶段不是传统五级流水寄存器切分，而是三类有效执行阶段。

### 4.1 F 阶段：取指请求与 IROM 响应对齐

涉及状态：`ST_FETCH`，以及 `ST_EXEC/ST_WAIT_MEM` 中的预取。

IROM 当前是单端口一拍取指模型：

```text
cycle N:     irom_ena=1, irom_addr=目标 PC
posedge N:  IROM_0 锁存 addra
cycle N+1:  irom_data 对应该 PC 指令
```

`ST_FETCH` 用于 reset 后首条指令、分支错误预测、异常跳转、MRET 等重定向场景。正常流式执行时不会每条指令都回 `ST_FETCH`，而是在 `ST_EXEC` 期间直接给 IROM 发下一条预测 PC。

关键逻辑：

```systemverilog
assign irom_addr = ((state_q == ST_EXEC) || (state_q == ST_WAIT_MEM))
                 ? pred_next_pc_c
                 : pc_q;
assign irom_ena  = (state_q == ST_FETCH) ||
                   (state_q == ST_EXEC) ||
                   (state_q == ST_WAIT_MEM);
```

设计意图：把 IROM 一拍延迟隐藏到当前指令执行周期里。

如果这里改错，典型 bug 是：顺序指令每条都多等一拍，IPC 掉到约 0.5；或者 redirect 后拿到错误路径的指令，出现难定位的控制流错误。

### 4.2 X 阶段：解码、执行、写回、提交

涉及状态：`ST_EXEC`。

当前大部分指令在 `ST_EXEC` 一个状态内完成：

```text
irom_data/inst_q -> opcode/funct/rs/rd 解码
                 -> 读取 regs_q/CSR
                 -> ALU/branch/CSR/M 计算
                 -> write_gpr/csr_write
                 -> perf_commit++
                 -> pc_q <= next_pc
                 -> state_q <= ST_EXEC 或 ST_FETCH
```

正常非访存指令：

```text
ST_EXEC 当前指令提交
  -> next_pc == pred_next_pc_c
  -> 下一拍仍在 ST_EXEC
  -> irom_data 已经是下一条指令
```

控制流指令：

```text
ST_EXEC 计算真实 next_pc
  -> 比较 next_pc 和 pred_next_pc_c
  -> 相等：预测正确，继续 ST_EXEC
  -> 不等：预测错误，pc_q <= next_pc，回 ST_FETCH
```

设计取舍：把 decode/execute/writeback/commit 合并后，控制简单、正确性容易收敛、Verilator 回归稳定；代价是 Vivado 关键路径可能集中在 `riscv_cpu.sv` 的执行组合逻辑，尤其是 RV32M 乘除法、CSR/branch/BTB mux 共同参与的路径。

如果这里继续盲目合并更多逻辑，可能提升 IPC 但降低 Fmax，最终程序运行时间反而变差。当前建议先综合，看真实 critical path 后再拆。

### 4.3 M 阶段：数据访存请求与 load 等待

涉及状态：`ST_EXEC`、`ST_WAIT_MEM`。

store 路径：

```text
ST_EXEC 计算地址/写数据/byte strobe
  -> dmem_req_valid=1, dmem_req_write=1
  -> dmem_req_ready=1 时提交
  -> 不等待 resp_valid
```

load 路径：

```text
ST_EXEC 计算地址
  -> dmem_req_valid=1, dmem_req_write=0
  -> dmem_req_ready=1 后锁存 rd/funct3/address
  -> state_q <= ST_WAIT_MEM

ST_WAIT_MEM
  -> 等 dmem_resp_valid
  -> load_extend(dmem_resp_rdata)
  -> write_gpr(load_rd_q, data)
  -> pc_q <= pc_q + 4
  -> perf_commit++
  -> state_q <= ST_EXEC
```

`ST_WAIT_MEM` 期间仍然给 IROM 发 `pred_next_pc_c`，所以 BRAM load 的等待周期可以和下一条顺序指令取指部分重叠。

如果 load 上下文不锁存，响应回来时 rd/funct3 可能已经被下一条指令覆盖，导致 load 写错寄存器或符号扩展错误。

## 5. 分支预测与控制流

当前预测器是 64-entry direct-mapped BTB：

```text
index = pc_q[7:2]
tag   = pc_q[31:8]
target= btb_target_q[index]

btb_hit ? target : pc_q + 4
```

更新策略：

| 指令 | BTB 行为 |
| --- | --- |
| `JAL/JALR` | 总是写入 target |
| conditional branch taken | 写入 target |
| conditional branch not-taken 且 BTB hit | 清除该 entry |

提交时比较：

```text
redirect = (真实 next_pc != pred_next_pc_c)
```

预测正确时不回 `ST_FETCH`，下一拍继续执行预取到的指令。预测错误时 `pc_q <= next_pc`，回 `ST_FETCH` 重新发真实 PC。

设计取舍：

1. BTB 很小，组合查找代价低，适合先上板。
2. 不做 BHT、RAS、2-way，是为了避免前端预测器本身成为 Fmax 问题。
3. 对循环 taken branch 和 JAL/JALR 收益明显，对复杂分支模式收益有限。

如果 BTB tag/target 更新时机错，常见 bug 是旧 target 污染新 PC，表现为偶发跳到错误地址；如果 not-taken 不清 entry，会导致循环退出后一再错误预测 taken。

## 6. 存储系统

### 6.1 IROM

`IROM_0` 当前是 Vivado `Single_Port_ROM` 的仿真平替：

```text
输入： addra/clka/ena
输出： douta
行为： ena 时打一拍地址，douta 输出该地址内容
```

`student_top` 中使用 `irom_addr[13:2]` 作为 32-bit word address。当前 IROM 是单端口，不再保留之前超标量残留的双端口取指接口。

### 6.2 DRAM

`DRAM_0` 当前是单端口 32-bit byte-write BRAM 模型：

```text
read:  posedge 读取 mem[addra] 到 douta
write: posedge 按 wea byte enable 写入
```

CPU 不直接面对 BRAM 端口，而是面对 ready/valid dmem 接口。`DramBramAdapter` 负责：

1. byte address 到 word address。
2. store wdata 左移到正确 byte lane。
3. store byte enable 左移到正确 lane。
4. load 响应按原 offset 右移，再交给 CPU 做符号/零扩展。
5. 对 read 产生一拍后的 `resp_valid`。

当前 DRAM 背后仍按 BRAM 实现，这是合理的。因为数据存储器本身在片上，且当前 `srcSmoke` 的主要收益来自隐藏 IROM 延迟和减少分支重定向，不需要立即引入复杂 D-cache。

### 6.3 D-cache 状态

当前没有真正集成 D-cache。`rtl/core/memory/DCache.sv` 和 `StoreWriteBuffer.sv` 只是后续拆分用的占位模块。

暂不实现 D-cache 的原因：

1. 当前 DRAM 是片上 BRAM，不是高延迟外部存储。
2. 直接加 cache 会引入 tag/data array、miss/refill FSM、flush/uncached 一致性问题。
3. 在 Vivado timing 未知前，cache 可能增加面积和关键路径，未必提升最终运行速度。

后续只有在综合结果显示 Fmax 充足、程序访存 stall 明显、或数据存储迁移到外部高延迟存储时，才建议把 D-cache 提上优先级。

## 7. SoC 地址空间与外设路径

`SocMemBridge` 当前地址译码：

| 地址范围/地址 | 目标 |
| --- | --- |
| `0x8010_0000` 到 `0x8014_0000` | DRAM |
| `0x8020_0000` | SW low |
| `0x8020_0004` | SW high |
| `0x8020_0010` | KEY |
| `0x8020_0020` | SEG |
| `0x8020_0040` | LED |
| `0x8020_0050` | counter |

DRAM read 和 MMIO read 都以 `resp_valid/resp_rdata` 返回。MMIO write 在请求周期更新寄存器，不产生 CPU 需要等待的读响应。当前 `req_uncached` 被保留在接口里，但没有参与 cache 仲裁，因为尚未集成 cache。

## 8. 性能现状

已记录的 `srcSmoke` 性能：

| 版本 | cycles | commit | IPC | branch miss rate |
| --- | ---: | ---: | ---: | ---: |
| 功能基线 | 92,976,339 | 30,758,720 | 0.330823 | 59.45% |
| 顺序预取 | 39,101,279 | 30,758,601 | 0.786639 | 59.45% |
| 顺序预取 + BTB | 34,014,770 | 30,758,589 | 0.904272 | 19.88% |

当前 IPC 已经接近单发射顺序核心的合理上限。后续优化不应只看 IPC，还要看：

```text
程序运行时间 = cycles / Fmax
```

如果为了减少少量 cycle 把 Fmax 拉低，最终上板运行时间会变差。当前建议停止继续压缩流水，先跑 Vivado 综合/实现。

## 9. Vivado 友好性与风险点

当前已经做了这些 Vivado 友好处理：

1. IROM/DRAM 恢复为单端口 BRAM 风格。
2. DRAM 使用 byte write enable，适配 Vivado blk_mem_gen。
3. SoC 顶层端口保持稳定。
4. `dmem` 使用 ready/valid，后续可接 cache 或多周期 memory。
5. BTB 规模小，不引入复杂预测器。

但仍有以下 timing 风险：

| 风险点 | 原因 | 建议处理 |
| --- | --- | --- |
| RV32M 除法 | 当前 `/`、`%` 是组合表达式 | 若 critical path 指向这里，改为 `DIV_0` 或多周期除法单元 |
| RV32M 乘法 | 当前 `*` 在 `ST_EXEC` 内组合完成 | 若 Fmax 不够，接 `MUL_0` 或打一拍 |
| 大 execute case | decode/ALU/CSR/branch/writeback 合并在一拍 | 若 critical path 指向主 case，拆成 decode/execute 或 execute/writeback |
| BTB lookup 到 PC mux | `pc_q -> BTB -> pred_next_pc_c -> irom_addr` | 若成为关键路径，减小 BTB 或打一拍预测 |
| reset fanout | 寄存器堆和 BTB valid reset | 若 reset path 报告难看，优先只 reset valid/控制态 |

当前不要再为了 IPC 主动减少阶段。正确策略是以 Vivado timing report 为准：哪里慢，拆哪里。

## 10. 已通过验证

当前 RTL 已通过：

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
make sim-rv32 SUITE=rv32ui NO_BUILD=1 MAX_CYCLES=1000000
make sim-rv32 SUITE=rv32um NO_BUILD=1 MAX_CYCLES=2000000
make sim-rv32 SUITE=rv32mi NO_BUILD=1 MAX_CYCLES=2000000
make sim-src TEST=srcSmoke NO_BUILD=1 MAX_CYCLES=40000000 CPU_FREQ_MHZ=50
```

结果：

| 测试 | 结果 |
| --- | --- |
| `rv32ui` | 40/40 PASS |
| `rv32um` | 8/8 PASS |
| `rv32mi` | 4/4 PASS |
| `srcSmoke` | PASS |

## 11. 后续决策规则

Vivado 综合后按下面规则决策：

1. 如果 critical path 在乘除法，优先把 RV32M 改为多周期单元，不要拆无关流水段。
2. 如果 critical path 在 `ST_EXEC` 大 case，优先拆 decode/execute 或 execute/writeback。
3. 如果 critical path 在 BTB 前端，只减小/重定时 BTB，不上复杂预测器。
4. 如果 Fmax 已满足目标但程序仍慢，再看访存 stall 和分支 miss 是否值得优化。
5. 如果 DRAM/BRAM 路径稳定且数据都在片上，暂时不加 D-cache。
6. 如果后续接外部存储或访存延迟变大，再重新评估 D-cache、write buffer、uncached 通路。

## 12. 一句话总结

当前架构是“单发射顺序提交 + 一拍 IROM 预取隐藏 + 小 BTB 降低控制流气泡 + BRAM 数据存储”的务实版本。它已经能在 Verilator 上通过基础回归并把 `srcSmoke` IPC 提到约 0.90；下一步不应继续盲目压流水，而应让 Vivado timing report 决定是否拆分乘除法、执行级或 BTB 路径。
