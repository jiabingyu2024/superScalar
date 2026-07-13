`include "cpu_defines.svh"

module reg_c1_c2 (
    input  logic             i_clk,
    input  logic             i_rst_n,
    input  logic             i_valid,
    input  logic [`RF_BUS]   i_rd_addr,
    input  logic [`DATA_BUS] i_alu_res,
    input  logic             i_wb_src,
    input  logic             i_reg_write,
    input  logic [3:0]       i_mem_mask,
    input  logic             i_load_unsigned,

    output logic             o_valid,
    output logic [`RF_BUS]   o_rd_addr,
    output logic [`DATA_BUS] o_alu_res,
    output logic             o_wb_src,
    output logic             o_reg_write,
    output logic [3:0]       o_mem_mask,
    output logic             o_load_unsigned
);
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_valid         <= 1'b0;
            o_rd_addr       <= '0;
            o_alu_res       <= '0;
            o_wb_src        <= `WB_SRC_ALU;
            o_reg_write     <= 1'b0;
            o_mem_mask      <= `MASK_WORD;
            o_load_unsigned <= 1'b0;
        end else begin
            o_valid         <= i_valid;
            o_rd_addr       <= i_rd_addr;
            o_alu_res       <= i_alu_res;
            o_wb_src        <= i_wb_src;
            o_reg_write     <= i_reg_write;
            o_mem_mask      <= i_mem_mask;
            o_load_unsigned <= i_load_unsigned;
        end
    end
endmodule

