# 单实例 MUL_0 乘法 IP 替换记录

## 背景

后续 FPGA 上板不希望综合器自由推断乘法器实现，而是希望像 `IROM_0/DRAM_0` 一样使用明确的 Vivado IP 边界。用户进一步确认：当前只例化一个 `mul` IP，不做两 lane 各一颗乘法器。

## 本次设计决策

1. 只替换乘法路径，除法/取余暂不接 Vivado IP。
2. `MUL_0` 端口固定为 `CLK/A/B/P`，其中 `A/B` 为 signed 33 bit，`P` 为 signed 66 bit。
3. `MUL_0` 固定 3 拍 pipeline，无 reset、无 clock enable。
4. core 内只例化一颗 `MUL_0`。
5. `IssueQueue` 只允许 issue slot 0 选择 `TUBE_TYPE_MUL`，避免两个 lane 同时争用单颗 M 执行入口。
6. `ExecuteMulStage` 用 metadata 保存 `Rd/writeRd/robIndex/lane`，在 3 拍后将乘法结果写回原 lane。

## 修改内容

| 文件 | 修改 |
| --- | --- |
| `rtl/core/DispatchStage/IssueQueue.sv` | 新增 `mulSelected`，并禁止 issue slot 1 pop `TUBE_TYPE_MUL`，把 M 类 uop 收敛到单 issue lane。 |
| `rtl/core/ExecuteStage/ExecuteMulStage.sv` | 从多实例乘法模型改为单实例 `MUL_0`；新增 lane metadata；乘法结果按原 lane 写回。 |
| `rtl/ip/MUL_0.sv` | 新增 Verilator 行为模型，模拟 33x33 signed、3 拍 pipeline 的 Vivado `mult_gen`。 |
| `scripts/filelists/ip_verilator.f` | 纳入 `rtl/ip/MUL_0.sv`。 |
| `scripts/filelists/verilator_mycpu.f` | 纳入 `ip_verilator.f`，保证 rv32/myCPU DUT 能解析 core 内 `MUL_0` 实例。 |
| `fpga/create_vivado_project.tcl` | 新增 Vivado `mult_gen` IP `MUL_0` 的创建和参数设置。 |
| `docs/design/rtl_core_design.md` | 更新 M 扩展执行单元、单乘法 IP、issue 约束和 lane 写回说明。 |
| `docs/fpga/vivado_project.md` | 新增 Vivado 工程/IP 生成约定。 |
| `docs/sim/verilator_plan.md` | 更新 filelist 说明和本次 smoke 结果。 |

## 验证记录

已运行：

```sh
make verilator-build BUILD_JOBS=4
make sim-rv32 SUITE=rv32ui MAX_CYCLES=30000 NO_BUILD=1
make sim-rv32 SUITE=rv32um MAX_CYCLES=30000 NO_BUILD=1
make verilator-build-src BUILD_JOBS=4
make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1
```

结果：

1. `make verilator-build` 通过。
2. `rv32ui` 全部通过。
3. `rv32um` 全部通过：`div/divu/mul/mulh/mulhsu/mulhu/rem/remu`。
4. `make verilator-build-src` 通过。
5. `srcSmoke` 10000 周期短跑按预期 TIMEOUT，但早期 SEG/counter/MMIO 记录正常：`SEG=0x37000000`，counter start cycle 为 `2569`。

未在本机运行 Vivado，因此 `fpga/create_vivado_project.tcl` 中 `mult_gen` 的 `CONFIG.*` 属性尚未经过 Vivado 实测。若 Vivado 版本属性名不一致，应以 `report_property [get_ips MUL_0]` 为准微调 Tcl。

## 后续注意

1. 单颗 `MUL_0` 和单 issue lane 会降低连续 M 类 uop 吞吐，不应再按“两路各一颗乘法器”估算 M 扩展 IPC。
2. 如果后续要提升 `srcWithMext` 性能，需要单独评估是否增加第二颗 `MUL_0`、拆分 MUL/DIV issue 资源，或将 DIV/REM 替换为独立 IP。
3. `rtl/ip/MUL_0.sv` 只服务 Verilator，不应加入 FPGA sources。
