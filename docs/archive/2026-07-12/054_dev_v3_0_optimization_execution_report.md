# dev-v3.0 优化计划执行报告

## 1. 执行范围

本轮基于 `053_dev_v3_0_250mhz_deep_timing_analysis.md` 执行 Phase A、Phase B，以及可在不破坏 IPC 的前提下落地的 Phase C/D 项目。Vivado 只在 RTL 批次基本稳定后集中运行两次，用于确认结构变化和 IP 配置的真实实现结果。

## 2. 已落地优化

### 2.1 外部 memory request/response 边界

- `myCPU` 增加满吞吐的 registered request slot：DCache 仍可每拍提交请求，SoC/BRAM 端口只由寄存器驱动。
- response 在 DCache 外部增加一拍寄存器，切断 BRAM/SoC response 到 DCache 的组合传播。
- `SocMemBridge` 和 `DCache` 都把 256 KiB 对齐地址窗改成高位 prefix compare，去掉 32-bit range compare/subtract。
- DRAM `ENA` 常置 1，读消费由 `REGCEA` 和 valid token 定义；这消除了 68 个 BRAM tile 的高扇出 ENA setup 路径。

### 2.2 DRAM 两拍合同

- `DRAM_0` 行为模型实现 `memory latch -> primitive output register`。
- `DramBramAdapter` 用 `read_valid_d1` 驱动 `REGCEA`，用 d2 对齐 `resp_valid` 和 byte offset。
- Vivado Tcl 启用 `Register_PortA_Output_of_Memory_Primitives=true`、`Use_REGCEA_Pin=true`。

### 2.3 DCache refill 和局部化

- refill 改为 critical-word-first 后连续发出四个固定顺序请求，响应按顺序写入 line；不再“发一字、等返回、再发下一字”。
- tag 强制 distributed RAM；四个 word bank 显式复制 write-index 网络，限制单个地址网的物理扇出。
- DCache 的 miss lookup 仍保持原有 hit latency，未强行改成全同步 BRAM。

### 2.4 completion/LS 控制

- 四候选 ordered gearbox 改为固定深度显式优先逻辑，去掉通用 `for`/整数计数推导。
- q1 采用 cold spill：q1 valid 时只冻结一拍并移入 q0，q1 的 rd/data 不再进入 C0/C1 快旁路；q0/当前 EX/LS WB 保留局部快路径。
- LS 对当前 C1 producer 的结果在 LS 入槽边沿直接捕获地址/写数据；q1 或更老的 LS-load 依赖仍按寄存后下一拍请求。

### 2.5 reset、M 单元和综合层次

- core 内异步 reset 全部改为同步 reset；front/exec/LS 各有本地 reset replica，payload/data/tag 不再挂异步 CLR/PRE。
- 三套 LUT multiplier 合并为一套可选符号扩展的 33x33 multiplier。
- MUL latency 从 3 改为 2；Vivado Tcl 最终确认 `Multiplier_Construction=Use_Mults`，实现为 4 个 DSP block、0 LUT。
- 移除顶层 `student_top` 的 `dont_touch`，默认 `flatten_hierarchy rebuilt`。

## 3. 已验证结果

### Verilator

| 项目 | 结果 |
| --- | --- |
| RV32 全套 directed | PASS |
| `srcSmoke` 50M 上限 | PASS，约 38.9M 周期完成 |
| `srcWithMext` 5M | TIMEOUT 采样，IPC `0.819108` |
| `srcWithMext` 100M（L0 实验前） | TIMEOUT 采样，IPC `0.851737` |

L0 hot-line 实验曾把所有非 L0 hit 延迟到 registered L1 lookup，5M IPC 降至 `0.608878`，因此已撤销。当前工作树已恢复到 pre-L0 版本，`srcSmoke` 和 5M 重新验证通过。

### Vivado routed

基线来自 053 文档：WNS `-3.892 ns`、TNS `-19,995.914 ns`、11,278 个 setup failing endpoints。

第一轮结构优化（request/response boundary、sync reset、streaming refill、q0/q1、ENA 常开、flatten rebuilt）：

- WNS `-3.292 ns`
- TNS `-8,977.573 ns`
- setup failing endpoints `8,482`
- router estimated WHS `+0.029 ns`

第二轮增加 DCache prefix compare 和 DSP multiplier：

- WNS `-3.442 ns`
- TNS `-8,742.284 ns`
- setup failing endpoints `8,201`
- DSP blocks `4`，`u_mul` LUT `0`

第二轮 WNS 比第一轮差 `0.150 ns`，属于 placement/route 变化，不能说明 DSP 化无价值；TNS 和 failing endpoint 数继续下降。

## 4. 当前剩余主瓶颈

第二轮最差路径已不再是外部 BRAM enable，而是：

```text
u_reg_c1_c2/o_rd_addr 或 o_reg_write
  -> q/LS dependency compare
  -> LS address/offset carry
  -> DCache distributed tag lookup/hit
  -> hazard/hold/reset CE
  -> reg_id_c1/reg_id_ls/IFID
```

典型路径 data delay `7.0--7.1 ns`，route 占比约 `77%`，15--17 logic levels。它证明剩余问题是全局 ready/hold 控制与 DCache tag lookup 同拍耦合，单纯继续做 LUT 优化或 seed 搜索不会达到 250 MHz。

## 5. 下一阶段明确方向

1. 把 LS/DCache 请求改成真正的局部 elastic slot：global front/C1 不再直接由 DCache tag hit 或 LS dependency 组合决定。
2. 用两项局部状态替代全局 stall：LS request pending、DCache lookup pending；只有 slot 满时才冻结前端。
3. 对 DCache 做同步 RAM/L0 方案时，必须保持非热点 hit 的一拍路径；本轮 L0 实验表明“所有 L1 miss 都额外两拍”不可接受。
4. 在下一轮 Vivado 前增加 routed path 聚类脚本，分别统计 `reg_id_c1` reset/CE、`reg_id_ls` CE、BPU write 和 DCache tag endpoints。

当前结论：本轮已把 WNS 改善约 `0.6 ns`、TNS 降低约 `56%`，IPC 长窗口保持在 `0.85` 左右，但 250 MHz 尚未达标。下一轮需要改变全局 stall 的微架构边界，而不是继续堆叠局部综合 directive。

## 6. LS elastic FIFO 实验及否决结论

在第二轮 routed 结果之后，实现并验证了一个 2-entry LS request/metadata FIFO。该版本把 `{read/write, addr, wdata, mask, rd, unsigned}` 一起排队，DCache `ready` 只驱动 FIFO 出队，不再组合进入 `ls_busy -> c1/front hold`。功能上完整 RV32 directed 全部通过，证明请求、store 顺序和 load metadata 可以在这个边界正确对齐。

但该方案把常规 DCache hit 也变成“先入 FIFO、下一拍 lookup”，性能不可接受：

| 配置 | 5M `srcWithMext` IPC | load-return stall | 结论 |
| --- | ---: | ---: | --- |
| 稳定基线 | `0.819108` | `0` | 保留 |
| 2-entry registered FIFO | `0.568933` | `1,819,980` | 否决并撤销 |

随后试验 empty-queue fall-through：hit 直达 DCache，只有 miss/replay 落入 FIFO，并用 registered pending-load tag 冻结相关 C1。该实验的 `lb` directed 通过，但 `lw` 在 cache miss/replay 后进入错误测试循环，因此同样撤销，没有进入稳定 RTL。

最终 `rtl/core/core.sv` 已逐字恢复到 FIFO 实验前版本，并重新验证：

- 两个 Verilator model 均重新构建成功；
- 完整 RV32 directed 全部 PASS；
- 5M `srcWithMext` 恢复为 commit `4,095,542`、IPC `0.819108`；
- 当前 routed checkpoint 与恢复后的 RTL 对应，不需要为已完全撤销的实验重复运行 Vivado。

这个实验把下一版 elastic 设计的约束进一步收紧：不能给普通 hit 增加固定寄存拍；必须显式区分 hit completion 与 miss token；pending-load scoreboard 必须覆盖 C0 RAW/WAW、已经进入 C1 的相关指令，以及 miss/replay 边沿的数据旁路。满足这三点前，不应再次把 DCache ready 从当前接口直接替换成普通 FIFO ready。
