//==============================================================================
// 模块: stage_ex
// 功能概述：
//   执行（EX）级顶层。根据前递选择信号从 rs1/rs2/imm/pc、EX/M、M/W 结果中选择操作数，送 ALU；
//   分支类指令配合 branch_cmp 产生是否更新预测表、正确目标等；输出 ALU 结果供 MEM/WB 使用。
//   RV32M：通过 m_unit 处理多周期乘除，m_busy 通知 hazard_unit 冻结流水线。
//   CSR/ecall/ebreak/mret：通过内部 csr_file 实现，ecall/mret 复用 o_error 机制跳转。
//==============================================================================
`include "cpu_defines.svh"

module stage_ex(
    input  logic                            i_clk,
    input  logic                            i_rst_n,
    input  logic                            i_flush_e,
    input  logic                            i_stall_e,

    input  logic  [`DATA_BUS]               i_rs1_data,
    input  logic  [`DATA_BUS]               i_rs2_data,
    input  logic  [`RF_BUS]                 i_rs1_addr,
    input  logic  [`RF_BUS]                 i_rs2_addr,
    input  logic  [`DATA_BUS]               i_imm,
    input  logic  [`PC_BUS]                 i_pc,
    input  logic  [`DATA_BUS]               i_fwd_e_m,
    input  logic                            i_fwd_mem_read_m,
    input  logic                            i_fwd_load_m_valid,
    input  logic  [`DATA_BUS]               i_fwd_load_m,
    input  logic  [`DATA_BUS]               i_fwd_m_w,
    input  logic  [`DATA_BUS]               i_fwd_m_m,
    input  logic  [`RF_BUS]                 i_fwd_rd_m,
    input  logic                            i_fwd_reg_write_m,
    input  logic  [`RF_BUS]                 i_fwd_rd_m2,
    input  logic                            i_fwd_reg_write_m2,
    input  logic  [`RF_BUS]                 i_fwd_rd_w,
    input  logic                            i_fwd_reg_write_w,

    input  logic  [`PC_BUS]                 i_pc_d_e,
    input  logic  [`PC_BUS]                 i_pc_target,
    input  logic  [`PC_BUS]                 i_pc_predict,

    input  logic  [1:0]                     i_rs1_fwd_sel,
    input  logic  [1:0]                     i_rs2_fwd_sel,

    input  logic  [3:0]                     i_alu_ctrl,
    input  logic  [2:0]                     i_func3,

    input  logic                            i_is_branch,
    input  logic                            i_is_rs2_imm,
    input  logic  [3:0]                     i_inst_spec,

    input  logic                            i_is_m_ext,
    input  logic  [`M_OP_BUS]               i_m_op,

    input  logic  [11:0]                    i_csr_addr,

    input  logic  [`RF_BUS]                 i_rd_addr,
    input  logic                            i_mem_read,
    input  logic                            i_mem_write,
    input  logic                            i_wb_src,
    input  logic                            i_reg_write,
    input  logic  [3:0]                     i_mem_mask,
    input  logic                            i_load_unsigned,

    output logic  [`DATA_BUS]               o_alu_res,
    output logic  [`DATA_BUS]               o_a2_data,

    output logic  [`RF_BUS]                 o_rd_addr,
    output logic                            o_mem_read,
    output logic                            o_mem_write,
    output logic                            o_wb_src,
    output logic                            o_reg_write,
    output logic  [3:0]                     o_mem_mask,
    output logic                            o_load_unsigned,

    output logic                            o_update_taken,
    output logic                            o_update_en,
    output logic  [`PC_BUS]                 o_update_pc,
    output logic  [`PC_BUS]                 o_update_target,
    output logic                            o_error,

    output logic                            o_m_busy,
    output logic                            o_is_mul,
    output logic  [`M_OP_BUS]               o_m_op,
    output logic                            o_mul_result_valid,
    output logic  [`DATA_BUS]               o_mul_result
);

    logic [`DATA_BUS] a1_data;
    logic [`DATA_BUS] a2_data;
    logic [`DATA_BUS] rs1_exec_mux;
    logic [`DATA_BUS] rs2_exec_mux;
    logic [`DATA_BUS] stalled_rs1_q;
    logic [`DATA_BUS] stalled_rs2_q;
    logic             stalled_operands_valid_q;
    logic [`DATA_BUS] rs1_exec_q;
    logic [`DATA_BUS] rs2_exec_q;
    // These buses feed several physically separated EX2 consumers.  Keep
    // their synthesized fanout bounded so Vivado duplicates the late-bypass
    // muxes close to ALU/branch/hold consumers instead of routing one shared
    // high-fanout result across the whole execute region.
    (* max_fanout = 16 *) logic [`DATA_BUS] rs1_exec_final;
    (* max_fanout = 16 *) logic [`DATA_BUS] rs2_exec_final;
    logic [`RF_BUS]   rs1_addr_q;
    logic [`RF_BUS]   rs2_addr_q;
    logic [`DATA_BUS] imm_q;
    logic [`PC_BUS]   pc_q;
    logic [`PC_BUS]   pc_d_e_q;
    logic [`PC_BUS]   pc_target_q;
    logic [`PC_BUS]   pc_predict_q;
    logic [3:0]       alu_ctrl_q;
    logic [2:0]       func3_q;
    logic             is_branch_q;
    logic             is_rs2_imm_q;
    logic [3:0]       inst_spec_q;
    logic             is_m_ext_q;
    logic [`M_OP_BUS] m_op_q;
    logic [11:0]      csr_addr_q;
    logic [`RF_BUS]   rd_addr_q;
    logic             mem_read_q;
    logic             mem_write_q;
    logic             wb_src_q;
    logic             reg_write_q;
    logic [3:0]       mem_mask_q;
    logic             load_unsigned_q;
    logic [`PC_BUS]   t1_data;
    logic [`DATA_BUS] alu_res_raw;

    // ---- Forwarding mux ----
    always_comb begin
        // EX2 may forward only into the EX1 operand registers.  This keeps the
        // consumer ALU behind a register boundary while avoiding conservative
        // ALU-to-ALU dependency stalls. Loads are excluded because their final
        // value is not available until the memory pipeline.
        if (reg_write_q && !mem_read_q && (rd_addr_q != '0) &&
            (rd_addr_q == i_rs1_addr)) begin
            rs1_exec_mux = o_alu_res;
        end else if (i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
                     (i_fwd_rd_m == i_rs1_addr)) begin
            rs1_exec_mux = i_fwd_e_m;
        end else if (i_fwd_reg_write_m2 && (i_fwd_rd_m2 != '0) &&
                     (i_fwd_rd_m2 == i_rs1_addr)) begin
            rs1_exec_mux = i_fwd_m_m;
        end else if (i_fwd_reg_write_w && (i_fwd_rd_w != '0) &&
                     (i_fwd_rd_w == i_rs1_addr)) begin
            rs1_exec_mux = i_fwd_m_w;
        end else begin
            rs1_exec_mux = stalled_operands_valid_q ? stalled_rs1_q : i_rs1_data;
        end
        if (reg_write_q && !mem_read_q && (rd_addr_q != '0) &&
            (rd_addr_q == i_rs2_addr)) begin
            rs2_exec_mux = o_alu_res;
        end else if (i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
                     (i_fwd_rd_m == i_rs2_addr)) begin
            rs2_exec_mux = i_fwd_e_m;
        end else if (i_fwd_reg_write_m2 && (i_fwd_rd_m2 != '0) &&
                     (i_fwd_rd_m2 == i_rs2_addr)) begin
            rs2_exec_mux = i_fwd_m_m;
        end else if (i_fwd_reg_write_w && (i_fwd_rd_w != '0) &&
                     (i_fwd_rd_w == i_rs2_addr)) begin
            rs2_exec_mux = i_fwd_m_w;
        end else begin
            rs2_exec_mux = stalled_operands_valid_q ? stalled_rs2_q : i_rs2_data;
        end

        // With one load-use bubble the consumer reaches EX2 in the same cycle
        // that the producer's registered response is present in M2.  Override
        // the EX1-captured operand here.  A matching M1 producer is younger
        // than M2 and therefore suppresses the override.
        rs1_exec_final = rs1_exec_q;
        if (i_fwd_load_m_valid && i_fwd_mem_read_m &&
            i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
            (i_fwd_rd_m == rs1_addr_q)) begin
            rs1_exec_final = i_fwd_load_m;
        end else if (i_fwd_reg_write_m2 && (i_fwd_rd_m2 != '0) &&
            (i_fwd_rd_m2 == rs1_addr_q) &&
            !(i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
              (i_fwd_rd_m == rs1_addr_q))) begin
            rs1_exec_final = i_fwd_m_m;
        end else if (i_fwd_reg_write_w && (i_fwd_rd_w != '0) &&
                     (i_fwd_rd_w == rs1_addr_q) &&
                     !(i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
                       (i_fwd_rd_m == rs1_addr_q))) begin
            rs1_exec_final = i_fwd_m_w;
        end

        rs2_exec_final = rs2_exec_q;
        if (i_fwd_load_m_valid && i_fwd_mem_read_m &&
            i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
            (i_fwd_rd_m == rs2_addr_q)) begin
            rs2_exec_final = i_fwd_load_m;
        end else if (i_fwd_reg_write_m2 && (i_fwd_rd_m2 != '0) &&
            (i_fwd_rd_m2 == rs2_addr_q) &&
            !(i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
              (i_fwd_rd_m == rs2_addr_q))) begin
            rs2_exec_final = i_fwd_m_m;
        end else if (i_fwd_reg_write_w && (i_fwd_rd_w != '0) &&
                     (i_fwd_rd_w == rs2_addr_q) &&
                     !(i_fwd_reg_write_m && (i_fwd_rd_m != '0) &&
                       (i_fwd_rd_m == rs2_addr_q))) begin
            rs2_exec_final = i_fwd_m_w;
        end

        t1_data = (inst_spec_q == `EX_JALR) ? rs1_exec_final : pc_d_e_q;
        a1_data = (inst_spec_q == `EX_AUIPC) ? pc_q : rs1_exec_final;
        a2_data = (is_rs2_imm_q || (inst_spec_q == `EX_AUIPC)) ? imm_q : rs2_exec_final;
    end

    // A long M operation or memory backpressure holds ID/EX while older
    // producers continue through WB. Capture the fully forwarded incoming
    // operands on the first hold cycle so their source cannot disappear before
    // EX1 is finally allowed to accept the instruction.
    always_ff @(posedge i_clk) begin
        if (!i_rst_n || i_flush_e) begin
            stalled_rs1_q            <= '0;
            stalled_rs2_q            <= '0;
            stalled_operands_valid_q <= 1'b0;
        end else if (i_stall_e) begin
            stalled_rs1_q            <= rs1_exec_mux;
            stalled_rs2_q            <= rs2_exec_mux;
            stalled_operands_valid_q <= 1'b1;
        end else if (!i_stall_e) begin
            stalled_operands_valid_q <= 1'b0;
        end
    end

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            rs1_exec_q       <= '0;
            rs2_exec_q       <= '0;
            rs1_addr_q       <= '0;
            rs2_addr_q       <= '0;
            imm_q            <= '0;
            pc_q             <= '0;
            pc_d_e_q         <= '0;
            pc_target_q      <= '0;
            pc_predict_q     <= '0;
            alu_ctrl_q       <= `ALU_ADD;
            func3_q          <= '0;
            is_branch_q      <= 1'b0;
            is_rs2_imm_q     <= 1'b0;
            inst_spec_q      <= '0;
            is_m_ext_q       <= 1'b0;
            m_op_q           <= '0;
            csr_addr_q       <= '0;
            rd_addr_q        <= '0;
            mem_read_q       <= 1'b0;
            mem_write_q      <= 1'b0;
            wb_src_q         <= `WB_SRC_ALU;
            reg_write_q      <= 1'b0;
            mem_mask_q       <= `MASK_WORD;
            load_unsigned_q  <= 1'b0;
        end else if (i_flush_e) begin
            rs1_exec_q       <= '0;
            rs2_exec_q       <= '0;
            rs1_addr_q       <= '0;
            rs2_addr_q       <= '0;
            imm_q            <= '0;
            pc_q             <= '0;
            pc_d_e_q         <= '0;
            pc_target_q      <= '0;
            pc_predict_q     <= '0;
            alu_ctrl_q       <= `ALU_ADD;
            func3_q          <= '0;
            is_branch_q      <= 1'b0;
            is_rs2_imm_q     <= 1'b0;
            inst_spec_q      <= '0;
            is_m_ext_q       <= 1'b0;
            m_op_q           <= '0;
            csr_addr_q       <= '0;
            rd_addr_q        <= '0;
            mem_read_q       <= 1'b0;
            mem_write_q      <= 1'b0;
            wb_src_q         <= `WB_SRC_ALU;
            reg_write_q      <= 1'b0;
            mem_mask_q       <= `MASK_WORD;
            load_unsigned_q  <= 1'b0;
        end else if (i_stall_e) begin
            // Keep the current EX2 instruction in place, but refresh operands
            // as older producers become available through late forwarding.
            rs1_exec_q       <= rs1_exec_final;
            rs2_exec_q       <= rs2_exec_final;
        end else begin
            rs1_exec_q       <= rs1_exec_mux;
            rs2_exec_q       <= rs2_exec_mux;
            rs1_addr_q       <= i_rs1_addr;
            rs2_addr_q       <= i_rs2_addr;
            imm_q            <= i_imm;
            pc_q             <= i_pc;
            pc_d_e_q         <= i_pc_d_e;
            pc_target_q      <= i_pc_target;
            pc_predict_q     <= i_pc_predict;
            alu_ctrl_q       <= i_alu_ctrl;
            func3_q          <= i_func3;
            is_branch_q      <= i_is_branch;
            is_rs2_imm_q     <= i_is_rs2_imm;
            inst_spec_q      <= i_inst_spec;
            is_m_ext_q       <= i_is_m_ext;
            m_op_q           <= i_m_op;
            csr_addr_q       <= i_csr_addr;
            rd_addr_q        <= i_rd_addr;
            mem_read_q       <= i_mem_read;
            mem_write_q      <= i_mem_write;
            wb_src_q         <= i_wb_src;
            reg_write_q      <= i_reg_write;
            mem_mask_q       <= i_mem_mask;
            load_unsigned_q  <= i_load_unsigned;
        end
    end

    // ---- ALU ----
    alu u_alu (
        .i_alu1     (a1_data),
        .i_alu2     (a2_data),
        .i_alu_ctrl (alu_ctrl_q),
        .o_alu_res  (alu_res_raw)
    );

    // ---- Branch unit (produces branch redirect) ----
    logic            branch_error;
    logic [`PC_BUS]  branch_update_target;

    branch_cmp u_branch_cmp (
        .i_b1_data       (rs1_exec_final),
        .i_b2_data       (rs2_exec_final),
        .i_func3         (func3_q),
        .i_pc_d_e        (pc_d_e_q),
        .i_pc_target     (pc_target_q),
        .i_pc_predict    (pc_predict_q),
        .i_t1_data       (t1_data),
        .i_t2_data       (imm_q),
        .i_is_branch     (is_branch_q),
        .i_inst_spec     (inst_spec_q),
        .o_update_taken  (o_update_taken),
        .o_update_en     (o_update_en),
        .o_update_pc     (o_update_pc),
        .o_update_target (branch_update_target),
        .o_error         (branch_error),
        .o_right_pc      ()
    );

    // ---- M extension ----
    logic             m_start_pulse;
    logic             m_busy_int, m_done_int;
    logic [`DATA_BUS] m_res;
    logic             m_issued;
    logic signed [32:0] mul_a;
    logic signed [32:0] mul_b;
    logic signed [65:0] mul_product;
    logic               is_div_q;
    logic               mul_issue;
    logic [2:0]         mul_valid_pipe;
    logic [`M_OP_BUS]  mul_op_pipe [0:2];

    assign is_div_q      = is_m_ext_q && m_op_q[2];
    assign m_start_pulse = is_div_q && !m_busy_int && !m_issued;
    assign o_m_busy      = is_div_q && !m_done_int;
    assign o_is_mul      = is_m_ext_q && !m_op_q[2];
    assign o_m_op        = m_op_q;
    assign mul_issue     = o_is_mul && !i_stall_e && !i_flush_e;

    // A single signed 33x33 multiplier covers all RV32M multiply variants by
    // selecting sign/zero extension before the IP.  MUL_0 remains the same
    // three-stage IP configured in the Vivado Tcl and Verilator model.
    assign mul_a = (m_op_q == `M_MULHU) ? {1'b0, rs1_exec_final} :
                                           {rs1_exec_final[31], rs1_exec_final};
    assign mul_b = ((m_op_q == `M_MUL) || (m_op_q == `M_MULH)) ?
                   {rs2_exec_final[31], rs2_exec_final} :
                   {1'b0, rs2_exec_final};

    MUL_0 u_mul_pipe (
        .CLK (i_clk),
        .A   (mul_a),
        .B   (mul_b),
        .P   (mul_product)
    );

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            mul_valid_pipe <= '0;
            mul_op_pipe[0] <= '0;
            mul_op_pipe[1] <= '0;
            mul_op_pipe[2] <= '0;
        end else begin
            mul_valid_pipe[0] <= mul_issue;
            mul_valid_pipe[1] <= mul_valid_pipe[0];
            mul_valid_pipe[2] <= mul_valid_pipe[1];
            mul_op_pipe[0] <= m_op_q;
            mul_op_pipe[1] <= mul_op_pipe[0];
            mul_op_pipe[2] <= mul_op_pipe[1];
        end
    end

    assign o_mul_result_valid = mul_valid_pipe[2];
    assign o_mul_result = (mul_op_pipe[2] == `M_MUL) ? mul_product[31:0] :
                                                           mul_product[63:32];

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            m_issued <= 1'b0;
        end else if (i_flush_e || m_done_int || !is_div_q) begin
            m_issued <= 1'b0;
        end else if (m_start_pulse) begin
            m_issued <= 1'b1;
        end
    end

    m_unit u_m_unit (
        .i_clk   (i_clk),
        .i_rst_n (i_rst_n),
        .i_start (m_start_pulse),
        .i_flush (i_flush_e),
        .i_rs1   (rs1_exec_final),
        .i_rs2   (rs2_exec_final),
        .i_m_op  (m_op_q),
        .o_busy  (m_busy_int),
        .o_done  (m_done_int),
        .o_res   (m_res)
    );

    // ---- CSR file ----
    logic [31:0] csr_rdata;
    logic [31:0] csr_wdata_next;
    logic        csr_we;
    logic [1:0]  csr_wmode;       // 00=write, 01=set, 10=clear
    logic [31:0] mtvec_val;
    logic [31:0] mepc_val;

    // 判断是否需要写CSR：CSRRW/CSRRWI 始终写；CSRRS/CSRRC/I 变体仅当操作数非零时写
    logic        is_csr_inst;
    logic [31:0] csr_operand;     // CSR操作数：rs1（非立即数版）或zimm（立即数版）

    assign is_csr_inst = (inst_spec_q == `EX_CSR);

    // func3[2]=1 时为立即数版本；i_imm 已由 imm_unit 计算为 {27'b0, instr[19:15]}
    assign csr_operand = (func3_q[2]) ? imm_q : rs1_exec_final;

    // wmode: func3[1:0] - 1 → 01→00(write), 10→01(set), 11→10(clear)
    assign csr_wmode = func3_q[1:0] - 2'b01;

    // 只有 CSRRS/CSRRC（及立即数变体）在操作数为0时跳过写
    logic csr_skip_write;
    assign csr_skip_write = (func3_q[1:0] != 2'b01) && (csr_operand == 32'h0);
    assign csr_we = is_csr_inst && !csr_skip_write;

    // ecall/ebreak/mret 检测
    logic is_ecall, is_ebreak, is_mret;
    assign is_ecall  = (inst_spec_q == `EX_ECALL);
    assign is_ebreak = (inst_spec_q == `EX_EBREAK);
    assign is_mret   = (inst_spec_q == `EX_MRET);

    // ecall mcause: M-mode ecall = 11, ebreak = 3
    logic [31:0] trap_cause;
    assign trap_cause = is_ecall ? 32'd11 : 32'd3;

    csr_file u_csr_file (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        // 读
        .i_raddr      (csr_addr_q),
        .o_rdata      (csr_rdata),
        // 写
        .i_we         (csr_we),
        .i_waddr      (csr_addr_q),
        .i_wdata      (csr_operand),
        .i_wmode      (csr_wmode),
        // Trap 入口
        .i_trap_en    (is_ecall || is_ebreak),
        .i_trap_pc    (pc_q),           // EX2 PC = ecall 指令地址
        .i_trap_cause (trap_cause),
        // Trap 返回
        .i_mret_en    (is_mret),
        // 直接输出
        .o_mtvec      (mtvec_val),
        .o_mepc       (mepc_val)
    );

    // ---- 重定向逻辑（复用 o_error/o_update_target 机制）----
    // ecall/ebreak → 跳 mtvec；mret → 跳 mepc；分支误预测 → 跳 branch target
    // 优先级：ecall/ebreak > mret > branch（实际上不会同时有多个）
    always_comb begin
        if (is_ecall || is_ebreak) begin
            o_error     = 1'b1;
            o_update_target = mtvec_val;
        end else if (is_mret) begin
            o_error     = 1'b1;
            o_update_target = mepc_val;
        end else begin
            o_error     = branch_error;
            o_update_target = branch_update_target;
        end
    end

    // ---- EX2 metadata / result outputs ----
    assign o_rd_addr       = rd_addr_q;
    assign o_mem_read      = mem_read_q;
    assign o_mem_write     = mem_write_q;
    assign o_wb_src        = wb_src_q;
    assign o_reg_write     = reg_write_q;
    assign o_mem_mask      = mem_mask_q;
    assign o_load_unsigned = load_unsigned_q;

    always_comb begin
        o_a2_data = rs2_exec_final;

        if (is_div_q) begin
            o_alu_res = m_res;
        end else if (o_is_mul) begin
            o_alu_res = 32'd0;
        end else if (is_csr_inst) begin
            o_alu_res = csr_rdata;   // rd ← 旧 CSR 值
        end else begin
            unique case (inst_spec_q)
                `EX_LUI:          o_alu_res = imm_q;
                `EX_JAL,
                `EX_JALR:         o_alu_res = pc_q + 32'd4;
                `EX_ECALL,
                `EX_EBREAK,
                `EX_MRET:         o_alu_res = 32'h0;  // 不写 rd
                default:          o_alu_res = alu_res_raw;
            endcase
        end
    end

endmodule
