# Verilator TB：myCPU rv32/src 判定链路

> 本次只实现 testbench、运行脚本和仿真文档，不修改 core 内部 RTL 行为。

## 1. 新增/修改内容

| 文件 | 内容 |
| --- | --- |
| `tb/verilator/tb_mycpu.cpp` | `myCPU` C++ testbench，包含 IROM/DRAM/MMIO/counter/virtual_seg 行为模型，以及 rv32/src 自检判定。 |
| `scripts/run_verilator.py` | Verilator 编译、测试发现、单测/批量运行、日志和 JSON 结果汇总。 |
| `Makefile` | 提供 `sim-rv32`、`sim-rv32-all`、`sim-src`、`sim-src-all`、`verilator-build` 入口。 |
| `scripts/filelists/core.f` | 调整 package 顺序，满足 Verilator 对 `StoreBufferIndexPath` 的声明依赖。 |
| `docs/sim/verilator_plan.md` | 从规划更新为当前仿真使用说明。 |

## 2. TB 判定范围

rv32：

1. 从 `.dump` 解析 `<tohost>` 地址。
2. CPU 上升沿采样 `perip_wen/perip_addr/perip_wdata`。
3. `tohost == 1` 为 PASS；非 0 非 1 为 FAIL；超时为 TIMEOUT；找不到符号为 UNSUPPORTED。

src：

1. 写 LED `0x24181824` 为 FAIL。
2. 写 LED `0x01221c08` 后进入 SEG 检查。
3. 要求 SEG 高两位 BCD 为 37，低六位 BCD 等于 TB counter_ms。
4. 要求 virtual_seg 编码能还原当前 `seg_wdata`。
5. LED PASS 后 512 CPU 周期内仍不匹配则 FAIL，最大周期无结果则 TIMEOUT。

## 3. 外设模型关键点

1. IROM：地址上升沿寄存，随后组合读寄存地址。
2. DRAM：普通读请求两拍返回；读数据按 `addr[1:0]` 右移，匹配 `dram_driver` 行为。
3. counter：默认每 50000 个 CPU 周期加 1ms，可由 `--counter-cycles-per-ms` 调整。
4. MMIO 写会进入测试日志，方便确认判定来源。

## 4. 已验证命令

```sh
python3 -m py_compile scripts/run_verilator.py
git diff --check
scripts/run_verilator.py rv32 --test rv32ui-p-simple --build --build-only
scripts/run_verilator.py rv32 --test rv32ui-p-simple --max-cycles 20000
scripts/run_verilator.py src --test srcSmoke --max-cycles 200000 --counter-cycles-per-ms 50
```

当前 smoke 运行结果：

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| `rv32ui-p-simple` | FAIL，tohost 写 `0xffffffc4` | TB 正常捕获 FAIL。 |
| `srcSmoke` | TIMEOUT | TB 正常输出 TIMEOUT；未观察到 LED PASS 写。 |

以上结果不代表 RTL 正确，只说明 TB/Verilator 链路能够编译、运行并记录结果。
