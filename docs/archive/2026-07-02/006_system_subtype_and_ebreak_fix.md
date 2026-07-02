# RTL 修复：SYSTEM/MISC-MEM subtype 与 EBREAK trap

> 本次按已确认 RTL 错误做窄范围修复，不修改 `myCPU` 端口、不修改 `counter.sv`，不改变 IROM/DRAM 时序、CSR 白名单或 reset 策略。

## 1. 修复内容

1. 在 `BasicTypes.sv` 中增加 `SYS_SUBTYPE_FENCE` 和 `SYS_SUBTYPE_MRET`。
2. `DecodeMISCMEM` 不再把 FENCE/FENCE.I 译成 EBREAK，而是译成 `SYS_SUBTYPE_FENCE`。
3. `DecodeSYSTEM` 不再用 “EBREAK + csrAddr=0x302” 表达 MRET，而是直接译成 `SYS_SUBTYPE_MRET`。
4. `ExecuteSysStage` 将 EBREAK 纳入 trap 路径：`mepc=pc`、`mcause=3`、跳转到 `mtvec`。
5. FENCE/FENCE.I 保持 serial NOP：可提交，不产生 exception，不产生 cache 相关副作用。

## 2. 修改文件

| 文件 | 修改 |
| --- | --- |
| `rtl/core/BasicTypes.sv` | 扩展 SYS subtype 枚举。 |
| `rtl/core/DecodeStage/DecodeTypes.sv` | 修正 FENCE/FENCE.I、MRET 的 subtype。 |
| `rtl/core/ExecuteStage/ExecuteSysStage.sv` | 增加 `is_trap`，让 EBREAK 进入 trap redirect。 |
| `docs/design/rtl_core_design.md` | 同步 SYS 执行单元行为说明。 |
| `docs/design/memory_and_test_contract.md` | 同步 CSR/trap 行为说明。 |

备份文件保存在 `backup/20260702_000000_system_fix/`。

## 3. 验证状态

本次只做文本级一致性检查和 diff 检查，未运行 Verilator、仿真或 lint。后续建议优先用包含 ECALL/EBREAK/MRET/FENCE 的 directed 程序确认：

1. EBREAK 写入 `mcause=3` 并跳转 `mtvec`。
2. ECALL 仍写入 `mcause=11`。
3. MRET 从 `mepc` 返回。
4. FENCE/FENCE.I 能作为 serial 指令提交，且不触发 exception。
