//------------------------------------------------------------------------------
// PipelineTypes.sv
// 作用：定义各流水级之间传递的 payload。
// 微架构定位：这里描述“某一级寄存器后一拍送到下一级”的信息边界，例如
// PF->IF、IF->ID、ID->RN、RN->DS、IS->RR、RR->EX、EX->WB。它不拥有 ROB、
// IssueQueue、StoreBuffer、Recovery 等存储/仲裁协议。当前保留对这些独立
// Types package 的 export，是为了兼容已有 IF 文件，后续可逐步改成直接 import。
//------------------------------------------------------------------------------

import BasicTypes::*;
import ROBTypes::*;
import StoreBufferTypes::*;
import RecoveryTypes::*;

package PipelineTypes;

    import BasicTypes::*;
    import ROBTypes::*;
    import StoreBufferTypes::*;
    import RecoveryTypes::*;

    export ROBTypes::*;
    export StoreBufferTypes::*;
    export RecoveryTypes::*;

    // ctrl
    typedef struct packed {
        logic stall;
        logic flush;
    } PipeCtrlPath;

    // PF to IF
    typedef struct packed {
        PcPath pcPred; // 来自分支预测器的预测PC地址
        logic  isPred;
    } PredInfoPath;

    typedef struct packed {
        PcPath       pc;
        PredInfoPath predInfo;
        logic        valid;
    } PfToIfPath;

    // IF to ID
    typedef struct packed {
        PcPath       pc;
        InstPath     inst;
        logic        valid;
        PredInfoPath predInfo;
    } IfToIdPath;

    // ID to RN
    typedef struct packed {
        logic           valid;
        logic           isSerial;
        logic           writeReg;

        TubeTypePath    tubeType;
        SubTypePath     SubType;

        OperandTypePath opTypeA;
        OperandTypePath opTypeB;
    } InstInfoPath;

    typedef struct packed {
        logic         lgcRegNumSrcAValid;
        logic         lgcRegNumSrcBValid;
        logic         lgcRegNumDstValid;
        LgcRegNumPath lgcRegNumSrcA;
        LgcRegNumPath lgcRegNumSrcB;
        LgcRegNumPath lgcRegNumDst;
    } LgcRegInfoPath;

    typedef struct packed {
        logic         PhyRegNumSrcAValid;
        logic         PhyRegNumSrcBValid;
        logic         PhyRegNumDstValid;
        logic         PhyRegNumSrcAReady;
        logic         PhyRegNumSrcBReady;
        PhyRegNumPath PhyRegNumSrcA;
        PhyRegNumPath PhyRegNumSrcB;
        PhyRegNumPath PhyRegNumDst;
    } PhyRegInfoPath;

    typedef struct packed {
        logic          valid;
        PcPath         pc;
        InstPath       inst;
        PredInfoPath   predInfo;

        LgcRegInfoPath lgcRegInfo;
        CsrAddrPath    csrAddr;
        InstInfoPath   instInfo;
        DataPath       imm;
    } IdToRnPath;

    // RN to DS
    typedef struct packed {
        logic          valid;
        PcPath         pc;
        PredInfoPath   predInfo;

        LgcRegInfoPath lgcRegInfo;
        CsrAddrPath    csrAddr;
        InstInfoPath   instInfo;
        DataPath       imm;
        PhyRegInfoPath phyRegInfo;
        PhyRegNumPath  phyPrevDst;

        logic           chkptValid;
        ChkptIndexPath  specRATChkptIndex;
        ChkptIndexPath  freeListChkptIndex;

        logic                storeBufferIndexValid;
        StoreBufferIndexPath storeBufferIndex;
    } RnToDsPath;

    // DS to IS
    typedef struct packed {
        logic valid;
    } DsToIsPath;

    // IS to RR. Keep this as a real stage payload, not a pair of IssueQueue
    // and Payload RAM entries, so PipelineTypes does not depend on IssueTypes.
    typedef struct packed {
        logic           valid;
        PcPath          pc;
        PredInfoPath    predInfo;
        CsrAddrPath     csrAddr;
        SubTypePath     SubType;
        OperandTypePath opTypeA;
        OperandTypePath opTypeB;
        DataPath        imm;

        TubeTypePath    tubeType;
        PhyRegNumPath   srcA;
        PhyRegNumPath   srcB;
        PhyRegNumPath   dst;
        logic           writeDst;
        RobIndexPath    robIndex;

        logic                storeBufferIndexValid;
        StoreBufferIndexPath storeBufferIndex;
    } IsToRrPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;

        DataPath      dataA;
        DataPath      dataB;
        PhyRegNumPath Rs1;
        PhyRegNumPath Rs2;
        logic         srcAIsRs1;
        logic         srcBIsRs2;

        PhyRegNumPath Rd;
        logic         writeRd;

        RobIndexPath  robIndex;
    } RrToExAluPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;

        DataPath      dataA;
        DataPath      dataB;
        PhyRegNumPath Rs1;
        PhyRegNumPath Rs2;
        logic         srcAIsRs1;
        logic         srcBIsRs2;

        DataPath      imm;

        PhyRegNumPath Rd;
        logic         writeRd;

        RobIndexPath  robIndex;

        logic                storeBufferIndexValid;
        StoreBufferIndexPath storeBufferIndex;
    } RrToExMemPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;

        DataPath      dataA;
        DataPath      dataB;
        PhyRegNumPath Rs1;
        PhyRegNumPath Rs2;
        logic         srcAIsRs1;
        logic         srcBIsRs2;

        PcPath        pc;
        DataPath      imm;

        PhyRegNumPath Rd;
        logic         writeRd;

        RobIndexPath  robIndex;
    } RrToExMulPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;

        DataPath      dataA;
        DataPath      dataB;
        PhyRegNumPath Rs1;
        PhyRegNumPath Rs2;
        logic         srcAIsRs1;
        logic         srcBIsRs2;

        PcPath        pc;
        DataPath      imm;

        PhyRegNumPath Rd;
        logic         writeRd;

        RobIndexPath  robIndex;
    } RrToExBrcPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;

        PcPath        pc;
        DataPath      dataA;
        PhyRegNumPath Rs1;
        logic         srcAIsRs1;

        CsrAddrPath   csrAddr;

        PhyRegNumPath Rd;
        logic         writeRd;

        RobIndexPath  robIndex;
    } RrToExSysPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath Rd;
        logic         writeRd;
        DataPath      data;
        RobIndexPath  robIndex;
    } ExAluToWbPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath Rd;
        logic         writeRd;
        DataPath      data;
        RobIndexPath  robIndex;
    } ExMemToWbPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath Rd;
        logic         writeRd;
        DataPath      data;
        RobIndexPath  robIndex;
    } ExMulToWbPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath Rd;
        logic         writeRd;
        DataPath      data;

        PcPath        trueTargetPc;
        logic         taken;

        RobIndexPath  robIndex;
    } ExBrcToWbPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath Rd;
        logic         writeRd;
        DataPath      data;

        RobIndexPath  robIndex;
        PcPath        trueTargetPc;

        logic         isSerial;
        logic         exception;
    } ExSysToWbPath;

endpackage : PipelineTypes
