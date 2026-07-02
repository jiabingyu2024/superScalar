//------------------------------------------------------------------------------
// ROBTypes.sv
// 作用：定义重排序缓冲区 ROB 的 entry 结构和 push/pop/done 协议类型。
// 微架构定位：ROB 是乱序执行到有序提交的核心边界。Dispatch 按程序序分配
// ROB entry，WriteBack/执行结果回填 done/异常/分支真实结果，Commit 只能从
// head 连续退休。这里的类型只描述 ROB 资源本身，不放级间流水 payload。
//------------------------------------------------------------------------------

import BasicTypes::*;
import StoreBufferTypes::*;

package ROBTypes;
    import BasicTypes::*;
    import StoreBufferTypes::*;

    typedef logic [ROB_DEPTH_WIDTH:0] RobFreeCountPath;

    typedef struct packed {
        logic               valid;
        logic               done;
        PcPath              pc;

        logic               DstValid;
        LgcRegNumPath       lgcRegNum;
        PhyRegNumPath       phyRegNum;
        PhyRegNumPath       phyPrevRegNum;

        logic               isBranch;
        logic               takenPred;
        logic               takenActual;
        logic               isMiss;
        PcPath              predPc;
        PcPath              truePc;
        logic               chkptValid;
        ChkptIndexPath      specRATChkptIndex;
        ChkptIndexPath      freeListChkptIndex;

        logic               isStore;
        StoreBufferIndexPath storeBufferIndex;

        logic               isSerial;
        logic               exception;
    } RobEntryPath;

    typedef struct packed {
        RobIndexPath robIndex;
        logic        position;
        logic        valid;
    } RobPushResPath;

    typedef struct packed {
        RobEntryPath entry;
        logic        req;
    } RobPushReqPath;

    typedef struct packed {
        logic req;
    } RobPopReqPath;

    typedef struct packed {
        RobEntryPath entry;
        logic        valid;
    } RobPopResPath;

    typedef struct packed {
        logic        valid;
        RobIndexPath robIndex;
        logic        isSerial;
        logic        exception;
        PcPath       trueTargetPc;
        logic        taken;
    } RobDoneReqPath;

endpackage : ROBTypes
