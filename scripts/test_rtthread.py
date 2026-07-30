#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TESTS = ("startup", "boot", "tick", "context", "preempt")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-build-images", action="store_true")
    parser.add_argument("--no-build-verilator", action="store_true")
    parser.add_argument("--max-cycles", type=int, default=10_000_000)
    args = parser.parse_args()

    if not args.no_build_images:
        subprocess.run(["python3", "scripts/build_rtthread_images.py"], cwd=REPO, check=True)

    failed = False
    for index, test in enumerate(TESTS):
        cmd = ["python3", "scripts/run_verilator.py", "src", "--test",
               f"rtthread-{test}", "--max-cycles", str(args.max_cycles)]
        if args.no_build_verilator or index != 0:
            cmd.append("--no-build")
        failed |= subprocess.run(cmd, cwd=REPO).returncode != 0
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
