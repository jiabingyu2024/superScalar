import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreBranchPredictor (
    input  logic  clk,
    input  logic  rst,
    input  PcPath pc_i,
    output logic  pred_valid_o,
    output logic  pred_taken_o,
    output PcPath pred_target_o,
    input  logic  update_valid_i,
    input  PcPath update_pc_i,
    input  logic  update_taken_i,
    input  PcPath update_target_i
);
    logic unused_update;
    assign unused_update = update_valid_i ^ update_pc_i[0] ^ update_taken_i ^ update_target_i[0];

    always_comb begin
        pred_valid_o  = 1'b1;
        pred_taken_o  = 1'b0;
        pred_target_o = pc_i + 32'd8;
    end
endmodule : CoreBranchPredictor
