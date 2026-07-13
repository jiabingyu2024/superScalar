`include "cpu_defines.svh"

module reg_id_c1 (
    input  logic             i_clk,
    input  logic             i_rst_n,
    input  logic             i_flush,
    input  logic             i_hold,
    input  logic             i_bubble,
    input  logic             i_valid,

    input  logic [`DATA_BUS] i_rs1_data,
    input  logic [`RF_BUS]   i_rs1_addr,
    input  logic [`DATA_BUS] i_rs2_data,
    input  logic [`RF_BUS]   i_rs2_addr,
    input  logic [`RF_BUS]   i_rd_addr,
    input  logic [`DATA_BUS] i_imm,
    input  logic [`DATA_BUS] i_mem_addr,
    input  logic             i_mem_read,
    input  logic             i_mem_write,
    input  logic             i_reg_write,
    input  logic             i_wb_src,
    input  logic             i_is_rs2_imm,
    input  logic [3:0]       i_inst_spec,
    input  logic [3:0]       i_alu_ctrl,
    input  logic [2:0]       i_func3,
    input  logic [3:0]       i_mem_mask,
    input  logic             i_load_unsigned,
    input  logic             i_is_branch,
    input  logic [`PC_BUS]   i_pc,
    input  logic [`PC_BUS]   i_pc_target,
    input  logic [`PC_BUS]   i_pc_predict,
    input  logic             i_predict_taken,
    input  logic             i_is_m_ext,
    input  logic [`M_OP_BUS] i_m_op,
    input  logic [11:0]      i_csr_addr,

    output logic             o_valid,
    output logic [`DATA_BUS] o_rs1_data,
    output logic [`RF_BUS]   o_rs1_addr,
    output logic [`DATA_BUS] o_rs2_data,
    output logic [`RF_BUS]   o_rs2_addr,
    output logic [`RF_BUS]   o_rd_addr,
    output logic [`DATA_BUS] o_imm,
    output logic [`DATA_BUS] o_mem_addr,
    output logic             o_mem_read,
    output logic             o_mem_write,
    output logic             o_reg_write,
    output logic             o_wb_src,
    output logic             o_is_rs2_imm,
    output logic [3:0]       o_inst_spec,
    output logic [3:0]       o_alu_ctrl,
    output logic [2:0]       o_func3,
    output logic [3:0]       o_mem_mask,
    output logic             o_load_unsigned,
    output logic             o_is_branch,
    output logic [`PC_BUS]   o_pc,
    output logic [`PC_BUS]   o_pc_target,
    output logic [`PC_BUS]   o_pc_predict,
    output logic             o_predict_taken,
    output logic             o_is_m_ext,
    output logic [`M_OP_BUS] o_m_op,
    output logic [11:0]      o_csr_addr
);
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_valid         <= 1'b0;
        end else if (i_flush) begin
            o_valid         <= 1'b0;
        end else if (i_hold) begin
            o_valid <= o_valid;
        end else if (i_bubble) begin
            o_valid         <= 1'b0;
        end else begin
            o_valid         <= i_valid;
            o_rs1_data      <= i_rs1_data;
            o_rs1_addr      <= i_rs1_addr;
            o_rs2_data      <= i_rs2_data;
            o_rs2_addr      <= i_rs2_addr;
            o_rd_addr       <= i_rd_addr;
            o_imm           <= i_imm;
            o_mem_addr      <= i_mem_addr;
            o_mem_read      <= i_mem_read;
            o_mem_write     <= i_mem_write;
            o_reg_write     <= i_reg_write;
            o_wb_src        <= i_wb_src;
            o_is_rs2_imm    <= i_is_rs2_imm;
            o_inst_spec     <= i_inst_spec;
            o_alu_ctrl      <= i_alu_ctrl;
            o_func3         <= i_func3;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
            o_is_branch     <= i_is_branch;
            o_pc            <= i_pc;
            o_pc_target     <= i_pc_target;
            o_pc_predict    <= i_pc_predict;
            o_predict_taken <= i_predict_taken;
            o_is_m_ext      <= i_is_m_ext;
            o_m_op          <= i_m_op;
            o_csr_addr      <= i_csr_addr;
        end
    end
endmodule
