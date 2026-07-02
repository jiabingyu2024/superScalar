//------------------------------------------------------------------------------
// ReadyTableIF.sv
// 作用：定义物理寄存器 ready/busy 状态表接口。
// 微架构定位：ReadyTable 独立于 FreeList。Rename 查询源物理寄存器是否 ready，
// 并在分配新目的物理寄存器时置 busy；WriteBack 在结果写回后置 ready。
//------------------------------------------------------------------------------

import BasicTypes::*;
import ReadRegTypes::*;

interface ReadyTableIF(input logic clk, rst);
    localparam int READY_READ_PORT_NUM = WAY_NUM * 2;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath phyRegNum;
    } ReadyReadReqPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath phyRegNum;
    } ReadyMarkReqPath;

    ReadyReadReqPath readReq [READY_READ_PORT_NUM];
    logic            readReady [READY_READ_PORT_NUM];

    ReadyMarkReqPath markBusy [WAY_NUM];
    ReadyMarkReqPath markReady [BYPASS_WB_PORT_NUM];
    logic            recoverReadyAll;

    modport ReadyTable(
        input
            clk,
            rst,
            readReq,
            markBusy,
            markReady,
            recoverReadyAll,
        output
            readReady
    );

    modport RenameStage(
        input
            readReady,
        output
            readReq,
            markBusy
    );

    modport WriteBackStage(
        output
            markReady
    );
endinterface
