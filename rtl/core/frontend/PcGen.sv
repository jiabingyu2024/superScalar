import CoreTypesPkg::*;

module CorePcGen (
    input  logic  clk,
    input  logic  rst,
    input  logic  hold_i,
    input  logic  recovery_valid_i,
    input  PcPath recovery_pc_i,
    input  logic  pred_valid_i,
    input  PcPath pred_pc_i,
    output PcPath pc_o
);
    PcPath pc_q;

    assign pc_o = pc_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_q <= 32'h8000_0000;
        end else if (!hold_i) begin
            if (recovery_valid_i) begin
                pc_q <= recovery_pc_i;
            end else if (pred_valid_i) begin
                pc_q <= pred_pc_i;
            end else begin
                pc_q <= pc_q + 32'd8;
            end
        end
    end
endmodule : CorePcGen
