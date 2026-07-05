# 单实例 DIV_0 除法 IP 替换记录

## 背景

在乘法已经收敛为单实例 `MUL_0` 后，本次继续把 RV32M 的 `DIV/DIVU/REM/REMU` 路径替换为明确的 Vivado `div_gen` IP 边界。用户确认不沿用原先 36 拍 RTL 恢复除法，改用更典型的 34 拍 unsigned 32/32 Radix-2 配置，目标频率至少 150 MHz。

## 本次设计决策

1. core 内只例化一颗 `DIV_0`。
2. `DIV_0` 使用 AXI4-Stream 风格端口，和 Vivado Divider Generator 保持同名边界。
3. `DIV_0` 只做 unsigned 32/32，输出 quotient + remainder。
4. `DIV_LATENCY` 固定为 34。
5. `IssueQueue` 仍只允许 issue slot 0 发射 `TUBE_TYPE_MUL`，因此 `MUL/DIV/REM` 共享单 M issue lane。
6. RISC-V signed、除零、`0x80000000 / -1` 溢出由 `ExecuteMulStage` 外围处理，不依赖 IP 特殊输出。
7. 对除零/溢出这类特例，仍给 `DIV_0` 送安全假输入，以保持 IP 输出流和 metadata 的 34 拍节奏对齐。

## 修改内容

| 文件 | 修改 |
| --- | --- |
| `rtl/core/ExecuteStage/ExecuteMulStage.sv` | 删除原 36 拍恢复除法迭代管线；新增单实例 `DIV_0`；用 `divMetaPipe` 延迟 metadata 并在 34 拍后做符号恢复和结果选择。 |
| `rtl/core/DispatchStage/DispatchStage.sv` | `delay_for()` 中 div/rem wakeup delay 从 36 改为 34。 |
| `rtl/ip/DIV_0.sv` | 新增 Verilator 行为模型，模拟 unsigned 32/32、remainder mode、34 拍输出。 |
| `scripts/filelists/ip_verilator.f` | 纳入 `rtl/ip/DIV_0.sv`。 |
| `fpga/create_vivado_project.tcl` | 新增 Vivado `div_gen` IP `DIV_0` 的创建和参数设置。 |
| `docs/design/rtl_core_design.md` | 更新 M 扩展执行单元、`DIV_LATENCY=34`、`DIV_0` AXIS 打包和 signed/特例处理说明。 |
| `docs/fpga/vivado_project.md` | 更新 Vivado IP 表和 `DIV_0` 端口/打包约定。 |
| `docs/sim/verilator_plan.md` | 更新 filelist 说明和本次构建结果描述。 |

## 验证记录

已运行：

```sh
make verilator-build BUILD_JOBS=4
make sim-rv32 SUITE=rv32um MAX_CYCLES=30000 NO_BUILD=1
make sim-rv32 SUITE=rv32ui MAX_CYCLES=30000 NO_BUILD=1
make verilator-build-src BUILD_JOBS=4
make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1
```

结果：

1. `make verilator-build` 通过。
2. `rv32um` 全部通过：`div/divu/mul/mulh/mulhsu/mulhu/rem/remu`。
3. `rv32ui` 全部通过。
4. `make verilator-build-src` 通过。
5. `srcSmoke` 10000 周期短跑按预期 TIMEOUT，但早期 SEG/counter/MMIO 记录正常：`SEG=0x37000000`，counter start cycle 为 `2569`。

未在本机运行 Vivado，因此 `fpga/create_vivado_project.tcl` 中 `div_gen` 的 `CONFIG.*` 属性尚未经过 Vivado 实测。若 Vivado 版本属性名不一致，应以 `report_property [get_ips DIV_0]` 为准微调 Tcl。

## 后续注意

1. 当前 M 类 uop 仍是单 issue lane，不应按两路 M 执行估算性能。
2. `DIV_0` 的 AXIS ready 当前按 fully pipelined、始终可接收输入使用；若 Vivado 配置导致 `tready` 不是常高，需要给 `ExecuteMulStage` 增加 backpressure，否则 metadata 和数据流会错位。
3. `MUL_0` 和 `DIV_0` 可能同周期完成并争用同一 `nextMulToStage[lane]`。当前保持原有优先级：MUL 覆盖 DIV。若后续真实程序触发该碰撞，应补 M 执行单元输出仲裁或 issue 侧结果端口避让。
