import CoreTypesPkg::*;

module CoreIntPipe (
    input  CoreDecodeUop uop_i,
    input  DataPath src0_i,
    input  DataPath src1_i,
    output DataPath result_o
);
    always_comb begin
        result_o = src0_i + src1_i;
        if (!uop_i.valid) begin
            result_o = '0;
        end
    end
endmodule : CoreIntPipe
