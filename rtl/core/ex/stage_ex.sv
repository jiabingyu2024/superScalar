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

    input  logic  [`DATA_BUS]               i_rs1_data,
    input  logic  [`DATA_BUS]               i_rs2_data,
    input  logic  [`DATA_BUS]               i_imm,
    input  logic  [`PC_BUS]                 i_pc,
    input  logic  [`DATA_BUS]               i_fwd_e_m,
    input  logic  [`DATA_BUS]               i_fwd_m_w,
    input  logic  [`DATA_BUS]               i_fwd_m_m,

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

    output logic  [`DATA_BUS]               o_alu_res,
    output logic  [`DATA_BUS]               o_a2_data,

    output logic                            o_update_taken,
    output logic                            o_update_en,
    output logic  [`PC_BUS]                 o_update_pc,
    output logic  [`PC_BUS]                 o_update_target,
    output logic                            o_error,
    output logic  [`PC_BUS]                 o_right_pc,

    output logic                            o_m_busy
);

    logic [`DATA_BUS] a1_data;
    logic [`DATA_BUS] a2_data;
    logic [`DATA_BUS] rs1_exec_data;
    logic [`DATA_BUS] rs2_exec_data;
    logic [`PC_BUS]   t1_data;
    logic [`DATA_BUS] alu_res_raw;

    // ---- Forwarding mux ----
    always_comb begin
        unique case (i_rs1_fwd_sel)
            `FWD_E_M:  rs1_exec_data = i_fwd_e_m;
            `FWD_M_M:  rs1_exec_data = i_fwd_m_m;
            `FWD_M_W:  rs1_exec_data = i_fwd_m_w;
            default:   rs1_exec_data = i_rs1_data;
        endcase
        unique case (i_rs2_fwd_sel)
            `FWD_E_M:  rs2_exec_data = i_fwd_e_m;
            `FWD_M_M:  rs2_exec_data = i_fwd_m_m;
            `FWD_M_W:  rs2_exec_data = i_fwd_m_w;
            default:   rs2_exec_data = i_rs2_data;
        endcase
        t1_data = (i_inst_spec == `EX_JALR) ? rs1_exec_data : i_pc_d_e;
        a1_data = (i_inst_spec == `EX_AUIPC) ? i_pc : rs1_exec_data;
        a2_data = (i_is_rs2_imm || (i_inst_spec == `EX_AUIPC)) ? i_imm : rs2_exec_data;
    end

    // ---- ALU ----
    alu u_alu (
        .i_alu1     (a1_data),
        .i_alu2     (a2_data),
        .i_alu_ctrl (i_alu_ctrl),
        .o_alu_res  (alu_res_raw)
    );

    // ---- Branch unit (produces branch redirect) ----
    logic            branch_error;
    logic [`PC_BUS]  branch_right_pc;

    branch_cmp u_branch_cmp (
        .i_b1_data       (rs1_exec_data),
        .i_b2_data       (rs2_exec_data),
        .i_func3         (i_func3),
        .i_pc_d_e        (i_pc_d_e),
        .i_pc_target     (i_pc_target),
        .i_pc_predict    (i_pc_predict),
        .i_t1_data       (t1_data),
        .i_t2_data       (i_imm),
        .i_is_branch     (i_is_branch),
        .i_inst_spec     (i_inst_spec),
        .o_update_taken  (o_update_taken),
        .o_update_en     (o_update_en),
        .o_update_pc     (o_update_pc),
        .o_update_target (o_update_target),
        .o_error         (branch_error),
        .o_right_pc      (branch_right_pc)
    );

    // ---- M extension ----
    logic             m_start_pulse;
    logic             m_busy_int, m_done_int;
    logic [`DATA_BUS] m_res;
    logic             m_issued;

    assign m_start_pulse = i_is_m_ext && !m_busy_int && !m_issued;
    assign o_m_busy      = i_is_m_ext && !m_done_int;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            m_issued <= 1'b0;
        end else if (i_flush_e || m_done_int || !i_is_m_ext) begin
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
        .i_rs1   (rs1_exec_data),
        .i_rs2   (rs2_exec_data),
        .i_m_op  (i_m_op),
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

    assign is_csr_inst = (i_inst_spec == `EX_CSR);

    // func3[2]=1 时为立即数版本；i_imm 已由 imm_unit 计算为 {27'b0, instr[19:15]}
    assign csr_operand = (i_func3[2]) ? i_imm : rs1_exec_data;

    // wmode: func3[1:0] - 1 → 01→00(write), 10→01(set), 11→10(clear)
    assign csr_wmode = i_func3[1:0] - 2'b01;

    // 只有 CSRRS/CSRRC（及立即数变体）在操作数为0时跳过写
    logic csr_skip_write;
    assign csr_skip_write = (i_func3[1:0] != 2'b01) && (csr_operand == 32'h0);
    assign csr_we = is_csr_inst && !csr_skip_write;

    // ecall/ebreak/mret 检测
    logic is_ecall, is_ebreak, is_mret;
    assign is_ecall  = (i_inst_spec == `EX_ECALL);
    assign is_ebreak = (i_inst_spec == `EX_EBREAK);
    assign is_mret   = (i_inst_spec == `EX_MRET);

    // ecall mcause: M-mode ecall = 11, ebreak = 3
    logic [31:0] trap_cause;
    assign trap_cause = is_ecall ? 32'd11 : 32'd3;

    csr_file u_csr_file (
        .i_clk        (i_clk),
        .i_rst_n      (i_rst_n),
        // 读
        .i_raddr      (i_csr_addr),
        .o_rdata      (csr_rdata),
        // 写
        .i_we         (csr_we),
        .i_waddr      (i_csr_addr),
        .i_wdata      (csr_operand),
        .i_wmode      (csr_wmode),
        // Trap 入口
        .i_trap_en    (is_ecall || is_ebreak),
        .i_trap_pc    (i_pc),           // EX 级 PC = ecall 指令地址
        .i_trap_cause (trap_cause),
        // Trap 返回
        .i_mret_en    (is_mret),
        // 直接输出
        .o_mtvec      (mtvec_val),
        .o_mepc       (mepc_val)
    );

    // ---- 重定向逻辑（复用 o_error/o_right_pc 机制）----
    // ecall/ebreak → 跳 mtvec；mret → 跳 mepc；分支误预测 → 跳 branch_right_pc
    // 优先级：ecall/ebreak > mret > branch（实际上不会同时有多个）
    always_comb begin
        if (is_ecall || is_ebreak) begin
            o_error     = 1'b1;
            o_right_pc  = mtvec_val;
        end else if (is_mret) begin
            o_error     = 1'b1;
            o_right_pc  = mepc_val;
        end else begin
            o_error     = branch_error;
            o_right_pc  = branch_right_pc;
        end
    end

    // ---- 结果输出 ----
    always_comb begin
        o_a2_data = rs2_exec_data;

        if (i_is_m_ext) begin
            o_alu_res = m_res;
        end else if (is_csr_inst) begin
            o_alu_res = csr_rdata;   // rd ← 旧 CSR 值
        end else begin
            unique case (i_inst_spec)
                `EX_LUI:          o_alu_res = i_imm;
                `EX_JAL,
                `EX_JALR:         o_alu_res = i_pc + 32'd4;
                `EX_ECALL,
                `EX_EBREAK,
                `EX_MRET:         o_alu_res = 32'h0;  // 不写 rd
                default:          o_alu_res = alu_res_raw;
            endcase
        end
    end

endmodule
