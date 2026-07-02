#!/usr/bin/env python3
"""Prepare local test artifacts in-place under data/.

Generated files are intentionally placed next to their source test files:
- rv32 ELF files get <test>.dump when missing and <test>.hex when missing.
- src COE files get irom.hex/dram.hex when missing.

The script is idempotent by default and only overwrites with --force.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


RV32_PREFIX = "rv32"
SRC_PREFIX = "src"


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def is_elf(path: Path) -> bool:
    if not path.is_file() or "." in path.name:
        return False
    try:
        with path.open("rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def write_text_if_needed(path: Path, text: str, force: bool, dry_run: bool) -> bool:
    if path.exists() and not force:
        return False
    if dry_run:
        print(f"would write {path}")
        return True
    path.write_text(text)
    return True


def elf_to_word_hex(elf: Path, objcopy: str) -> str:
    with tempfile.TemporaryDirectory() as tmpdir:
        binary = Path(tmpdir) / "image.bin"
        run([objcopy, "-O", "binary", str(elf), str(binary)])
        data = binary.read_bytes()

    words: list[str] = []
    for offset in range(0, len(data), 4):
        chunk = data[offset : offset + 4]
        if len(chunk) < 4:
            chunk = chunk + bytes(4 - len(chunk))
        words.append(f"{int.from_bytes(chunk, byteorder='little'):08x}")
    return "\n".join(words) + "\n"


def prepare_rv32(data_dir: Path, force: bool, dry_run: bool) -> tuple[int, int]:
    objcopy = shutil.which("riscv64-unknown-elf-objcopy") or shutil.which("riscv32-unknown-elf-objcopy")
    objdump = shutil.which("riscv64-unknown-elf-objdump") or shutil.which("riscv32-unknown-elf-objdump")
    if objcopy is None:
        raise RuntimeError("missing riscv objcopy; install riscv64-unknown-elf-objcopy or riscv32-unknown-elf-objcopy")

    hex_count = 0
    dump_count = 0
    for suite_dir in sorted(p for p in data_dir.iterdir() if p.is_dir() and p.name.startswith(RV32_PREFIX)):
        for elf in sorted(p for p in suite_dir.iterdir() if is_elf(p)):
            hex_path = elf.with_suffix(".hex")
            if not hex_path.exists() or force:
                text = elf_to_word_hex(elf, objcopy)
                if write_text_if_needed(hex_path, text, force, dry_run):
                    hex_count += 1

            dump_path = elf.with_suffix(".dump")
            if (not dump_path.exists() or force) and objdump is not None:
                if dry_run:
                    print(f"would write {dump_path}")
                    dump_count += 1
                else:
                    with dump_path.open("w") as f:
                        subprocess.run([objdump, "-D", str(elf)], check=True, stdout=f)
                    dump_count += 1
    return hex_count, dump_count


def coe_to_hex_text(coe: Path) -> str:
    raw = coe.read_text()
    radix_match = re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;", raw, re.IGNORECASE)
    if not radix_match or int(radix_match.group(1)) != 16:
        raise ValueError(f"only radix=16 COE files are supported: {coe}")

    vector_match = re.search(r"memory_initialization_vector\s*=\s*(.*?);", raw, re.IGNORECASE | re.DOTALL)
    if not vector_match:
        raise ValueError(f"missing memory_initialization_vector: {coe}")

    words = []
    for item in vector_match.group(1).replace("\n", " ").split(","):
        word = item.strip()
        if not word:
            continue
        words.append(f"{int(word, 16) & 0xffffffff:08x}")
    return "\n".join(words) + ("\n" if words else "")


def prepare_src(data_dir: Path, force: bool, dry_run: bool) -> int:
    hex_count = 0
    for src_dir in sorted(p for p in data_dir.iterdir() if p.is_dir() and p.name.startswith(SRC_PREFIX)):
        for coe in sorted(src_dir.glob("*.coe")):
            hex_path = coe.with_suffix(".hex")
            if not hex_path.exists() or force:
                text = coe_to_hex_text(coe)
                if write_text_if_needed(hex_path, text, force, dry_run):
                    hex_count += 1
    return hex_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", default="data", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--rv32-only", action="store_true")
    parser.add_argument("--src-only", action="store_true")
    args = parser.parse_args()

    data_dir = args.data_dir
    if not data_dir.is_dir():
        raise RuntimeError(f"data directory not found: {data_dir}")

    rv32_hex = rv32_dump = src_hex = 0
    if not args.src_only:
        rv32_hex, rv32_dump = prepare_rv32(data_dir, args.force, args.dry_run)
    if not args.rv32_only:
        src_hex = prepare_src(data_dir, args.force, args.dry_run)

    print(f"prepared rv32_hex={rv32_hex} rv32_dump={rv32_dump} src_hex={src_hex}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
