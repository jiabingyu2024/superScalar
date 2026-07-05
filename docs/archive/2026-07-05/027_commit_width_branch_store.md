# Commit 宽度优化：branch/store 后允许 lane1 普通提交

## 背景

原 `CommitStage` 在遇到 branch 或 store 时都会无条件 `stopCommit=1`。这使大量正确预测 branch、以及已经被 StoreBuffer 接受写出的 store，也会把二路 commit 退化成一路。用户要求先做保守版本：

1. lane0 branch 且 `isMiss=0`：更新 BPU、释放 checkpoint、pop lane0，并允许继续看 lane1。
2. lane1 若是普通 ALU/MUL/MEM-load 且已 done，可以同周期 commit。
3. lane1 若是 branch/store/exception/serial，仍按原保守规则停止。
4. lane0 store 且 `StoreBufferCommitReady=1`：发 store commit req、pop lane0，并允许 lane1 安全普通指令同周期 commit。
5. lane1 store 仍不允许同周期提交，因为 StoreBuffer 外部写口只有一个。

## 修改内容

| 文件 | 修改 |
| --- | --- |
| `rtl/core/CommitStage/CommitStage.sv` | 新增 `can_follow_complex_lane0()`，定义 lane1 可跟随提交的安全普通指令条件。 |
| `rtl/core/CommitStage/CommitStage.sv` | 正确预测 branch 不再无条件阻断 lane1；branch miss 仍发恢复并停止。 |
| `rtl/core/CommitStage/CommitStage.sv` | commit-ready store 不再无条件阻断 lane1；store 未 ready 或 lane1 非安全普通指令时仍停止。 |
| `rtl/core/CommitStage/CommitStage.sv` | `free_checkpoint()` 改为只有 `entry.chkptValid=1` 时才写 checkpoint free 端口。 |

## 安全边界

lane1 必须满足：

```text
done
!exception
!isBranch
!isStore
!isSerial
!chkptValid
```

因此本次没有引入：

1. 双 branch 同周期提交。
2. 双 BPU update。
3. 双 checkpoint free。
4. 双 store commit。
5. exception/serial 与前序复杂事件同周期提交。

## 回归中发现的问题

第一次实现后，`rv32ui/rv32um/rv32mi` 出现大量 TIMEOUT。原因是：

```text
lane0 正确 branch -> free_checkpoint(branch)
lane1 普通指令 -> free_checkpoint(lane1)
lane1.chkptValid=0 时把前面的 checkpoint free 端口覆盖成 0
```

结果是正确预测 branch 的 checkpoint 没有释放，长跑后 checkpoint 资源泄漏并阻塞前端。已通过两处修复：

1. `free_checkpoint()` 只有 `chkptValid=1` 时才写端口。
2. `can_follow_complex_lane0()` 要求 lane1 `!chkptValid`。

## 验证记录

已运行：

```sh
make verilator-build BUILD_JOBS=4
make verilator-build-src BUILD_JOBS=4
make sim-rv32 SUITE=rv32ui MAX_CYCLES=30000 NO_BUILD=1
make sim-rv32 SUITE=rv32um MAX_CYCLES=30000 NO_BUILD=1
make sim-rv32 SUITE=rv32mi MAX_CYCLES=30000 NO_BUILD=1
make sim-src TEST=srcSmoke MAX_CYCLES=10000 NO_BUILD=1
```

结果：

1. rv32/myCPU 和 src/student_top Verilator 构建通过。
2. `rv32ui` 全部 PASS。
3. `rv32um` 全部 PASS。
4. `rv32mi` 全部 PASS。
5. `srcSmoke` 10000 周期短跑按预期 TIMEOUT，早期 `SEG=0x37000000`、counter 仍正常。

## 后续注意

1. 本次提高的是“预测已经正确、或 store 已经 commit-ready”时的退休宽度，不减少 branch miss。
2. 若要继续放开 lane1 branch，需要改 BPU update、Perf branch 统计、checkpoint free 为双端口或增加仲裁。
3. 若要继续放开 lane1 store，需要 StoreBuffer/DRAM store commit 支持双写或增加提交仲裁。
