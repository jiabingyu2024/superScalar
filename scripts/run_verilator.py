#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
BUILD_DIR = REPO / "build"
VERILATOR_DIR = BUILD_DIR / "verilator" / "mycpu"
BIN = VERILATOR_DIR / "sim_mycpu"
RESULT_DIR = BUILD_DIR / "result"
LOG_DIR = BUILD_DIR / "log"
WAVE_DIR = BUILD_DIR / "wave"
SRC_PROFILE_FILE = REPO / "tb" / "verilator" / "src_profiles.json"
TB_SOURCES = [
    "tb/verilator/main.cpp",
    "tb/verilator/sim_common.cpp",
    "tb/verilator/sim_config.cpp",
    "tb/verilator/sim_memory.cpp",
    "tb/verilator/sim_display.cpp",
    "tb/verilator/sim_trace.cpp",
    "tb/verilator/perf_stats.cpp",
    "tb/verilator/checker.cpp",
    "tb/verilator/checker_rv32.cpp",
    "tb/verilator/checker_src.cpp",
]


@dataclass(frozen=True)
class TestCase:
    name: str
    mode: str
    irom_hex: Path
    dram_hex: Path | None = None
    dump: Path | None = None
    tohost: int | None = None
    src_checker: str = "ledseg"
    src_led_pass: int | None = None
    src_led_fail: int | None = None
    pass_counter_addr: int | None = None
    fail_counter_addr: int | None = None
    expected_pass_count: int | None = None
    src_test_mask: int | None = None
    src_pass_marker: int | None = None
    src_fail_marker: int | None = None
    expected_rv32i_count: int | None = None
    expected_mext_count: int | None = None


def run(cmd: list[str], *, cwd: Path = REPO, log: Path | None = None) -> int:
    if log is None:
        proc = subprocess.run(cmd, cwd=cwd)
        return proc.returncode
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as f:
        proc = subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, text=True)
    return proc.returncode


def source_newer_than_bin() -> bool:
    if not BIN.exists():
        return True
    bin_mtime = BIN.stat().st_mtime
    candidates = [REPO / src for src in TB_SOURCES]
    candidates.extend((REPO / "tb" / "verilator").glob("*.h"))
    candidates.extend((REPO / "scripts" / "filelists").glob("*.f"))
    for path in candidates:
        if path.exists() and path.stat().st_mtime > bin_mtime:
            return True
    return False


def build_verilator(force: bool) -> None:
    if not force and not source_newer_than_bin():
        return
    VERILATOR_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        "verilator",
        "-sv",
        "--cc",
        "--exe",
        "--build",
        "-j",
        "0",
        "--top-module",
        "myCPU",
        "-f",
        "scripts/filelists/verilator_mycpu.f",
        *TB_SOURCES,
        "-Mdir",
        str(VERILATOR_DIR),
        "-o",
        BIN.name,
        "--trace-fst",
        "-Wno-fatal",
        "-CFLAGS",
        "-std=c++17",
    ]
    log = LOG_DIR / "build_mycpu.log"
    rc = run(cmd, log=log)
    if rc != 0:
        raise SystemExit(f"Verilator build failed, see {log}")


def parse_tohost(dump: Path) -> int | None:
    if not dump.exists():
        return None
    pattern = re.compile(r"#\s*([0-9a-fA-F]+)\s+<tohost>")
    for line in dump.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = pattern.search(line)
        if m:
            return int(m.group(1), 16)
    return None


def parse_int_value(value: object) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        return int(value, 0)
    raise TypeError(f"bad integer value in src profile: {value!r}")


def load_src_profiles() -> dict[str, dict[str, object]]:
    if not SRC_PROFILE_FILE.exists():
        return {}
    raw = json.loads(SRC_PROFILE_FILE.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise SystemExit(f"{SRC_PROFILE_FILE} must contain a JSON list")
    profiles: dict[str, dict[str, object]] = {}
    for item in raw:
        if not isinstance(item, dict) or "name" not in item:
            raise SystemExit(f"bad src profile entry in {SRC_PROFILE_FILE}: {item!r}")
        profiles[str(item["name"])] = item
    return profiles


def rv32_tests(args: argparse.Namespace) -> list[TestCase]:
    roots: list[Path]
    if args.suite:
        roots = [REPO / "data" / args.suite]
        if not roots[0].is_dir():
            raise SystemExit(f"unknown rv32 suite: {args.suite}")
    else:
        roots = sorted(p for p in (REPO / "data").glob("rv32*") if p.is_dir())

    hex_files: list[Path] = []
    if args.test:
        for root in roots:
            candidate = root / f"{args.test}.hex"
            if candidate.exists():
                hex_files.append(candidate)
        if not hex_files:
            raise SystemExit(f"unknown rv32 test: {args.test}")
    else:
        for root in roots:
            hex_files.extend(sorted(root.glob("*.hex")))

    tests: list[TestCase] = []
    for hex_path in sorted(hex_files):
        name = hex_path.stem
        dump = hex_path.with_suffix(".dump")
        tohost = parse_tohost(dump)
        if tohost is None:
            tests.append(TestCase(name=name, mode="rv32", irom_hex=hex_path, dump=dump))
        else:
            tests.append(TestCase(name=name, mode="rv32", irom_hex=hex_path,
                                  dump=dump, tohost=tohost))
    return tests


def src_tests(args: argparse.Namespace) -> list[TestCase]:
    roots: list[Path]
    if args.test:
        roots = [REPO / "data" / args.test]
        if not roots[0].is_dir():
            raise SystemExit(f"unknown src test: {args.test}")
    else:
        roots = sorted(p for p in (REPO / "data").glob("src*") if p.is_dir())

    profiles = load_src_profiles()
    tests: list[TestCase] = []
    for root in roots:
        irom = root / "irom.hex"
        dram = root / "dram.hex"
        if not irom.exists() or not dram.exists():
            continue
        dumps = sorted(root.glob("*.dump"))
        profile = profiles.get(root.name, {})
        tests.append(TestCase(name=root.name, mode="src", irom_hex=irom,
                              dram_hex=dram, dump=dumps[0] if dumps else None,
                              src_checker=str(profile.get("checker", "observe")),
                              src_led_pass=parse_int_value(profile.get("led_pass")),
                              src_led_fail=parse_int_value(profile.get("led_fail")),
                              pass_counter_addr=parse_int_value(profile.get("pass_counter_addr")),
                              fail_counter_addr=parse_int_value(profile.get("fail_counter_addr")),
                              expected_pass_count=parse_int_value(
                                  profile.get("expected_pass_count")),
                              src_test_mask=parse_int_value(profile.get("test_lamp_mask")),
                              src_pass_marker=parse_int_value(profile.get("pass_marker")),
                              src_fail_marker=parse_int_value(profile.get("fail_marker")),
                              expected_rv32i_count=parse_int_value(
                                  profile.get("expected_rv32i_count")),
                              expected_mext_count=parse_int_value(
                                  profile.get("expected_mext_count"))))
    if not tests:
        raise SystemExit("no src tests found")
    return tests


def write_unsupported_result(test: TestCase, reason: str) -> Path:
    path = RESULT_DIR / test.mode / f"{test.name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "test": test.name,
        "mode": test.mode,
        "status": "UNSUPPORTED",
        "reason": reason,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def run_test(test: TestCase, args: argparse.Namespace) -> tuple[str, Path]:
    result = RESULT_DIR / test.mode / f"{test.name}.json"
    log = LOG_DIR / test.mode / f"{test.name}.log"
    wave = WAVE_DIR / test.mode / f"{test.name}.fst"
    result.parent.mkdir(parents=True, exist_ok=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    wave.parent.mkdir(parents=True, exist_ok=True)

    if test.mode == "rv32" and test.tohost is None:
        path = write_unsupported_result(test, "tohost symbol not found in dump")
        return "UNSUPPORTED", path

    max_cycles = args.max_cycles
    if max_cycles is None and test.mode == "src":
        max_cycles = int(os.environ.get("SRC_TEST_MAX_CYCLES", "20000000"))
    if max_cycles is None:
        max_cycles = 2000000

    cmd = [
        str(BIN),
        f"--mode={test.mode}",
        f"--test-name={test.name}",
        f"--irom-hex={test.irom_hex}",
        f"--result={result}",
        f"--max-cycles={max_cycles}",
    ]
    if test.mode == "rv32":
        cmd.append(f"--tohost=0x{test.tohost:08x}")
    if test.mode == "src":
        cmd.append(f"--dram-hex={test.dram_hex}")
        cmd.append(f"--src-checker={test.src_checker}")
        cmd.append(f"--src-seg-grace={args.src_seg_grace}")
        cmd.append(f"--counter-cycles-per-ms={args.counter_cycles_per_ms}")
        if test.src_led_pass is not None:
            cmd.append(f"--src-led-pass=0x{test.src_led_pass:08x}")
        if test.src_led_fail is not None:
            cmd.append(f"--src-led-fail=0x{test.src_led_fail:08x}")
        if test.pass_counter_addr is not None:
            cmd.append(f"--pass-counter-addr=0x{test.pass_counter_addr:08x}")
        if test.fail_counter_addr is not None:
            cmd.append(f"--fail-counter-addr=0x{test.fail_counter_addr:08x}")
        if test.expected_pass_count is not None:
            cmd.append(f"--expected-pass-count={test.expected_pass_count}")
        if test.src_test_mask is not None:
            cmd.append(f"--src-test-mask=0x{test.src_test_mask:08x}")
        if test.src_pass_marker is not None:
            cmd.append(f"--src-pass-marker=0x{test.src_pass_marker:08x}")
        if test.src_fail_marker is not None:
            cmd.append(f"--src-fail-marker=0x{test.src_fail_marker:08x}")
        if test.expected_rv32i_count is not None:
            cmd.append(f"--expected-rv32i-count={test.expected_rv32i_count}")
        if test.expected_mext_count is not None:
            cmd.append(f"--expected-mext-count={test.expected_mext_count}")
    if args.trace:
        cmd.append("--trace")
        cmd.append(f"--wave={wave}")

    rc = run(cmd, log=log)
    if result.exists():
        try:
            status = json.loads(result.read_text(encoding="utf-8")).get("status", "UNKNOWN")
        except json.JSONDecodeError:
            status = "BAD_RESULT"
    else:
        status = "CRASH" if rc else "NO_RESULT"
    return status, result


def main() -> int:
    parser = argparse.ArgumentParser(description="Build and run Verilator myCPU tests.")
    sub = parser.add_subparsers(dest="mode", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--test")
        p.add_argument("--max-cycles", type=int)
        p.add_argument("--trace", action="store_true")
        p.add_argument("--build", action="store_true", help="force rebuild before running")
        p.add_argument("--build-only", action="store_true")
        p.add_argument("--no-build", action="store_true")

    p_rv32 = sub.add_parser("rv32")
    add_common(p_rv32)
    p_rv32.add_argument("--suite")
    p_rv32.add_argument("--all", action="store_true")

    p_src = sub.add_parser("src")
    add_common(p_src)
    p_src.add_argument("--all", action="store_true")
    p_src.add_argument("--src-seg-grace", type=int, default=512)
    p_src.add_argument("--counter-cycles-per-ms", type=int, default=50000)

    args = parser.parse_args()
    if not args.no_build:
        build_verilator(force=args.build)
    if args.build_only:
        return 0

    tests = rv32_tests(args) if args.mode == "rv32" else src_tests(args)
    if args.test is None and not getattr(args, "all", False) and getattr(args, "suite", None) is None:
        raise SystemExit("batch run requires --all or --suite; single run requires --test")

    summary: list[dict[str, str]] = []
    bad = False
    for test in tests:
        status, result = run_test(test, args)
        print(f"{test.name}: {status} ({result})")
        summary.append({"test": test.name, "mode": test.mode, "status": status,
                        "result": str(result)})
        if status != "PASS":
            bad = True

    summary_path = RESULT_DIR / args.mode / "summary.json"
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
                            encoding="utf-8")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
