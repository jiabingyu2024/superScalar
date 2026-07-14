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

import run_verilator as rv


REPO = Path(__file__).resolve().parents[1]
BUILD_DIR = REPO / "build"
RESULT_DIR = BUILD_DIR / "result" / "difftest"
LOG_DIR = BUILD_DIR / "log" / "difftest"
WAVE_DIR = BUILD_DIR / "wave" / "difftest"

COMMON_TB_SOURCES = rv.COMMON_TB_SOURCES
DIFFTEST_COMMON_SOURCES = [
    "tb/difftest/adapter/difftest_adapter.cpp",
    "tb/difftest/adapter/reference_model.cpp",
    "tb/difftest/upstream/build/generated-src/difftest-dpic.cpp",
]
UPSTREAM_RTL_SOURCES = [
    "tb/difftest/generated/build/rtl/DiffExtArchEvent.v",
    "tb/difftest/generated/build/rtl/DiffExtInstrCommit.v",
    "tb/difftest/generated/build/rtl/DiffExtTrapEvent.v",
    "tb/difftest/generated/build/rtl/DiffExtCommitData.v",
]
MYCPU_DIFFTEST_SOURCES = [
    "tb/difftest/harness/main_difftest_mycpu.cpp",
    "tb/difftest/adapter/dut_commit_io.cpp",
    "tb/verilator/dut_mycpu_io.cpp",
    *DIFFTEST_COMMON_SOURCES,
    *COMMON_TB_SOURCES,
]
STUDENT_TOP_DIFFTEST_SOURCES = [
    "tb/difftest/harness/main_difftest_student_top.cpp",
    "tb/difftest/adapter/dut_student_top_commit_io.cpp",
    "tb/verilator/dut_student_top_io.cpp",
    *DIFFTEST_COMMON_SOURCES,
    *COMMON_TB_SOURCES,
]

@dataclass(frozen=True)
class BuildTarget:
    name: str
    top_module: str
    filelist: Path
    sources: list[str]
    out_dir: Path
    bin_path: Path
    log_path: Path
    defines: tuple[str, ...] = ("VERILATOR_TB", "ENABLE_DIFFTEST", "DIFFTEST")


def build_target_for_mode(mode: str) -> BuildTarget:
    if mode == "rv32":
        out_dir = BUILD_DIR / "verilator" / "mycpu_difftest"
        return BuildTarget(
            name="mycpu_difftest",
            top_module="myCPU",
            filelist=REPO / "scripts" / "filelists" / "verilator_mycpu.f",
            sources=MYCPU_DIFFTEST_SOURCES,
            out_dir=out_dir,
            bin_path=out_dir / "sim_mycpu_difftest",
            log_path=LOG_DIR / "build_mycpu_difftest.log",
        )
    if mode == "src":
        out_dir = BUILD_DIR / "verilator" / "student_top_difftest"
        return BuildTarget(
            name="student_top_difftest",
            top_module="student_top",
            filelist=REPO / "scripts" / "filelists" / "verilator_student_top.f",
            sources=STUDENT_TOP_DIFFTEST_SOURCES,
            out_dir=out_dir,
            bin_path=out_dir / "sim_student_top_difftest",
            log_path=LOG_DIR / "build_student_top_difftest.log",
        )
    raise SystemExit(f"unknown mode: {mode}")


def run(cmd: list[str], *, cwd: Path = REPO, log: Path | None = None,
        env: dict[str, str] | None = None) -> int:
    if log is None:
        proc = subprocess.run(cmd, cwd=cwd, env=env)
        return proc.returncode
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as f:
        proc = subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT,
                              text=True, env=env)
    return proc.returncode


def source_newer_than_bin(target: BuildTarget) -> bool:
    if not target.bin_path.exists():
        return True
    bin_mtime = target.bin_path.stat().st_mtime
    candidates = [REPO / src for src in target.sources]
    candidates.extend((REPO / "tb" / "verilator").glob("*.h"))
    candidates.extend((REPO / "tb" / "difftest").glob("**/*.h"))
    candidates.extend((REPO / "scripts" / "filelists").glob("*.f"))
    candidates.extend(rv.collect_filelist_sources(target.filelist))
    candidates.append(REPO / "scripts" / "run_difftest.py")
    for path in candidates:
        if path.exists() and path.stat().st_mtime > bin_mtime:
            return True
    return False


def build_verilator(target: BuildTarget, force: bool, jobs: int, cxx: str | None) -> None:
    rc = run([sys.executable, "scripts/prepare_difftest_upstream.py"])
    if rc != 0:
        raise SystemExit("failed to prepare OpenXiangShan DiffTest generated sources")
    if not force and not source_newer_than_bin(target):
        return
    target.out_dir.mkdir(parents=True, exist_ok=True)
    # Keep the independent difftest build reproducible in the sandbox too:
    # Verilator's make rules may invoke a read-only default ccache directory.
    cmd = [
        "env",
        "CCACHE_DISABLE=1",
        "verilator",
        "-sv",
        "--cc",
        "--exe",
        "--build",
        "-j",
        str(jobs),
        "--top-module",
        target.top_module,
        "--output-split",
        "20000",
        "--output-split-cfuncs",
        "20000",
    ]
    for define in target.defines:
        cmd.append(f"-D{define}")
    config_text = (REPO / "rtl/core/pkg/core_config_pkg.sv").read_text(encoding="utf-8")
    upstream_generated = REPO / "tb/difftest/upstream/build/generated-src"
    upstream_common = REPO / "tb/difftest/upstream/src/test/csrc/common"
    upstream_difftest = REPO / "tb/difftest/upstream/src/test/csrc/difftest"
    upstream_config = REPO / "tb/difftest/upstream/config"
    ref_defines: list[str] = []
    for group in ("ZBA", "ZBB", "ZBC", "ZBKB", "ZBKX", "ZBS"):
        match = re.search(rf"CFG_{group}\s*=\s*1'b([01])", config_text)
        if match is None:
            raise SystemExit(f"cannot read CFG_{group} from core_config_pkg.sv")
        ref_defines.append(f"-DREF_{group}={match.group(1)}")
    cmd.extend([
        "-f",
        str(target.filelist.relative_to(REPO)),
        "-Itb/difftest/upstream/build/generated-src",
        *UPSTREAM_RTL_SOURCES,
        *target.sources,
        "-Mdir",
        str(target.out_dir),
        "-o",
        target.bin_path.name,
        "--trace-fst",
        "-Wno-fatal",
        "-CFLAGS",
        "-std=c++17 -O3 "
        f"-I{upstream_generated} "
        f"-I{upstream_common} "
        f"-I{upstream_difftest} "
        f"-I{upstream_config} " + " ".join(ref_defines),
    ])
    if cxx:
        cmd.extend(["-MAKEFLAGS", f"CXX={cxx} OBJCACHE="])
    rc = run(cmd, log=target.log_path)
    if rc != 0:
        raise SystemExit(f"DiffTest Verilator build failed, see {target.log_path}")


def write_unsupported_result(test: rv.TestCase, reason: str) -> Path:
    path = RESULT_DIR / test.mode / f"{test.name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "test": test.name,
        "mode": test.mode,
        "status": "UNSUPPORTED",
        "reason": reason,
        "difftest": {
            "mode": "openxiangshan_dpic_rv32_reference",
            "reference_enabled": True,
        },
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def disabled_zb_extension(test: rv.TestCase) -> str | None:
    match = re.match(r"rv32u(zba|zbb|zbc|zbkb|zbkx|zbs)-", test.name)
    if match is None:
        return None
    group = match.group(1).upper()
    config_text = (REPO / "rtl/core/pkg/core_config_pkg.sv").read_text(encoding="utf-8")
    enabled = re.search(rf"CFG_{group}\s*=\s*1'b1", config_text) is not None
    return None if enabled else group


def run_test(test: rv.TestCase, args: argparse.Namespace,
             target: BuildTarget) -> tuple[str, Path]:
    result = RESULT_DIR / test.mode / f"{test.name}.json"
    log = LOG_DIR / test.mode / f"{test.name}.log"
    wave = WAVE_DIR / test.mode / f"{test.name}.fst"
    result.parent.mkdir(parents=True, exist_ok=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    wave.parent.mkdir(parents=True, exist_ok=True)
    result.unlink(missing_ok=True)

    if test.mode == "rv32" and test.tohost is None:
        path = write_unsupported_result(test, "tohost symbol not found in dump")
        return "UNSUPPORTED", path

    max_cycles = args.max_cycles
    if max_cycles is None and test.mode == "src":
        max_cycles = int(os.environ.get(
            "SRC_MAX_CYCLES",
            os.environ.get("SRC_TEST_MAX_CYCLES", "100000000"),
        ))
    if max_cycles is None:
        max_cycles = 2000000

    cmd = [
        str(target.bin_path),
        f"--mode={test.mode}",
        f"--test-name={test.name}",
        f"--irom-hex={test.irom_hex}",
        f"--result={result}",
        f"--max-cycles={max_cycles}",
    ]
    if test.mode == "rv32":
        cmd.append(f"--tohost=0x{test.tohost:08x}")
    if test.mode == "src":
        cmd.insert(1, f"+dram_hex={test.dram_hex}")
        cmd.insert(1, f"+irom_hex={test.irom_hex}")
        cmd.append(f"--dram-hex={test.dram_hex}")
        cmd.append(f"--src-checker={test.src_checker}")
        cmd.append(f"--src-seg-grace={args.src_seg_grace}")
        cmd.append(f"--counter-cycles-per-ms={args.counter_cycles_per_ms}")
        cmd.append(f"--cpu-freq-mhz={args.cpu_freq_mhz}")
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

    env = os.environ.copy()
    if args.difftrace:
        env["DIFFTRACE"] = "1"
    rc = run(cmd, log=log, env=env)
    if result.exists():
        try:
            status = json.loads(result.read_text(encoding="utf-8")).get("status", "UNKNOWN")
        except json.JSONDecodeError:
            status = "BAD_RESULT"
    else:
        status = "CRASH" if rc else "NO_RESULT"
    return status, result


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build and run commit-level RV32 reference DiffTest harnesses.")
    sub = parser.add_subparsers(dest="mode", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--test")
        p.add_argument("--max-cycles", type=int)
        p.add_argument("--trace", action="store_true")
        p.add_argument("--difftrace", action="store_true",
                       help="print every commit observed by the difftest harness")
        p.add_argument("--build", action="store_true", help="force rebuild before running")
        p.add_argument("--build-only", action="store_true")
        p.add_argument("--no-build", action="store_true")
        p.add_argument("--build-jobs", type=int,
                       default=int(os.environ.get("VERILATOR_BUILD_JOBS", "0")))
        p.add_argument("--build-cxx", default=os.environ.get("VERILATOR_CXX"))

    p_rv32 = sub.add_parser("rv32")
    add_common(p_rv32)
    p_rv32.add_argument("--suite")
    p_rv32.add_argument("--all", action="store_true")

    p_src = sub.add_parser("src")
    add_common(p_src)
    p_src.add_argument("--all", action="store_true")
    p_src.add_argument("--src-seg-grace", type=int, default=512)
    p_src.add_argument("--counter-cycles-per-ms", type=int, default=50000)
    p_src.add_argument("--cpu-freq-mhz", type=float,
                       default=float(os.environ.get("CPU_FREQ_MHZ", "50")))

    args = parser.parse_args()
    target = build_target_for_mode(args.mode)
    if not args.no_build:
        build_verilator(target, force=args.build, jobs=args.build_jobs, cxx=args.build_cxx)
    if args.build_only:
        return 0

    tests = rv.rv32_tests(args) if args.mode == "rv32" else rv.src_tests(args)
    if args.test is None and not args.all and getattr(args, "suite", None) is None:
        raise SystemExit("batch run requires --all or --suite; single run requires --test")

    summary: list[dict[str, str]] = []
    bad = False
    for test in tests:
        disabled_group = disabled_zb_extension(test)
        if disabled_group is not None:
            if args.test is None:
                continue
            result = write_unsupported_result(
                test, f"CFG_{disabled_group}=0 in core_config_pkg.sv")
            print(f"{test.name}: UNSUPPORTED ({result})")
            summary.append({"test": test.name, "mode": test.mode,
                            "status": "UNSUPPORTED", "result": str(result)})
            continue
        status, result = run_test(test, args, target)
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
