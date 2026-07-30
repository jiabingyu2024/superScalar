#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BSP = REPO / "rt-thread" / "bsp" / "superscalar-verilator"
TESTS = ("startup", "boot", "tick", "context", "preempt")


def run(cmd: list[str], cwd: Path = REPO) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)


def binary_to_word_hex(binary: Path, output: Path) -> None:
    data = binary.read_bytes()
    data += bytes((-len(data)) & 3)
    words = [data[i:i + 4][::-1].hex() for i in range(0, len(data), 4)]
    output.write_text("\n".join(words) + "\n", encoding="ascii")


def build(test: str, scons: str) -> None:
    run([scons, "-j4", f"RTT_TEST={test}"], BSP)
    out = REPO / "data" / f"rtthread-{test}"
    out.mkdir(parents=True, exist_ok=True)
    elf = out / "rtthread.elf"
    raw = out / "rtthread.bin"
    shutil.copy2(BSP / "rtthread.elf", elf)
    run(["riscv64-unknown-elf-objcopy", "-O", "binary", str(elf), str(raw)])
    binary_to_word_hex(raw, out / "irom.hex")
    (out / "dram.hex").write_text("00000000\n", encoding="ascii")
    with (out / "rtthread.dump").open("w", encoding="utf-8") as dump:
        subprocess.run(["riscv64-unknown-elf-objdump", "-d", "-S", str(elf)],
                       cwd=out, check=True, stdout=dump)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", choices=TESTS)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--scons", default=shutil.which("scons") or "/home/hw/.local/bin/scons")
    args = parser.parse_args()
    if args.live:
        build("live", args.scons)
    else:
        for test in (args.test,) if args.test else TESTS:
            build(test, args.scons)


if __name__ == "__main__":
    main()
