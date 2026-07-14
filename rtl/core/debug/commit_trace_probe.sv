`timescale 1ns / 1ps

`ifdef VERILATOR_TB
module commit_trace_probe (
    input  logic clk,
    input  logic rst,
    input  logic commit_i,
    input  logic commit_normal_i,
    input  core_types_pkg::scoreboard_entry_t commit_entry_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] commit_trans_id_i,
    input  logic [31:0] csr_result_i,
    input  logic [31:0] csr_mtvec_i,
    input  logic [31:0] csr_mepc_i,
    input  logic issue_i,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] issue_trans_id_i,
    input  core_types_pkg::uop_t issue_uop_i,
    input  logic branch_resolve_i,
    input  logic [31:0] branch_actual_next_i,
    input  core_types_pkg::exec_req_t exec_i,
    input  logic [31:0] exec_mem_addr_i,
    input  logic [63:0] cycle_i,
    input  logic [63:0] commit_count_i,

    output logic commit_valid_o,
    output logic [31:0] commit_pc_o,
    output logic [31:0] commit_inst_o,
    output logic commit_wen_o,
    output logic [4:0] commit_rd_o,
    output logic [31:0] commit_wdata_o,
    output logic commit_is_load_o,
    output logic commit_is_store_o,
    output logic commit_is_trap_o,
    output logic [31:0] commit_cause_o,
    output logic [31:0] commit_next_pc_o,
    output logic [31:0] commit_mem_addr_o,
    output logic [31:0] commit_mem_wdata_o,
    output logic [3:0] commit_mem_wstrb_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    logic [31:0] mem_addr_q [0:SCOREBOARD_DEPTH-1];
    logic [31:0] mem_wdata_q [0:SCOREBOARD_DEPTH-1];
    logic [3:0] mem_wstrb_q [0:SCOREBOARD_DEPTH-1];
    logic [31:0] next_pc_q [0:SCOREBOARD_DEPTH-1];
    integer i;

    // Sample the pre-NBA resource state. The C++ harness observes these
    // registered outputs after the same edge, naming the instruction that
    // actually retired rather than the next scoreboard head.
    always_ff @(posedge clk) begin
        if (rst) begin
            commit_valid_o <= 1'b0;
            commit_pc_o <= '0;
            commit_inst_o <= '0;
            commit_wen_o <= 1'b0;
            commit_rd_o <= '0;
            commit_wdata_o <= '0;
            commit_is_load_o <= 1'b0;
            commit_is_store_o <= 1'b0;
            commit_is_trap_o <= 1'b0;
            commit_cause_o <= '0;
            commit_next_pc_o <= '0;
            commit_mem_addr_o <= '0;
            commit_mem_wdata_o <= '0;
            commit_mem_wstrb_o <= '0;
            for (i = 0; i < SCOREBOARD_DEPTH; i = i + 1) begin
                mem_addr_q[i] <= '0;
                mem_wdata_q[i] <= '0;
                mem_wstrb_q[i] <= '0;
                next_pc_q[i] <= '0;
            end
        end else begin
            commit_valid_o <= commit_i;
            if (commit_i) begin
                commit_pc_o <= commit_entry_i.pc;
                commit_inst_o <= commit_entry_i.instr;
                commit_wen_o <= commit_normal_i && commit_entry_i.writes_rd &&
                                commit_entry_i.rd != 0;
                commit_rd_o <= commit_entry_i.rd;
                commit_wdata_o <= commit_entry_i.sys_op == SYS_CSR ?
                                  csr_result_i : commit_entry_i.result;
                commit_is_load_o <= commit_entry_i.fu == FU_LOAD;
                commit_is_store_o <= commit_entry_i.fu == FU_STORE;
                commit_is_trap_o <= commit_entry_i.exception_valid;
                commit_cause_o <= {27'd0, commit_entry_i.exception_cause};
                commit_mem_addr_o <= mem_addr_q[commit_trans_id_i];
                commit_mem_wdata_o <= mem_wdata_q[commit_trans_id_i];
                commit_mem_wstrb_o <= mem_wstrb_q[commit_trans_id_i];
                if (commit_entry_i.exception_valid)
                    commit_next_pc_o <= csr_mtvec_i;
                else if (commit_entry_i.sys_op == SYS_MRET)
                    commit_next_pc_o <= csr_mepc_i;
                else
                    commit_next_pc_o <= next_pc_q[commit_trans_id_i];
            end
            if (issue_i)
                next_pc_q[issue_trans_id_i] <= issue_uop_i.pc + 32'd4;
            if (branch_resolve_i)
                next_pc_q[exec_i.trans_id] <= branch_actual_next_i;
            if (exec_i.valid && (exec_i.uop.fu == FU_LOAD ||
                                 exec_i.uop.fu == FU_STORE)) begin
                mem_addr_q[exec_i.trans_id] <= exec_mem_addr_i;
                mem_wdata_q[exec_i.trans_id] <=
                    exec_i.uop.fu == FU_STORE ? exec_i.op2 : 32'd0;
                if (exec_i.uop.fu == FU_STORE) begin
                    unique case (exec_i.uop.mem_size)
                        MEM_BYTE: mem_wstrb_q[exec_i.trans_id] <= 4'b0001;
                        MEM_HALF: mem_wstrb_q[exec_i.trans_id] <= 4'b0011;
                        default: mem_wstrb_q[exec_i.trans_id] <= 4'b1111;
                    endcase
                end else begin
                    mem_wstrb_q[exec_i.trans_id] <= 4'b0000;
                end
            end
        end
    end

`ifdef ENABLE_DIFFTEST
    DiffExtInstrCommit u_difftest_commit (
        .clock(clk), .enable(commit_i), .io_valid(commit_i), .io_skip(1'b0),
        .io_isRVC(1'b0),
        .io_rfwen(commit_normal_i && commit_entry_i.writes_rd && commit_entry_i.rd != 0),
        .io_fpwen(1'b0), .io_vecwen(1'b0), .io_v0wen(1'b0),
        .io_wpdest(commit_entry_i.rd), .io_wdest({3'b000, commit_entry_i.rd}),
        .io_otherwpdest_0('0), .io_otherwpdest_1('0),
        .io_otherwpdest_2('0), .io_otherwpdest_3('0),
        .io_otherwpdest_4('0), .io_otherwpdest_5('0),
        .io_otherwpdest_6('0), .io_otherwpdest_7('0),
        .io_otherwpdest_8('0), .io_otherwpdest_9('0),
        .io_otherwpdest_10('0), .io_otherwpdest_11('0),
        .io_otherwpdest_12('0), .io_otherwpdest_13('0),
        .io_otherwpdest_14('0), .io_otherwpdest_15('0),
        .io_pc({32'd0, commit_entry_i.pc}), .io_instr(commit_entry_i.instr),
        .io_robIdx({{(10-TRANS_ID_W){1'b0}}, commit_trans_id_i}),
        .io_lqIdx('0), .io_sqIdx('0),
        .io_isLoad(commit_entry_i.fu == FU_LOAD),
        .io_isStore(commit_entry_i.fu == FU_STORE),
        .io_nFused(8'd0), .io_special(8'd0), .io_coreid(8'd0), .io_index(8'd0)
    );

    DiffExtCommitData u_difftest_commit_data (
        .clock(clk), .enable(commit_i), .io_valid(commit_i),
        .io_data({32'd0, commit_entry_i.sys_op == SYS_CSR ?
                          csr_result_i : commit_entry_i.result}),
        .io_coreid(8'd0), .io_index(8'd0)
    );

    DiffExtArchEvent u_difftest_arch_event (
        .clock(clk), .enable(commit_i && commit_entry_i.exception_valid),
        .io_valid(commit_entry_i.exception_valid), .io_interrupt(32'd0),
        .io_exception(32'b1 << commit_entry_i.exception_cause),
        .io_exceptionPC({32'd0, commit_entry_i.pc}),
        .io_exceptionInst(commit_entry_i.instr), .io_hasNMI(1'b0),
        .io_virtualInterruptIsHvictlInject(1'b0), .io_irToHS(1'b0),
        .io_irToVS(1'b0), .io_coreid(8'd0)
    );

    DiffExtTrapEvent u_difftest_trap_event (
        .clock(clk), .enable(commit_i),
        .io_hasTrap(commit_entry_i.exception_valid), .io_cycleCnt(cycle_i),
        .io_instrCnt(commit_count_i), .io_hasWFI(1'b0),
        .io_code({59'd0, commit_entry_i.exception_cause}),
        .io_pc({32'd0, commit_entry_i.pc}), .io_coreid(8'd0)
    );
`endif
endmodule
`endif
