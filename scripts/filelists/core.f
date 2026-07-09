# Core RTL filelist. Paths are relative to the repository root.
# Keep packages/types/interfaces before modules that import or bind them.

rtl/core/BasicTypes.sv

rtl/core/IromAccessIF.sv
rtl/core/DramAccessIF.sv
rtl/core/DebugIF.sv
rtl/core/PerfIF.sv
rtl/core/InOrderTypes.sv
rtl/core/InOrderFetchStage.sv
rtl/core/InOrderDecodeStage.sv
rtl/core/InOrderIssueQueue.sv
rtl/core/InOrderExecuteStage.sv
rtl/core/InOrderMulDivUnit.sv
rtl/core/core.sv
rtl/core/myCPU.sv
