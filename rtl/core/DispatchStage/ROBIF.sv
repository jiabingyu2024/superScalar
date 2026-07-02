//------------------------------------------------------------------------------
// ROBIF.sv
// 作用：定义 ROB 与 Dispatch、WriteBack、Commit 的资源协议。
// 微架构定位：Dispatch 按程序序 push 新 entry 并得到 robIndex；WriteBack 多端口
// 回填 done/异常/分支真实结果；Commit 只能从 head 读取并按序 pop。ROB 是乱序
// 执行结果转成精确架构状态的边界，不直接修改 RAT/FreeList。
//------------------------------------------------------------------------------


import BasicTypes::*;
import PipelineTypes::*;
import ROBTypes::*;
import RenameTypes::*;


interface ROBIF( input logic clk, rst );
    


    RobPushReqPath     RobPushReq [WAY_NUM];
    RobPushResPath     RobPushRes[WAY_NUM];  

    RobPopReqPath       RobPopReq  [WAY_NUM];
    RobPopResPath       RobPopRes [WAY_NUM];  

    RobFreeCountPath    RobFreeCount;
    logic               RobFlush;

    localparam int ROB_DONE_PORT_NUM = WAY_NUM * 5;

    RobDoneReqPath      RobDoneReq [ROB_DONE_PORT_NUM];

    

    modport ROB(
        input
            clk,
            rst,
            RobFlush,
            RobPushReq,
            RobPopReq,
            RobDoneReq,
        output
            RobPushRes,
            RobPopRes,
            RobFreeCount      
    );

    modport CommitStage(
        input
            RobPopRes,
        output
            RobPopReq,
            RobFlush
            
    );

    modport DispatchStage(
        
        input
            RobPushRes,
            RobFreeCount,
        output
            RobPushReq
    );

    modport WriteBackStage(
        output
            RobDoneReq
    );


    // ROB接口
    

endinterface
