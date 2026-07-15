# 有限双发拒绝与镜像 DCache 方向

## 结论

通用有限顺序双发已经完成 RTL 实验并被拒绝。主线恢复到 iteration11：

- `srcWithMext` 500k：IPC `0.689944`，RV32I=37、M=8、fail=0。
- `srcWithMext` 20M：IPC `0.741227`。
- iteration11 综合：WNS `-0.739 ns`，估算 Fmax `174.2 MHz`。
- `IPC x Fmax` 约 `129.2`，仍是当前最佳点。

被拒绝版本保存在 `backup/20260714_220000_limited_dual_issue_rejected/`。

## 通用有限双发实验

实验加入了双端口 IROM、双取指、4 项 ID FIFO、第二组 RF/Scoreboard 查询口、第二 ALU lane 和受限双提交。

关键结果：

| 版本 | 500k IPC | issue w2 | commit w2 | 结论 |
|---|---:|---:|---:|---|
| 仅 ALU+ALU 配对 | 0.689950 | 32180 | 32201 | 与单发基线无差异 |
| lane0 扩至非系统/非分支，lane1 ALU | 0.689978 | 43260 | 32202 | 仅提升 0.004%，load stall 增加 |
| 错误允许 branch+ALU | 0.523132 | 69729 | 30282 | 全量 flush 无局部 checkpoint，分支 miss 升至 40.5%，拒绝 |

20M 稳态窗口中，安全有限双发版本 IPC 为 `0.741228`，相对基线只增加 `0.000001`；尽管双发 482400 拍，双提交只有 38553 拍，load-return stall 达 5185007 拍。因此不进入 Vivado 综合。

## 双镜像 DCache 可行结构

不能直接实例化两个自治 DCache。两个控制器会在 miss 时重复或交错发 DRAM 请求，并使 refill 内容分叉。

正确结构：

1. 保留一个共享 init/store/miss/refill/uncached 控制器和一个外部 DRAM 请求口。
2. 复制 tag BRAM 和四个 data word bank，形成 lookup A/B 两套镜像数组。
3. init、store hit 更新和每个 refill beat 同时广播写入两套数组。
4. 两个端口只在对齐、cacheable、无更老 store、无 RAW 的两条 load 上同时读取。
5. 两路都 hit 时同拍返回两个结果；任一路 miss 时进入共享 miss 状态机，按程序序服务，并把 refill 广播到两份。
6. store、MMIO、refill、kill、异常和分支恢复期间退化为单路。

当前 DCache 为 1 个 tag RAMB18 加 8 个 data RAMB36。镜像预计再增加约 1 个 RAMB18 和 8 个 RAMB36。新增 BRAM 本身不是主要时序风险；真正的风险是双地址生成、双 Scoreboard 分配/完成以及 hit/result 控制扇出，必须分别寄存，不能形成 DCache hit 到下一拍请求的组合回环。

## Workload 门槛

对 `data/srcWithMext/irom.hex` 的静态统计：

- 指令 2216 条；
- load 341 条；
- 连续 load 对 75 组；
- 排除 `load0.rd -> load1.rs1` RAW 后剩 71 组；
- 安全连续 load 对约为 load 数的 20.8%。

静态密度足以继续动态实验，但不能直接当作 IPC 收益。下一步应先加入动态 adjacent-load-pair 计数，再实现 load 专用双分配/双完成和镜像 DCache；不恢复通用双 ALU 后端。

动态计数最终否决了该方向：500k 窗口 86135 次 load 只有 44 组安全相邻 load；20M 稳态窗口 4759953 次 load 只有 68 组，占 `0.00143%`。热点循环中的 load 与计算或依赖交错，双镜像 DCache 几乎没有可利用的同拍 load 对。因此不实现镜像数组，后续改为单 DCache 的寄存早地址和低延迟 load 启动。
