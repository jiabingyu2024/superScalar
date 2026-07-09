import CoreTypesPkg::*;

module CoreMulDivPipe (
    input  DataPath src0_i,
    input  DataPath src1_i,
    input  logic [2:0] funct3_i,
    output DataPath result_o
);
    logic [63:0] mul_u;
    logic signed [63:0] mul_s;

    always_comb begin
        mul_u = {32'b0, src0_i} * {32'b0, src1_i};
        mul_s = $signed(src0_i) * $signed(src1_i);
        case (funct3_i)
            3'b000: result_o = mul_u[31:0];
            3'b001: result_o = mul_s[63:32];
            3'b011: result_o = mul_u[63:32];
            default: result_o = 32'b0;
        endcase
    end
endmodule : CoreMulDivPipe
