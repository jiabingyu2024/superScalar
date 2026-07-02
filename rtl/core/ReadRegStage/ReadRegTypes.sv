//------------------------------------------------------------------------------
// ReadRegTypes.sv
// 作用：定义物理寄存器堆读写协议，以及 WB-only bypass 的查询/返回协议。
// 微架构定位：ReadRegStage 先从 PRF 读出操作数并写入 RR/EX 流水寄存器；
// ExecuteStage 在真正执行前，用源物理寄存器号查询 Bypass 网络，从 WriteBack
// 前递结果中选择最新操作数。旁路源只来自 WB，不从 EX stage 直接前递。
//------------------------------------------------------------------------------

import BasicTypes::*;
import PipelineTypes::*;

package ReadRegTypes;

    localparam  REG_DEPTH = PHYREG_NUM;
    localparam int REGFILE_READ_PORT_NUM = WAY_NUM * 2;
    localparam int REGFILE_WRITE_PORT_NUM = WAY_NUM * 5;
    localparam int BYPASS_READ_PORT_NUM = WAY_NUM * 2;
    localparam int BYPASS_WB_PORT_NUM   = WAY_NUM * 5;
    
    typedef struct packed {
        PhyRegNumPath  regIndex;
        logic          enaRead;   
    } RegFileReadReqPath;

    typedef struct packed {
        DataPath       data;  
    } RegFileReadResPath;

    typedef struct packed {
        logic          enaWrite;
        PhyRegNumPath  regIndex;
        DataPath       data;
    }RegFileWriteReqPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath phyRegNum;
    } BypassReadReqPath;

    typedef struct packed {
        logic    hit;
        DataPath data;
    } BypassReadResPath;

    typedef struct packed {
        logic         valid;
        logic         writeRd;
        PhyRegNumPath rd;
        DataPath      data;
        RobIndexPath  robIndex;
    } BypassWritePath;




endpackage
