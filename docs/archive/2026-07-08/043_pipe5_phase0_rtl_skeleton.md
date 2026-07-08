# 五级流水 Phase 0 RTL 骨架切换记录

日期：2026-07-08

## 目标

按 `042_pipe5_rtl_modification_plan.md` 执行第一阶段：先把旧 OoO core 的 filelist 断开，建立五级流水工程骨架、单端口 IROM、ready/valid 数据总线和 SoC memory bridge，使 Verilator 能重新 elaboration。此阶段不实现 RV32 功能正确性。

## 修改范围

### 1. 新建五级流水 core 骨架

新增：

```text
rtl/core/CoreTypes.sv
rtl/core/riscv_cpu.sv
rtl/core/myCPU.sv
rtl/core/front/*
rtl/core/decode/*
rtl/core/regs/*
rtl/core/execute/*
rtl/core/memory/*
rtl/core/control/*
rtl/core/perf/*
```

当前 `riscv_cpu` 只做：

1. reset 后 PC 从 `0x8000_0000` 开始。
2. 每周期发单端口 IROM 取指请求。
3. 保存一拍 IF 调试状态。
4. 数据总线保持 idle。
5. `perf_cycle` 递增，其他提交/分支计数为 0。

后续 Phase 1 再实现 decode、execute、load/store 和提交。

### 2. IP 平替模型调整

`rtl/ip/IROM_0.sv`：

- 从双端口 ROM 改为单端口 ROM。
- 保留地址打一拍、`douta = mem[addr_q]` 的取指相位。

`rtl/ip/DRAM_0.sv`：

- 保持单端口 RAM、byte write enable。
- read 周期直接 `douta <= mem[addra]`，配合 adapter 对外形成 request 后下一拍可采样的响应模型。

`fpga/create_vivado_project.tcl`：

- `IROM_0` 从 `Dual_Port_ROM` 改为 `Single_Port_ROM`。
- 删除 B 口相关配置。

### 3. SoC memory bridge 骨架

新增：

```text
rtl/soc/DramBramAdapter.sv
rtl/soc/SocMemBridge.sv
```

`DramBramAdapter` 负责：

1. byte address 转 DRAM word address。
2. store data/mask 按 `addr[1:0]` 左移。
3. load data 按 offset 右移。
4. 对外用 `resp_valid/resp_rdata` 表示读返回。

`SocMemBridge` 负责：

1. DRAM 地址范围分流到 `DramBramAdapter`。
2. MMIO 地址处理 SW/KEY/SEG/LED/counter。
3. 保持 `counter.sv` 不修改。

### 4. `student_top` 适配

`rtl/soc/student_top.sv` 已重写为：

```text
student_top
  -> myCPU
  -> single-port IROM_0
  -> SocMemBridge
```

外部端口保持不变。`VERILATOR_TB` 下只保留当前骨架实际提供的基本调试口：

```text
dbg_perip_addr/wdata/mask/wen
dbg_perf_cycle/commit/branch/branch_miss
```

### 5. filelist 和 Verilator TB 适配

`scripts/filelists/core.f`：

- 替换为新五级流水文件顺序。

`scripts/filelists/soc.f`：

- 移除旧 `dram_driver.sv/perip_bridge.sv`。
- 加入 `DramBramAdapter.sv/SocMemBridge.sv`。

Verilator C++ 适配：

- `dut_mycpu_io.cpp` 改为单 IROM + dmem ready/valid 端口。
- `dut_student_top_io.cpp` 改为读取精简 perf debug 口。
- `sim_memory` 增加 `current_dmem_resp_valid()`，并把 memory response 模型调整为一拍响应视角。

## 验证

已通过：

```text
make verilator-build BUILD_JOBS=8
make verilator-build-src BUILD_JOBS=8
```

说明：

1. `myCPU` Verilator elaboration/build 通过。
2. `student_top` Verilator elaboration/build 通过。
3. 此阶段没有运行 ISA 仿真通过性，因为 CPU 功能尚未实现，运行会超时是预期行为。

## 已知未完成

1. `riscv_cpu` 还没有 decode/execute/writeback。
2. `LoadStoreUnit/DCache/StoreWriteBuffer` 目前是占位模块。
3. `RegFile/CsrFile/MulDivUnit` 目前是占位模块。
4. `PerfCounter` 目前只通过 `riscv_cpu` 输出基础 cycle。
5. Vivado 未运行；Tcl 只做静态同步修改。
6. 旧 `rtl/core` 删除记录和旧 `backup/` 删除记录是本次开始前工作树已有状态，本次没有恢复或清理。

## 下一步

进入 Phase 1：

1. 实现 `RegFile`、`Decode`、`Alu`。
2. 接通 IF/ID/EX/MA/WB payload。
3. 先用保守 RAW stall 跑通 RV32I ALU/branch/load/store。
4. 用 `rv32ui-p-simple` 作为第一个功能目标。
