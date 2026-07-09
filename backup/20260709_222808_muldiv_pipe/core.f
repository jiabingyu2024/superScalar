# Current NOP-Core migration RTL filelist. Paths are relative to the repository root.

rtl/core/CoreConfigPkg.sv
rtl/core/CoreTypesPkg.sv
rtl/core/CoreUtilPkg.sv

rtl/core/IromAccessIF.sv
rtl/core/DramAccessIF.sv
rtl/core/DebugIF.sv
rtl/core/PerfIF.sv

rtl/core/common/MultiPushFifo.sv

rtl/core/frontend/PcGen.sv
rtl/core/frontend/IromFetch2.sv
rtl/core/frontend/FetchBuffer.sv
rtl/core/decode/Rv32Decoder.sv

rtl/core/rename/FreeList.sv
rtl/core/rename/RenameUnit.sv
rtl/core/rename/BusyTable.sv

rtl/core/dispatch/ROB.sv
rtl/core/dispatch/DispatchUnit.sv

rtl/core/issue/CompressedQueue.sv
rtl/core/issue/IntIssueQueue.sv
rtl/core/issue/MemIssueQueue.sv
rtl/core/issue/MulDivIssueQueue.sv

rtl/core/execute/PhysRegFile.sv
rtl/core/execute/ExecuteCluster.sv
rtl/core/execute/StoreBuffer.sv

rtl/core/commit/CommitUnit.sv
rtl/core/backend/CoreBackend.sv

rtl/core/core.sv
rtl/core/myCPU.sv
