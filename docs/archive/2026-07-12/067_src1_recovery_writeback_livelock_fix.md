# src1 Store 数据丢唤醒与 LSU 活锁修复记录

日期：2026-07-12

## 1. 现象

`src1` 在约 2.1k 周期后停止提交，长跑到 5,000,000 周期后以 `TIMEOUT` 返回。停止前约提交 1,050 条指令，最后提交 PC 为 `0x80000420`。仿真进程能够正常结束，因此不是 Verilator 卡死。

长期阻塞计数呈现稳定活锁：ROB 头等待 INT、INT IQ 反压、MEM request stage 有效以及 StoreBuffer partial-alias 几乎同时持续到测试结束；DCache miss 和实际 load pending 周期很少，不能解释停顿。

触发附近指令为：

```text
80000418  sw   x1,28(x2)
8000041c  sw   x8,24(x2)
80000420  addi x8,x2,32
80000424  sw   x10,-20(x8)
80000428  sw   x11,-24(x8)
8000042c  lw   x14,-20(x8)
```

## 2. 根因

定向日志确认最终阻塞 entry 为：

```text
store pc=0x80000424, rob=19, data_prd=42, data_valid=0
load  pc=0x8000042c, addr=0x80134f7c, forward_hit=1, forward_full=0
```

PRD42 的正确 completion（结果为 2）发生在 store 从 MEM-IQ 提前进行地址发射之后、request/StoreBuffer 数据 owner 建立之前。MEM-IQ 已因地址发射移除了 store；StoreBuffer shell 尚不存在；原 LSU 只匹配当前拍 completion，没有保存刚刚错过的 completion。因此 producer 不会再次完成，`data_valid` 永久为 0。

```text
T0: store 地址发射，src2 尚未 ready，MEM-IQ 移除 store
T1: src2 completion 到达，但 StoreBuffer shell 尚未可见
T2: shell 建立，completion 已结束，之后永久等待
```

后续同地址 load 因 `forward_hit && !forward_full` 既不能访问 DCache，也不能完整转发；LSU request 无法 consume，最终形成全后端活锁。

此外，提交 `a971785` 移除了 `ExecuteCluster` 写回边界上的 `!clear_i` 屏蔽。它不是此次稳定复现的直接根因，但 ROB index 没有 generation tag，恢复边沿可见的旧路径 completion/wakeup/PRF write 属于独立所有权风险。

## 3. 修复

仅修改 `rtl/core/execute/ExecuteCluster.sv`：

1. 增加一拍 `store_wakeup_hold_*_q`，保存最近 completion 的 valid/PRD/result；
2. request queue 中已有的数据待定 store，以及当拍新入队 store，都同时匹配当前 completion 和上一拍保留 completion；
3. `clear_i` 清除 hold valid，禁止恢复前 completion 被新 owner 使用；
4. 保留地址先发射优化，不强制 store 等到 src2 ready 才进入 LSU；
5. 恢复 `complete_valid_o`、early wakeup、PRF/CSR write、本地 bypass 和 issue acceptance 的 `clear_i` 隔离。

修复不改变模块接口、流水级数或存储器映射。新增状态只有每个 completion lane 的一拍 valid/PRD/result hold。

## 4. 正确性约束

地址/数据拆分后的 store 必须满足：从 MEM-IQ 移除开始，到 request queue 或 StoreBuffer 建立 data owner 为止，任意周期到达的 producer completion 都必须有接收者。不能假设 completion 会在 shell 建立后重复出现。

恢复周期还必须满足：

```text
clear_i -> no ROB completion / IQ wakeup / PRF or CSR write
clear_i -> no issue ownership transfer
clear_i -> invalidate held store completion
```

## 5. 验证结果

- `git diff --check` 通过，`doc/rtl_changes.json` 可解析。
- 重建 student_top Verilator/difftest 模型成功。
- 20k：11,417 commits，最后 PC `0x80001d1c`；失败版本只有 1,050 commits，停在 `0x80000420`。
- 1M：607,804 commits，持续前进。
- 5M 原始复现窗口：3,043,208 commits，最后 PC `0x80000574`；partial-alias 为 104,123 周期，没有再次形成永久保持。
- 5M 运行仍因固定上限返回 `TIMEOUT`，但这是测试尚未跑到 LED/pass-counter 终止标记，不再是停提交活锁。

## 6. 后续验证

- 完整 LED/pass-counter 测试需要高于 5M 的运行窗口；
- 建议补跑 RV32MI、RV32UI、RV32UM 与 `src0/src2`；
- 下一次 100 MHz Vivado 实现检查新增 hold 寄存器路径以及 recovery/clear 扇出。

