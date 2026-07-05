# DIV_0 blocking 输出端口修正记录

## 背景

Vivado 综合报错：

```text
[Synth 8-11365] for the instance 'div_ip' of module 'DIV_0' ... named port connection 'm_axis_dout_tready' does not exist
```

当前 `fpga/create_vivado_project.tcl` 将 `DIV_0` 配置为：

```tcl
set_ip_config_required DIV_0 {FlowControl flow_control} {Blocking}
```

该配置下 Vivado `div_gen` 输出通道没有 `m_axis_dout_tready`。原 RTL 仍按带输出 ready 的 AXI-Stream 边界例化，因此综合阶段端口不匹配。

## 修改内容

1. `rtl/core/ExecuteStage/ExecuteMulStage.sv`
   - 删除 `DIV_0` 例化中的 `.m_axis_dout_tready(1'b1)`。
   - 保留输入侧 `s_axis_dividend_tready/s_axis_divisor_tready`，与当前 stub 报错信息一致。

2. `rtl/ip/DIV_0.sv`
   - 删除行为模型端口 `m_axis_dout_tready`。
   - 输出侧改为固定每拍推进，`m_axis_dout_tvalid/tdata` 直接由 34 拍 pipeline 末端寄存输出。

3. `docs/design/rtl_core_design.md`
   - 记录 `DIV_0` 使用 `FlowControl=Blocking`，输出侧没有 ready，core 也不支持除法输出反压。

4. `docs/fpga/vivado_project.md`
   - 更新 `DIV_0` 端口表和 Vivado IP 约定。

## 设计结论

当前 core 的 M 扩展路径是单入口、固定延迟 metadata 对齐设计：

```text
divLaunch
  -> DIV_0 输入 valid
  -> divMetaPipe 固定推进 34 拍
  -> m_axis_dout_tvalid + divMetaPipe[34] 同时有效
  -> ExecuteMulStage 直接写回
```

因此输出侧没有必要引入 `tready`。如果后续将 `DIV_0` 改成 NonBlocking 或需要结果反压，必须同步增加 metadata pipeline 暂停/保持逻辑，否则 quotient/remainder 会和 ROB/Rd/lane 元信息错位。

## 验证

已执行：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果通过，说明 RTL 和 `rtl/ip/DIV_0.sv` 行为模型端口已一致。未执行 Vivado。
