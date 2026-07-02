# src 测试 dump 补齐记录

## 背景

用户要求 src 类测试也必须具备 dump 文件。当前已有 `src0/src1/src2/srcSmoke` 的 dump，但 `srcWithMext` 和 `srcWithoutMext` 缺失 dump。

## 本次修改

更新 `scripts/prepare_test_data.py`：

1. src profile 继续从 `irom.coe/dram.coe` 生成 `irom.hex/dram.hex`。
2. 对每个 `data/src*/` 目录，如果目录内没有任何 `.dump`，则由 `irom.coe` 生成 `<profile>.dump`。
3. 生成的 src dump 是 raw RV32 反汇编，基地址固定为 `0x80000000`，不包含 ELF 符号。
4. 默认不覆盖已有 dump；需要覆盖时使用 `--force`。

## 已生成文件

```text
data/srcWithMext/srcWithMext.dump
data/srcWithoutMext/srcWithoutMext.dump
```

## 验证

执行：

```sh
python3 -m py_compile scripts/prepare_test_data.py
scripts/prepare_test_data.py --src-only --dry-run
scripts/prepare_test_data.py --src-only
scripts/prepare_test_data.py --src-only --dry-run
```

最终 dry-run 输出：

```text
prepared rv32_hex=0 rv32_dump=0 src_hex=0 src_dump=0
```

