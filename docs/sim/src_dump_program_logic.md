# SRC 测试程序 dump 级执行逻辑说明

本文只基于 `data/src*/*.dump` 的 RISC-V 反汇编理解程序逻辑，不引用 Verilator TB、checker 或仿真日志作为依据。函数名、测试分类名是从 `jal` 调用链、固定地址访问、立即数和最终比较行为中反推的，不代表原始 C 源码中一定存在同名函数。

## 1. 阅读结论总览

`src*` 程序本质上都是“裸机自检程序”：

1. 从 `0x80000000` 入口启动，初始化 `sp`。
2. 先运行一组 RV32I 指令语义测试。每个小测试自己判断成功或失败，成功累加 `0x80100000`，失败累加 `0x80100004`。
3. 再运行扩展指令、CSR/trap、矩阵/排序/CRC/算术循环等综合测试。
4. 程序自己通过 MMIO 写 LED、数码管和计数器。最终 PASS/FAIL 也是程序内部写出的结果，不是 TB 才知道。
5. 完成后跳到自身形成死循环，避免 PC 跑到无效区域。

关键点：判断程序是否真正跑通，不能只看“没有崩溃”。dump 里最终路径会显式选择 PASS LED 或 FAIL LED，并且部分版本还会把每类测试通过情况 OR 到一个 lamp 累积位中。

## 2. dump 中反推出的地址约定

| 地址 | 作用 | 出现版本 | dump 依据 |
| --- | --- | --- | --- |
| `0x80000000` | 复位入口 `_start` | 全部 `src*` | dump 第一条指令均从此处开始 |
| `0x80100000` | RV32I 通过计数 | 全部 `src*` | 每个 RV32I 小测试成功路径 `lw/addi/sw` 更新该地址 |
| `0x80100004` | RV32I 失败计数 | 全部 `src*` | 每个 RV32I 小测试失败路径更新该地址 |
| `0x80100008` 附近 | scratch / 保存返回地址 / load-store 测试区 | 全部 `src*` | RV32I dispatcher 用 `sw ra,24(t1)` 保存返回地址，小测试也访问该区域 |
| `0x80100030` | 新版无 M 程序的 lamp 累积位；有 M 程序的 M/Z 通过计数 | `srcWithoutMext`, `srcWithMext` | `srcWithoutMext` 在 `0x800001f4` OR lamp；`srcWithMext` 最终检查其值等于 8 |
| `0x80100034` | M/Z 失败计数 | `srcWithMext` | M 扩展失败路径更新 |
| `0x80100038` | 有 M 程序的 lamp 累积位 | `srcWithMext` | `0x80000810` 读改写该地址 |
| `0x80200000` | SW0 读口 | 多数 `src*` | helper 直接 `lw` |
| `0x80200004` | SW1 读口 | 多数 `src*` | helper 直接 `lw` |
| `0x80200020` | 数码管 SEG | 全部 `src*` | BCD 后写该地址 |
| `0x80200040` | LED | 全部 `src*` | PASS/FAIL/lamp helper 写该地址 |
| `0x80200050` | 计数器 | 全部 `src*` | 写 `0x80000000` 启动，写 `0xffffffff` 停止，读取得耗时 |

这些地址是程序和 SoC 之间的裸机 ABI。CPU RTL 调试时，如果这些地址的 store/load 没有正确到达外设侧，即使核心指令执行基本正确，最终显示也会错。

## 3. 两代 SRC 程序形态

### 3.1 老式固定 PASS/FAIL 形态：`srcSmoke`, `src0`, `src1`, `src2`

这类程序最终只显示一个固定 PASS 或 FAIL 图案，不维护“右侧小灯逐项通过”的完整位图。

典型结构：

```text
0x80000000:
  set sp
  jal rv32i_suite
  jal workload_or_final
  jal self
```

`srcSmoke` 的入口最清晰：

```text
80000000: sp = 0x80108030
80000008: jal 0x800005a8   ; RV32I 37 项测试
8000000c: jal 0x80000540   ; 性能/结果测试与最终 PASS/FAIL
80000010: jal 0x80000010   ; 死循环
```

老式 PASS LED 图案由 `srcSmoke` 的 `0x800001ec` 构造，最终写 `0x80200040`，组合结果为 `0x01221c08`。FAIL LED 图案由 `0x80000288` 构造，组合结果为 `0x24181824`。

### 3.2 新式 lamp 累积形态：`srcWithoutMext`, `srcWithMext`

这类程序会维护一个 lamp bitmask。每通过一类测试，就 OR 一个 bit 到累积寄存区，并即时写 LED。最终 PASS/FAIL 图案再 OR 上这个 bitmask。

新式 PASS/FAIL 基础图案：

```text
PASS base = 0x04887020
FAIL base = 0x90606090
final_led = base | lamp_mask
```

`srcWithoutMext` 使用 `0x80100030` 保存 lamp mask；`srcWithMext` 因为 `0x80100030` 已用作 M/Z 通过计数，所以改用 `0x80100038` 保存 lamp mask。

当新式程序全部通过时，dump 中会累计以下 lamp bits：

```text
0x00000001  RV32I/基础计数检查
0x00000002  固定类别标记
0x00000100  性能/矩阵类测试
0x00000200  固定类别标记
0x00010000  固定类别标记
0x00020000  CSR/trap 或固定类别标记，具体版本中含义略有差异
0x01000000  固定类别标记
0x02000000  固定类别标记
```

全亮 bitmask 为：

```text
0x03030303
```

因此新式全通过最终 LED 常见为：

```text
0x04887020 | 0x03030303 = 0x078b7323
```

如果失败，最终会写：

```text
0x90606090 | 已经通过的 lamp_mask
```

这也是为什么只看最终 LED 的左侧 PASS/FAIL 图案不够，还要看右侧 lamp mask 可以定位哪一类没走完。

## 4. RV32I 指令测试套件

所有 `src*` 都有一段 RV32I dispatcher。它不是单个测试，而是顺序调用 37 个小函数。每个小函数内部用常量构造输入，执行目标指令，再用 `bne/beq/blt/...` 判断结果。

以 `srcWithMext` 为例：

```text
80000008: jal 0x80000f78   ; 进入 RV32I suite

80000f78:
  保存 ra 到 0x80100020 附近
  jal 0x80001028   ; ADD
  jal 0x8000110c   ; SUB
  jal 0x800012d8   ; SLT
  ...
  jal 0x80001c94   ; JALR
  恢复 ra
  ret
```

单个小测试的公共模式如下：

```c
void rv32i_one_test(void) {
    if (all_internal_checks_pass) {
        *(uint32_t *)0x80100000 += 1;
    } else {
        *(uint32_t *)0x80100004 += 1;
    }
}
```

例如 `srcWithMext` 的 ADD 测试 `0x80001028` 做了多组溢出和普通加法检查：

```text
0x7fffffff + 1        == 0x80000000
-1 + 1               == 0
0x12345678+0x87654321 == 0x99999999
0x99999999+0x99999999 == 0x33333332
```

全部满足才更新 `0x80100000`，任意一个比较失败就跳到失败路径更新 `0x80100004`。

从 dump 调用顺序和指令内容可归类为：

| 类别 | 覆盖指令 |
| --- | --- |
| 算术 | `ADD`, `ADDI`, `SUB` |
| 逻辑 | `AND`, `ANDI`, `OR`, `ORI`, `XOR`, `XORI` |
| 比较 | `SLT`, `SLTI`, `SLTU`, `SLTIU` |
| 移位 | `SLL`, `SLLI`, `SRL`, `SRLI`, `SRA`, `SRAI` |
| 立即数/PC | `LUI`, `AUIPC` |
| load/store | `LB`, `LH`, `LW`, `LBU`, `LHU`, `SB`, `SH`, `SW` |
| 跳转/分支 | `JAL`, `JALR`, `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |

最终 `0x80100000 == 37` 表示 RV32I 的 37 个小测试都走了成功路径。若小于 37，说明至少一个小测试失败或程序中途跑飞。若 `0x80100004 != 0`，说明有小测试显式走了失败路径。

## 5. `srcWithMext` 详细执行流程

### 5.1 入口

```text
80000000: auipc sp,0x121
80000004: addi  sp,sp,80       ; sp = 0x80121050
80000008: jal   0x80000f78     ; RV32I suite
8000000c: jal   0x80001cf8     ; M/Z 扩展 suite
80000010: jal   0x800000e4     ; 最终 harness
80000014: jal   0x80000014     ; 死循环
```

这说明 `srcWithMext` 的最终 PASS 并不是 RV32I suite 结束就给出，而是必须经过三段：

```text
RV32I 37 项 -> M/Z 8 项 -> CSR/trap + 性能/矩阵 + lamp/final
```

### 5.2 M/Z 扩展 suite

`0x80001cf8` 顺序调用 8 个 M 扩展测试：

```text
0x80001d2c  MUL
0x80001db4  MULH
0x80001e3c  MULHSU
0x80001ec8  MULHU
0x80001f54  DIV
0x80001fd8  DIVU
0x80002060  REM
0x800020e4  REMU
```

成功路径累加：

```text
0x80100030 += 1
```

失败路径累加：

```text
0x80100034 += 1
```

所以 `srcWithMext` 的基础指令结果要求是：

```text
*(0x80100000) == 37
*(0x80100030) == 8
```

### 5.3 最终 harness：`0x800000e4`

核心逻辑可还原为：

```c
void final_src_with_mext(void) {
    uint32_t ok = 1;

    bool base_ok =
        (*(uint32_t *)0x80100000 == 37) &&
        (*(uint32_t *)0x80100030 == 8);

    lamp_if(base_ok, 0x00000001, &ok);
    write_seg_rv32i_and_mext_counts();
    counter_start();

    lamp_if(test_csr_trap(), 0x00020000, &ok);
    lamp_if(test_matrix_perf(), 0x00000100, &ok);

    lamp_if(1, 0x00000002, &ok);
    lamp_if(1, 0x00000200, &ok);
    lamp_if(1, 0x00010000, &ok);
    lamp_if(1, 0x01000000, &ok);
    lamp_if(1, 0x02000000, &ok);

    if (ok)
        final_pass();
    else
        final_fail();
}
```

`lamp_if` 对应 `0x80000018`：

```text
a0 = condition
a1 = lamp_bit
a2 = &ok

if (condition != 0)
    OR lamp_bit into 0x80100038, then write LED
else
    *ok = 0
```

这个 helper 很关键：它把“显示某类已通过”和“全局失败锁存”合在一起。只要有一个必须通过的测试返回 0，`ok` 被清零；后续即使还有固定 lamp 被点亮，也不会恢复 PASS。

### 5.4 SEG 和 counter 行为

`0x800006f8` 会读取：

```text
0x80100000  RV32I pass count
0x80100030  M/Z pass count
```

经过 BCD 转换后写到 `0x80200020` 的高位区域：

```text
SEG = (rv32i_bcd & 0xff) << 24
    | (mext_bcd  & 0x0f) << 20
```

之后 `0x800008e8` 写 `0x80000000` 到 `0x80200050` 启动计数器。最终 PASS/FAIL wrapper 会：

```text
write 0xffffffff to 0x80200050  ; 停止计数器
read  0x80200050                ; 读取耗时
BCD 后 OR 到 SEG 低位
写 PASS 或 FAIL LED
```

### 5.5 最终 PASS/FAIL wrapper

`0x800000a4` 是 PASS wrapper：

```text
stop counter
read counter
update SEG low digits
write LED = 0x04887020 | *(0x80100038)
t6 = 1
```

`0x80000064` 是 FAIL wrapper：

```text
stop counter
read counter
update SEG low digits
write LED = 0x90606090 | *(0x80100038)
t6 = 0
```

`t6` 不是 RISC-V ABI 标准返回值，而是这个裸机程序额外留下的最终状态标记。观察程序本身时，LED store 更直接；观察仿真内部寄存器时，`t6=1/0` 也能辅助定位最终路径。

## 6. `srcWithoutMext` 详细执行流程

入口：

```text
80000000: sp = 0x80121048
80000008: jal 0x80000fb0   ; RV32I suite
8000000c: jal 0x800003bc   ; final harness
80000010: jal 0x80000010   ; 死循环
```

`srcWithoutMext` 没有 M/Z suite，所以最终 harness 只检查 RV32I pass count 是否等于 37。

`0x800003bc` 可还原为：

```c
void final_src_without_mext(void) {
    uint32_t ok = 1;

    if (*(uint32_t *)0x80100000 == 37)
        mark_lamp(0x00000001);
    else
        ok = 0;

    write_seg_rv32i_count();
    counter_start();

    if (test_csr_trap())
        mark_lamp(0x00000002);
    else
        ok = 0;

    if (test_matrix_perf())
        mark_lamp(0x00000100);
    else
        ok = 0;

    mark_lamp(0x00000200);
    mark_lamp(0x00010000);
    mark_lamp(0x00020000);
    mark_lamp(0x01000000);
    mark_lamp(0x02000000);

    final(ok);
}
```

其中 `mark_lamp` 对应 `0x800001f4`：

```text
0x80100030 = 0x80100030 | lamp_bit
LED        = 0x80100030
```

`final(ok)` 对应 `0x80000364`：

```text
stop counter
read counter
update SEG low digits
if ok:
    LED = 0x04887020 | *(0x80100030)
    t6 = 1
else:
    LED = 0x90606090 | *(0x80100030)
    t6 = 0
```

所以 `srcWithoutMext` 的程序内 PASS 条件是：

```text
RV32I pass count == 37
CSR/trap test returns nonzero
matrix/perf test returns nonzero
```

后面几个固定 lamp bit 是类别标记，不会独立造成失败。

## 7. `srcSmoke` 详细执行流程

`srcSmoke` 是更小的老式程序，入口：

```text
80000000: sp = 0x80108030
80000008: jal 0x800005a8   ; RV32I 37 项
8000000c: jal 0x80000540   ; workload + final
80000010: jal 0x80000010   ; 死循环
```

RV32I suite 同样顺序调用 37 个小测试，成功更新 `0x80100000`，失败更新 `0x80100004`。

`0x80000540` 的最终阶段可还原为：

```c
void final_src_smoke(void) {
    write_seg_rv32i_count();
    counter_start();

    uint32_t n = 100000;          // 0x186a0
    uint32_t r = workload(n);

    if (r == 0xbef16570)
        final_pass();
    else
        final_fail();
}
```

这里的 workload 从 `0x80000494` 开始，循环 `i = 0..n-1`，多次调用算术 helper，累加得到固定校验值。这个测试对分支、函数调用、乘除/软件除法 helper、长循环和寄存器保存都有压力。

老式 final wrapper：

```text
final_pass:
  stop counter
  read counter
  update SEG low digits
  write LED = 0x01221c08
  t6 = 1

final_fail:
  stop counter
  read counter
  update SEG low digits
  write LED = 0x24181824
  t6 = 0
```

注意：`srcSmoke` 的 final workload 没有像新式程序一样显式检查 `0x80100000 == 37` 后再决定最终 PASS。它会把 RV32I count 写到 SEG 高位，因此 RV32I 小测试失败时可以从 SEG 看到 count 不满 37；最终 LED 主要由 workload 校验值决定。

## 8. `src0/src1/src2` 的共同形态

`src0/src1/src2` 比 `srcSmoke` 更重，仍属于老式固定 PASS/FAIL 形态。以 `src0` 为代表：

```text
80000000: sp = 0x8013d244
80000008: jal 0x80001174   ; RV32I 37 项
8000000c: jal 0x80000fb0   ; 综合 workload/final
80000010: jal 0x80000010   ; 死循环
```

综合 workload 中可以从 dump 看到多块数据区和多类算法 helper：

```text
0x801138c4
0x8011b754
0x801235e4
0x8012b474
```

这些地址被用于矩阵/数组输入输出。`src0` 的 final 阶段有明显的多轮循环结构：

1. 写 RV32I count 到 SEG。
2. 启动 counter。
3. 循环 10 轮左右，填充矩阵/数组。
4. 调用矩阵乘、搬移/转置、比较 helper。
5. 调用排序、CRC 或算术类 helper。
6. 任一关键比较失败就走 final_fail；全部完成走 final_pass。

与 `srcSmoke` 一样，老式 PASS/FAIL LED 是固定图案，不带新式 lamp mask：

```text
PASS LED = 0x01221c08
FAIL LED = 0x24181824
```

因此 `src0/src1/src2` 调试时应同时看：

```text
0x80100000 是否达到 37
0x80100004 是否非 0
最终是否进入 pass wrapper
counter 是否启动/停止
LED 是否写出老式 PASS/FAIL 图案
```

## 9. CSR/trap 测试在 dump 中的形态

`srcWithoutMext` 的 CSR/trap 测试入口是 `0x8000055c`，trap handler 在 `0x80000e80` 附近。

`srcWithMext` 的 CSR/trap 测试入口是 `0x800002ec`，trap handler 在 `0x80002170` 附近。

共同特征：

1. 先写 `mtvec` 为自定义 handler 地址。
2. 构造一批固定常量，测试 CSR 读写、异常入口、`mepc/mcause/mstatus` 保存恢复。
3. handler 会保存大量通用寄存器到栈上。
4. handler 读取 `mcause/mstatus/mepc`，调用辅助函数记录/检查。
5. 恢复 `mstatus/mepc` 后执行 `mret`。
6. 测试函数最终返回 `a0 != 0` 表示通过。

这类测试对超标量/乱序核心尤其敏感：

| 风险点 | dump 表现 | RTL 常见问题 |
| --- | --- | --- |
| CSR 写后读 | 写 `mtvec` 后立即 `csrrs` 检查 | CSR 旁路或提交时序错误 |
| 异常精确性 | handler 读取 `mepc/mcause` | 异常点不是精确 PC |
| `mret` 恢复 | handler 末尾 `mret` | flush/redirect 未清干净 |
| 寄存器保护 | handler 保存/恢复几乎所有 GPR | 异常期间 rename/commit 状态破坏 |
| `mepc += 4` 类行为 | helper 修改异常返回地址 | 返回到错误 PC 会死循环或跳过检查 |

如果程序卡在 CSR/trap 阶段，通常表现为 counter 已启动，但后续 lamp 不再变化，最终 PASS/FAIL wrapper 没有被调用。

## 10. 如何从 dump 判断“最终正确程序”

### 10.1 新式 `srcWithMext`

程序自身的最终正确路径：

```text
0x80100000 == 37
0x80100030 == 8
CSR/trap returns pass
matrix/perf returns pass
进入 0x800000a4 final_pass
写 LED = 0x04887020 | 0x80100038
```

全通过时 `0x80100038` 应累计到 `0x03030303`，最终 LED 应为：

```text
0x078b7323
```

失败路径：

```text
进入 0x80000064 final_fail
写 LED = 0x90606090 | 0x80100038
```

### 10.2 新式 `srcWithoutMext`

程序自身的最终正确路径：

```text
0x80100000 == 37
CSR/trap returns pass
matrix/perf returns pass
进入 0x80000364 且参数 ok != 0
写 LED = 0x04887020 | 0x80100030
```

全通过时 `0x80100030` 应累计到 `0x03030303`，最终 LED 也应为：

```text
0x078b7323
```

失败路径：

```text
进入 0x80000364 且参数 ok == 0
写 LED = 0x90606090 | 0x80100030
```

### 10.3 老式 `srcSmoke/src0/src1/src2`

程序自身的最终正确路径：

```text
进入 final_pass wrapper
停止 counter
更新 SEG 低位耗时
写 LED = 0x01221c08
t6 = 1
```

失败路径：

```text
进入 final_fail wrapper
停止 counter
更新 SEG 低位耗时
写 LED = 0x24181824
t6 = 0
```

老式程序没有新式 lamp bitmask，因此定位失败阶段主要靠 PC、最后一次 MMIO store、`0x80100000/04` 计数、以及是否进入 workload 比较失败分支。

## 11. 调试时按程序执行阶段定位

### 阶段 A：入口都没跑起来

观察点：

```text
PC 是否从 0x80000000 开始
sp 是否被设置到 0x8010xxxx/0x8012xxxx/0x8013xxxx
第一条 jal 是否跳到 RV32I suite
```

可能问题：

```text
取指 base 地址错误
irom 初始化端序错误
reset PC 错误
JAL immediate 解码错误
```

### 阶段 B：RV32I count 不到 37

观察点：

```text
0x80100000 最终值
0x80100004 是否增加
最后一次进入哪个 RV32I 小测试地址
```

定位方法：

1. 从 dispatcher 的 `jal` 顺序数第几个小测试。
2. 看该小测试失败路径的 branch 条件。
3. 根据目标指令定位 ALU、branch compare、load/store 或 PC+4 写回问题。

典型例子：

```text
ADD/ADDI/SUB 失败：看 ALU 加减和符号扩展
SLT/SLTU 失败：看 signed/unsigned 比较路径
SRA/SRAI 失败：看算术右移是否补符号位
LB/LH/LBU/LHU 失败：看 byte lane、符号扩展、对齐
JAL/JALR 失败：看 link PC、目标地址 bit0 清零、flush
branch 失败：看比较条件和 redirect
```

### 阶段 C：RV32I 通过但没有最终 LED

观察点：

```text
是否进入 final harness
是否写 0x80200020
是否写 0x80200050 启动 counter
是否卡在 CSR/trap 或 workload
```

可能问题：

```text
函数返回 ra 被破坏
load-store 对栈访问错误
CSR/trap flush 错误
长循环中分支预测恢复或流水线握手错误
```

### 阶段 D：进入 FAIL wrapper

观察点：

```text
新式：lamp_mask 已有哪些 bit
老式：失败前最后一个比较分支来自哪个 helper
counter 是否已经停止
```

新式程序中，lamp mask 是最有价值的定位信息。某个必须通过的阶段没亮，说明它返回了 0 或之前就没执行到。

## 12. GNU 工具能做到什么

当前 dump 已经是 objdump 风格反汇编。`riscv64-unknown-elf-objdump/readelf/nm/addr2line` 这类 GNU 工具可以帮助做三件事：

1. 把 raw `irom.hex` 包成 ELF，方便按 `0x80000000` 地址查看。
2. 重新反汇编，得到更规整的 instruction/地址输出。
3. 如果有原始 ELF 和 debug info，可以恢复符号名、源码行号。

但 GNU binutils 不能直接把这些 dump 反编译成高层 C 程序。真正的伪 C 需要 Ghidra、RetDec、IDA、Binary Ninja 这类反编译器；即便如此，没有符号和类型时，CSR/trap、MMIO、裸机 ABI 仍然要靠人工校正。

对本项目来说，最稳的理解方式仍然是：

```text
入口 jal 链 -> dispatcher -> 每个测试的 pass/fail 计数 -> final harness -> MMIO 写结果
```

## 13. 面向 CPU RTL 的自检清单

1. `PC=0x80000000` 后第一拍取到的指令是否正确，不要把 COE/HEX 端序弄反。
2. `JAL/JALR` 是否同时正确写 link register 和 redirect PC。
3. RV32I suite 返回后 `0x80100000` 是否等于 37，`0x80100004` 是否为 0。
4. `LB/LH/LBU/LHU/SB/SH/SW` 的 byte enable、符号扩展、地址低位选择是否正确。
5. `SLT/SLTI` 和 `SLTU/SLTIU` 是否没有混用 signed/unsigned。
6. `SRA/SRAI` 是否算术补符号位，而不是逻辑右移。
7. CSR 写后读、异常进入、`mret` 返回是否具备精确 flush。
8. MMIO store 到 `0x80200020/40/50` 是否不会被 cache 或普通内存路径吞掉。
9. 长循环 workload 中，分支恢复后是否会错误提交 younger 指令。
10. 最终应看到 stop counter，再更新 SEG 低位，再写 PASS/FAIL LED；顺序颠倒通常表示 final wrapper 没按 dump 路径执行。

