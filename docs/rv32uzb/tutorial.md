# RISC-V B扩展实现规划

> 本文档基于当前仓库测试集（`data/rv32uzb*/`）和 RISC-V Bitmanip 规范 1.0 整理。
> 描述实现目标、指令含义、改动计划和性能预期。实现过程中应同步更新本文。

---

## 1. RISC-V B扩展子扩展

当前测试集覆盖 6 个 Bitmanip 子扩展，每个子扩展对应一个测试目录：

| 目录 | 子扩展名 | 全称 | 代表指令 |
|------|---------|------|---------|
| `data/rv32uzba/` | **Zba** | Address generation | `sh1add`, `sh2add`, `sh3add` |
| `data/rv32uzbb/` | **Zbb** | Basic bit-manipulation | `andn`, `orn`, `xnor`, `clz`, `ctz`, `cpop`, `max`, `min`, `rol`, `ror`, `rori`, `rev8`, `orc.b`, `sext.b`, `sext.h`, `zext.h` |
| `data/rv32uzbc/` | **Zbc** | Carry-less multiplication | `clmul`, `clmulh`, `clmulr` |
| `data/rv32uzbkb/` | **Zbkb** | Bit-manipulation for cryptography | `brev8`, `pack`, `packh`（及 Zbb 的 `rol`/`ror`/`rori`） |
| `data/rv32uzbkx/` | **Zbkx** | Crossbar permutations | `xperm4`, `xperm8` |
| `data/rv32uzbs/` | **Zbs** | Single-bit instructions | `bclr`, `bclri`, `bext`, `bexti`, `binv`, `binvi`, `bset`, `bseti` |

各子扩展的逻辑独立，可以分批实现。

---

## 2. 各子集指令含义及格式、规范

所有 B 扩展指令均为标准 RV32 32-bit 编码，格式为 R-type 或 I-type（立即数变体）。
操作数全部来自通用整数寄存器，无浮点、无内存访问、无控制流改变。

### 2.1 Zba — 地址生成

| 指令 | 格式 | 语义 | funct7 | funct3 |
|------|------|------|--------|--------|
| `sh1add rd, rs1, rs2` | R | `rd = rs2 + (rs1 << 1)` | `0010000` | `010` |
| `sh2add rd, rs1, rs2` | R | `rd = rs2 + (rs1 << 2)` | `0010000` | `100` |
| `sh3add rd, rs1, rs2` | R | `rd = rs2 + (rs1 << 3)` | `0010000` | `110` |

共用 opcode `0110011`（OP），funct7=`0010000` 区分于 base ISA。

### 2.2 Zbb — 基础位操作

**逻辑类（R-type，opcode=OP，funct7=`0100000`）：**

| 指令 | 语义 |
|------|------|
| `andn rd, rs1, rs2` | `rd = rs1 & ~rs2` |
| `orn  rd, rs1, rs2` | `rd = rs1 \| ~rs2` |
| `xnor rd, rs1, rs2` | `rd = ~(rs1 ^ rs2)` |

**计数类（I-type，opcode=OP-IMM，funct12 区分）：**

| 指令 | 语义 |
|------|------|
| `clz  rd, rs1` | 从高位开始数前导零个数 |
| `ctz  rd, rs1` | 从低位开始数尾随零个数 |
| `cpop rd, rs1` | 统计置1的比特数（popcount） |

**符号/零扩展类（I-type）：**

| 指令 | 语义 |
|------|------|
| `sext.b rd, rs1` | 把 rs1[7:0] 符号扩展到32位 |
| `sext.h rd, rs1` | 把 rs1[15:0] 符号扩展到32位 |
| `zext.h rd, rs1` | 把 rs1[15:0] 零扩展到32位（等价于 `andi rd, rs1, 0xFFFF`，但有专用编码） |

**最大最小值（R-type，funct7=`0000101`）：**

| 指令 | 语义 |
|------|------|
| `max  rd, rs1, rs2` | 有符号最大值 |
| `maxu rd, rs1, rs2` | 无符号最大值 |
| `min  rd, rs1, rs2` | 有符号最小值 |
| `minu rd, rs1, rs2` | 无符号最小值 |

**旋转移位（R-type / I-type）：**

| 指令 | 语义 |
|------|------|
| `rol  rd, rs1, rs2` | 循环左移 rs2[4:0] 位 |
| `ror  rd, rs1, rs2` | 循环右移 rs2[4:0] 位 |
| `rori rd, rs1, shamt` | 循环右移立即数 shamt 位（I-type，funct7=`0110000`） |

**字节操作（I-type，仅 rs1 无 rs2）：**

| 指令 | 语义 |
|------|------|
| `orc.b rd, rs1` | 对每个字节，若任意位为1则该字节全置1，否则全清0 |
| `rev8  rd, rs1` | 字节序翻转（大小端转换），等价于 `bswap` |

### 2.3 Zbc — 无进位乘法

在 GF(2) 多项式域上做乘法，即将进位替换为 XOR：

| 指令 | 语义 |
|------|------|
| `clmul  rd, rs1, rs2` | 取乘积低32位 |
| `clmulh rd, rs1, rs2` | 取乘积高32位 |
| `clmulr rd, rs1, rs2` | 取乘积第32~63位（即 `clmulh` 结果左移一位 \| `clmul` 结果最高位） |

全部 R-type，opcode=OP，funct7=`0000101`，funct3 区分。

硬件实现：32位 XOR 树，combinational 1 cycle：

```
result = 0
for i in 0..31:
    if rs2[i]:
        result ^= (rs1 << i)
```

### 2.4 Zbkb — 密码学位操作

是 Zbb 子集加额外指令，面向密码学加速：

| 指令 | 来源 | 语义 |
|------|------|------|
| `brev8  rd, rs1` | Zbkb 新增 | 对每个字节内部翻转比特顺序 |
| `pack   rd, rs1, rs2` | Zbkb 新增 | `rd = {rs2[15:0], rs1[15:0]}`，打包低半字 |
| `packh  rd, rs1, rs2` | Zbkb 新增 | `rd = {16'b0, rs2[7:0], rs1[7:0]}`，打包低字节 |
| `rol`/`ror`/`rori` | 与 Zbb 共享 | 同 Zbb |

### 2.5 Zbkx — 交叉置换

以 rs2 作为查找表，对 rs1 的每个 nibble/byte 做置换：

| 指令 | 语义 |
|------|------|
| `xperm4 rd, rs1, rs2` | 每个 4-bit nibble 用 rs2 作16项查找表置换 |
| `xperm8 rd, rs1, rs2` | 每个 8-bit byte 用 rs2 作8项查找表置换（RV64 才完整，RV32 只能处理4字节） |

`xperm4` 伪代码：
```
for i in 0..7:
    idx = rs1[(i*4+3):(i*4)]    // 取第i个nibble
    rd[(i*4+3):(i*4)] = rs2[(idx*4+3):(idx*4)]
```

### 2.6 Zbs — 单比特操作

对由 rs2[4:0]（或立即数 shamt）指定的位进行操作：

| 指令 | R-type | I-type | 语义 |
|------|--------|--------|------|
| `bclr` / `bclri` | ✓ | ✓ | 清除指定位（置0） |
| `bext` / `bexti` | ✓ | ✓ | 提取指定位（结果在 bit[0]） |
| `binv` / `binvi` | ✓ | ✓ | 翻转指定位 |
| `bset` / `bseti` | ✓ | ✓ | 设置指定位（置1） |

语义示例（`bclr`）：`rd = rs1 & ~(1 << rs2[4:0])`

---

## 3. 指令实现顺序、总体规划

### 原则

1. 先实现架构改动最小、最易验证的子扩展，跑通完整测试流程后再扩展。
2. 所有 B 扩展指令均为 1-cycle 组合逻辑，复用现有 `TUBE_TYPE_ALU` 管道，不新增执行单元。
3. `AluSubType` 需从 4-bit 扩展到 **6-bit**（当前10个值，加上B扩展约35条，合计约45个枚举值，6-bit=64个容量足够）。

### 推荐实现顺序

```
阶段一（Zba，3条）
  sh1add / sh2add / sh3add
  → 验证 B 扩展完整流程（decode→ALU→test pass）

阶段二（Zbs，8条）
  bclr/bclri / bext/bexti / binv/binvi / bset/bseti
  → 全是简单位操作，逻辑直观

阶段三（Zbb，~18条）
  andn/orn/xnor（逻辑类，最简单）
  max/min/maxu/minu
  rol/ror/rori
  clz/ctz/cpop
  sext.b/sext.h/zext.h
  orc.b/rev8

阶段四（Zbkb，3条新增）
  brev8 / pack / packh
  （rol/ror/rori 已在 Zbb 实现，复用）

阶段五（Zbc，3条）
  clmul / clmulh / clmulr
  → XOR 树逻辑，需仔细验证

阶段六（Zbkx，2条）
  xperm4 / xperm8
```

---

## 4. 各指令实现步骤及具体改动位置

所有 B 扩展指令的实现只涉及三个文件，不新增模块，不修改流水线结构：

```
rtl/core/BasicTypes.sv          ← Step 1：扩展 AluSubType 位宽和枚举值
rtl/core/DecodeStage/DecodeTypes.sv  ← Step 2：在 DecodeOP/DecodeOPIMM 中识别新指令
rtl/core/ExecuteStage/ExecuteAluStage.sv  ← Step 3：在 alu() 函数中添加计算逻辑
```

### Step 1：扩展 BasicTypes.sv 中的 AluSubType

将 `AluSubType` 从 `logic [3:0]` 扩展到 `logic [5:0]`，同时 `SubTypePath` union 的位宽需一致：

```systemverilog
// 修改前
typedef enum logic [3:0] { ALU_SUBTYPE_ADD = 4'b0000, ... } AluSubType;

// 修改后（示例）
typedef enum logic [5:0] {
    ALU_SUBTYPE_ADD   = 6'd0,
    ALU_SUBTYPE_SUB   = 6'd1,
    // ... 保留原有10个 ...
    ALU_SUBTYPE_SLTU  = 6'd9,

    // Zba
    ALU_SUBTYPE_SH1ADD = 6'd10,
    ALU_SUBTYPE_SH2ADD = 6'd11,
    ALU_SUBTYPE_SH3ADD = 6'd12,

    // Zbs
    ALU_SUBTYPE_BCLR  = 6'd13,
    ALU_SUBTYPE_BEXT  = 6'd14,
    ALU_SUBTYPE_BINV  = 6'd15,
    ALU_SUBTYPE_BSET  = 6'd16,

    // Zbb（逻辑类）
    ALU_SUBTYPE_ANDN  = 6'd17,
    ALU_SUBTYPE_ORN   = 6'd18,
    ALU_SUBTYPE_XNOR  = 6'd19,
    // ... 其余 Zbb ...

    // Zbc
    ALU_SUBTYPE_CLMUL  = 6'd32,
    ALU_SUBTYPE_CLMULH = 6'd33,
    ALU_SUBTYPE_CLMULR = 6'd34,

    // Zbkb
    ALU_SUBTYPE_BREV8  = 6'd35,
    ALU_SUBTYPE_PACK   = 6'd36,
    ALU_SUBTYPE_PACKH  = 6'd37,

    // Zbkx
    ALU_SUBTYPE_XPERM4 = 6'd38,
    ALU_SUBTYPE_XPERM8 = 6'd39
} AluSubType;
```

> **注意**：`SubTypePath` 是 union，其他 SubType（`MemSubType`、`MulSubType` 等）仍是 4-bit；
> union 宽度取最宽成员，需把所有 4-bit 枚举改为 6-bit，或只扩展 `AluSubType` 并让 union
> 自动对齐（SV union packed 取最宽成员）。推荐统一改成 6-bit 避免隐式截断警告。

### Step 2：DecodeTypes.sv 中添加译码

B 扩展指令大多在 `DecodeOP`（opcode=`OP`）或 `DecodeOPIMM`（opcode=`OP-IMM`）中扩展。
关键是识别新的 funct7 值：

```
funct7 = 0010000 → Zba (sh1add/sh2add/sh3add)
funct7 = 0100000 → Zbb 逻辑类 (andn/orn/xnor，与 SUB/SRA 共 funct7，靠 funct3 区分)
funct7 = 0000101 → Zbb max/min 和 Zbc clmul 系列
funct7 = 0110000 → Zbb 旋转类 (rol/ror) 和 Zbkb/Zbs 的部分立即数变体
funct7 = 0100100 → Zbs bclr/bext/binv/bset (R-type)
funct7 = 0110100 → Zbs bclri/bexti/binvi/bseti (I-type，立即数变体 via OP-IMM)
funct7 = 0010100 → Zbkb pack/packh, Zbkx xperm4/xperm8
```

`DecodeOP` 函数中增加 funct7 的 case 分支，在对应 funct7 内再 case funct3 区分具体指令。

对于无 rs2 的单操作数指令（`clz`, `ctz`, `cpop`, `sext.b`, `sext.h`, `zext.h`, `brev8`），
在 `DecodeOPIMM` 中处理（它们编码为 `OP-IMM`，funct12 直接编码操作，rs2 字段为0）：

```systemverilog
// 示例：在 DecodeOPIMM 中区分 clz/ctz/cpop
if (inst[14:12] == 3'b001 && inst[31:25] == 7'b0110000) begin
    unique case (inst[24:20])
        5'b00000: instInfo.SubType.aluSubType = ALU_SUBTYPE_CLZ;
        5'b00001: instInfo.SubType.aluSubType = ALU_SUBTYPE_CTZ;
        5'b00010: instInfo.SubType.aluSubType = ALU_SUBTYPE_CPOP;
        ...
    endcase
    lgcRegInfo.lgcRegNumSrcAValid = TRUE;   // 只有 rs1，无 rs2
    lgcRegInfo.lgcRegNumSrcBValid = FALSE;
end
```

### Step 3：ExecuteAluStage.sv 中添加计算逻辑

在 `alu()` 函数的 `unique case` 里追加新的 case 分支：

```systemverilog
// Zba
ALU_SUBTYPE_SH1ADD: alu = b + (a << 1);
ALU_SUBTYPE_SH2ADD: alu = b + (a << 2);
ALU_SUBTYPE_SH3ADD: alu = b + (a << 3);

// Zbs（shamt 来自 b[4:0]）
ALU_SUBTYPE_BCLR: alu = a & ~(32'd1 << b[4:0]);
ALU_SUBTYPE_BSET: alu = a | (32'd1 << b[4:0]);
ALU_SUBTYPE_BINV: alu = a ^ (32'd1 << b[4:0]);
ALU_SUBTYPE_BEXT: alu = DataPath'((a >> b[4:0]) & 32'd1);

// Zbb 逻辑类
ALU_SUBTYPE_ANDN: alu = a & ~b;
ALU_SUBTYPE_ORN:  alu = a | ~b;
ALU_SUBTYPE_XNOR: alu = ~(a ^ b);

// Zbb 旋转
ALU_SUBTYPE_ROL:  alu = (a << b[4:0]) | (a >> (32 - b[4:0]));
ALU_SUBTYPE_ROR:  alu = (a >> b[4:0]) | (a << (32 - b[4:0]));

// Zbc（clmul，XOR 树）
ALU_SUBTYPE_CLMUL: begin
    DataPath prod;
    prod = '0;
    for (int k = 0; k < 32; k++) begin
        if (b[k]) prod ^= (a << k);
    end
    alu = prod;
end

// Zbkb
ALU_SUBTYPE_BREV8: begin
    for (int byte_i = 0; byte_i < 4; byte_i++) begin
        for (int bit_j = 0; bit_j < 8; bit_j++) begin
            alu[byte_i*8 + bit_j] = a[byte_i*8 + (7-bit_j)];
        end
    end
end

// Zbkx xperm4
ALU_SUBTYPE_XPERM4: begin
    for (int nibble_i = 0; nibble_i < 8; nibble_i++) begin
        logic [3:0] idx;
        idx = a[nibble_i*4 +: 4];
        alu[nibble_i*4 +: 4] = b[idx*4 +: 4];
    end
end
```

> **提示**：SystemVerilog `unique case` 里的循环会被综合成纯组合逻辑（XOR树 / MUX树），
> 不引入时序路径，延迟与 ALU 加法器相当。

### 立即数编码说明

对于 I-type 变体（`bclri`, `bexti`, `binvi`, `bseti`, `rori`），shamt 在 `inst[24:20]`，
`DecodeTypes.sv` 中的 `ImmGen` 函数使用 `OP_SYSTEM` 路径（`{27'b0, inst[19:15]}`）不适用；
需在 `ImmGen` 里为这些指令添加正确的立即数提取路径，或在 `DecodeOPIMM` 中直接以 `OP_TYPE_IMM`
传入，并让 `ImmGen` 已有的 `OP_OP_IMM` 分支自然截取低5位（`b[4:0]`）。
确认 `ImmGen` 对 `OP_OP_IMM` 的处理：`imm = {{20{inst[31]}}, inst[31:20]}`，低5位即 shamt，可直接复用。

---

## 5. 实现后预期性能影响与完善计划

### 5.1 IPC 影响

B 扩展指令全部走 ALU 管道（1-cycle），不增加流水线级数，不引入新的发射冲突。
预期 IPC 与基础 RV32IM 相同，对使用了 B 扩展的程序（密码学、位操作密集型）相较于
软件模拟版本有显著加速，但对 IPC 本身无负面影响。

`clmul` 是 B 扩展中逻辑最复杂的指令，32-bit XOR 树在综合后关键路径约为 log2(32)=5 级 XOR 门，
与 32-bit 加法器的进位链延迟相近，不会成为时序瓶颈。

`xperm4` 展开后是 8 个 4-bit 宽的 32:4 MUX，面积略大但时序可控。

### 5.2 面积影响

ALU 新增约 30 个 case 分支，增加 ALU 面积约 10~15%（主要来自 `clmul` 的 XOR 树
和 `xperm4` 的 MUX 阵列），对整体 SoC 面积影响可忽略。

### 5.3 仿真测试完善计划

当前测试集每个子扩展只提供一条代表性指令的测试（如 `sh1add`, `andn`）。
完善计划：

1. **阶段验证**：每个子扩展实现后立即跑对应测试（`make sim-rv32 SUITE=rv32uzba` 等）。
2. **回归保护**：B 扩展全部实现后纳入 `make sim-rv32-all` 回归，防止破坏基础 ISA。
3. **角落用例**：`clmul`/`clmulh`/`clmulr` 建议补充边界测试（全0、全1、0xAAAA_AAAA 等），
   现有单测试用例不足以验证正确性。
4. **波形 debug**：若某指令测试失败，优先检查 decode 阶段（`csrAddr.valid` 和 `tubeType`
   是否正确路由到 ALU 而非 SYS）。

### 5.4 已知风险

| 风险 | 说明 | 建议处置 |
|------|------|---------|
| `SubTypePath` union 位宽扩展 | 其余 SubType 为 4-bit，union 扩展后需确认所有 case 语句无截断警告 | 统一将所有 SubType 扩展到 6-bit |
| B 扩展与 base ISA 编码重叠 | 部分 funct7 与 `SUB`/`SRA` 共用，靠 funct3 区分，decode 顺序敏感 | 在 `DecodeOP` 的 funct7 case 内严格按 funct3 细分，勿依赖优先级 |
| `clmul` for 循环综合 | 部分工具对 `always_comb` 内的 `for` 综合为时序逻辑而非组合逻辑 | 验证 Verilator 仿真正确后再确认 Vivado 综合结果 |
| `rori` shamt 字段位置 | `rori` 的 shamt 在 `inst[24:20]`，而非 `inst[19:15]`（与 `slli` 等一致） | 在 decode 时单独处理，不走通用 `ImmGen` |
