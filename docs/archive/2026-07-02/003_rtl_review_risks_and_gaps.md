# RTL 评审问题与不完善点归档

> 本文是对当前 `rtl/` 的静态阅读评审，未运行编译、仿真或 lint。结论分为“代码直接可见的问题”和“需要后续仿真确认的风险”。本次不修改 RTL。

## 1. 总体评价

当前 RTL 已经具备一个 2-way 超标量乱序核的完整骨架：前端取指/预测、Decode 拆包、Rename + checkpoint、ROB/IQ/Payload/StoreBuffer、五类执行单元、WriteBack、Commit、RecoveryManager 都有基本实现。

主要不足不在“模块数量不够”，而在以下几类：

1. 仿真/上板 memory 时序契约还不够硬，`myCPU`、`rtl/ip`、`rtl/soc` 三层存在错拍风险。
2. 若干异常/非法指令/CSR 路径不完整，会影响 rv32mi 和后续严格正确性测试。
3. M 扩展当前直接用 RTL 运算符和自写除法流水，没有明确 FPGA IP/资源/Fmax 策略。
4. 恢复、ReadyTable、StoreBuffer forwarding 等乱序关键路径有简化实现，必须用 directed tests 验证。
5. 当前接口没有标准 ready/valid transaction 记录，debug 时需要额外波形和断言辅助。

## 2. 阻塞仿真一致性的优先问题

### 2.1 `myCPU` 固定 `dromAccess.accessReady=1`，但 SoC DRAM 实际有返回延迟

证据：

- `rtl/core/myCPU.sv:43-50`：`dromAccess.readData = perip_rdata; dromAccess.accessReady = 1'b1`
- `rtl/soc/perip_bridge.sv:68-83`：DRAM/MMIO/counter read select 有寄存选择
- `rtl/soc/perip_bridge.sv:162-171`：`dram_read_sel_d2` 后才选择 `dram_rdata`
- `rtl/soc/dram_driver.sv:53-62`：offset 打两拍后对 `dram_rdata_raw` 右移
- `rtl/core/ExecuteStage/ExecuteMemStage.sv:87-99`、`128-134`：core 用 `loadMetaPipe0/1` 对齐 load 返回

影响：

`myCPU` 对 core 声称访问立即 ready，但 `perip_rdata` 对 DRAM load 不是立即有效。若 Verilator TB 给 `myCPU` 做零延迟内存，会掩盖真实上板错拍；若 TB 复刻 SoC 延迟，又要确认 `ExecuteMemStage` 的 metadata 与返回延迟严格一致。

建议：

1. 后续先写 `docs/design/memory_contract` 的时序表：load request T0、readData T?。
2. `myCPU` 主仿真 memory model 必须显式模拟 IROM/DRAM 延迟。
3. 给 `ExecuteMemStage` 加 directed test：连续 load、load 后 ALU、load 与 store forwarding 交错。

优先级：P0。

### 2.2 `student_top` 例化 `rtl/ip/IROM_0/DRAM_0` 时没有传初始化文件

证据：

- `rtl/soc/student_top.sv:104-113`：`IROM_0 Mem_IROM` 无 `INIT_FILE` 参数
- `rtl/soc/dram_driver.sv:44-51`：`DRAM_0 Mem_DRAM` 无 `INIT_FILE` 参数
- `rtl/ip/IROM_0.sv:10-14`、`30-33`：仿真模型只有 `INIT_FILE` 非空才 `$readmemh`
- `rtl/ip/DRAM_0.sv:11-15`、`32-35`：同样依赖 `INIT_FILE`

影响：

`student_top` 作为 Verilator SoC smoke DUT 时，IROM/DRAM 默认未初始化。除非 testbench 通过层级访问强制写 memory，或者后续改 IP wrapper/parameter，否则 `student_top` 仿真无法直接加载程序。

建议：

1. 主线仍用 `myCPU` 做 L1 DUT，避免先被这个问题挡住。
2. 后续若做 `student_top` smoke，需要在不影响 Vivado IP 的前提下，为仿真模型提供 plusarg/parameter/ifdef 初始化路径。

优先级：P0 for `student_top` 仿真，P2 for `myCPU` 主仿真。

### 2.3 IROM 行为模型与 FetchStage 绑定关系敏感

证据：

- `rtl/core/FetchStage/FetchStage.sv:15-23`：保存上一拍 PF payload
- `rtl/core/FetchStage/FetchStage.sv:26-31`：组合绑定当前 `iromAccess.inst[i]`
- `rtl/ip/IROM_0.sv:36-49`：地址打一拍 `addra_q/addrb_q` 后读 memory

影响：

FetchStage 没有显式 instruction valid/ready，只假设 IROM 返回和 `pipeReg` 中的 PC/预测信息同拍对齐。仿真模型若实现成异步 ROM、零延迟 ROM 或多一拍 ROM，都会直接改变取指结果绑定。

建议：

1. `myCPU` TB 的 IROM 模型必须明确“地址打一拍、数据组合读注册地址”还是“同步读两拍”。
2. 用 `rv32ui-p-simple` 前先做一个取指 trace：PC 和 inst dump 前 20 条必须逐条对齐。

优先级：P0。

## 3. 正确性风险

### 3.1 非法/不支持指令没有形成异常，可能像普通 uop 一样流过

证据：

- `rtl/core/DecodeStage/DecodeTypes.sv:47-58`：`SetInvalidDecode` 将 `instInfo.valid=FALSE`，但默认 tube 是 ALU、op none
- `rtl/core/DecodeStage/DecodeStage.sv:91-93`：`decodedStage[i].valid` 只来自流水 valid，不依赖 `instInfo.valid`
- `rtl/core/RenameStage/RenameStage.sv:165-167`：`nextStage[i].valid = pipeReg[i].valid && canRename`
- `rtl/core/DispatchStage/DispatchStage.sv:94-111`：ROB entry 仍可被创建

影响：

非法指令、未支持指令、部分 CSR 无效编码可能不会触发 illegal instruction exception，而是作为默认 ALU/NOP 类 uop 执行并提交。这会影响 rv32mi 异常类测试，也会让 bug 难定位。

建议：

1. 明确策略：不支持指令是 trap，还是仿真子集内直接禁止。
2. 若要严格 rv32，Decode 应输出 exception cause 或 SYS trap uop，而不是仅置 `instInfo.valid=0`。
3. directed test：非法 opcode、非法 funct3、非法 CSR。

优先级：P0/P1，取决于 rv32mi 覆盖范围。

### 3.2 EBREAK/MISC-MEM/FENCE 类路径不完整

证据：

- `rtl/core/DecodeStage/DecodeTypes.sv:364-379`：`OP_MISC_MEM` 被标成 SYS + `SYS_SUBTYPE_EBREAK`
- `rtl/core/DecodeStage/DecodeTypes.sv:393-408`：`EBREAK` 也被标成 `SYS_SUBTYPE_EBREAK`
- `rtl/core/ExecuteStage/ExecuteSysStage.sv:153-154`：exception 只对 ECALL 或 MRET 拉高，不包含 EBREAK

影响：

`rv32mi-p-sbreak` 这类测试很可能失败。FENCE/FENCE.I 被 serial 化但没有真正内存序/取指序语义；在无 cache 设计中可以简化，但必须有明确定义。

建议：

1. 明确 `EBREAK` 是否作为 trap。
2. `FENCE/FENCE.I` 在当前无 cache 场景可作为 serial NOP，但文档和测试预期要一致。

优先级：P1。

### 3.3 CSR 覆盖不足，Zicntr/机器态测试可能失败

证据：

- `rtl/core/ExecuteStage/ExecuteSysStage.sv:11-15`：只显式定义 `mstatus/mtvec/mepc/mcause`
- `rtl/core/ExecuteStage/ExecuteSysStage.sv:34-41`：其他 CSR 读默认返回 0
- `rtl/core/DecodeStage/DecodeTypes.sv:409-435`：多数 CSR 指令编码会被接收

影响：

`rv32mi-p-zicntr`、部分 CSR 测试、需要 `mcycle/minstret` 的程序可能失败。更危险的是 CSR 指令“看似支持”，但返回值不符合 spec。

建议：

1. 列出支持 CSR 白名单。
2. 对不支持 CSR 选择 illegal trap 或明确返回 0 的非标准行为。
3. 若 src 性能要读 cycle，应设计 MMIO counter 或内部 perf 暴露方式，不要混用未实现 CSR。

优先级：P1。

### 3.4 ReadyTable 恢复时直接全 ready，可能掩盖恢复后依赖关系

证据：

- `rtl/core/core.sv:50-51`：backend flush 时 `recoverReadyAll`
- `rtl/core/RenameStage/ReadyTable.sv:25-27`：恢复时 `readyMask <= '1`

影响：

恢复后所有物理寄存器都被认为 ready。若恢复点的 SpecRAT 指向某个尚未真正写回的物理寄存器，后续消费者可能过早发射。这个设计依赖 checkpoint/ROB flush 语义保证恢复后的映射只指向已完成或架构安全的值，但当前没有断言验证。

建议：

1. 用 branch miss 后立刻消费旧寄存器的 directed test 验证。
2. 更稳妥方案是 ReadyTable 也做 checkpoint，或恢复到 ArchRAT 对应 ready 集合。

优先级：P1。

### 3.5 StoreBuffer forwarding 对同字节多 store 的年龄选择需要验证

证据：

- `rtl/core/DispatchStage/StoreBuffer.sv:49-60`：从 head 到 count 遍历，匹配字节直接写 `StoreBufferMatchOut.data`
- `rtl/core/DispatchStage/StoreBuffer.sv:61-72`：只根据最终 matchedMask 判定 hit/block

影响：

如果同一 word/byte 有多个未提交 store，load 应看到比自己老的最近 store。当前遍历顺序从 head 到 tail，后面的更年轻 entry 会覆盖前面的数据，这对“load 之后更年轻 store 不应被看到”的场景是否安全，取决于 StoreBuffer 中是否可能存在比该 load 年轻但已执行的 store。乱序执行下这是可能的，需要验证或增加年龄边界。

建议：

1. StoreBufferMatchIn 最好带 load 的 ROB/order 信息，只匹配比 load 老的 store。
2. directed test：`store older -> load -> store younger`，让 younger store 先执行，检查 load 不被污染。

优先级：P0/P1，内存正确性关键。

### 3.6 StoreBuffer 分配和 store 执行没有显式校验 index 生命周期

证据：

- `rtl/core/DispatchStage/DispatchStage.sv:83-85`：每包最多一个 store 时依赖 `storeBuffer.allocRdy`
- `rtl/core/DispatchStage/DispatchStage.sv:139-145`：storeBufferIndex 写入 payload
- `rtl/core/ExecuteStage/ExecuteMemStage.sv:153-161`：执行 store 时按 payload index 写 StoreBuffer

影响：

如果 Decode 拆包或 Dispatch 资源判断出错，多个 store 可能共用同一个 `allocIndex`。当前 Decode 有 `multiStore` 拆包，但这个约束散落在 ID/DS 两处，没有断言保护。

建议：

1. 后续加断言：同周期 dispatch storeCount <= 1。
2. 若未来扩展真正 2 store/周期，StoreBuffer alloc 接口必须变成多端口。

优先级：P2，目前是维护风险。

## 4. 性能和资源风险

### 4.1 乘法没有明确 IP/DSP 策略，当前组合乘法资源重

证据：

- `rtl/core/ExecuteStage/ExecuteMulStage.sv:57-68`：同一函数中同时计算 signed、unsigned、mixed 三个 64-bit product
- `rtl/core/ExecuteStage/ExecuteMulStage.sv:153-161`：每个 lane launch 时直接使用组合乘法结果
- `rtl/core/BasicTypes.sv:41`：`WAY_NUM=2`，因此该逻辑按双 lane 复制

影响：

Vivado 可能推 DSP，也可能产生较重组合路径；三种 product 同时算会增加资源和时序压力。src 性能目标下，CPU 频率/Fmax 和 M 扩展吞吐都会受影响。

建议：

1. 先确定策略：纯 RTL 推断 DSP、显式 Xilinx multiplier IP、还是共享单个乘法器。
2. 若目标是 FPGA 性能，建议把 MUL 单元边界做成可替换模块，保留行为模型和 FPGA IP 两套实现。
3. Verilator 行为模型可以保持简单，但上板实现应固定资源和延迟契约。

优先级：P1。

### 4.2 除法为 36 拍、双 lane 全流水，资源可能偏大

证据：

- `rtl/core/ExecuteStage/ExecuteMulStage.sv:11-12`：`DIV_LATENCY=36`
- `rtl/core/ExecuteStage/ExecuteMulStage.sv:43-44`：每个 lane 都有 `divPipe[DIV_LATENCY]`
- `rtl/core/ExecuteStage/ExecuteMulStage.sv:233-235`：每拍推进 36 级 div pipeline

影响：

这相当于双 lane、36 级除法流水，面积较大。若 src 程序除法不密集，资源/时序可能不划算；若密集，吞吐可能好但 Fmax 风险高。

建议：

1. 统计 src 是否大量使用 DIV/REM。
2. 若不密集，考虑单发射/迭代除法器，牺牲吞吐换资源和频率。
3. 保持 `delay_for()` 与实际延迟一致，否则 IssueQueue 依赖会错。

优先级：P2/P1，取决于 src。

### 4.3 Load pipeline 每周期最多接受一个 load，且 load 返回会阻塞当前 MEM uop

证据：

- `rtl/core/ExecuteStage/ExecuteMemStage.sv:114`、`167-198`：`currentLoadSelected` 限制每周期一个 load
- `rtl/core/ExecuteStage/ExecuteMemStage.sv:125`、`204`：`loadReturnBlocked` 阻塞 EX
- `rtl/core/DispatchStage/IssueQueue.sv:61`、`71-72`：IssueQueue 每周期最多选择一个 MEM uop

影响：

这是正确性友好但性能偏保守的设计。src 若 load 密集，IPC 会明显受限；但在当前阶段可以接受，先保证正确性。

建议：

1. 性能优化前不要改。
2. 先用 perf 统计 load/use、MEM stall、StoreBuffer block。

优先级：P2。

### 4.4 IssueQueue 不复用同周期 pop 出来的空槽，资源判断偏保守

证据：

- `rtl/core/DispatchStage/IssueQueue.sv:30-51`：push 分配只看当前 `valid`，不考虑同周期 pop
- `rtl/core/DispatchStage/ROB.sv` 也有类似保守 free count 行为，`RobPushRes` 不利用同周期 pop

影响：

接近满队列时会产生额外 stall，影响性能但不影响正确性。

建议：

先不优化。等正确性稳定后再统计 IQ/ROB full stall 占比。

优先级：P3。

## 5. 控制、恢复与时序可维护性问题

### 5.1 reset 风格不一致

证据：

- `rtl/core/FetchStage/FetchStage.sv:15-23`：同步 reset 写在 `always_ff @(posedge self.clk)`
- `rtl/core/DecodeStage/DecodeStage.sv:33-72`：同步 reset
- 多数后端模块使用 `always_ff @(posedge clk or posedge rst)`
- `rtl/core/ReadRegStage/RegFile.sv:19`：负沿写 + 异步 reset
- SoC UART/twin_controller 使用低有效 reset，core 多数使用高有效 reset

影响：

仿真一般可跑，但上板复位释放、CDC、时序约束和 debug 会复杂。尤其 `top.sv` 中 PLL `locked` 被反相后给 `student_top`，而 UART/twin_controller 用 `rst_n`，复位极性混杂。

建议：

1. 文档明确每层 reset 极性和同步/异步策略。
2. 后续不要随意混用 reset 风格。
3. 若需要上板稳定，建议 CPU 域 reset 做同步释放。

优先级：P1/P2。

### 5.2 PRF 负沿写是隐含关键时序假设

证据：

- `rtl/core/ReadRegStage/RegFile.sv:9-17`：组合读
- `rtl/core/ReadRegStage/RegFile.sv:19-31`：负沿写
- `rtl/core/WriteBackStage/WriteBackStage.sv:106-112`：WB 写 PRF、ReadyTable、IssueWakeup 同时发生

影响：

负沿写能缓解同周期 WB/RR 读写冲突，但 FPGA 上对时序、综合 RAM/寄存器推断不友好。PRF 大概率会被综合成寄存器堆而非 BRAM；双沿时序会让约束和 Fmax 变难。

建议：

1. 先保持用于正确性 bringup。
2. 后续若追性能/Fmax，应改成明确的同步写 + bypass/read-during-write 策略。

优先级：P2。

### 5.3 恢复事件打一拍，flush 与 redirect 的波形时序需要明确

证据：

- `rtl/core/CommitStage/RecoveryManager.sv:24-62`：recovery 请求进入 `recoveryReg`
- `rtl/core/CommitStage/RecoveryManager.sv:65-89`：下一拍输出 `recoveryInfo/pcUpdate/checkpoint recover`
- `rtl/core/Ctrl.sv:37-57`：`recoveryInfo.valid` 时 flush 覆盖 stall

影响：

这是可接受的设计，但后续 debug branch miss 时，commit 发现 miss 和前端 redirect 不是同一拍。如果 testbench 或波形检查按同拍预期写，会误判。

建议：

1. 在仿真 trace 中输出 commitRecoveryReq、recoveryInfo、pcUpdate 三个阶段。
2. 文档中固定恢复时序。

优先级：P2。

### 5.4 `writeBackRecoveryReq` 接口存在但当前未实际使用

证据：

- `rtl/core/WriteBackStage/WriteBackStage.sv:45`：`recovery.writeBackRecoveryReq = '0`
- `rtl/core/CommitStage/RecoveryManager.sv:41-46`、`50-55`：RecoveryManager 支持 WB recovery 仲裁

影响：

接口预留是好事，但当前恢复全部依赖 Commit。若后续想做 branch early recovery，需要重新定义精确状态边界、checkpoint free、ROB/StoreBuffer flush 语义。

建议：

短期保持不用。不要在 WB 临时拉 recovery，除非同时设计精确恢复协议。

优先级：P3。

## 6. SoC/FPGA 集成问题

### 6.1 `rtl/ip` 是行为模型，不应混入 FPGA sources

证据：

- `rtl/ip/IROM_0.sv`、`rtl/ip/DRAM_0.sv`、`rtl/ip/pll.sv` 都是行为/软模型
- Vivado Tcl 应创建真实 `pll/IROM_0/DRAM_0` IP

影响：

如果 Verilator filelist 和 Vivado sources 没分清，会出现同名模块重复定义或行为模型替代真实 IP 的问题。

建议：

1. 保持 `scripts/filelists/ip_verilator.f` 只用于仿真。
2. FPGA Tcl 不加入 `rtl/ip`。

优先级：P1。

### 6.2 `CORE_NEW` 分支引用未定义模块

证据：

- `rtl/soc/student_top.sv:80-84`：`ifdef CORE_NEW` 时例化 `myCPU_core_new`

影响：

如果构建环境误定义 `CORE_NEW`，会直接缺模块。这个宏路径目前不是主线，应清理或文档标注。

建议：

短期：不要定义 `CORE_NEW`。中期：删除或补齐该路径。

优先级：P2。

### 6.3 SoC perip 总线没有显式 read enable

证据：

- `rtl/core/myCPU.sv:43-47`：只有 `perip_wen`，读靠 `readEn || writeEn` 时输出地址
- `rtl/soc/perip_bridge.sv:65-66`：`dram_read_sel = ~perip_wen & dram_sel`

影响：

当 core 无访问时，`myCPU` 将 `perip_addr` 置 0，桥用地址和 `perip_wen` 推断读。当前因为地址 0 不在 DRAM/MMIO 范围，通常安全；但协议表达不清晰，后续外设扩展或 debug trace 不方便。

建议：

不改 `myCPU` 端口的前提下，testbench/文档要把“读访问有效条件”定义成 `perip_addr` 落入有效地址范围且 `perip_wen=0`。

优先级：P2。

## 7. 可维护性问题

### 7.1 文件命名和模块命名存在小不一致

例子：

- `rtl/core/DispatchStage/DIspatchStageIF.sv` 文件名大小写拼写异常，但 interface 名是 `DispatchStageIF`
- `RegReadStage` 模块位于 `ReadRegStage.sv`

影响：

Linux 区分大小写，脚本/filelist 容易出错；新人阅读会被命名干扰。

建议：

短期保持 filelist 明确列出。中期在一次单独重命名提交里统一命名。

优先级：P3。

### 7.2 控制信号缺少断言保护

当前最应该加断言的点：

1. Decode 输出同包 store 数不超过 1。
2. Rename 同周期 checkpoint 数不超过 1。
3. Dispatch 成功时 ROB/IQ/Payload/StoreBuffer index 一致。
4. StoreBuffer load match 不能看到比 load 年轻的 store。
5. Recovery 时 ROB/StoreBuffer flush 与 RAT/FreeList recover 同步。
6. WriteBack 同物理寄存器多端口写冲突行为。

影响：

现在 debug core bug 时只能靠波形人工看，定位效率低。

建议：

后续在 Verilator bringup 后加入 `ifdef ASSERT` 的轻量 SVA 或 immediate assertions。

优先级：P1。

## 8. 建议处理顺序

### 第一阶段：先保证仿真闭环可信

1. 固定 `myCPU` TB 的 IROM/DRAM 时序模型。
2. 取指 trace 对齐 dump。
3. 明确 `tohost` 地址和 store 监控。
4. 不先碰性能优化。

### 第二阶段：修正确性阻塞

1. 非法/不支持指令处理。
2. EBREAK/ECALL/MRET/CSR 子集定义。
3. StoreBuffer forwarding 年龄问题。
4. ReadyTable recovery 策略验证。

### 第三阶段：再考虑性能和 FPGA 资源

1. MUL/DIV 实现策略：推断 DSP、Xilinx IP、共享/流水方案。
2. PRF 写读时序和 bypass 策略。
3. MEM 单发射和 load-return blocking 的性能影响。
4. ROB/IQ 同周期 pop/push 资源复用。

## 9. 本次未做

1. 未运行 Verilator/lint/synthesis。
2. 未修改 RTL。
3. 未判断每条风险是否已经在某个测试中实际失败。

