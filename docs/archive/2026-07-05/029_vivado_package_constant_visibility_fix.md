# Vivado package 常量可见性修正记录

## 背景

Vivado 综合报错：

```text
[Synth 8-36] 'WAY_NUM' is not declared
```

发生在 `rtl/core/RenameStage/RenameTypes.sv` 的 package 作用域内。根因不是 `WAY_NUM` 本身缺失，而是若干 `package` 文件直接依赖外层 `import BasicTypes::*;` 的可见性，Vivado 综合在该边界上不稳定。

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

## 修正原则

1. package 内不再裸用 `WAY_NUM`、`PHYREG_NUM`、`ROB_DEPTH_WIDTH` 等共享常量。
2. 包常量统一写成 `BasicTypes::...`。
3. 接口/模块内与 `WAY_NUM` 相关的数组尺寸，也尽量改成显式 `BasicTypes::WAY_NUM`，减少工具对导入顺序的敏感性。
4. `scripts/filelists/core.f` 和 `fpga/create_vivado_project.tcl` 的 type/package 编译顺序同步调整为更接近依赖拓扑的顺序。

## 风险判断

这类错误通常不会影响功能逻辑，但会导致：

1. Vivado 综合阶段直接报错。
2. 仿真能过、综合不过，形成“仿真与上板路径分裂”。
3. 之后新增 package 时如果继续裸引用共享常量，问题会复发。

## 处理结论

这是当前 RTL 的综合可移植性问题，不是架构性 bug。后续新增 package 或接口常量时，应默认使用显式命名空间引用，避免再次依赖工具对 `import` 传播边界的宽松处理。
