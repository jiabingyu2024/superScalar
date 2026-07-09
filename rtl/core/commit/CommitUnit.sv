import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreCommitUnit (
    input  logic [RETIRE_WIDTH-1:0] rob_valid_i,
    output logic [RETIRE_WIDTH-1:0] rob_ready_o,
    input  CoreRobEntry [RETIRE_WIDTH-1:0] rob_entry_i,

    output logic [RETIRE_WIDTH-1:0] commit_valid_o,
    output LgcRegNumPath [RETIRE_WIDTH-1:0] commit_arch_o,
    output PhyRegNumPath [RETIRE_WIDTH-1:0] commit_prd_o,
    output PhyRegNumPath [RETIRE_WIDTH-1:0] free_old_prd_o,
    output logic [RETIRE_WIDTH-1:0] free_old_valid_o,

    output logic recover_valid_o,
    output PcPath recover_pc_o
);
    always_comb begin
        recover_valid_o = 1'b0;
        recover_pc_o = '0;
        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            rob_ready_o[i] = 1'b1;
            commit_valid_o[i] = rob_valid_i[i] && !recover_valid_o;
            commit_arch_o[i] = rob_entry_i[i].uop.rd;
            commit_prd_o[i] = rob_entry_i[i].prd;
            free_old_prd_o[i] = rob_entry_i[i].old_prd;
            free_old_valid_o[i] = commit_valid_o[i] &&
                                  rob_entry_i[i].alloc_prd &&
                                  (rob_entry_i[i].old_prd != '0);

            if (rob_valid_i[i] &&
                (rob_entry_i[i].exception || rob_entry_i[i].branch_miss) &&
                !recover_valid_o) begin
                recover_valid_o = 1'b1;
                recover_pc_o = rob_entry_i[i].redirect_pc;
                commit_valid_o[i] = 1'b0;
                free_old_valid_o[i] = 1'b0;
            end
        end
    end
endmodule : CoreCommitUnit
