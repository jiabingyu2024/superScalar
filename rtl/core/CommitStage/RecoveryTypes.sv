//------------------------------------------------------------------------------
// RecoveryTypes.sv
// 作用：定义全局恢复请求的原因和恢复 payload。
// 微架构定位：branch miss、精确异常、replay、serial/system recovery 都统一抽象
// 成 RecoveryReqPath。RecoveryManager 负责仲裁请求并驱动前端重定向、后端 flush
// 和 rename checkpoint 恢复；各模块不应私自拉全局 flush。
//------------------------------------------------------------------------------

import BasicTypes::*;

package RecoveryTypes;

    typedef enum logic [2:0] {
        REC_NONE,
        REC_BRANCH_MISS,
        REC_EXCEPTION,
        REC_REPLAY,
        REC_SERIAL
    } RecoveryCausePath;

    typedef struct packed {
        logic             valid;
        RecoveryCausePath cause;
        PcPath            recoverPc;
        ChkptIndexPath    specRATChkptIndex;
        ChkptIndexPath    freeListChkptIndex;
        logic             chkptRecoverEn;
        logic             recoverFreeEn;
        PhyRegNumPath     recoverFreePhyRegNum;
        logic             frontendFlush;
        logic             backendFlush;
    } RecoveryReqPath;

endpackage : RecoveryTypes
