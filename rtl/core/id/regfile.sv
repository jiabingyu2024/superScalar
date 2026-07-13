//==============================================================================
// 模块: regfile
// 功能概述：
//   通用寄存器堆（x0~x31）。双读端口（rs1/rs2）单写端口；写使能有效且地址非 x0 时写入。
// 接口/协作审查（供采纳）：
//   - 读为异步或同步读需团队统一；典型五级流水线为“ID 读、WB 写”，注意 x0 恒 0。
//   - 端口使用 `RF_BUS`/`DATA_BUS`，与 stage_id 的地址宽度一致即可。
//==============================================================================
`include "cpu_defines.svh"

module regfile(
    input wire              i_clk,
    input wire              i_rst_n,
    input wire              i_we,
    input wire [`RF_BUS]    i_rs1_addr,
    input wire [`RF_BUS]    i_rs2_addr,
    input wire [`RF_BUS]    i_w_addr,
    input wire [`DATA_BUS]  i_w_data,
    output wire [`DATA_BUS] o_rs1_data,
    output wire [`DATA_BUS] o_rs2_data
);

    // One mirrored LUTRAM per asynchronous read port.  Architectural state is
    // defined by writes and x0 masking, so resetting the payload is unnecessary.
    // This removes the half-cycle write path and the high-fanout RF reset tree.
    (* ram_style = "distributed" *) logic [`DATA_BUS] rf_rs1_mem [0:`RF_DEPTH-1];
    (* ram_style = "distributed" *) logic [`DATA_BUS] rf_rs2_mem [0:`RF_DEPTH-1];

    always_ff @(posedge i_clk) begin
        if (i_we && (i_w_addr != '0)) begin
            rf_rs1_mem[i_w_addr] <= i_w_data;
            rf_rs2_mem[i_w_addr] <= i_w_data;
        end
    end

    assign o_rs1_data = (i_rs1_addr == '0) ? '0 : rf_rs1_mem[i_rs1_addr];
    assign o_rs2_data = (i_rs2_addr == '0) ? '0 : rf_rs2_mem[i_rs2_addr];

endmodule
