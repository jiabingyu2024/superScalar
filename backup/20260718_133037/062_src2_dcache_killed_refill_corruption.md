# src2 暴露的 DCache killed-refill 隐藏数据破坏

## 结论

当前 `dev-v4.2` 的 `srcWithMext` 虽然能完整 PASS，但不能证明 DCache 的 refill/flush 交互正确。`src2` 的真实失败根因是：**DCache refill 逐 word 直接覆盖 data RAM，而新 tag 只在最后一拍安装；refill 中途遇到 branch flush/`kill_i` 后，已经写入的 word 不回滚，旧 tag 却继续有效，最终形成“旧 tag + 新行局部数据”的伪 hit。**

本次复现结果：

| 测试 | 结果 | 关键证据 |
| --- | --- | --- |
| `srcWithMext` 完整运行 | PASS | 约 `407,900,947` cycles，最终 LED `0x078b7323` |
| `src2` 普通 Verilator | FAIL | `3,630,274` cycles 写 FAIL LED `0x24181824`；RV32I 仍为 37/37 |
| `src2` 提交级差分 | 首个真实偏离 | cycle `3,101,506`，commit `2,164,023`，PC `0x80000930` |

因此这不是 RV32I 基础指令错误，也不是 checker 误判；它是只有特定 cache index 冲突与分支恢复时序同时出现才会触发的微架构一致性 bug。

## 第一条架构偏离

`data/src2/src2.dump` 中的关键代码为：

```text
8000092c: 09c72703  lw x14,156(x14)  ; 取链表指针
80000930: 00072703  lw x14,0(x14)    ; 取当前节点数据
```

失败迭代的提交轨迹：

```text
PC 0x8000092c: addr=0x8013a4cc, result=0x80104458
PC 0x80000930: addr=0x80104458
                 DUT result=0x80101030
                 REF result=0x0000003d
```

第二条 load 的地址计算是正确的，错误发生在 DCache 返回数据。`0x80101030` 不是随机值，而是另一个冲突 cache line 中的有效指针数据。

## 精确污染过程

当前参数：

```text
line size   = 16 B
line count  = 2048
capacity    = 32 KiB
index       = addr[14:4]
```

两个关键 cache line：

| 地址 | index | tag | word2 数据 |
| --- | ---: | ---: | ---: |
| `0x80104450` | `0x445` | `0` | `0x0000003d` |
| `0x8013c450` | `0x445` | `7` | `0x80101030` |

现场顺序如下：

1. `0x80104450` 已完整 refill，tag RAM 为 `{valid=1, tag=0}`，word2=`0x0000003d`。
2. load `0x8013c458` 访问同一 index、不同 tag，触发 miss；refill 从请求 word2 开始。
3. 第一份 memory response 为 `0x80101030`，`bank_write_en=1`、`tag_write_en=0`，所以 word2 已覆盖到 index `0x445`。
4. refill 尚未完成时发生分支恢复，`kill_i=1`；`killed_q` 置位，剩余响应只 drain，不再写 data/tag。
5. tag RAM 没有在 miss 开始时失效，也没有在 kill 时清除，仍保持 `{valid=1, tag=0}`。
6. 后续访问 `0x80104458` 时 tag0 命中，却读到已被 tag7 refill 首拍覆盖的 `0x80101030`。

这解释了为什么内存本体和 load 地址都正确，但 cache hit 数据错误。

## RTL 根因

问题集中在 `rtl/core/memory/dcache.sv` 的两个非原子动作。

data RAM 在每个有效 refill response 都立即写：

```systemverilog
else if (state_q == DC_REFILL_WAIT && mem_resp_valid_i &&
         !killed_q && !kill_i) begin
    bank_write_en = 1'b1;
    bank_write_index = req_addr_q[TAG_LSB-1:4];
    bank_write_word = fill_word_q;
    bank_write_data = mem_resp_rdata_i;
end
```

tag/valid 只在第 4 个 response 写入：

```systemverilog
assign tag_write_en = state_q == DC_INIT ||
    (state_q == DC_REFILL_WAIT && mem_resp_valid_i &&
     !killed_q && !kill_i && refill_count_q == 2'd3);
```

kill 路径只是停止后续写入并 drain response：

```systemverilog
if (killed_q || kill_i) begin
    state_q <= DC_IDLE;
    killed_q <= 1'b0;
end
```

缺失的协议约束是：**在新行 data 开始覆盖 victim set 前，旧 tag 必须不可命中；或者所有 refill data 必须先放在旁路 buffer 中，最后与 tag 原子安装。**

如果只在 kill 分支补状态跳转、但不处理已写 data，bug 仍然存在。

## 为什么 srcWithMext 能 PASS

该 bug 需要四个条件同时成立：

1. index 中已有仍会被再次访问的有效行 A；
2. 冲突行 B 对同一 index 发起 miss；
3. B 至少返回一个 word 后、最终 tag 安装前发生 branch flush；
4. 之后再次读取 A 中恰好被 B 覆盖的 word。

`src2` 的链表/排序 workload 同时具有大跨度冲突地址和高分支恢复频率；失败结果中的 branch miss rate 约为 `19.3%`。`srcWithMext` 完整结果的 branch miss rate 约为 `1.2%`，且热点以高局部性的连续数据访问为主，没有在最终检查数据上形成上述四条件组合。因此 `srcWithMext` PASS 只是该程序路径没有观察到破坏，不是设计正确性的充分条件。

## 可以快速判错的部分仿真

### 1. 不跑长测，直接跑 src2 4M 窗口

```bash
python3 scripts/run_verilator.py src --test src2 \
  --max-cycles 4000000 --no-build
```

当前版本约 5 秒即可在 cycle `3,630,274` 得到明确 FAIL。相比 `srcWithMext` 的约 408M cycles，这个 4M 窗口更适合每次 DCache/flush 修改后的快速门禁。

建议固定最小回归层级：

```text
RV32 directed -> src2 4M -> srcSmoke -> srcWithMext 500k -> 完整 srcWithMext
```

其中 `srcWithMext 500k` 的 TIMEOUT 只能检查早期 counter/marker，不可视为完整 PASS。

### 2. 最小 DCache directed test

不需要运行软件 workload，构造以下几百周期序列即可稳定复现：

```text
refill A(index=i, tag=0) 完成
refill B(index=i, tag=7)，让第一个 word response 写入
在最后一个 response 前拉高 kill
再次读取 A 的同一 word
期望：不能以 A 的旧 tag 命中 B 的数据
```

这个 directed test 应成为修复后的首要回归，因为它直接覆盖 refill 原子性，而不是依赖软件偶然形成冲突。

## 提交级差分的附加假阳性

当前提交探针还有一个与功能失败独立的问题：相邻 move 融合的第二个 `adjacent_move_alias` 项没有进入 IQ，因此 `commit_trace_probe.next_pc_q[tid]` 从未为它写入 `pc+4`。TID 槽位复用后，差分会先报陈旧 next-PC：

```text
src2:        cycle 3222, commit 647,
             DUT next_pc=0x80001194, REF=0x80000120
srcWithMext: cycle 3706, commit 808,
             DUT next_pc=0x80002018, REF=0x80002038
```

这两个都是观测探针假阳性，不是实际控制流跳错。定位本次真实问题时临时对 alias commit 使用 `commit_entry_i.pc + 4`，之后差分才运行到 310 万周期并捕获真实 load data mismatch。该临时修改未保留在 RTL 中。

后续应正式修正 probe，否则“跑一小段 difftest”会在几千周期提前退出，掩盖真正的数据错误。

## 修复方向与验收条件

可选方案按工程复杂度排序：

1. **miss 启动时立即 invalidate victim tag。** 即使 refill 中途被 kill，部分 data 也因 valid=0 不可见；以后访问旧行会重新 miss。实现简单，但要处理 tag RAM 单写口仲裁。
2. **wrong-path refill 继续完成。** branch flush 只抑制原 load completion，不取消 cache fill；四拍完成后正常安装新 tag。cache fill 是非架构可见副作用，通常允许这样处理，但必须保证 load queue 元数据已被 kill、不会错误完成。
3. **refill buffer + 原子安装。** 四个 word 先进入临时 buffer，最后统一写 data/tag；语义最清楚，但增加 128-bit buffer 和安装周期。

验收不能只看 `srcWithMext`：

- DCache killed-refill directed test PASS；
- `src2 --max-cycles 4000000` 不再写 FAIL signature；
- 修正 commit probe 后，`src2` 至少跑过原始 mismatch 点 `3,101,506` cycles 无差分；
- `src0/src1/src2/srcSmoke/srcWithMext/srcWithoutMext` 全部按各自 checker 回归；
- 增加断言：任何 partially overwritten index 在新 tag 安装前不得以旧 tag 对 CPU 报 hit。

## 回归经验

单一长程序 PASS 不能替代覆盖矩阵。每次改 DCache、load queue、branch recovery 或 kill/drain 协议后，至少同时保留：

- 一个基础 ISA 集，检查局部指令语义；
- 一个 4M 以内能结束的 `src2`，检查冲突 cache 与控制恢复组合；
- 一个短窗口 `srcWithMext`，检查热点性能和早期 marker；
- 一个针对 refill/kill 的模块级 directed test，直接检查隐藏状态不变量。

这次问题正说明：**最终 signature 是必要条件，但“部分仿真 + 首个架构偏离 + 模块级异常时序”更适合快速判断当前版本是否真的正确。**
