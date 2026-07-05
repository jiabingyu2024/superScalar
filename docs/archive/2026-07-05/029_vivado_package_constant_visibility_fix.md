# Vivado package 常量可见性修正记录

## 背景

Vivado 综合报错：

```text
[Synth 8-36] 'WAY_NUM' is not declared
```

随后同类问题继续暴露：

```text
[Synth 8-36] 'InstInfoPath' is not declared
```

发生在 `rtl/core/DecodeStage/DecodeTypes.sv`。根因不是单个类型缺失，而是当前 `Types.sv` 组织存在两类综合不稳定点：

1. package 内部依赖 package 外层 `import BasicTypes::*;` 的可见性。
2. `DecodeTypes` 使用的译码输出类型原本定义在 `PipelineTypes`，形成 `DecodeTypes -> PipelineTypes` 的反向依赖。

## 修改内容

将以下文件中的共享常量引用改为显式包命名空间，并在 package 内部补 `import BasicTypes::*;`：

1. `rtl/core/RenameStage/RenameTypes.sv`
2. `rtl/core/ReadRegStage/ReadRegTypes.sv`
3. `rtl/core/DispatchStage/IssueTypes.sv`
4. `rtl/core/DispatchStage/ROBTypes.sv`
5. `rtl/core/DispatchStage/StoreBufferTypes.sv`
6. `rtl/core/RenameStage/ReadyTableIF.sv`
7. `rtl/core/RenameStage/ReadyTable.sv`
8. `rtl/core/DispatchStage/ROBIF.sv`

继续完成的类型层次重排：

1. `InstInfoPath`、`LgcRegInfoPath` 从 `PipelineTypes.sv` 移入 `DecodeTypes.sv`，因为它们是 decode 语义输出，不是通用级间寄存器所有物。
2. `PipelineTypes.sv` import/export `DecodeTypes::*`，保持旧模块通过 `import PipelineTypes::*;` 仍能看到 decode 输出类型。
3. `PredInfoPath` 从 `PipelineTypes.sv` 下沉到 `BasicTypes.sv`，因为预测元信息会被前端 payload、issue payload 同时携带，不应让 `IssueTypes` 反向依赖整套 `PipelineTypes`。
4. `ReadRegTypes.sv` 删除对 `PipelineTypes` 的不必要 import，`BypassWritePath` 所需的 `RobIndexPath` 已由 `BasicTypes` 提供。
5. `IssueTypes.sv` 删除对 `PipelineTypes` 的不必要 import，仅依赖 `BasicTypes` 和 `StoreBufferTypes`。
6. `RecoveryTypes.sv` 补 package 内 `import BasicTypes::*;`，避免 `PcPath/ChkptIndexPath/PhyRegNumPath` 只靠文件作用域 import。
7. 清理各 `Types.sv` 的 package 外层 import，只保留 package 内部 import，使依赖边界对 Vivado 更明确。

## 修正原则

1. package 内不再裸用 `WAY_NUM`、`PHYREG_NUM`、`ROB_DEPTH_WIDTH` 等共享常量。
2. 包常量统一写成 `BasicTypes::...`。
3. 接口/模块内与 `WAY_NUM` 相关的数组尺寸，也尽量改成显式 `BasicTypes::WAY_NUM`，减少工具对导入顺序的敏感性。
4. `scripts/filelists/core.f` 和 `fpga/create_vivado_project.tcl` 的 type/package 编译顺序同步调整为更接近依赖拓扑的顺序。
5. package 文件不依赖文件作用域 import；凡是 package 内用到的外部类型，都必须在 package 内 import 或显式 `Pkg::Type`。

当前推荐拓扑：

```text
BasicTypes
  -> DecodeTypes
  -> StoreBufferTypes
  -> ROBTypes
  -> RecoveryTypes
  -> PipelineTypes
  -> RenameTypes / ReadRegTypes / IssueTypes
```

其中：

1. `BasicTypes` 只放全局基础类型、索引、执行分类、预测元信息。
2. `DecodeTypes` 只放指令译码常量、译码函数和 decode 输出控制结构。
3. `PipelineTypes` 只放级间 payload，并通过 export 兼容已有模块。
4. `IssueTypes/ReadRegTypes/ROBTypes/StoreBufferTypes/RecoveryTypes` 各自拥有本资源/协议的结构体，不反向依赖 `PipelineTypes`。

## 风险判断

这类错误通常不会影响功能逻辑，但会导致：

1. Vivado 综合阶段直接报错。
2. 仿真能过、综合不过，形成“仿真与上板路径分裂”。
3. 之后新增 package 时如果继续裸引用共享常量，问题会复发。

## 处理结论

这是当前 RTL 的综合可移植性问题，不是架构性 bug。后续新增 package 或接口常量时，应默认使用显式命名空间引用，避免再次依赖工具对 `import` 传播边界的宽松处理。

已执行验证：

```bash
make verilator-build BUILD_JOBS=4 BUILD_CXX=g++ OBJCACHE=
```

结果通过。说明当前 Verilator 路径已能完整解析 `Types.sv` 并生成/编译 `myCPU` 仿真模型。若不加 `OBJCACHE=`，当前环境可能仍调用 `ccache g++` 并因缓存目录只读失败；这不是 RTL package 问题。
