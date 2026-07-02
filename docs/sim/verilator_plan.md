# Verilator 仿真规划

## 用户入口

后续 Makefile 应作为用户可见命令入口。Python 脚本可以在 Makefile 背后负责测试发现、路径展开、批量执行和结果汇总。

目标命令形态：

```sh
make sim-rv32 TEST=rv32ui-p-simple
make sim-rv32 SUITE=rv32ui
make sim-rv32-all
make sim-src TEST=srcSmoke
make sim-src-all
```

## 测试选择粒度

rv32 测试需要支持：

| 模式 | 示例 |
| --- | --- |
| 单个测试 | `TEST=rv32ui-p-add` |
| 单个套件 | `SUITE=rv32ui` |
| 全部套件 | `sim-rv32-all` |

src 测试需要支持：

| 模式 | 示例 |
| --- | --- |
| 单个 profile | `TEST=src0` |
| 全部 profile | `sim-src-all` |

## 文件列表

稳定 filelist 位于 `scripts/filelists/`：

| 文件 | 用途 |
| --- | --- |
| `core.f` | core package、interface、module、`core` 和 `myCPU`。 |
| `soc.f` | SoC wrapper RTL。 |
| `ip_verilator.f` | 仅 Verilator/仿真使用的 IP 行为模型。 |
| `verilator_mycpu.f` | 主 DUT `myCPU` 的仿真 filelist。 |
| `verilator_student_top.f` | SoC smoke DUT 的仿真 filelist。 |

## 生成输出

后续仿真输出建议使用：

```text
build/verilator/
build/log/
build/wave/
build/result/
```

`build/` 已被 git 忽略。

## 测试数据准备

使用：

```sh
scripts/prepare_test_data.py
```

该脚本会在 `data/` 原目录下补齐缺失的 `.hex` 和 `.dump`。默认幂等，不覆盖已有文件；需要覆盖时显式使用 `--force`。
