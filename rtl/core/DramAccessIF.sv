//------------------------------------------------------------------------------
// DramAccessIF.sv
// 作用：定义 core 与无 cache、固定读延迟 DRAM 的访问接口。
// 微架构定位：ExecuteMemStage 拉高 readEn 发起 load 读地址；StoreBuffer 拉高
// writeEn 提交已退休 store。accessReady 只表示本周期读/写地址被单端口仲裁器接受，
// 不表示 readData 有效；readData 由 DRAM 固定延迟返回，core 内部用延迟 metadata 对齐。
//------------------------------------------------------------------------------

import BasicTypes::*;

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

    always_comb begin
        readEn = exReadEn;
        writeEn = !exReadEn && storeWriteEn;
        accessAddr = exReadEn ? exReadAddr : storeWriteAddr;
        writeData = storeWriteData;
        writeMask = storeWriteMask;

        exReadData = readData;
        exReadReady = accessReady;
        storeWriteReady = accessReady && !exReadEn;
    end

    modport core(
        input
            readEn,
            writeEn,
            accessAddr,
            writeData,
            writeMask,
        output
            readData,
            accessReady
    );

    modport ExecuteMemStage(
        input
            exReadData,
            exReadReady,
        output
            exReadEn,
            exReadAddr
    );

    modport StoreBuffer(
        input
            storeWriteReady,
        output
            storeWriteEn,
            storeWriteAddr,
            storeWriteData,
            storeWriteMask
    );

    modport DRAM(
        input
            readEn,
            writeEn,
            accessAddr,
            writeData,
            writeMask,
        output
            readData,
            accessReady
    );
endinterface : DramAccessIF
