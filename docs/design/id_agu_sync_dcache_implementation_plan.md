# ID-AGU + 一拍同步 DCache 优化修改计划

## 1. 目标与非目标

目标：把当前 `ID -> EX -> M1 -> M2 -> WB` 后端改为普通 EX 通道与访存 Cache 通道并行的三段结构：

```text
普通：C0 ID        -> C1 EX             -> C2 WB
访存：C0 ID + AGU  -> C1 synchronous $  -> C2 WB/load 或 store done
长延迟：C0 ID      -> C1 MUL/DIV busy   -> C2 WB
```

本计划的首版目标是正确、可综合、可测量和 50 MHz 时序闭合。首版不做双发射、乱序、non-blocking cache、store buffer、内存乱序或 speculative store。

## 2. 推荐 RTL 框架

### 2.1 模块职责

| 模块 | 处理建议 | 职责 |
| --- | --- | --- |
| `stage_id.sv` | 保留并收窄输出 | decode、RF 读、立即数；不拥有 Cache FSM |
| 新 `agu.sv` | 新增 | `base + imm`、地址低位、访问 mask；只做地址生成 |
| 新 `reg_id_c1.sv` | 替代/重写 `reg_id_ex.sv` | 保存统一 valid、PC、rd、操作数和 mem/ex 控制；支持 accept/hold/kill |
| `stage_ex.sv` | 重构 | 普通 ALU、branch/redirect、CSR、MUL/DIV；不再生成 load/store 地址 |
| `DCache.sv` | 重写命中前端，保留 miss 后端思路 | 同步 tag/data lookup、hit pipeline、miss/uncached replay、store write-through |
| 新 `c2_result_mux.sv` | 新增 | 统一 ALU/load/MUL-DIV 写回结果与 rd/we/valid |
| 新 `reg_c2_wb.sv` | 替代 `reg_m2_wb.sv` | 单一写回边界，提供 WB -> EX/AGU 前递 |
| `hazard_unit.sv` | 重写 | 基于 valid/ready/kill 的前端冻结、地址相关 stall、redirect 优先级 |
| `forward_unit.sv` | 重写 | 分离 EX operand、AGU base、store data 三类前递决策 |
| `myCPU.sv` | 调整边界 | 建议让 core 直接使用 request/response 契约；至少移除历史 M1/M2 假设 |

模块边界按所有权划分：AGU 拥有地址计算，DCache 拥有请求保持与 replay，hazard 拥有停顿/清除优先级，C2 mux 拥有唯一写回选择。不要让 `core.sv` 重新堆积这些组合行为。

### 2.2 内部接口

建议将 C0 到 C1 的访存 payload 明确化：

```text
mem_req_payload = {
  valid, pc, is_load, is_store,
  addr, size, unsigned_load,
  store_data, store_mask,
  rd, reg_write
}
```

握手规则：

- `c0_accept = c0_valid && c1_ready && !kill_c0`
- `c1_valid` 在 miss/busy 时保持，payload 同时保持
- Cache/外部请求只在 `request_fire` 时发生一次副作用
- redirect/exception 的 kill 优先于 accept，reset 优先级最高
- C2 用 `valid + producer` 标识来源，不依赖旧的 `wb_src` 与流水级位置猜测

## 3. 分阶段实施

### Phase 0：建立可比较基线

1. 固定当前 commit 口径，修正 `myCPU.sv` 中仍为 0 的 load/store、MUL/DIV、load-use 性能计数。
2. DCache stall 拆为 `hit_pipeline_wait`、`miss_refill`、`uncached_wait`、`store_wait`。
3. 保存 `rv32ui/rv32um/rv32mi`、`srcSmoke`、`srcWithMext` 短窗口结果。
4. 生成 Vivado post-synth timing/utilization 基线，记录 WNS、关键路径、LUT/FF/BRAM/DSP。

完成门：能解释当前 CPI 中至少 90% 的额外周期来源；否则改造后无法判断好坏。

### Phase 1：统一 valid/ready/kill 控制，不改功能级数

1. 给现有流水边界补齐显式 valid，替换依靠控制信号全 0 表示 bubble 的隐式做法。
2. 定义统一优先级：`reset > redirect/exception kill > hold > accept`。
3. 添加断言：stall 时 payload 稳定、kill 后无 reg write/store、请求不重复、每条指令最多完成一次。
4. 先保持现有 EX/M1/M2 数据通路，跑全回归。

完成门：功能结果与基线一致，新增断言无失败。该阶段先降低后续大改的控制风险。

### Phase 2：增加 ID-AGU 和双 C1 通道

1. 新增独立 `agu.sv`，load/store 地址改由 C0 计算。
2. `reg_id_c1` 分发 `ex_valid` 或 `mem_valid`，二者互斥。
3. 普通指令继续临时穿过旧后级，访存地址先与旧 EX 结果做逐周期对比断言。
4. 实现三类 hazard：AGU base、EX operand、store data；首版对 C1 producer -> AGU base 相关停 1 拍。
5. store data 允许在 C1 再前递，避免把不必要的数据相关变成 AGU stall。

完成门：随机/定向测试中，新旧地址、mask、store data 一致；地址相关 stall 计数可见。

### Phase 3：把 DCache 改成一拍同步读

1. 把 data bank 改为同步读 inference 模板，tag 与 data 采用同一 C0 地址并行读取。
2. C1 完成 tag compare、word/byte 选择与符号扩展，C1 末寄存 load result。
3. 保留 blocking miss/replay，但将 hit pipeline 与 miss FSM 分离；miss 捕获原请求 payload 后不得依赖上游漂移。
4. store hit 更新 cache 的同时执行 write-through；只有外部 handshake 成功才报告 store done。
5. uncached/MMIO 绕过 cache array，但复用同一 C1 请求槽，保证顺序和不可重放。
6. DCache 对 core 暴露规范的 `req_valid/req_ready` 与 `resp_valid/resp_ready`，不再让 core 忽略 `cpu_resp_valid`。

完成门：连续独立 load hit 能做到 1 request/cycle；miss、同 index 冲突、store-hit 后 load、各 byte mask、MMIO 均通过。

### Phase 4：删除 M1/M2，建立统一 C2/WB

1. 普通 ALU/CSR/link 在 C1 末进入 `reg_c2_wb`。
2. load 数据从 Cache C1 末进入同一 C2；store 只生成完成事件，不置 `reg_write`。
3. 删除普通结果跨 `reg_ex_m1`、`reg_m1_m2`、`reg_m2_wb` 的旧路径及旧 `wb_src` 传播。
4. 分支 `error/right_pc` 直接从 C1 EX 送 PC/hazard；BPU update 可在 C1 锁存后更新，但 redirect 不再等待旧 M1。
5. 对 C2 producer 冲突加断言；若 MUL/DIV done 能与 Cache response 并发，加入一深度 result buffer 或冻结时保证互斥。

完成门：所有 RV32 回归通过；分支误预测恢复周期比基线少 1；错误路径 store 永不 fire。

### Phase 5：MUL/DIV 固定周期阻塞整理

1. C1 接受 M 指令时锁存 `rs1/rs2/op/rd/pc`，只发一个 start pulse。
2. MUL 固定 3 拍、DIV/REM 固定 34 拍；busy 期间 C0/前端 hold，旧指令允许先排空。
3. done 只产生一次 C2 valid；redirect/reset 可取消尚未产生架构副作用的操作。
4. 用 cycle-accurate 断言校验 start-to-done 延迟、busy 稳定性和结果对应关系。

完成门：全套 `rv32um` 通过，连续 M 指令、M 后相关、分支 kill M、除零和溢出定向测试通过。

### Phase 6：时序驱动优化

按以下顺序尝试，且每步都比较 IPC 与 WNS：

1. 默认保留 AGU base 相关 1 拍 stall，先确认同步 Cache 的 BRAM 推断和 50 MHz WNS。
2. 若地址相关 stall 占比显著且 WNS 充足，再加入 `EX -> ID/AGU` 旁路。
3. 不建议加入 `Cache -> ID/AGU` 组合旁路；优先接受 1 拍 stall，或增加小型 load result bypass register。
4. 若 miss 仍是第一瓶颈，下一项目应是 critical-word-first/early restart，而不是继续压缩流水寄存级。
5. 若 DIV busy 是第一瓶颈，再评估可流水 MUL、独立 MulDiv 单元或允许非相关指令前进；这些超出本计划首版范围。

## 4. 文件级修改清单

| 文件 | 预期动作 |
| --- | --- |
| `rtl/core/core.sv` | 重连 C0/C1/C2；移除 M1/M2 历史信号；接入直接 redirect |
| `rtl/core/id/stage_id.sv` | 输出紧凑 decode/RF payload |
| `rtl/core/id/agu.sv` | 新增地址生成与低位信息 |
| `rtl/core/ex/stage_ex.sv` | 去除访存地址职责；保留 ALU/branch/CSR/MulDiv |
| `rtl/core/memory/DCache.sv` | 同步 tag/data、规范 req/resp、hit/miss 分层 |
| `rtl/core/control/hazard_unit.sv` | 改为 valid/ready/kill + 分类 hazard |
| `rtl/core/control/forward_unit.sv` | 分类产生 EX、AGU、store-data 前递 |
| `rtl/core/pipeline_regs/` | 新增 `reg_id_c1.sv`、`reg_c2_wb.sv`，稳定后删除四个旧后端寄存器 |
| `rtl/core/myCPU.sv` | 更新 core-DCache 契约与性能计数 |
| `scripts/filelists/core.f` | 同步新增/删除文件，避免继续引用旧路径 |
| `docs/design/rtl_core_design.md` | 实现稳定后更新为新的当前设计事实 |

不要在第一提交中直接删除旧寄存器文件。先并行接入、对比，再删除，可显著降低定位成本。

## 5. 验证计划

### 5.1 定向测试

- ALU -> ALU、ALU -> branch、ALU -> load/store base
- load -> ALU、load -> branch、load -> load/store base
- ALU/load -> store data，地址与数据分别相关
- 连续 load、连续 store、load/store 同地址、不同 byte/half/word mask
- hit、conflict miss、refill、miss 后 replay、uncached/MMIO
- branch 与年轻 store 同拍，exception 与年轻 store 同拍
- MUL/DIV 前后 RAW，busy 时 miss/redirect/reset

### 5.2 回归命令

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make verilator-build-src BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
make sim-rv32-all NO_BUILD=1 OBJCACHE=
make sim-src TEST=srcSmoke NO_BUILD=1 OBJCACHE=
make sim-src TEST=srcWithMext MAX_CYCLES=200000 NO_BUILD=1 OBJCACHE=
```

控制路径、同步 RAM 模板和 filelist 改动完成后，再跑 Vivado batch 综合/实现并检查 RAM inference 与 timing report。

### 5.3 必要断言

- `ex_valid` 与 `mem_valid` 互斥
- hold 时 C1 payload 稳定
- kill 的指令不写 RF、不发 store、不更新 CSR/BPU
- 每个 accepted memory op 最多一个 completion
- store request 在 backpressure 下地址/数据/mask 稳定
- C2 每拍最多一个 writer，`rd==0` 时不写
- MUL/DIV start 单脉冲，done 延迟固定且只出现一次

## 6. 验收指标

| 类别 | 指标 |
| --- | --- |
| 正确性 | RV32 全套不退化，`srcSmoke` PASS，短窗口无断言失败 |
| Cache 吞吐 | 连续独立 hit 请求达到 1 request/cycle |
| 控制 | branch redirect 相对当前减少 1 拍；错误路径 store=0 |
| 性能 | IPC 不低于基线；每个新增 stall 都能由分类计数解释 |
| 时序 | Kintex-7 50 MHz post-route WNS >= 0；同步 RAM 确认映射到预期 BRAM/LUTRAM |
| 资源 | 记录 LUT/FF/BRAM/DSP 差异，不以 LUT 降低换取不可解释 stall |

性能目标分两级：首要门槛是 IPC 不退化且 Fmax/资源改善；进阶目标是根据 Phase 0 的真实 stall 分解，再设定 IPC 数值，而不是预先承诺固定提升。

## 7. 回滚点与实现顺序

建议每个 Phase 单独提交，顺序为：计数器基线 -> valid/kill -> ID-AGU shadow compare -> 同步 DCache -> C2 合并/删除旧级 -> MulDiv 整理 -> 时序优化。

每个提交必须保持可编译和最小回归可运行。若同步 DCache 阶段出现大面积错误，可回退到 shadow compare 版本继续定位，而不需要恢复整个控制路径。

