#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import urllib.request
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
UPSTREAM = REPO / "tb" / "difftest" / "upstream"
PROFILE = REPO / "tb" / "difftest" / "profiles" / "rv32_single_commit.json"
DESIGN_DIR = REPO / "tb" / "difftest" / "generated"
GEN_CSRC = UPSTREAM / "build" / "generated-src"
GEN_RTL = DESIGN_DIR / "build" / "rtl"
REQUIRED = [
    GEN_CSRC / "difftest-dpic.cpp",
    GEN_CSRC / "difftest-dpic.h",
    GEN_CSRC / "difftest-state.h",
    GEN_CSRC / "DifftestMacros.svh",
    GEN_RTL / "DiffExtArchEvent.v",
    GEN_RTL / "DiffExtInstrCommit.v",
    GEN_RTL / "DiffExtTrapEvent.v",
    GEN_RTL / "DiffExtCommitData.v",
]


def generated_is_current() -> bool:
    if not all(path.is_file() for path in REQUIRED):
        return False
    oldest_output = min(path.stat().st_mtime for path in REQUIRED)
    newest_input = max(
        PROFILE.stat().st_mtime,
        (UPSTREAM / "build.sc").stat().st_mtime,
    )
    return oldest_output >= newest_input


def find_mill() -> Path:
    system_mill = shutil.which("mill")
    if system_mill:
        return Path(system_mill)

    version = (UPSTREAM / ".mill-version").read_text(encoding="ascii").strip()
    local_mill = REPO / "build" / "tools" / "mill"
    if local_mill.is_file():
        return local_mill

    local_mill.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://github.com/com-lihaoyi/mill/releases/download/{version}/{version}"
    print(f"Downloading Mill {version} for upstream DiffTest generation...", flush=True)
    try:
        urllib.request.urlretrieve(url, local_mill)
    except Exception as exc:
        local_mill.unlink(missing_ok=True)
        raise SystemExit(f"failed to download Mill from {url}: {exc}") from exc
    local_mill.chmod(local_mill.stat().st_mode | stat.S_IXUSR)
    return local_mill


def main() -> int:
    if not (UPSTREAM / ".git").exists():
        raise SystemExit(
            "DiffTest submodule is missing; run: git submodule update --init tb/difftest/upstream"
        )
    if generated_is_current():
        return 0

    mill = find_mill()
    env = os.environ.copy()
    env["PATH"] = str(mill.parent) + os.pathsep + env.get("PATH", "")
    DESIGN_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        "make",
        "-C",
        str(UPSTREAM),
        f"PROFILE={PROFILE}",
        f"DESIGN_DIR={DESIGN_DIR}",
    ]
    subprocess.run(cmd, check=True, env=env)
    missing = [str(path) for path in REQUIRED if not path.is_file()]
    if missing:
        raise SystemExit("upstream DiffTest generation missed: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
