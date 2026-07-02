//------------------------------------------------------------------------------
// RenameTypes.sv
// 作用：定义 rename 相关的 RAT 读写、checkpoint create/recover/free 和 FreeList
// 分配/释放协议。
// 微架构定位：SpecRAT/FreeList 服务投机重命名，ArchRAT 服务提交态映射。
// 分支 checkpoint 在 rename 创建，分支正确提交时释放，错误预测或异常恢复时
// 由 RecoveryManager 触发恢复。全局 checkpoint 索引定义在 BasicTypes。
//------------------------------------------------------------------------------

import BasicTypes::*;

package RenameTypes;


    localparam SPECRAT_READ_PORT_NUM =  WAY_NUM * 3;  
    localparam SPECRAT_WRITE_PORT_NUM = WAY_NUM;

    localparam SPECRAT_ENTRY_NUM = LOGICREG_NUM;

    localparam ARCHRAT_WRITE_PORT_NUM = WAY_NUM;

    // update RAT
    typedef struct packed {
        logic            UpdateEn;
        PhyRegNumPath    UpdatePhyRegNum;
        LgcRegNumPath    UpdateLgcRegNum;
    } RATUpdatePath;

    // READ

    typedef struct packed {
        logic          ReadEn;
        LgcRegNumPath  ReadLgcRegNum;
    } RATReadPath;

    


    typedef struct packed {
        logic          ChkptIndexValid;
        ChkptIndexPath ChkptCreateIndex;
    }ChkptCreatePath; 
    typedef struct packed {
        logic          ChkptRecoverEn;
        ChkptIndexPath ChkptRecoverIndex;
        logic          RecoverFreeEn;
        PhyRegNumPath  RecoverFreePhyRegNum;
    }ChkptRecoveryPath;
    typedef struct packed {
        logic          ChkptFreeEn;
        ChkptIndexPath ChkptFreeIndex;
    }ChkptFreePath;

    // FreeList

    localparam FREE_LIST_WIDTH = $clog2(PHYREG_NUM);
    typedef logic [FREE_LIST_WIDTH-1:0] FreeListCountPath;


    typedef struct packed {
        logic          allocValid;
        PhyRegNumPath  allocPhyRegNum;
    } FreeListAllocPath;

    typedef struct packed {
        logic         freeReq;
        PhyRegNumPath freePhyRegNum;
    } FreeListFreePath;





    

endpackage : RenameTypes
