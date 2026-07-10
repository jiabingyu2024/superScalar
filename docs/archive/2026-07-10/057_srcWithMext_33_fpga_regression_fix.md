# srcWithMext 板级 33/37 回退定位与修复

日期：2026-07-10

## 1. 现象解码

板上数码管显示 `0x33800000`，按 `srcWithMext` 协议解码为：RV32I 通过 33/37，M 扩展通过 8/8。问题不在 DIV/MUL packing，而在基础测试或其计数访存路径。

正确的早期计数显示必须为 `0x37800000`，最终还需出现 PASS 灯阵。

## 2. 定位证据

### 2.1 RTL 回归

在提交 `d9e22f3` 上重建 Verilator：

| 回归 | 结果 |
| --- | ---: |
| RV32UI | 40/40 PASS |
| RV32UM | 8/8 PASS |
| RV32MI | 4/4 PASS |
| `srcWithMext`, 200000 cycles | 正常 TIMEOUT，无提前 FAIL |

短窗口在第 2259 周期写出 `SEG=0x37800000`，同时 RV32I pass/fail 为 37/0，M count 为 8。因此基础 ISA 和 M 扩展行为仿真正确；板级 33/37 是实现相关回退。

### 2.2 Vivado 实现证据

失败 bitstream 首次同时包含 DCache distributed RAM 和宽 payload 去异步复位两类 QoR 修改。Vivado 2023.2 报告：

- DCache data/tag 映射为 1520 个 `RAMD64E`；
- `CoreROB` 94 条 `Synth 8-7137`；
- `CoreBranchPredictor` 5 条 `Synth 8-7137`；
- `CoreMultiPushFifo` 1 条 `Synth 8-7137`。

该告警明确说明可能造成 simulation mismatch。原写法虽未在 reset 分支给 payload 赋值，但 payload 写入仍处在带异步 reset 的同一个 `always_ff` 中，Vivado会把整个过程按异步控制过程分析。

DCache 还有实现语义缺口：distributed RAM 是异步读、同步写，原 RTL 未显式固定写入后下一拍同址读取值；refill 最后一拍进入 `DC_FINISH` 和 byte/halfword store 后读取都依赖该行为。

### 2.3 不是 50 MHz 时序违例

失败 bitstream routed timing 为：CPU setup WNS `+0.923 ns`，CPU hold WHS `+0.026 ns`，TNS/THS 均为 0。所有已约束路径满足 50 MHz，没有证据把 33/37 归因于 setup/hold 违例。

## 3. RTL 修复

### 3.1 拆分 state 与 payload 时序块

`BranchPredictor.sv`、`ROB.sv`、`MultiPushFifo.sv` 将 valid/count/head/tail 与宽 payload 写入拆成独立过程。带异步 reset 的过程只维护 ownership/state；payload 位于仅 `posedge clk` 的过程，并用 `!rst && !clear_i` 禁止 reset/flush 期间写入。

该修改保留降低 reset fanout 的收益，并消除 Vivado 对 payload 异步控制语义的歧义。

### 3.2 DCache 写后读旁路

`DCache.sv` 记录最近一次 data RAM 写入的 way/address/data。读取地址命中上一拍写入时优先返回旁路数据，覆盖：

- refill 最后一拍到 `DC_FINISH` 的 critical word；
- store hit 后紧随的同址读取；
- byte/halfword 合并后的确定性读取。

RAM/tag 写时序块增加 `!rst` 门控。cache 容量、CPU 接口、命中判定和 miss 状态机拍数不变。

## 4. 验证状态

修改后的回归已完成：RV32UI 40/40、RV32UM 8/8、RV32MI 4/4；`srcWithMext` 200000-cycle 窗口为 `0x37800000`，无提前 FAIL；Verilator 未新增 `MULTIDRIVEN`、`UNOPTFLAT` 或 `ALWCOMBORDER`。

加入 reset 期间写门控后再次完成同一组最终回归，结果保持不变。

按用户要求停止了耗时的 routed netlist XSim，未得到门级动态结论。因此当前结论是“已定位并修复明确的综合语义风险”，不是“新 bitstream 已板验通过”。

## 5. 新工程验收

必须生成全新工程，不复用失败 run：

```tcl
set ::env(FPGA_MEM_PROFILE) srcWithMext
set ::env(FPGA_BUILD_TAG) implfix_p1
set ::env(FPGA_ENABLE_POWER_OPT) false
source fpga/create_vivado_project.tcl
```

验收条件：

1. ROB/BPU/MultiPushFifo 的上述 `Synth 8-7137` 归零；
2. DCache data/tag 仍推断为 distributed RAM；
3. routed setup/hold 均无违例；
4. 上板先看到 `0x37800000`，不能再是 `0x33800000`；
5. 最终 PASS 灯阵、右侧 8 灯和计时显示满足协议。

若新工程仍为 33/37，下一步增加 37 项子测试的 fail bitmap，而不是继续根据总数猜测失败编号。
