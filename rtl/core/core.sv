`timescale 1ns / 1ps

import BasicTypes::*;
import InOrderTypes::*;

module core (
    input  logic        clk,
    input  logic        rst,

    output logic [31:0] irom_addr,
    input  logic [31:0] irom_data,
    output logic        irom_ena,

    output logic        dmem_req_valid,
    input  logic        dmem_req_ready,
    output logic        dmem_req_write,
    output logic [31:0] dmem_req_addr,
    output logic [31:0] dmem_req_wdata,
    output logic [3:0]  dmem_req_wstrb,
    output logic        dmem_req_uncached,
    input  logic        dmem_resp_valid,
    input  logic [31:0] dmem_resp_rdata,

`ifdef VERILATOR_TB
    output logic [63:0] perf_cycle,
    output logic [63:0] perf_commit,
    output logic [63:0] perf_branch,
    output logic [63:0] perf_branch_miss,
    output logic [63:0] perf_load,
    output logic [63:0] perf_store,
    output logic [63:0] perf_dcache_access,
    output logic [63:0] perf_dcache_miss,
    output logic [63:0] perf_stall_front,
    output logic [63:0] perf_stall_mem,
    output logic [63:0] perf_stall_muldiv,
    output logic [63:0] perf_stall_load_use
`endif
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

    logic        cacheReqValid;
    logic        cacheReqReady;
    logic        cacheReqWrite;
    logic [31:0] cacheReqAddr;
    logic [31:0] cacheReqWdata;
    logic [3:0]  cacheReqWstrb;
    logic        cacheReqUncached;
    logic        cacheRespValid;
    logic [31:0] cacheRespRdata;
    logic [63:0] dcacheAccessCnt;
    logic [63:0] dcacheMissCnt;
    logic [63:0] dcacheStallCnt;

    logic [63:0] cycleCnt;
    logic [63:0] commitCnt;
    logic [63:0] branchCnt;
    logic [63:0] branchMissCnt;
    logic [63:0] loadCnt;
    logic [63:0] storeCnt;
    logic [63:0] stallFrontCnt;
    logic [63:0] stallMemCnt;
    logic [63:0] stallMulDivCnt;
    logic [63:0] stallLoadUseCnt;

    function automatic logic is_uncached_addr(input AddrPath addr);
        return !((addr >= 32'h8010_0000) && (addr < 32'h8014_0000));
    endfunction

    function automatic DataPath align_cache_load_data(input LoadInfo info, input DataPath data);
        if (is_uncached_addr(info.addr)) begin
            align_cache_load_data = data;
        end else begin
            align_cache_load_data = data >> {info.addr[1:0], 3'b000};
        end
    endfunction

    assign cacheReqValid = (memState == M_LOAD_REQ) || (memState == M_STORE_REQ);
    assign cacheReqWrite = (memState == M_STORE_REQ);
    assign cacheReqAddr = (memState == M_STORE_REQ) ? storeInfo.addr : loadInfo.addr;
    assign cacheReqWdata = storeInfo.data;
    assign cacheReqWstrb = (memState == M_STORE_REQ) ? storeInfo.mask : 4'b0000;
    assign cacheReqUncached = is_uncached_addr(cacheReqAddr);

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
        .iromAddr       (irom_addr),
        .iromData       (irom_data),
        .iromEna        (irom_ena),
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
        .cycle     (cycleCnt),
        .commitCnt (commitCnt),
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

    DCache #(
        .LINE_COUNT(16384)
    ) u_dcache (
        .clk                (clk),
        .rst                (rst),
        .cpu_req_valid      (cacheReqValid),
        .cpu_req_ready      (cacheReqReady),
        .cpu_req_write      (cacheReqWrite),
        .cpu_req_addr       (cacheReqAddr),
        .cpu_req_wdata      (cacheReqWdata),
        .cpu_req_wstrb      (cacheReqWstrb),
        .cpu_req_uncached   (cacheReqUncached),
        .cpu_resp_valid     (cacheRespValid),
        .cpu_resp_rdata     (cacheRespRdata),
        .mem_req_valid      (dmem_req_valid),
        .mem_req_ready      (dmem_req_ready),
        .mem_req_write      (dmem_req_write),
        .mem_req_addr       (dmem_req_addr),
        .mem_req_wdata      (dmem_req_wdata),
        .mem_req_wstrb      (dmem_req_wstrb),
        .mem_req_uncached   (dmem_req_uncached),
        .mem_resp_valid     (dmem_resp_valid),
        .mem_resp_rdata     (dmem_resp_rdata),
        .perf_dcache_access (dcacheAccessCnt),
        .perf_dcache_miss   (dcacheMissCnt),
        .perf_stall_mem     (dcacheStallCnt)
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
            cycleCnt <= '0;
            commitCnt <= '0;
            branchCnt <= '0;
            branchMissCnt <= '0;
            loadCnt <= '0;
            storeCnt <= '0;
            stallFrontCnt <= '0;
            stallMemCnt <= '0;
            stallMulDivCnt <= '0;
            stallLoadUseCnt <= '0;
            for (int r = 0; r < 32; r++) regs[r] <= '0;
        end else begin
            regs[0] <= '0;
            cycleCnt <= cycleCnt + 64'd1;

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

            commitCnt <= commitCnt + {63'b0, exResult[0].commit} +
                         {63'b0, exResult[1].commit};
            branchCnt <= branchCnt + {63'b0, exResult[0].branch} +
                         {63'b0, exResult[1].branch};
            branchMissCnt <= branchMissCnt + {63'b0, exResult[0].branchMiss} +
                             {63'b0, exResult[1].branchMiss};

            if (!queueCanAccept && memState == M_NORMAL) begin
                stallFrontCnt <= stallFrontCnt + 64'd1;
            end
            if (memState == M_LOAD_REQ || memState == M_LOAD_WAIT0 ||
                memState == M_STORE_REQ) begin
                stallMemCnt <= stallMemCnt + 64'd1;
            end
            if (memState == M_MULDIV_WAIT || memState == M_MULDIV_WB) begin
                stallMulDivCnt <= stallMulDivCnt + 64'd1;
            end

            unique case (memState)
                M_LOAD_REQ: begin
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                    if (cacheReqReady) begin
                        if (cacheRespValid) begin
                            wbPkt[0].valid <= loadInfo.valid && loadInfo.rd != 5'd0;
                            wbPkt[0].rd <= loadInfo.rd;
                            wbPkt[0].data <= load_extend(loadInfo.funct3,
                                                         align_cache_load_data(loadInfo,
                                                                               cacheRespRdata));
                            commitCnt <= commitCnt + 64'd1;
                            loadCnt <= loadCnt + 64'd1;
                            loadInfo <= '0;
                            memState <= M_NORMAL;
                            for (int i = 0; i < 2; i++) exUop[i] <= '0;
                        end else begin
                            memState <= M_LOAD_WAIT0;
                        end
                    end
                end
                M_LOAD_WAIT0: begin
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                    if (cacheRespValid) begin
                        wbPkt[0].valid <= loadInfo.valid && loadInfo.rd != 5'd0;
                        wbPkt[0].rd <= loadInfo.rd;
                        wbPkt[0].data <= load_extend(loadInfo.funct3,
                                                     align_cache_load_data(loadInfo,
                                                                           cacheRespRdata));
                        commitCnt <= commitCnt + 64'd1;
                        loadCnt <= loadCnt + 64'd1;
                        loadInfo <= '0;
                        memState <= M_NORMAL;
                        for (int i = 0; i < 2; i++) exUop[i] <= '0;
                    end
                end
                M_STORE_REQ: begin
                    wbPkt[0] <= '0;
                    wbPkt[1] <= '0;
                    if (cacheReqReady) begin
                        commitCnt <= commitCnt + 64'd1;
                        storeCnt <= storeCnt + 64'd1;
                        storeInfo <= '0;
                        memState <= M_NORMAL;
                        for (int i = 0; i < 2; i++) exUop[i] <= '0;
                    end
                end
                M_MULDIV_WAIT: begin
                    if (mulDivDone) begin
                        wbPkt[0] <= mulDivWb;
                        wbPkt[1] <= '0;
                        commitCnt <= commitCnt + 64'd1;
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
                            stallLoadUseCnt <= stallLoadUseCnt + 64'd1;
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

`ifdef VERILATOR_TB
    assign perf_cycle = cycleCnt;
    assign perf_commit = commitCnt;
    assign perf_branch = branchCnt;
    assign perf_branch_miss = branchMissCnt;
    assign perf_load = loadCnt;
    assign perf_store = storeCnt;
    assign perf_dcache_access = dcacheAccessCnt;
    assign perf_dcache_miss = dcacheMissCnt;
    assign perf_stall_front = stallFrontCnt;
    assign perf_stall_mem = stallMemCnt;
    assign perf_stall_muldiv = stallMulDivCnt;
    assign perf_stall_load_use = stallLoadUseCnt;
`endif
endmodule
