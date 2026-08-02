# RV32UF test data provenance

This directory contains the 11 official `rv32uf-p-*` tests built from
[`riscv-software-src/riscv-tests`](https://github.com/riscv-software-src/riscv-tests):

- upstream commit: `3cf82492ee5e6c0acec786e0e2670969a4041a41`
- `env` submodule commit: `6de71edb142be36319e380ce782c3d1830c65d68`
- source directory: `isa/rv32uf/`
- build date: 2026-08-02
- compiler: `riscv64-unknown-elf-gcc 13.2.0`
- binutils: Ubuntu `riscv64-unknown-elf-*` toolchain paired with that compiler

The upstream source and test environment were not modified. The upstream
Makefile builds these tests with `-march=rv32g -mabi=ilp32`. Consequently the
ELF architecture attribute advertises `D`, although the `rv32uf-p-*` test
disassembly contains no double-precision (`*.d`, `fld`, or `fsd`) instructions.
The tests exercise the scalar single-precision `F` extension.

## Included tests

- `rv32uf-p-fadd`
- `rv32uf-p-fclass`
- `rv32uf-p-fcmp`
- `rv32uf-p-fcvt`
- `rv32uf-p-fcvt_w`
- `rv32uf-p-fdiv`
- `rv32uf-p-fmadd`
- `rv32uf-p-fmin`
- `rv32uf-p-ldst`
- `rv32uf-p-move`
- `rv32uf-p-recoding`

Each test is stored in the repository's existing RV32 format:

- no extension: ELF32 little-endian RISC-V executable;
- `.dump`: official GNU objdump output used to locate `tohost`;
- `.hex`: one little-endian 32-bit word per line for `$readmemh`.

All generated `.hex` images are at most 2,124 words and fit the current 4,096
word IROM.

## Reproduction

```sh
git clone --recurse-submodules https://github.com/riscv-software-src/riscv-tests.git
cd riscv-tests
git checkout 3cf82492ee5e6c0acec786e0e2670969a4041a41
git submodule update --init --recursive
autoconf
./configure
make -C isa -f "$PWD/isa/Makefile" src_dir="$PWD/isa" XLEN=32 \
  rv32uf-p-fadd.dump rv32uf-p-fdiv.dump rv32uf-p-fclass.dump \
  rv32uf-p-fcmp.dump rv32uf-p-fcvt.dump rv32uf-p-fcvt_w.dump \
  rv32uf-p-fmadd.dump rv32uf-p-fmin.dump rv32uf-p-ldst.dump \
  rv32uf-p-move.dump rv32uf-p-recoding.dump
```

After copying the ELF and dump files into this directory, generate the hex
files with:

```sh
python3 scripts/prepare_test_data.py --rv32-only
```

Run the suite with:

```sh
make sim-rv32 SUITE=rv32uf NO_BUILD=1 OBJCACHE=
```

The upstream BSD license is reproduced in `LICENSE.riscv-tests` as required
for redistribution of the generated binaries.
