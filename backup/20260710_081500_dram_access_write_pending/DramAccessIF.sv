import CoreTypesPkg::*;

interface DramAccessIF(input logic clk, rst);
    logic    exReadEn;
    AddrPath exReadAddr;
    DataPath exReadData;
    logic    exReadReady;

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
    logic    accessReady;

    logic       exReadPending;
    logic       readGrant;
    logic       writeGrant;
    logic       readDone;

    always_comb begin
        readGrant = exReadEn && !exReadPending;
        readDone = exReadPending && accessReady;
        writeGrant = storeWriteEn && !exReadPending && !readGrant;

        readEn = readGrant;
        writeEn = writeGrant;
        accessAddr = readGrant ? exReadAddr : storeWriteAddr;
        writeData = storeWriteData;
        writeMask = storeWriteMask;

        exReadData = readData;
        exReadReady = readDone;
        storeWriteReady = accessReady && writeGrant;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            exReadPending <= 1'b0;
        end else if (readDone) begin
            exReadPending <= 1'b0;
        end else if (readGrant) begin
            exReadPending <= 1'b1;
        end
    end

    modport core(
        input  readEn,
        input  writeEn,
        input  accessAddr,
        input  writeData,
        input  writeMask,
        output readData,
        output accessReady
    );

    modport ExecuteMemStage(
        input  exReadData,
        input  exReadReady,
        output exReadEn,
        output exReadAddr
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
        output accessReady
    );
endinterface : DramAccessIF
