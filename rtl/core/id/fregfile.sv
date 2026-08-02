`include "cpu_defines.svh"

// RV32F architectural register file.  Three asynchronous read replicas keep
// rs3 out of the integer register-file mux cone; the sole write port is WB.
module fregfile(
    input  logic             i_clk,
    input  logic             i_we,
    input  logic [`RF_BUS]   i_rs1_addr,
    input  logic [`RF_BUS]   i_rs2_addr,
    input  logic [`RF_BUS]   i_rs3_addr,
    input  logic [`RF_BUS]   i_w_addr,
    input  logic [`DATA_BUS] i_w_data,
    output logic [`DATA_BUS] o_rs1_data,
    output logic [`DATA_BUS] o_rs2_data,
    output logic [`DATA_BUS] o_rs3_data
);
    (* ram_style = "distributed" *) logic [`DATA_BUS] rf_mem [0:`RF_DEPTH-1];
    integer idx;

    initial begin
        for (idx = 0; idx < `RF_DEPTH; idx = idx + 1) rf_mem[idx] = '0;
    end

    always_ff @(posedge i_clk) begin
        if (i_we) rf_mem[i_w_addr] <= i_w_data;
    end

    assign o_rs1_data = (i_we && (i_w_addr == i_rs1_addr)) ? i_w_data : rf_mem[i_rs1_addr];
    assign o_rs2_data = (i_we && (i_w_addr == i_rs2_addr)) ? i_w_data : rf_mem[i_rs2_addr];
    assign o_rs3_data = (i_we && (i_w_addr == i_rs3_addr)) ? i_w_data : rf_mem[i_rs3_addr];
endmodule
