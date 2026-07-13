`include "cpu_defines.svh"

// Single-issue C0/C1/C2 backend.
// C0: decode, register read and AGU.
// C1: integer/branch/MulDiv execution or DCache request.
// C2: load formatting and architectural write-back.
module core (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic [`DATA_BUS]      irom_data,
    output logic [`PC_BUS]        irom_addr,
    output logic                  irom_ena,

    input  logic [`DATA_BUS]      dram_rdata,
    input  logic                  dram_req_ready,
    output logic                  dram_wen,
    output logic                  dram_ren,
    output logic [`RAM_ADDR_BUS]  dram_addr,
    output logic [`DATA_BUS]      dram_wdata,
    output logic [3:0]            dram_mask
`ifdef VERILATOR_TB
    ,
    output logic [63:0]           dbg_perf_commit,
    output logic [63:0]           dbg_perf_branch,
    output logic [63:0]           dbg_perf_branch_miss,
    output logic [63:0]           dbg_perf_load,
    output logic [63:0]           dbg_perf_store,
    output logic [63:0]           dbg_perf_stall_front,
    output logic [63:0]           dbg_perf_stall_muldiv,
    output logic [63:0]           dbg_perf_stall_load_use
`endif
);
    // ------------------------------------------------------------------
    // Frontend: PC -> synchronous IROM align -> IF/ID.
    // ------------------------------------------------------------------
    logic [`PC_BUS]   pc_next;
    logic [`PC_BUS]   pc_p;
    logic [`PC_BUS]   pc_predict_p;
    logic [`PC_BUS]   pc_pf;
    logic [`PC_BUS]   pc_predict_pf;
    logic             valid_pf;
    logic             predict_taken_pf;
    logic [`PC_BUS]   pc_f;
    logic [`INST_BUS] inst_f;
    logic [`PC_BUS]   pc_predict_f;
    logic             predict_taken_f;
    logic [`PC_BUS]   predict_target_f;

    logic [`PC_BUS]   pc_d;
    logic [`INST_BUS] inst_d;
    logic [`PC_BUS]   pc_predict_d;
    logic             valid_d;
    logic             predict_taken_d;

    logic             stall_front;
    logic             flush_front;
    logic             flush_c1;
    logic             hold_c1;
    logic             bubble_c1;

    assign irom_addr = pc_p;
    assign irom_ena  = !stall_front;

    stage_pc u_stage_pc (
        .i_clk     (clk),
        .i_rst_n   (rst_n),
        .i_pc_next (pc_next),
        .o_pc_cur  (pc_p)
    );

    reg_pc_if u_reg_pc_if (
        .i_clk        (clk),
        .i_rst_n      (rst_n),
        .i_flush      (flush_front),
        .i_stall      (stall_front),
        .i_pc         (pc_p),
        .i_pc_predict (pc_predict_p),
        .i_predict_taken (predict_taken_f),
        .o_pc         (pc_pf),
        .o_pc_predict (pc_predict_pf),
        .o_predict_taken (predict_taken_pf),
        .o_valid      (valid_pf)
    );

    stage_if u_stage_if (
        .i_pc         (pc_pf),
        .i_inst       (irom_data),
        .i_pc_predict (pc_predict_pf),
        .i_valid      (valid_pf),
        .o_pc         (pc_f),
        .o_inst       (inst_f),
        .o_pc_predict (pc_predict_f)
    );

    reg_if_id u_reg_if_id (
        .i_clk        (clk),
        .i_rst_n      (rst_n),
        .i_flush      (flush_front),
        .i_stall      (stall_front),
        .i_pc_f_d     (pc_f),
        .i_inst_f_d   (inst_f),
        .i_pc_predict (pc_predict_f),
        .i_predict_taken (predict_taken_pf),
        .i_valid      (valid_pf),
        .o_pc_f_d     (pc_d),
        .o_inst_f_d   (inst_d),
        .o_pc_predict (pc_predict_d),
        .o_predict_taken (predict_taken_d),
        .o_valid      (valid_d)
    );

    // ------------------------------------------------------------------
    // C0: decode, RF read and address generation.
    // ------------------------------------------------------------------
    logic             mem_read_d;
    logic             mem_write_d;
    logic             reg_write_d;
    logic             wb_src_d;
    logic             is_rs2_imm_d;
    logic [3:0]       inst_spec_d;
    logic [3:0]       alu_ctrl_d;
    logic [2:0]       func3_d;
    logic [3:0]       mem_mask_d;
    logic             load_unsigned_d;
    logic             is_branch_d;
    logic             is_m_ext_d;
    logic [`M_OP_BUS] m_op_d;
    logic [11:0]      csr_addr_d;
    logic [`DATA_BUS] imm_d;
    logic [`DATA_BUS] rs1_data_d;
    logic [`RF_BUS]   rs1_addr_d;
    logic [`DATA_BUS] rs2_data_d;
    logic [`RF_BUS]   rs2_addr_d;
    logic [`RF_BUS]   rd_addr_d;
    logic [`PC_BUS]   pc_target_d;
    logic [`DATA_BUS] agu_base_d;
    logic [`DATA_BUS] mem_addr_d;
    logic [`DATA_BUS] rs1_issue_d;
    logic [`DATA_BUS] rs2_issue_d;
    logic [`RF_BUS]   rd_addr_c1;
    logic [`DATA_BUS] alu_res_c1;
    logic             c1_agu_forwardable;
    logic [`DATA_BUS] store_data_d;

    // C2 writeback signals are also the stable C0 bypass source.
    logic             valid_c2;
    logic [`RF_BUS]   rd_addr_c2;
    logic [`DATA_BUS] alu_res_c2;
    logic             wb_src_c2;
    logic             reg_write_c2;
    logic [3:0]       mem_mask_c2;
    logic             load_unsigned_c2;
    logic [`DATA_BUS] mem_data_c2;
    logic [`DATA_BUS] wb_data_c2;
    logic [`DATA_BUS] ex_wb_data_c2;
    logic [`DATA_BUS] ls_wb_data_c2;
    logic [`RF_BUS]   wb_rd_addr_c2;
    logic             wb_fire_c2;
    logic             ex_wb_fire_c2;
    logic             ls_wb_fire_c2;
    logic             ls_wb_valid;
    logic [`RF_BUS]   ls_wb_rd_addr;
    logic [3:0]       ls_wb_mem_mask;
    logic             ls_wb_load_unsigned;
    logic [`DATA_BUS] ls_mem_data;
    logic             wb_commit_valid;
    logic             wbq0_valid;
    logic [`RF_BUS]   wbq0_rd;
    logic [`DATA_BUS] wbq0_data;
    logic             wbq1_valid;
    logic [`RF_BUS]   wbq1_rd;
    logic [`DATA_BUS] wbq1_data;
    logic             wbq0_valid_next;
    logic [`RF_BUS]   wbq0_rd_next;
    logic [`DATA_BUS] wbq0_data_next;
    logic             wbq1_valid_next;
    logic [`RF_BUS]   wbq1_rd_next;
    logic [`DATA_BUS] wbq1_data_next;
    logic             wbq_overflow;

    assign ex_wb_fire_c2 = valid_c2 && reg_write_c2 && (rd_addr_c2 != '0);
    assign ls_wb_fire_c2 = ls_wb_valid && (ls_wb_rd_addr != '0);
    assign wb_commit_valid = valid_c2 || ls_wb_valid;

    // Fixed-depth ordered gearbox. Pending entries are older than current C2
    // results; a same-cycle LS result is older than EX because the LS sidecar
    // holds the earlier instruction. Keep this explicit so synthesis builds
    // local muxes instead of a generic loop/count priority network.
    always_comb begin : wb_ordered_gearbox
        wb_fire_c2       = 1'b0;
        wb_rd_addr_c2    = '0;
        wb_data_c2       = '0;
        wbq0_valid_next  = 1'b0;
        wbq0_rd_next     = '0;
        wbq0_data_next   = '0;
        wbq1_valid_next  = 1'b0;
        wbq1_rd_next     = '0;
        wbq1_data_next   = '0;
        wbq_overflow     = 1'b0;

        if (wbq0_valid) begin
            wb_fire_c2    = 1'b1;
            wb_rd_addr_c2 = wbq0_rd;
            wb_data_c2    = wbq0_data;
            if (wbq1_valid) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = wbq1_rd;
                wbq0_data_next  = wbq1_data;
                if (ls_wb_fire_c2) begin
                    wbq1_valid_next = 1'b1;
                    wbq1_rd_next    = ls_wb_rd_addr;
                    wbq1_data_next  = ls_wb_data_c2;
                    wbq_overflow    = ex_wb_fire_c2;
                end else if (ex_wb_fire_c2) begin
                    wbq1_valid_next = 1'b1;
                    wbq1_rd_next    = rd_addr_c2;
                    wbq1_data_next  = ex_wb_data_c2;
                end
            end else if (ls_wb_fire_c2) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = ls_wb_rd_addr;
                wbq0_data_next  = ls_wb_data_c2;
                if (ex_wb_fire_c2) begin
                    wbq1_valid_next = 1'b1;
                    wbq1_rd_next    = rd_addr_c2;
                    wbq1_data_next  = ex_wb_data_c2;
                end
            end else if (ex_wb_fire_c2) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = rd_addr_c2;
                wbq0_data_next  = ex_wb_data_c2;
            end
        end else if (wbq1_valid) begin
            wb_fire_c2    = 1'b1;
            wb_rd_addr_c2 = wbq1_rd;
            wb_data_c2    = wbq1_data;
            if (ls_wb_fire_c2) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = ls_wb_rd_addr;
                wbq0_data_next  = ls_wb_data_c2;
                if (ex_wb_fire_c2) begin
                    wbq1_valid_next = 1'b1;
                    wbq1_rd_next    = rd_addr_c2;
                    wbq1_data_next  = ex_wb_data_c2;
                end
            end else if (ex_wb_fire_c2) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = rd_addr_c2;
                wbq0_data_next  = ex_wb_data_c2;
            end
        end else if (ls_wb_fire_c2) begin
            wb_fire_c2    = 1'b1;
            wb_rd_addr_c2 = ls_wb_rd_addr;
            wb_data_c2    = ls_wb_data_c2;
            if (ex_wb_fire_c2) begin
                wbq0_valid_next = 1'b1;
                wbq0_rd_next    = rd_addr_c2;
                wbq0_data_next  = ex_wb_data_c2;
            end
        end else if (ex_wb_fire_c2) begin
            wb_fire_c2    = 1'b1;
            wb_rd_addr_c2 = rd_addr_c2;
            wb_data_c2    = ex_wb_data_c2;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wbq0_valid <= 1'b0;
            wbq1_valid <= 1'b0;
        end else begin
            wbq0_valid <= wbq0_valid_next;
            wbq0_rd    <= wbq0_rd_next;
            wbq0_data  <= wbq0_data_next;
            wbq1_valid <= wbq1_valid_next;
            wbq1_rd    <= wbq1_rd_next;
            wbq1_data  <= wbq1_data_next;
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (rst_n && wbq_overflow) begin
            $fatal(1, "ordered completion gearbox overflow");
        end
    end
`endif

    stage_id u_stage_id (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc_f_d        (pc_d),
        .i_inst_f_d      (inst_d),
        .i_pc_predict    (pc_predict_d),
        .i_we            (wb_fire_c2),
        .i_w_addr        (wb_rd_addr_c2),
        .i_w_data        (wb_data_c2),
        .o_mem_read      (mem_read_d),
        .o_mem_write     (mem_write_d),
        .o_reg_write     (reg_write_d),
        .o_wb_src        (wb_src_d),
        .o_is_rs2_imm    (is_rs2_imm_d),
        .o_inst_spec     (inst_spec_d),
        .o_alu_ctrl      (alu_ctrl_d),
        .o_func3         (func3_d),
        .o_mem_mask      (mem_mask_d),
        .o_load_unsigned (load_unsigned_d),
        .o_is_branch     (is_branch_d),
        .o_is_m_ext      (is_m_ext_d),
        .o_m_op          (m_op_d),
        .o_csr_addr      (csr_addr_d),
        .o_imm           (imm_d),
        .o_rs1_data      (rs1_data_d),
        .o_rs1_addr      (rs1_addr_d),
        .o_rs2_data      (rs2_data_d),
        .o_rs2_addr      (rs2_addr_d),
        .o_rd_addr       (rd_addr_d)
    );

    assign pc_target_d = pc_d + imm_d;
    assign rs1_issue_d = ex_wb_fire_c2 && (rd_addr_c2 == rs1_addr_d) ?
                         ex_wb_data_c2 :
                         (ls_wb_fire_c2 && (ls_wb_rd_addr == rs1_addr_d) ?
                          ls_wb_data_c2 :
                          (wbq1_valid && (wbq1_rd == rs1_addr_d) ?
                           wbq1_data :
                           (wbq0_valid && (wbq0_rd == rs1_addr_d) ?
                            wbq0_data : rs1_data_d)));

    assign rs2_issue_d = ex_wb_fire_c2 && (rd_addr_c2 == rs2_addr_d) ?
                         ex_wb_data_c2 :
                         (ls_wb_fire_c2 && (ls_wb_rd_addr == rs2_addr_d) ?
                          ls_wb_data_c2 :
                          (wbq1_valid && (wbq1_rd == rs2_addr_d) ?
                           wbq1_data :
                           (wbq0_valid && (wbq0_rd == rs2_addr_d) ?
                            wbq0_data : rs2_data_d)));

    assign agu_base_d   = rs1_issue_d;
    assign store_data_d = rs2_issue_d;

    agu u_agu (
        .i_base   (agu_base_d),
        .i_offset (imm_d),
        .o_addr   (mem_addr_d)
    );

    // ------------------------------------------------------------------
    // C1 pipeline register and execution/cache request slot.
    // ------------------------------------------------------------------
    logic             valid_c1;
    logic [`DATA_BUS] rs1_data_c1;
    logic [`RF_BUS]   rs1_addr_c1;
    logic [`DATA_BUS] rs2_data_c1;
    logic [`RF_BUS]   rs2_addr_c1;
    logic [`DATA_BUS] imm_c1;
    logic [`DATA_BUS] mem_addr_c1;
    logic             mem_read_c1;
    logic             mem_write_c1;
    logic             reg_write_c1;
    logic             wb_src_c1;
    logic             is_rs2_imm_c1;
    logic [3:0]       inst_spec_c1;
    logic [3:0]       alu_ctrl_c1;
    logic [2:0]       func3_c1;
    logic [3:0]       mem_mask_c1;
    logic             load_unsigned_c1;
    logic             is_branch_c1;
    logic [`PC_BUS]   pc_c1;
    logic [`PC_BUS]   pc_target_c1;
    logic [`PC_BUS]   pc_predict_c1;
    logic             is_m_ext_c1;
    logic             predict_taken_c1;
    logic [`M_OP_BUS] m_op_c1;
    logic [11:0]      csr_addr_c1;

    reg_id_c1 u_reg_id_c1 (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (flush_c1),
        .i_hold          (hold_c1),
        .i_bubble        (bubble_c1),
        .i_valid         (valid_d && !mem_read_d && !mem_write_d),
        .i_rs1_data      (rs1_issue_d),
        .i_rs1_addr      (rs1_addr_d),
        .i_rs2_data      (rs2_issue_d),
        .i_rs2_addr      (rs2_addr_d),
        .i_rd_addr       (rd_addr_d),
        .i_imm           (imm_d),
        .i_mem_addr      (mem_addr_d),
        .i_mem_read      (mem_read_d),
        .i_mem_write     (mem_write_d),
        .i_reg_write     (reg_write_d),
        .i_wb_src        (wb_src_d),
        .i_is_rs2_imm    (is_rs2_imm_d),
        .i_inst_spec     (inst_spec_d),
        .i_alu_ctrl      (alu_ctrl_d),
        .i_func3         (func3_d),
        .i_mem_mask      (mem_mask_d),
        .i_load_unsigned (load_unsigned_d),
        .i_is_branch     (is_branch_d),
        .i_pc            (pc_d),
        .i_pc_target     (pc_target_d),
        .i_pc_predict    (pc_predict_d),
        .i_predict_taken (predict_taken_d),
        .i_is_m_ext      (is_m_ext_d),
        .i_m_op          (m_op_d),
        .i_csr_addr      (csr_addr_d),
        .o_valid         (valid_c1),
        .o_rs1_data      (rs1_data_c1),
        .o_rs1_addr      (rs1_addr_c1),
        .o_rs2_data      (rs2_data_c1),
        .o_rs2_addr      (rs2_addr_c1),
        .o_rd_addr       (rd_addr_c1),
        .o_imm           (imm_c1),
        .o_mem_addr      (mem_addr_c1),
        .o_mem_read      (mem_read_c1),
        .o_mem_write     (mem_write_c1),
        .o_reg_write     (reg_write_c1),
        .o_wb_src        (wb_src_c1),
        .o_is_rs2_imm    (is_rs2_imm_c1),
        .o_inst_spec     (inst_spec_c1),
        .o_alu_ctrl      (alu_ctrl_c1),
        .o_func3         (func3_c1),
        .o_mem_mask      (mem_mask_c1),
        .o_load_unsigned (load_unsigned_c1),
        .o_is_branch     (is_branch_c1),
        .o_pc            (pc_c1),
        .o_pc_target     (pc_target_c1),
        .o_pc_predict    (pc_predict_c1),
        .o_predict_taken (predict_taken_c1),
        .o_is_m_ext      (is_m_ext_c1),
        .o_m_op          (m_op_c1),
        .o_csr_addr      (csr_addr_c1)
    );

    logic             valid_ls;
    logic [`DATA_BUS] mem_addr_ls;
    logic [`DATA_BUS] store_data_ls;
    logic [3:0]       mem_mask_ls;
    logic             load_unsigned_ls;
    logic             mem_read_ls;
    logic             mem_write_ls;
    logic [`RF_BUS]   rd_addr_ls;
    logic             ls_busy;
    logic             ls_advance;
    logic [`DATA_BUS] ls_offset;
    logic             ls_addr_pending;
    logic [`RF_BUS]   ls_addr_dep_rd;
    logic             ls_data_pending;
    logic [`RF_BUS]   ls_data_dep_rd;
    logic             addr_pending_d;
    logic [`RF_BUS]   addr_dep_rd_d;
    logic             data_pending_d;
    logic [`RF_BUS]   data_dep_rd_d;
    logic             ls_operands_ready;
    logic [`DATA_BUS] resolved_mem_addr_ls;
    logic [`DATA_BUS] resolved_store_data_ls;
    logic             resolve_addr_ls;
    logic             resolve_data_ls;
    logic [`DATA_BUS] resolved_addr_capture_ls;
    logic [`DATA_BUS] resolved_data_capture_ls;
    logic             ls_waits_for_c1;
    logic             addr_dep_ex_match;
    logic             addr_dep_ls_match;
    logic             addr_dep_q1_match;
    logic             addr_dep_q0_match;
    logic             data_dep_ex_match;
    logic             data_dep_ls_match;
    logic             data_dep_q1_match;
    logic             data_dep_q0_match;
    logic [`DATA_BUS] pending_addr_base_ls;
    logic [`DATA_BUS] pending_store_data_ls;

    assign addr_pending_d = valid_d && (mem_read_d || mem_write_d) &&
                            ((valid_c1 && reg_write_c1 &&
                              (rd_addr_c1 != '0) &&
                              (rd_addr_c1 == rs1_addr_d)) ||
                             (valid_ls && mem_read_ls &&
                              (rd_addr_ls != '0) &&
                              (rd_addr_ls == rs1_addr_d)));
    assign addr_dep_rd_d = (valid_c1 && reg_write_c1 &&
                            (rd_addr_c1 == rs1_addr_d)) ?
                           rd_addr_c1 : rd_addr_ls;
    assign data_pending_d = valid_d && mem_write_d &&
                            ((valid_c1 && reg_write_c1 &&
                              (rd_addr_c1 != '0) &&
                              (rd_addr_c1 == rs2_addr_d)) ||
                             (valid_ls && mem_read_ls &&
                              (rd_addr_ls != '0) &&
                              (rd_addr_ls == rs2_addr_d)));
    assign data_dep_rd_d = (valid_c1 && reg_write_c1 &&
                            (rd_addr_c1 == rs2_addr_d)) ?
                           rd_addr_c1 : rd_addr_ls;

    reg_id_ls u_reg_id_ls (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush         (flush_c1),
        .i_hold          (ls_busy),
        .i_valid         (valid_d && (mem_read_d || mem_write_d) &&
                          !m_busy_c1),
        .i_mem_addr      (mem_addr_d),
        .i_store_data    (store_data_d),
        .i_offset        (imm_d),
        .i_addr_pending  (addr_pending_d),
        .i_addr_dep_rd   (addr_dep_rd_d),
        .i_data_pending  (data_pending_d),
        .i_data_dep_rd   (data_dep_rd_d),
        .i_resolve_addr  (resolve_addr_ls),
        .i_resolved_addr (resolved_addr_capture_ls),
        .i_resolve_data  (resolve_data_ls),
        .i_resolved_data (resolved_data_capture_ls),
        .i_mem_mask      (mem_mask_d),
        .i_load_unsigned (load_unsigned_d),
        .i_mem_read      (mem_read_d),
        .i_mem_write     (mem_write_d),
        .i_rd_addr       (rd_addr_d),
        .o_valid         (valid_ls),
        .o_mem_addr      (mem_addr_ls),
        .o_store_data    (store_data_ls),
        .o_offset        (ls_offset),
        .o_addr_pending  (ls_addr_pending),
        .o_addr_dep_rd   (ls_addr_dep_rd),
        .o_data_pending  (ls_data_pending),
        .o_data_dep_rd   (ls_data_dep_rd),
        .o_mem_mask      (mem_mask_ls),
        .o_load_unsigned (load_unsigned_ls),
        .o_mem_read      (mem_read_ls),
        .o_mem_write     (mem_write_ls),
        .o_rd_addr       (rd_addr_ls)
    );

    logic [`DATA_BUS] rs1_exec_c1;
    logic [`DATA_BUS] rs2_exec_c1;
    logic [`DATA_BUS] store_data_c1;
    logic             update_taken_c1;
    logic             update_en_c1;
    logic [`PC_BUS]   update_pc_c1;
    logic [`PC_BUS]   update_target_c1;
    logic             error_c1;
    logic [`PC_BUS]   right_pc_c1;
    logic             m_busy_c1;
    logic             mem_busy_c1;
    logic             c1_busy;
    logic             addr_dep;
    logic             c1_advance;

    assign rs1_exec_c1 = ex_wb_fire_c2 && (rd_addr_c2 == rs1_addr_c1) ?
                         ex_wb_data_c2 :
                         (ls_wb_fire_c2 && (ls_wb_rd_addr == rs1_addr_c1) ?
                          ls_wb_data_c2 :
                          (wbq1_valid && (wbq1_rd == rs1_addr_c1) ?
                           wbq1_data :
                           (wbq0_valid && (wbq0_rd == rs1_addr_c1) ?
                            wbq0_data : rs1_data_c1)));
    assign rs2_exec_c1 = ex_wb_fire_c2 && (rd_addr_c2 == rs2_addr_c1) ?
                         ex_wb_data_c2 :
                         (ls_wb_fire_c2 && (ls_wb_rd_addr == rs2_addr_c1) ?
                          ls_wb_data_c2 :
                          (wbq1_valid && (wbq1_rd == rs2_addr_c1) ?
                           wbq1_data :
                           (wbq0_valid && (wbq0_rd == rs2_addr_c1) ?
                            wbq0_data : rs2_data_c1)));

    stage_ex u_stage_ex (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_flush_e       (1'b0),
        .i_stall_e       (c1_busy),
        .i_rs1_data      (rs1_exec_c1),
        .i_rs2_data      (rs2_exec_c1),
        .i_imm           (imm_c1),
        .i_pc            (pc_c1),
        .i_fwd_e_m       ('0),
        .i_fwd_m_w       ('0),
        .i_fwd_m_m       ('0),
        .i_pc_d_e        (pc_c1),
        .i_pc_target     (pc_target_c1),
        .i_pc_predict    (pc_predict_c1),
        .i_predict_taken (predict_taken_c1),
        .i_rs1_fwd_sel   (`FWD_RF),
        .i_rs2_fwd_sel   (`FWD_RF),
        .i_alu_ctrl      (alu_ctrl_c1),
        .i_func3         (func3_c1),
        .i_is_branch     (valid_c1 && is_branch_c1),
        .i_is_rs2_imm    (is_rs2_imm_c1),
        .i_inst_spec     (valid_c1 ? inst_spec_c1 : 4'b0000),
        .i_is_m_ext      (valid_c1 && is_m_ext_c1),
        .i_m_op          (m_op_c1),
        .i_csr_addr      (csr_addr_c1),
        .o_alu_res       (alu_res_c1),
        .o_a2_data       (store_data_c1),
        .o_update_taken  (update_taken_c1),
        .o_update_en     (update_en_c1),
        .o_update_pc     (update_pc_c1),
        .o_update_target (update_target_c1),
        .o_error         (error_c1),
        .o_right_pc      (right_pc_c1),
        .o_m_busy        (m_busy_c1)
    );

    assign addr_dep_ex_match = ex_wb_fire_c2 &&
                               (rd_addr_c2 == ls_addr_dep_rd);
    assign addr_dep_ls_match = ls_wb_fire_c2 &&
                               (ls_wb_rd_addr == ls_addr_dep_rd);
    assign addr_dep_q1_match = wbq1_valid &&
                               (wbq1_rd == ls_addr_dep_rd);
    assign addr_dep_q0_match = wbq0_valid &&
                               (wbq0_rd == ls_addr_dep_rd);
    assign data_dep_ex_match = ex_wb_fire_c2 &&
                               (rd_addr_c2 == ls_data_dep_rd);
    assign data_dep_ls_match = ls_wb_fire_c2 &&
                               (ls_wb_rd_addr == ls_data_dep_rd);
    assign data_dep_q1_match = wbq1_valid &&
                               (wbq1_rd == ls_data_dep_rd);
    assign data_dep_q0_match = wbq0_valid &&
                               (wbq0_rd == ls_data_dep_rd);
    assign pending_addr_base_ls = addr_dep_ex_match ?
                                   ex_wb_data_c2 :
                                   (addr_dep_ls_match ? ls_wb_data_c2 :
                                    (addr_dep_q1_match ? wbq1_data : wbq0_data));
    assign pending_store_data_ls = data_dep_ex_match ?
                                    ex_wb_data_c2 :
                                    (data_dep_ls_match ? ls_wb_data_c2 :
                                     (data_dep_q1_match ? wbq1_data : wbq0_data));
    // A wakeup only resolves the held LS slot on this edge. It cannot make a
    // request or alter global ready/CE until the resolved operand is registered
    // and its pending bit is clear on the following cycle.
    assign ls_operands_ready = !ls_addr_pending && !ls_data_pending;
    assign resolve_addr_ls = ls_addr_pending &&
                             (addr_dep_ex_match || addr_dep_ls_match ||
                              addr_dep_q1_match || addr_dep_q0_match);
    assign resolve_data_ls = ls_data_pending &&
                             (data_dep_ex_match || data_dep_ls_match ||
                              data_dep_q1_match || data_dep_q0_match);
    assign resolved_addr_capture_ls = pending_addr_base_ls + ls_offset;
    assign resolved_data_capture_ls = pending_store_data_ls;
    assign resolved_mem_addr_ls = mem_addr_ls;
    assign resolved_store_data_ls = store_data_ls;

    assign dram_wen   = valid_ls && ls_operands_ready && mem_write_ls;
    assign dram_ren   = valid_ls && ls_operands_ready && mem_read_ls;
    assign dram_addr  = resolved_mem_addr_ls;
    assign dram_wdata = resolved_store_data_ls;
    assign dram_mask  = mem_mask_ls;

    assign ls_busy      = valid_ls &&
                          (!ls_operands_ready || !dram_req_ready);
    assign mem_busy_c1  = ls_busy;
    assign ls_waits_for_c1 = valid_c1 && reg_write_c1 &&
                             (rd_addr_c1 != '0) &&
                             ((ls_addr_pending &&
                               (ls_addr_dep_rd == rd_addr_c1)) ||
                              (ls_data_pending &&
                               (ls_data_dep_rd == rd_addr_c1)));

    assign c1_busy      = m_busy_c1 ||
                          (ls_busy && !ls_waits_for_c1);
    assign c1_advance   = valid_c1 && !c1_busy;
    assign ls_advance   = valid_ls && ls_operands_ready && dram_req_ready;
    // Keep all AGU dependencies on the registered WB path.  The direct
    // C1-ALU-to-C0-AGU bypass is intentionally removed to break the feedback
    // path identified by routed timing.
    assign c1_agu_forwardable = 1'b0;

    // A C0 memory address cannot consume a result still being generated in C1
    // without creating an EX/Cache-to-AGU combinational path. Insert one bubble;
    // on the following cycle the value is available from the registered C2 path.
    assign addr_dep = 1'b0;

    hazard_unit u_hazard_unit (
        .i_pc_cur         (pc_p),
        .i_predict_taken  (predict_taken_f),
        .i_predict_target (predict_target_f),
        .i_error          (valid_c1 && error_c1),
        .i_right_pc       (right_pc_c1),
        .i_c1_busy        (c1_busy),
        .i_front_busy     (m_busy_c1 || ls_busy),
        .i_addr_dep       (addr_dep),
        .o_stall_front    (stall_front),
        .o_flush_front    (flush_front),
        .o_flush_c1       (flush_c1),
        .o_hold_c1        (hold_c1),
        .o_bubble_c1      (bubble_c1),
        .o_pc_next        (pc_next),
        .o_pc_predict     (pc_predict_p)
    );

    bpu_top u_bpu_top (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_pc_cur        (pc_p),
        .i_update_en     (valid_c1 && update_en_c1),
        .i_update_taken  (update_taken_c1),
        .i_update_target (update_target_c1),
        .i_update_pc     (update_pc_c1),
        .o_predict_taken (predict_taken_f),
        .o_predict_target(predict_target_f)
    );

    // ------------------------------------------------------------------
    // C2: registered metadata, load formatting and write-back.
    // ------------------------------------------------------------------
    reg_c1_c2 u_reg_c1_c2 (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_valid         (c1_advance),
        .i_rd_addr       (rd_addr_c1),
        .i_alu_res       (alu_res_c1),
        .i_wb_src        (wb_src_c1),
        .i_reg_write     (valid_c1 && reg_write_c1),
        .i_mem_mask      (mem_mask_c1),
        .i_load_unsigned (load_unsigned_c1),
        .o_valid         (valid_c2),
        .o_rd_addr       (rd_addr_c2),
        .o_alu_res       (alu_res_c2),
        .o_wb_src        (wb_src_c2),
        .o_reg_write     (reg_write_c2),
        .o_mem_mask      (mem_mask_c2),
        .o_load_unsigned (load_unsigned_c2)
    );

    reg_ls_wb u_reg_ls_wb (
        .i_clk           (clk),
        .i_rst_n         (rst_n),
        .i_valid         (ls_advance && mem_read_ls && (rd_addr_ls != '0)),
        .i_rd_addr       (rd_addr_ls),
        .i_mem_mask      (mem_mask_ls),
        .i_load_unsigned (load_unsigned_ls),
        .o_valid         (ls_wb_valid),
        .o_rd_addr       (ls_wb_rd_addr),
        .o_mem_mask      (ls_wb_mem_mask),
        .o_load_unsigned (ls_wb_load_unsigned)
    );

    // DCache registers the aligned and extended load value.  Keeping the
    // formatter on the cache-register input avoids placing it in series with
    // the C2 bypass and the next instruction's C0 AGU.
    stage_m2 u_stage_m2 (
        .i_mem_mask      (ls_wb_mem_mask),
        .i_load_unsigned (ls_wb_load_unsigned),
        .i_dram_rdata    (dram_rdata),
        .o_mem_rdata     (ls_mem_data)
    );

    stage_wb u_stage_wb (
        .i_alu_res  (alu_res_c2),
        .i_mem_data (mem_data_c2),
        .i_wb_src   (wb_src_c2),
        .o_wb_data  (ex_wb_data_c2)
    );

    assign ls_wb_data_c2 = ls_mem_data;

`ifdef VERILATOR_TB
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_perf_commit         <= 64'd0;
            dbg_perf_branch         <= 64'd0;
            dbg_perf_branch_miss    <= 64'd0;
            dbg_perf_load           <= 64'd0;
            dbg_perf_store          <= 64'd0;
            dbg_perf_stall_front    <= 64'd0;
            dbg_perf_stall_muldiv   <= 64'd0;
            dbg_perf_stall_load_use <= 64'd0;
        end else begin
            if (valid_c2 || ls_wb_valid ||
                (ls_advance && mem_write_ls)) begin
                dbg_perf_commit <= dbg_perf_commit +
                                   (valid_c2 ? 64'd1 : 64'd0) +
                                   (ls_wb_valid ? 64'd1 : 64'd0) +
                                   ((ls_advance && mem_write_ls) ?
                                    64'd1 : 64'd0);
            end
            if (valid_c1 && update_en_c1 && !c1_busy) begin
                dbg_perf_branch <= dbg_perf_branch + 64'd1;
                if (error_c1) begin
                    dbg_perf_branch_miss <= dbg_perf_branch_miss + 64'd1;
                end
            end
            if (ls_advance && mem_read_ls) begin
                dbg_perf_load <= dbg_perf_load + 64'd1;
            end
            if (ls_advance && mem_write_ls) begin
                dbg_perf_store <= dbg_perf_store + 64'd1;
            end
            if (stall_front) begin
                dbg_perf_stall_front <= dbg_perf_stall_front + 64'd1;
            end
            if (m_busy_c1) begin
                dbg_perf_stall_muldiv <= dbg_perf_stall_muldiv + 64'd1;
            end
            if (addr_dep && !c1_busy) begin
                dbg_perf_stall_load_use <= dbg_perf_stall_load_use + 64'd1;
            end
        end
    end
`endif

endmodule
