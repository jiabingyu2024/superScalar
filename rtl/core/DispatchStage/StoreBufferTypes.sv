//------------------------------------------------------------------------------
// StoreBufferTypes.sv
// 作用：定义 StoreBuffer 的分配、写入、提交弹出和 load 匹配查询协议。
// 微架构定位：StoreBuffer 承担 store 的投机暂存和按 commit 顺序对外可见。
// Dispatch 分配 entry，ExecuteMem 写入地址/数据并供 load forwarding 查询，
// Commit 按 ROB 顺序授权 head store 对外写出，保证 store 不会在异常或错误路径上
// 提前生效；StoreBuffer 自己负责驱动 DRAM 并在写请求被接受后释放 entry。
//------------------------------------------------------------------------------

import BasicTypes::*;

package StoreBufferTypes;

    localparam STORE_BUFFER_DEPTH = 8;
    localparam STORE_BUFFER_WIDTH = $clog2(STORE_BUFFER_DEPTH);
    typedef logic [STORE_BUFFER_WIDTH-1:0] StoreBufferIndexPath;
    typedef StoreBufferIndexPath StoreBufferIndex;

    typedef struct packed {
        logic                valid;
        StoreBufferIndexPath index;
        AddrPath             addr;
        DataPath             data;
        logic [3:0]          wstrb;
    } StoreBufferPushReqPath;

    typedef struct packed {
        logic                valid;
        StoreBufferIndexPath index;
    } StoreBufferCommitReqPath;

    typedef struct packed {
        logic    valid;
        AddrPath addr;
        logic [3:0] rstrb;
    } StoreBufferMatchInPath;

    typedef struct packed {
        logic    hit;
        logic    block;
        DataPath data;
    } StoreBufferMatchOutPath;

    typedef struct packed {
        logic                valid;
        StoreBufferIndexPath index;
        AddrPath             addr;
        DataPath             data;
        logic [3:0]          wstrb;
    } StoreBufferCommitPath;

endpackage : StoreBufferTypes
