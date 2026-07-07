//------------------------------------------------------------------------------
// IssueTypes.sv
// 作用：定义 IssueQueue 与 Payload 存储结构的 push/pop/entry 协议。
// 微架构定位：Dispatch 将已分配 ROB 的 uop 写入 IssueQueue，并把较大的静态
// 执行 payload 写入 Payload 存储；Issue 选择 ready entry 后结合 payload 送往
// ReadReg。这里描述调度队列/载荷存储协议，不描述通用级间寄存器。
//------------------------------------------------------------------------------

package IssueTypes;
    import BasicTypes::*;
    import StoreBufferTypes::*;

    localparam SHIFT_WIDTH = 36;
    typedef logic [SHIFT_WIDTH-1:0] ShiftType;

    localparam int INT_ISSUE_QUEUE_DEPTH = 16;
    localparam int MEM_ISSUE_QUEUE_DEPTH = 4;
    localparam int MUL_ISSUE_QUEUE_DEPTH = 4;
    localparam int ISSUE_PAYLOAD_DEPTH = INT_ISSUE_QUEUE_DEPTH +
                                         MEM_ISSUE_QUEUE_DEPTH +
                                         MUL_ISSUE_QUEUE_DEPTH;
    localparam int ISSUE_PAYLOAD_WIDTH = $clog2(ISSUE_PAYLOAD_DEPTH);
    localparam int INT_ISSUE_QUEUE_WIDTH = $clog2(INT_ISSUE_QUEUE_DEPTH);
    localparam int MEM_ISSUE_QUEUE_WIDTH = $clog2(MEM_ISSUE_QUEUE_DEPTH);
    localparam int MUL_ISSUE_QUEUE_WIDTH = $clog2(MUL_ISSUE_QUEUE_DEPTH);
    localparam int ISSUE_WAKEUP_PORT_NUM = BasicTypes::WB_PORT_NUM;

    localparam int INT_PAYLOAD_BASE = 0;
    localparam int MEM_PAYLOAD_BASE = INT_ISSUE_QUEUE_DEPTH;
    localparam int MUL_PAYLOAD_BASE = INT_ISSUE_QUEUE_DEPTH + MEM_ISSUE_QUEUE_DEPTH;

    typedef logic [ISSUE_PAYLOAD_WIDTH:0] IssueFreeCountPath;
    typedef logic [ISSUE_PAYLOAD_WIDTH-1:0] IssueIndexPath;
    typedef logic [INT_ISSUE_QUEUE_WIDTH:0] IssueIntFreeCountPath;
    typedef logic [MEM_ISSUE_QUEUE_WIDTH:0] IssueMemFreeCountPath;
    typedef logic [MUL_ISSUE_QUEUE_WIDTH:0] IssueMulFreeCountPath;

    typedef struct packed {
        logic flush;
    } IssueCtrlPath;

    typedef struct packed {
        IssueIndexPath  payloadIndex;
        TubeTypePath tubeType;


        logic           freed;
        logic           issued;

        PhyRegNumPath   srcA;
        logic           srcAMatched;
        ShiftType       srcAShift;
        logic           srcARdy;

        PhyRegNumPath   srcB;
        logic           srcBMatched;
        ShiftType       srcBShift;
        logic           srcBRdy;

        PhyRegNumPath   dst;
        logic           writeDst;

        logic           srcBIsImm;
        ShiftType       delay;
        logic [31:0]    age;

        logic           robIndexPosition;
        RobIndexPath    robIndex;

        // TubeTypePath tubeType;
        // SubTypePath  SubType;

        // OperandTypePath opTypeA;
        // OperandTypePath opTypeB;
    } IssueEntryPath;

    typedef struct packed {
        logic            valid;
        IssueEntryPath       entry;
    } IssuePushReqPath;

    typedef struct packed {
        logic                done;
        IssueIndexPath       payloadIndex;
    }IssuePushResPath;

    typedef struct packed {
        logic            valid;
    } IssuePopReqPath;

    typedef struct packed {
        logic            done;
        IssueEntryPath       entry;
    } IssuePopResPath;

    typedef struct packed {
        logic         valid;
        PhyRegNumPath phyRegNum;
    } IssueWakeupPath;

    typedef struct packed {
        PcPath pc;
        PredInfoPath predInfo;
        
        CsrAddrPath  csrAddr;

        SubTypePath  SubType;

        OperandTypePath opTypeA;
        OperandTypePath opTypeB;

        DataPath         imm;

        logic                storeBufferIndexValid;
        StoreBufferIndexPath storeBufferIndex;
    } PayloadEntryPath;

    //payload
    typedef struct packed {
        logic valid;
        IssueIndexPath payloadIndex;
        PayloadEntryPath entry;
    } PayloadPushReqPath;

    typedef struct packed {
        logic done;
    } PayloadPushResPath;

    typedef struct packed {
        logic        valid;
        IssueIndexPath payloadIndex;
    } PayloadPopReqPath;

    typedef struct packed {
        logic         valid;
        PayloadEntryPath entry;
    } PayloadPopResPath;


endpackage
