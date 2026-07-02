# 评审修订：IROM/DRAM、CSR、无 cache 与 reset 约束

> 本次根据用户反馈修订 `003_rtl_review_risks_and_gaps.md`，并把确认后的硬件设计细节同步到 `docs/design/`。本次不修改 RTL。

## 1. 修订结论

1. IROM 时序明确为 BRAM 风格：地址在时钟沿寄存，随后用寄存地址组合读出指令。
2. DRAM 时序明确为两拍读返回，`myCPU` 中 `accessReady=1'b1` 表示命令接受，不表示 load 数据同拍有效。
3. 当前设计没有 cache，因此 `FENCE/FENCE.I` 在项目内按 serial NOP 处理，不要求 cache flush 或取指失效语义。
4. CSR 当前只承诺测试子集：`mstatus/mtvec/mepc/mcause`；非白名单 CSR 读 0、写忽略，不承诺 Zicntr。
5. reset 暂不重构 RTL，统一成文档约束：CPU 域高有效 reset，UART/twin_controller 低有效 reset，后续新增 core 模块默认高有效 `rst`。

## 2. 修改文件

| 文件 | 修改内容 |
| --- | --- |
| `docs/archive/2026-07-02/003_rtl_review_risks_and_gaps.md` | 更正 2.1、3.2、3.3、5.1 的风险描述、优先级和处理口径。 |
| `docs/design/memory_and_test_contract.md` | 增加 IROM/DRAM 周期表、CSR 白名单、FENCE/FENCE.I 无 cache 行为约束。 |
| `docs/design/rtl_core_design.md` | 增加 reset 层级约束、IROM 取指时序、CSR/FENCE 支持边界，并修正维护风险表述。 |

## 3. 后续行动约束

1. 编写 Verilator TB 时，IROM/DRAM 模型必须按本文档固定时序实现。
2. rv32 测试集合选择应避开当前不承诺的 CSR/Zicntr 能力，除非先扩展 RTL。
3. 若后续要支持 `rv32mi-p-sbreak`，应单独补 EBREAK trap，而不是把 FENCE 路径当成同一问题处理。
4. reset 统一化若需要做，应作为独立硬件改造任务，并配套仿真和上板验证。
