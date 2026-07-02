# 中文文档与 RTL 设计文档更新归档

## 背景

用户要求 `docs/` 下文档统一使用中文，并新增 `docs/README.md` 作为索引和总览。同时要求详细阅读当前 `rtl/core`，维护当前 RTL 设计文档。

## 本次修改

1. 将已有工程框架、存储/测试契约、Verilator 规划、归档文档改为中文。
2. 新增 `docs/README.md`，作为文档总览和索引。
3. 新增 `docs/design/rtl_core_design.md`，记录当前 `rtl/core` 的：
   - 顶层定位和文件分层
   - 全局参数
   - PF/IF/ID/RN/DS/IS/RR/EX/WB/CM 主流水
   - Ctrl/Recovery 控制优先级
   - SpecRAT/ArchRAT/FreeList/ReadyTable
   - ROB/IssueQueue/Payload/StoreBuffer
   - ALU/MEM/MUL/BRC/SYS 执行单元
   - WriteBack/Commit/RecoveryManager 行为
   - 当前维护风险和推荐 debug 顺序

## 未修改内容

1. 未修改任何 RTL。
2. 未修改 filelist。
3. 未新增仿真 harness 或 Makefile。

## 后续建议

后续开始 Verilator harness 或 core bug 修复时，以 `docs/design/rtl_core_design.md` 作为当前设计事实基线；若发现文档与 RTL 不一致，应优先更新设计文档。

