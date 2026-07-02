//------------------------------------------------------------------------------
// RecoveryManagerIF.sv
// 作用：定义全核恢复管理接口。
// 微架构定位：Commit/WriteBack 等恢复请求源只发 RecoveryReqPath；RecoveryManager
// 仲裁并打一拍后统一输出 recoveryInfo、PC redirect 和分支预测器更新信息。
// PreFetch 只消费重定向 PC，Ctrl 只消费 flush/stall 所需恢复事件，Rename 只消费
// checkpoint 恢复信息，避免各模块私自生成不一致的全局恢复控制。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;
import RecoveryTypes::*;

interface RecoveryManagerIF(
    input logic clk,
    input logic rst
);
    RecoveryReqPath commitRecoveryReq;
    RecoveryReqPath writeBackRecoveryReq;
    RecoveryReqPath recoveryInfo;

    logic           commitBranchUpdateValid;
    PcPath          commitBranchPc;
    logic           commitBranchTaken;
    PcPath          commitBranchTarget;

    logic           pcUpdateEn;
    PcPath          pcUpdate;

    logic           branchUpdateValid;
    PcPath          branchPc;
    logic           branchTaken;
    PcPath          branchTarget;
    logic           branchMiss;

    modport RecoveryManager(
        input
            clk,
            rst,
            commitRecoveryReq,
            writeBackRecoveryReq,
            commitBranchUpdateValid,
            commitBranchPc,
            commitBranchTaken,
            commitBranchTarget,
        output
            recoveryInfo,
            pcUpdateEn,
            pcUpdate,
            branchUpdateValid,
            branchPc,
            branchTaken,
            branchTarget,
            branchMiss
    );

    modport CommitStage(
        input
            recoveryInfo,
        output
            commitRecoveryReq,
            commitBranchUpdateValid,
            commitBranchPc,
            commitBranchTaken,
            commitBranchTarget
    );

    modport WriteBackStage(
        input
            recoveryInfo,
        output
            writeBackRecoveryReq
    );

    modport PreFetchStage(
        input
            recoveryInfo,
            pcUpdateEn,
            pcUpdate
    );

    modport CtrlUnit(
        input
            recoveryInfo,
            pcUpdateEn
    );

    modport RenameStage(
        input
            recoveryInfo
    );

    modport BPU(
        input
            branchUpdateValid,
            branchPc,
            branchTaken,
            branchTarget,
            branchMiss
    );

endinterface
