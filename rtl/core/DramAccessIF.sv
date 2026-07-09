import CoreTypesPkg::*;

interface DramAccessIF(input logic clk, rst);
    localparam logic [3:0] STORE_STARVE_LIMIT = 4'd2;

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

    logic [3:0] storeStarveCnt;
    logic       storeForce;
    logic       readGrant;
    logic       writeGrant;

    always_comb begin
        storeForce = storeWriteEn && (storeStarveCnt >= STORE_STARVE_LIMIT);
        readGrant = exReadEn && !storeForce;
        writeGrant = storeWriteEn && (!exReadEn || storeForce);

        readEn = readGrant;
        writeEn = writeGrant;
        accessAddr = readGrant ? exReadAddr : storeWriteAddr;
        writeData = storeWriteData;
        writeMask = storeWriteMask;

        exReadData = readData;
        exReadReady = accessReady && readGrant;
        storeWriteReady = accessReady && writeGrant;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            storeStarveCnt <= '0;
        end else if (storeWriteReady) begin
            storeStarveCnt <= '0;
        end else if (storeWriteEn && exReadEn && readGrant && accessReady) begin
            if (storeStarveCnt != 4'hf) begin
                storeStarveCnt <= storeStarveCnt + 1'b1;
            end
        end else if (!storeWriteEn) begin
            storeStarveCnt <= '0;
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
