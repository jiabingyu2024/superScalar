`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module core(
    input logic clk,
    input logic rst,

    IromAccessIF.core iromAccess,
    DramAccessIF dromAccess,
    DebugIF.core debug,
    PerfIF.core perf
);
    MemState memState;
    FetchPacket ifPkt;
    Uop exUop[2];
    Uop decodeUop[2];
    Uop issueUop[2];
    WbEntry wbPkt[2];
    ExecuteResult exResult[2];

    LoadInfo loadInfo;
    StoreInfo storeInfo;

    DataPath regs[32];
    CsrState csr;

    logic decodeValid;
    logic [1:0] decodeCount;
    logic queueCanAccept;
    logic queueFlush;
    logic enqueueDecode;
    logic issueAllow;
    logic queueIssueValid;

    logic redirectNow;
    PcPath redirectPc;
    logic memReqNow;
    logic mulDivReqNow;
    logic executeBlockNow;
    logic fetchFlush;
    PcPath fetchFlushPc;
    logic fetchAdvance;
    logic fetchConsume;
    logic fetchRun;

    logic bpuTrainValid;
    PcPath bpuTrainPc;
    logic bpuTrainTaken;
    PcPath bpuTrainTarget;

    logic mulDivStart;
    MulDivInfo mulDivStartInfo;
    logic mulDivDone;
    WbEntry mulDivWb;

    assign dromAccess.exReadEn = (memState == M_LOAD_REQ);
    assign dromAccess.exReadAddr = loadInfo.addr;
    assign dromAccess.storeWriteEn = (memState == M_STORE_REQ);
    assign dromAccess.storeWriteAddr = storeInfo.addr;
    assign dromAccess.storeWriteData = storeInfo.data;
    assign dromAccess.storeWriteMask = storeInfo.mask;

    assign redirectNow = exResult[0].redirect || exResult[1].redirect;
    assign redirectPc = exResult[0].redirect ? exResult[0].redirectPc : exResult[1].redirectPc;
    assign memReqNow = exResult[0].loadReq || exResult[0].storeReq;
    assign mulDivReqNow = exResult[0].mulDivReq || exResult[1].mulDivReq;
    assign executeBlockNow = memReqNow || mulDivReqNow;
    assign fetchRun = (memState == M_NORMAL);
    assign mulDivStart = (memState == M_NORMAL) && !redirectNow && mulDivReqNow;
    assign mulDivStartInfo = exResult[0].mulDivReq ? exResult[0].mulDivInfo :
                                                        exResult[1].mulDivInfo;

    always_comb begin
        fetchFlush = 1'b0;
        fetchFlushPc = RESET_PC;
        fetchAdvance = 1'b0;
        fetchConsume = 1'b0;

        if (memState == M_NORMAL) begin
            if (redirectNow) begin
                fetchFlush = 1'b1;
                fetchFlushPc = redirectPc;
            end else if (mulDivReqNow) begin
                fetchConsume = 1'b0;
            end else if (memReqNow) begin
                fetchConsume = enqueueDecode;
            end else if (queueCanAccept) begin
                fetchAdvance = 1'b1;
            end
        end
    end

    assign queueFlush = redirectNow;
    assign enqueueDecode = decodeValid && queueCanAccept && !queueFlush &&
                           !mulDivReqNow && (memState == M_NORMAL);
    assign issueAllow = (memState == M_NORMAL) && !redirectNow && !executeBlockNow && queueIssueValid;

    always_comb begin
        bpuTrainValid = 1'b0;
        bpuTrainPc = '0;
        bpuTrainTaken = 1'b0;
        bpuTrainTarget = '0;

        for (int i = 0; i < 2; i++) begin
            if (exResult[i].condBranch) begin
                bpuTrainValid = 1'b1;
                bpuTrainPc = exUop[i].pc;
                bpuTrainTaken = (exResult[i].redirectPc != (exUop[i].pc + 32'd4));
                bpuTrainTarget = exResult[i].redirectPc;
            end
        end
    end

    InOrderFetchStage u_fetch (
        .clk            (clk),
        .rst            (rst),
        .iromAccess     (iromAccess),
        .run            (fetchRun),
        .stall          (!queueCanAccept || executeBlockNow),
        .advance        (fetchAdvance),
        .consume        (fetchConsume),
        .flush          (fetchFlush),
        .flushPc        (fetchFlushPc),
        .bpuTrainValid  (bpuTrainValid),
        .bpuTrainPc     (bpuTrainPc),
        .bpuTrainTaken  (bpuTrainTaken),
        .bpuTrainTarget (bpuTrainTarget),
        .ifPkt          (ifPkt)
    );

    InOrderDecodeStage u_decode (
        .ifPkt       (ifPkt),
        .decodeValid (decodeValid),
        .decodeCount (decodeCount),
        .decodeUop   (decodeUop)
    );

    InOrderIssueQueue u_issue_queue (
        .clk          (clk),
        .rst          (rst),
        .flush        (queueFlush),
        .enqueue      (enqueueDecode),
        .enqueueCount (decodeCount),
        .enqueueUop   (decodeUop),
        .canAccept    (queueCanAccept),
        .issueAllow   (issueAllow),
        .issueValid   (queueIssueValid),
        .issueUop     (issueUop)
    );

    InOrderExecuteStage u_execute (
        .exUop     (exUop),
        .regs      (regs),
        .wbPkt     (wbPkt),
        .csr       (csr),
        .cycle     (perf.cycle),
        .commitCnt (perf.commitCnt),
        .exResult  (exResult)
    );

    InOrderMulDivUnit u_muldiv (
        .clk   (clk),
        .rst   (rst),
        .start (mulDivStart),
        .req   (mulDivStartInfo),
        .done  (mulDivDone),
        .wb    (mulDivWb)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            memState <= M_NORMAL;
            for (int i = 0; i < 2; i++) begin
                exUop[i] <= '0;
                wbPkt[i] <= '0;
            end
            loadInfo <= '0;
            storeInfo <= '0;
            csr <= '0;
            perf.cycle <= '0;
            perf.commitCnt <= '0;
            perf.branchCnt <= '0;
            perf.branchMissCnt <= '0;
            perf.condBranchCnt <= '0;
            perf.condBranchMissCnt <= '0;
            perf.jalCnt <= '0;
            perf.jalMissCnt <= '0;
            perf.jalrCnt <= '0;
            perf.jalrMissCnt <= '0;
            for (int r = 0; r < 32; r++) regs[r] <= '0;
        end else begin
            regs[0] <= '0;
            perf.cycle <= perf.cycle + 64'd1;

            for (int i = 0; i < 2; i++) begin
                if (wbPkt[i].valid && wbPkt[i].rd != 5'd0) begin
                    regs[wbPkt[i].rd] <= wbPkt[i].data;
                end
            end

            for (int i = 0; i < 2; i++) begin
                if (exResult[i].csrUpdate.valid) begin
                    csr <= exResult[i].csrUpdate.state;
                end
            end

            perf.commitCnt <= perf.commitCnt + {63'b0, exResult[0].commit} +
                              {63'b0, exResult[1].commit};
            perf.branchCnt <= perf.branchCnt + {63'b0, exResult[0].branch} +
                              {63'b0, exResult[1].branch};
            perf.branchMissCnt <= perf.branchMissCnt + {63'b0, exResult[0].branchMiss} +
                                  {63'b0, exResult[1].branchMiss};
            perf.condBranchCnt <= perf.condBranchCnt + {63'b0, exResult[0].condBranch} +
                                  {63'b0, exResult[1].condBranch};
            perf.condBranchMissCnt <= perf.condBranchMissCnt + {63'b0, exResult[0].condBranchMiss} +
                                      {63'b0, exResult[1].condBranchMiss};
            perf.jalCnt <= perf.jalCnt + {63'b0, exResult[0].jal} +
                           {63'b0, exResult[1].jal};
            perf.jalMissCnt <= perf.jalMissCnt + {63'b0, exResult[0].jalMiss} +
                               {63'b0, exResult[1].jalMiss};
            perf.jalrCnt <= perf.jalrCnt + {63'b0, exResult[0].jalr} +
                            {63'b0, exResult[1].jalr};
            perf.jalrMissCnt <= perf.jalrMissCnt + {63'b0, exResult[0].jalrMiss} +
                                {63'b0, exResult[1].jalrMiss};

            unique case (memState)
                M_LOAD_REQ: begin
                    memState <= M_LOAD_WAIT0;
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                end
                M_LOAD_WAIT0: begin
                    memState <= M_LOAD_WAIT1;
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                end
                M_LOAD_WAIT1: begin
                    wbPkt[0].valid <= loadInfo.valid && loadInfo.rd != 5'd0;
                    wbPkt[0].rd <= loadInfo.rd;
                    wbPkt[0].data <= load_extend(loadInfo.funct3, dromAccess.exReadData);
                    wbPkt[1] <= '0;
                    perf.commitCnt <= perf.commitCnt + 64'd1;
                    loadInfo <= '0;
                    memState <= M_NORMAL;
                    for (int i = 0; i < 2; i++) exUop[i] <= '0;
                end
                M_STORE_REQ: begin
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                    perf.commitCnt <= perf.commitCnt + 64'd1;
                    storeInfo <= '0;
                    memState <= M_NORMAL;
                    for (int i = 0; i < 2; i++) exUop[i] <= '0;
                end
                M_MULDIV_WAIT: begin
                    if (mulDivDone) begin
                        wbPkt[0] <= mulDivWb;
                        wbPkt[1] <= '0;
                        perf.commitCnt <= perf.commitCnt + 64'd1;
                        memState <= M_MULDIV_WB;
                    end else begin
                        wbPkt[0] <= '0;
                        wbPkt[1] <= '0;
                    end
                    for (int i = 0; i < 2; i++) exUop[i] <= '0;
                end
                M_MULDIV_WB: begin
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                    memState <= M_NORMAL;
                    for (int i = 0; i < 2; i++) exUop[i] <= '0;
                end
                default: begin
                    if (redirectNow) begin
                        for (int i = 0; i < 2; i++) exUop[i] <= '0;
                        wbPkt[0] <= exResult[0].wb;
                        wbPkt[1] <= exResult[1].wb;
                    end else if (exResult[0].loadReq || exResult[0].storeReq) begin
                        for (int i = 0; i < 2; i++) exUop[i] <= '0;
                        wbPkt[0] <= '0;
                        wbPkt[1] <= '0;
                        if (exResult[0].loadReq) begin
                            loadInfo <= exResult[0].loadInfo;
                            memState <= M_LOAD_REQ;
                        end else begin
                            storeInfo <= exResult[0].storeInfo;
                            memState <= M_STORE_REQ;
                        end
                    end else if (mulDivReqNow) begin
                        for (int i = 0; i < 2; i++) exUop[i] <= '0;
                        wbPkt[0] <= exResult[0].mulDivReq ? '0 : exResult[0].wb;
                        wbPkt[1] <= '0;
                        memState <= M_MULDIV_WAIT;
                    end else begin
                        wbPkt[0] <= exResult[0].wb;
                        wbPkt[1] <= exResult[1].wb;

                        if (issueAllow) begin
                            exUop[0] <= issueUop[0];
                            exUop[1] <= issueUop[1];
                        end else begin
                            for (int i = 0; i < 2; i++) exUop[i] <= '0;
                        end
                    end
                end
            endcase
        end
    end
endmodule
