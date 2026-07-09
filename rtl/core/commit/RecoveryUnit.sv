import CoreTypesPkg::*;

module CoreRecoveryUnit (
    input  logic branch_miss_i,
    input  PcPath branch_target_i,
    input  logic trap_i,
    input  PcPath trap_target_i,
    output logic flush_o,
    output PcPath redirect_pc_o
);
    always_comb begin
        flush_o = trap_i || branch_miss_i;
        redirect_pc_o = branch_miss_i ? branch_target_i : trap_target_i;
        if (trap_i) begin
            redirect_pc_o = trap_target_i;
        end
    end
endmodule : CoreRecoveryUnit
