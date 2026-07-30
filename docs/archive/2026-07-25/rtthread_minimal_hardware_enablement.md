# RT-Thread 最小硬件使能

## 目标

在不创建或修改 RT-Thread BSP 的前提下，为当前单核 RV32 core 补齐首版
machine timer interrupt，并使 Harvard IROM 能承载普通 C 程序的只读数据。

## 硬件改动

- CSR File 新增 `mie.MTIE` 与只读 `mip.MTIP`。
- machine timer interrupt 接受条件为 `mstatus.MIE && mie.MTIE && mip.MTIP`。
- 中断在正常提交且 memory quiescent 时精确进入，写
  `mcause=0x80000007`、`mtval=0`，并把提交指令的架构 next-PC 写入 `mepc`。
- 新增 64 位 `mtime/mtimecmp`，MMIO 地址采用常见 CLINT 布局：
  `0x02004000/04` 与 `0x0200bff8/fc`。
- IROM 从 16 KiB 扩到 64 KiB，并在 SoC 中用相同初始化镜像增加只读数据口。
  数据口可读取 `.rodata` 和 `.data` 初值，写 IROM 无效果。
- DRAM 仍为 `0x80100000..0x8013ffff` 的 256 KiB。

## 保守边界

- 只实现 machine timer interrupt，不实现 MSIP、MEIP、中断嵌套或 `WFI`。
- 中断等待 memory quiescent，优先保证 StoreBuffer 和 load 状态的精确性；这可能
  增加中断延迟。
- BSP、链接脚本、UART控制台均未在本次修改范围内。

## 验证

- `make verilator-build`：通过。
- `make verilator-build-src`：通过。
- RV32I、RV32M、CSR/ECALL/EBREAK/Zicntr 支持集：全部通过。
- `rtos_timer_irq.S`：验证 MTIE/MIE 使能、`mcause=0x80000007`、对齐
  `mepc`、清除 timer pending 和 `mret` 返回，通过。
- `rtos_soc_hw.S`：在 `student_top` 验证内部 `mtime/mtimecmp`、ROM 数据口读取和
  timer interrupt 往返，通过。

全量 RV32 命令仍会运行已配置关闭的 Zb 扩展测试；这些用例继续按预期失败，
与本次修改无关。
