import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreCommitUnit (
    input  logic clk,
    input  logic rst,

    input  logic [RETIRE_WIDTH-1:0] rob_valid_i,
    output logic [RETIRE_WIDTH-1:0] rob_ready_o,
    input  CoreRobEntry [RETIRE_WIDTH-1:0] rob_entry_i,

    input  logic [ISSUE_WIDTH-1:0][11:0] csr_read_addr_i,
    output DataPath [ISSUE_WIDTH-1:0] csr_read_data_o,

    output logic [RETIRE_WIDTH-1:0] commit_valid_o,
    output LgcRegNumPath [RETIRE_WIDTH-1:0] commit_arch_o,
    output PhyRegNumPath [RETIRE_WIDTH-1:0] commit_prd_o,
    output PhyRegNumPath [RETIRE_WIDTH-1:0] free_old_prd_o,
    output logic [RETIRE_WIDTH-1:0] free_old_valid_o,

    output logic recover_valid_o,
    output PcPath recover_pc_o
);
    DataPath mstatus_q;
    PcPath mtvec_q;
    PcPath mepc_q;
    DataPath mcause_q;
    DataPath mtval_q;
    DataPath mie_q;
    DataPath medeleg_q;
    DataPath mideleg_q;
    DataPath mscratch_q;
    DataPath mcounteren_q;
    DataPath stvec_q;
    DataPath scounteren_q;
    DataPath satp_q;
    DataPath pmpcfg0_q;
    DataPath pmpaddr0_q;

    logic stop_retire;
    logic csr_we [RETIRE_WIDTH-1:0];
    logic [11:0] csr_waddr [RETIRE_WIDTH-1:0];
    DataPath csr_wdata [RETIRE_WIDTH-1:0];
    logic trap_take [RETIRE_WIDTH-1:0];
    DataPath trap_cause [RETIRE_WIDTH-1:0];
    PcPath trap_epc [RETIRE_WIDTH-1:0];
    DataPath trap_tval [RETIRE_WIDTH-1:0];

    function automatic DataPath csr_read(input logic [11:0] addr);
        begin
            unique case (addr)
                12'h100: csr_read = 32'b0;
                12'h105: csr_read = stvec_q;
                12'h106: csr_read = scounteren_q;
                12'h180: csr_read = satp_q;
                12'h300: csr_read = mstatus_q;
                12'h301: csr_read = 32'h4010_1100;
                12'h302: csr_read = medeleg_q;
                12'h303: csr_read = mideleg_q;
                12'h304: csr_read = mie_q;
                12'h305: csr_read = mtvec_q;
                12'h306: csr_read = mcounteren_q;
                12'h340: csr_read = mscratch_q;
                12'h341: csr_read = mepc_q;
                12'h342: csr_read = mcause_q;
                12'h343: csr_read = mtval_q;
                12'h3a0: csr_read = pmpcfg0_q;
                12'h3b0: csr_read = pmpaddr0_q;
                12'hc00,
                12'hc01,
                12'hc02,
                12'hc80,
                12'hc81,
                12'hc82: csr_read = 32'b0;
                12'hf14: csr_read = 32'b0;
                default: csr_read = 32'b0;
            endcase
        end
    endfunction

    always_comb begin
        for (int r = 0; r < ISSUE_WIDTH; r = r + 1) begin
            csr_read_data_o[r] = csr_read(csr_read_addr_i[r]);
        end

        recover_valid_o = 1'b0;
        recover_pc_o = '0;
        stop_retire = 1'b0;

        for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
            rob_ready_o[i] = 1'b0;
            commit_valid_o[i] = 1'b0;
            commit_arch_o[i] = rob_entry_i[i].uop.rd;
            commit_prd_o[i] = rob_entry_i[i].prd;
            free_old_prd_o[i] = rob_entry_i[i].old_prd;
            free_old_valid_o[i] = 1'b0;
            csr_we[i] = 1'b0;
            csr_waddr[i] = '0;
            csr_wdata[i] = '0;
            trap_take[i] = 1'b0;
            trap_cause[i] = '0;
            trap_epc[i] = rob_entry_i[i].uop.pc;
            trap_tval[i] = '0;

            if (rob_valid_i[i] && !stop_retire) begin
                if (rob_entry_i[i].exception) begin
                    rob_ready_o[i] = 1'b1;
                    trap_take[i] = 1'b1;
                    trap_cause[i] = rob_entry_i[i].exception_cause;
                    trap_epc[i] = rob_entry_i[i].uop.pc;
                    trap_tval[i] = rob_entry_i[i].uop.illegal ? rob_entry_i[i].uop.inst : 32'b0;
                    recover_valid_o = 1'b1;
                    recover_pc_o = {mtvec_q[31:2], 2'b00};
                    stop_retire = 1'b1;
                end else begin
                    rob_ready_o[i] = 1'b1;
                    commit_valid_o[i] = 1'b1;
                    free_old_valid_o[i] = rob_entry_i[i].alloc_prd &&
                                          (rob_entry_i[i].old_prd != '0);

                    if (rob_entry_i[i].csr_write) begin
                        csr_we[i] = 1'b1;
                        csr_waddr[i] = rob_entry_i[i].csr_addr;
                        csr_wdata[i] = rob_entry_i[i].csr_wdata;
                    end

                    if (rob_entry_i[i].uop.is_mret) begin
                        recover_valid_o = 1'b1;
                        recover_pc_o = mepc_q;
                        stop_retire = 1'b1;
                    end else if (rob_entry_i[i].branch_miss) begin
                        recover_valid_o = 1'b1;
                        recover_pc_o = rob_entry_i[i].redirect_pc;
                        stop_retire = 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus_q <= '0;
            mtvec_q <= '0;
            mepc_q <= '0;
            mcause_q <= '0;
            mtval_q <= '0;
            mie_q <= '0;
            medeleg_q <= '0;
            mideleg_q <= '0;
            mscratch_q <= '0;
            mcounteren_q <= '0;
            stvec_q <= '0;
            scounteren_q <= '0;
            satp_q <= '0;
            pmpcfg0_q <= '0;
            pmpaddr0_q <= '0;
        end else begin
            for (int i = 0; i < RETIRE_WIDTH; i = i + 1) begin
                if (csr_we[i]) begin
                    unique case (csr_waddr[i])
                        12'h100: begin end
                        12'h105: stvec_q <= csr_wdata[i];
                        12'h106: scounteren_q <= csr_wdata[i];
                        12'h180: satp_q <= csr_wdata[i];
                        12'h300: mstatus_q <= csr_wdata[i];
                        12'h302: medeleg_q <= csr_wdata[i];
                        12'h303: mideleg_q <= csr_wdata[i];
                        12'h304: mie_q <= csr_wdata[i];
                        12'h305: mtvec_q <= csr_wdata[i];
                        12'h306: mcounteren_q <= csr_wdata[i];
                        12'h340: mscratch_q <= csr_wdata[i];
                        12'h341: mepc_q <= csr_wdata[i];
                        12'h342: mcause_q <= csr_wdata[i];
                        12'h343: mtval_q <= csr_wdata[i];
                        12'h3a0: pmpcfg0_q <= csr_wdata[i];
                        12'h3b0: pmpaddr0_q <= csr_wdata[i];
                        default: begin end
                    endcase
                end

                if (trap_take[i]) begin
                    mepc_q <= trap_epc[i];
                    mcause_q <= trap_cause[i];
                    mtval_q <= trap_tval[i];
                end
            end
        end
    end
endmodule : CoreCommitUnit
