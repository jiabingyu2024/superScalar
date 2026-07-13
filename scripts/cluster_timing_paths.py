#!/usr/bin/env python3
"""Cluster Vivado timing-path CSV rows into reviewable endpoint families."""

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path


def family(name: str) -> str:
    name = re.sub(r"\[\d+\]", "[*]", name)
    name = re.sub(r"_(?:replica|repN)_?\d+", "_replica[*]", name)
    name = re.sub(r"ramloop\[\*\]", "ramloop[*]", name)
    return name


def block(name: str) -> str:
    checks = (
        ("/u_dcache/", "Core.DCache"),
        ("/mem_bridge/", "SoC.MemBridge"),
        ("/u_frontend/", "Core.Frontend"),
        ("/scoreboard_q", "Core.Scoreboard"),
        ("/producer_", "Core.ProducerMap"),
        ("/exec_q", "Core.ExecuteStage"),
        ("/id_uop_q", "Core.DecodeStage"),
        ("/store_q", "Core.StoreBuffer"),
        ("/load_q", "Core.LoadQueue"),
        ("/u_muldiv/", "Core.MulDiv"),
        ("/u_regfile/", "Core.RegFile"),
        ("/Core_cpu/u_core_top/", "Core.Other"),
        ("/uart_inst/", "SoC.UART"),
        ("/pll_inst/", "SoC.PLL"),
    )
    for needle, label in checks:
        if needle in name:
            return label
    return "SoC.Other"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("output_md", type=Path)
    args = parser.parse_args()

    groups: dict[tuple[str, str, str], dict[str, object]] = defaultdict(
        lambda: {
            "count": 0,
            "worst_slack": float("inf"),
            "max_delay": 0.0,
            "max_levels": 0,
        }
    )
    blocks: dict[tuple[str, str], dict[str, object]] = defaultdict(
        lambda: {
            "count": 0,
            "worst_slack": float("inf"),
            "max_delay": 0.0,
            "max_levels": 0,
        }
    )
    total = 0
    with args.csv_path.open(newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            total += 1
            key = (
                family(row["startpoint_pin"]),
                family(row["endpoint_pin"]),
                row["path_group"],
            )
            item = groups[key]
            item["count"] = int(item["count"]) + 1
            item["worst_slack"] = min(float(item["worst_slack"]), float(row["slack_ns"]))
            item["max_delay"] = max(float(item["max_delay"]), float(row["datapath_delay_ns"]))
            item["max_levels"] = max(int(item["max_levels"]), int(row["logic_levels"]))
            block_item = blocks[(block(row["startpoint_pin"]), block(row["endpoint_pin"]))]
            block_item["count"] = int(block_item["count"]) + 1
            block_item["worst_slack"] = min(
                float(block_item["worst_slack"]), float(row["slack_ns"])
            )
            block_item["max_delay"] = max(
                float(block_item["max_delay"]), float(row["datapath_delay_ns"])
            )
            block_item["max_levels"] = max(
                int(block_item["max_levels"]), int(row["logic_levels"])
            )

    ordered = sorted(
        groups.items(),
        key=lambda pair: (float(pair[1]["worst_slack"]), -int(pair[1]["count"])),
    )
    block_ordered = sorted(
        blocks.items(),
        key=lambda pair: (float(pair[1]["worst_slack"]), -int(pair[1]["count"])),
    )
    lines = [
        "# 全量 setup 违例路径聚类",
        "",
        f"- 原始违例路径数：{total}",
        f"- 聚类数：{len(ordered)}",
        "- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。",
        "",
        "## 模块级覆盖矩阵",
        "",
        "| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |",
        "|---:|---:|---:|---:|---:|---|---|",
    ]
    for index, ((start, end), item) in enumerate(block_ordered, 1):
        lines.append(
            f"| {index} | {item['count']} | {float(item['worst_slack']):.3f} | "
            f"{float(item['max_delay']):.3f} | {item['max_levels']} | `{start}` | `{end}` |"
        )
    lines.extend([
        "",
        "## 精细起终点族",
        "",
        "| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |",
        "|---:|---:|---:|---:|---:|---|---|---|",
    ])
    for index, ((start, end, path_group), item) in enumerate(ordered, 1):
        start = start.replace("|", "\\|")
        end = end.replace("|", "\\|")
        lines.append(
            f"| {index} | {item['count']} | {float(item['worst_slack']):.3f} | "
            f"{float(item['max_delay']):.3f} | {item['max_levels']} | `{start}` | `{end}` | "
            f"`{path_group}` |"
        )
    args.output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
