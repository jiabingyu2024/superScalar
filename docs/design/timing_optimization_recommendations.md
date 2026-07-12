# 时序优化建议与实施顺序

## 优先级判断

目标同时是 `IPC >= 0.8` 和 `200 MHz`。最直接的“所有相关 load/store 插一拍”确实能切断 C1->AGU 反馈，但实测 IPC 从 `0.826767` 降到 `0.789894`，不满足目标。因此不建议直接采用全量 bubble 方案。

## 建议一：把 AGU 旁路改为受控的短路径旁路

当前旁路让所有非 load、非 M 指令结果都可能进入 C0 AGU，综合后形成 32 位 ALU + AGU 的长反馈。建议按以下顺序收窄：

1. 只对 `ADDI/LUI/AUIPC` 等可证明为简单加法或立即数结果的指令旁路；
2. 排除会经过复杂 ALU、移位、比较、CSR、分支和 Zb 运算的结果；
3. 对地址依赖只保留 `rd == rs1` 且下一条确实是 load/store 的情况；
4. 在 RTL 中显式分离 `agu_base_fast`（简单结果）和 `agu_base_rf`（寄存器堆/C2），避免综合把复杂 ALU mux 放进 AGU 路径。

这预计能恢复大部分 `0.826767` IPC，同时减少最差路径的逻辑级数。需要用 Verilator 统计地址依赖覆盖率，确认旁路命中率和 IPC 损失。

## 建议二：增加一个“地址生成寄存器”而不是全量停顿

如果建议一仍不能达到 200 MHz，可只对地址相关指令增加轻量 AGU holding register：

```text
C0 ID/AGU -> AGU_Q
C1 Cache request
```

普通指令仍保持 `C0 ID -> C1 EX -> C2 WB`，只有 C1 结果紧邻的 load/store 使用 AGU_Q。这样不会把所有内存指令变成两拍，也不会像全量 bubble 一样影响独立 load/store；代价是相关 load/store 增加一拍。

## 建议三：reset release 分域同步

把 CPU reset release 改为 200 MHz 域的两级同步信号：

- 异步 assertion 保留；
- deassertion 在 `clk_out2_pll` 域同步；
- CPU 内部使用同步释放后的 reset；
- 50 MHz 外设继续使用自己的 reset synchronizer。

这样可以消除 `cpu_rst_sync_reg -> rf_mem CLR` 的 recovery 违例，而不是简单对 reset 路径加 false path。若工程规定允许把 reset recovery 从 signoff 排除，也必须在 XDC 中明确说明原因，并单独保留 reset CDC 检查。

## 建议四：DCache 实现方向

当前 DCache 数据阵列被 Vivado 映射为约 `258` 个 `RAM64M` 分布式 RAM。它满足功能上的一拍响应，但 tag compare、LUTRAM 读和返回 mux 仍会产生高布线延迟。后续可评估：

- 将 tag/data 改为真正的同步 BRAM 结构；
- 用 critical-word-first 保持 miss 的架构行为；
- 将 byte/half sign extension 放在 cache response register 前，但必须重新检查 C2 bypass 的 fanout；
- 对 cache hit 的 index/tag compare 做物理层级约束或局部复制。

这类改动可能影响资源和 IPC，必须以 routed report 和 Verilator 结果共同验收。

## 建议五：Vivado 验证门槛

每次候选改动按以下顺序验收：

1. `make sim-rv32-all NO_BUILD=1`；
2. `srcSmoke`；
3. `srcWithMext` 至少 5M 周期，记录 IPC、DCache 命中率和 stall；
4. `vivado.bat -mode batch -source fpga/run_vivado_impl.tcl -tclargs srcWithMext 200.000`；
5. 同时查看 setup、hold、recovery、TNS 和失败端点数；
6. 不接受只通过 setup、但 recovery/hold 仍违例的结果。

## 推荐下一轮实现

先实现“建议一”的受控简单结果旁路，并保留当前分支方向优化；不要采用全量 C1-AGU bubble。若 setup WNS 仍低于 `-0.3 ns`，再引入建议二的地址生成寄存器。reset 分域同步应作为独立提交，避免把 datapath 和 reset 约束问题混在同一次性能比较中。
