import CoreTypesPkg::*;

interface DramAccessIF(input logic clk, rst);
    logic    exReadEn;
    AddrPath exReadAddr;
    DataPath exReadData;
    logic    exReadReady;
    logic    exReadAccept;
    logic    exReadCacheable;

    logic    storeWriteEn;
    AddrPath storeWriteAddr;
    DataPath storeWriteData;
    logic [3:0] storeWriteMask;
    logic    storeWriteReady;

    logic    readEn;
    logic    writeEn;
    AddrPath accessAddr;
    DataPath writeData;
    logic [3:0] writeMask;
    DataPath readData;
    logic    readResponseValid;
    logic    writeRequestReady;

    logic       exReadPending;
    logic       exReadPendingCacheable;
    logic       exReadReady_q;
    DataPath    exReadData_q;
    logic       storeWritePending;
    logic       storeWriteReady_q;
    AddrPath    storeWriteAddr_q;
    DataPath    storeWriteData_q;
    logic [3:0] storeWriteMask_q;
    logic       readGrant;
    logic       writeGrant;
    logic       readDone;
    logic       writeActive;
    logic       writeDone;

    always_comb begin
        readDone = exReadPending && readResponseValid;
        // A cacheable DCache response can be replaced in the same cycle: a
        // hit leaves the cache in IDLE, while a critical-word miss response
        // has a one-entry read hold. Uncached responses cannot accept a
        // replacement until the cache returns to IDLE.
        readGrant = exReadEn && !storeWritePending &&
                    (!exReadPending ||
                     (readDone && exReadPendingCacheable));
        writeGrant = storeWriteEn && !exReadPending && !storeWritePending &&
                     !storeWriteReady_q && !readGrant;
        writeActive = writeGrant || storeWritePending;
        writeDone = writeActive && writeRequestReady;

        readEn = readGrant;
        writeEn = writeActive;
        accessAddr = readGrant ? exReadAddr :
                     storeWritePending ? storeWriteAddr_q : storeWriteAddr;
        writeData = storeWritePending ? storeWriteData_q : storeWriteData;
        writeMask = storeWritePending ? storeWriteMask_q : storeWriteMask;

        exReadData = exReadData_q;
        exReadReady = exReadReady_q;
        exReadAccept = readGrant;
        storeWriteReady = storeWriteReady_q;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            exReadPending <= 1'b0;
            exReadPendingCacheable <= 1'b0;
            exReadReady_q <= 1'b0;
            exReadData_q <= '0;
            storeWritePending <= 1'b0;
            storeWriteReady_q <= 1'b0;
            storeWriteAddr_q <= '0;
            storeWriteData_q <= '0;
            storeWriteMask_q <= '0;
        end else begin
            exReadReady_q <= readDone;
            if (readDone) begin
                exReadData_q <= readData;
            end
            storeWriteReady_q <= writeDone;
            if (readDone && !readGrant) begin
                exReadPending <= 1'b0;
            end else if (readGrant) begin
                exReadPending <= 1'b1;
            end
            if (readGrant) begin
                exReadPendingCacheable <= exReadCacheable;
            end

            if (writeDone) begin
                storeWritePending <= 1'b0;
            end else if (writeGrant) begin
                storeWritePending <= 1'b1;
                storeWriteAddr_q <= storeWriteAddr;
                storeWriteData_q <= storeWriteData;
                storeWriteMask_q <= storeWriteMask;
            end
        end
    end

    modport core(
        input  readEn,
        input  writeEn,
        input  accessAddr,
        input  writeData,
        input  writeMask,
        output readData,
        output readResponseValid,
        output writeRequestReady
    );

    modport ExecuteMemStage(
        input  exReadData,
        input  exReadReady,
        input  exReadAccept,
        output exReadEn,
        output exReadAddr,
        output exReadCacheable
    );

    modport StoreBuffer(
        input  storeWriteReady,
        output storeWriteEn,
        output storeWriteAddr,
        output storeWriteData,
        output storeWriteMask
    );

    modport DRAM(
        input  readEn,
        input  writeEn,
        input  accessAddr,
        input  writeData,
        input  writeMask,
        output readData,
        output readResponseValid,
        output writeRequestReady
    );
endinterface : DramAccessIF
