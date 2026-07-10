# FPGA 文档索引

`docs/fpga/` 只维护当前有效的 FPGA 工程事实，历史分析和单次修复记录放在 `docs/archive/YYYY-MM-DD/`。

| 文档 | 职责 |
| --- | --- |
| [vivado_project.md](vivado_project.md) | Windows Vivado GUI Tcl Console 建工程、分阶段综合实现、报告与验收命令 |
| [ip_timing_alignment.md](ip_timing_alignment.md) | Vivado IP、Verilator 行为模型、SoC adapter 和 core 消费端的 latency/packing/CDC 契约 |

维护规则：

1. GUI 操作和工程属性只写入 `vivado_project.md`。
2. IP latency、端口、packing 和模型一致性只写入 `ip_timing_alignment.md`。
3. 某次运行的日志、WNS、资源数字和修复过程写入 `docs/archive/`，不堆入当前操作手册。
4. 当前文档不提供额外的 Vivado 启动 Tcl；用户直接在 Windows Vivado GUI Tcl Console 执行命令。
