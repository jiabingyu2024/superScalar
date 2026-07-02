

import BasicTypes::*;


module PC(
    PreFetchStageIF.PC pcIF
);

    PcPath pcReg; // PC寄存器

    // PC寄存器更新逻辑
    always_ff @(posedge pcIF.clk or posedge pcIF.rst) begin
        if (pcIF.rst) begin
            pcReg <= 32'h8000_0000; // 复位时PC初始化为0
        end else if (pcIF.pcWe) begin
            pcReg <= pcIF.pcIn; // 当pcWe有效时更新PC寄存器
        end
    end

    // 输出当前PC值
    assign pcIF.pcOut = pcReg;

endmodule