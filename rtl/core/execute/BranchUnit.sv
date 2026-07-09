import CoreTypesPkg::*;

module CoreBranchUnit (
    input  CoreDecodeUop uop_i,
    input  DataPath src0_i,
    input  DataPath src1_i,
    output logic taken_o,
    output PcPath target_o
);
    always_comb begin
        taken_o = 1'b0;
        target_o = uop_i.pc + 32'd4;
        case (uop_i.funct3)
            3'b000: taken_o = (src0_i == src1_i);
            3'b001: taken_o = (src0_i != src1_i);
            3'b100: taken_o = ($signed(src0_i) < $signed(src1_i));
            3'b101: taken_o = ($signed(src0_i) >= $signed(src1_i));
            3'b110: taken_o = (src0_i < src1_i);
            3'b111: taken_o = (src0_i >= src1_i);
            default: taken_o = 1'b0;
        endcase
        if (uop_i.is_jal) begin
            taken_o = 1'b1;
            target_o = uop_i.pc + uop_i.imm_j;
        end else if (uop_i.is_jalr) begin
            taken_o = 1'b1;
            target_o = (src0_i + uop_i.imm_i) & 32'hffff_fffe;
        end else if (uop_i.is_branch && taken_o) begin
            target_o = uop_i.pc + uop_i.imm_b;
        end
    end
endmodule : CoreBranchUnit
