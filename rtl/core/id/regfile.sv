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

    // A resettable 32x32 array expands to 1024 flip-flops and a very large
    // reset tree.  Architectural registers other than x0 have no required
    // reset value, while an FPGA INIT keeps simulation/board startup
    // deterministic.  The distributed-RAM style gives two replicated async
    // read ports and one synchronous write port without changing ID timing.
    (* ram_style = "distributed" *) logic [`DATA_BUS] rf_mem [0:`RF_DEPTH-1];
    integer idx;

    initial begin
        for (idx = 0; idx < `RF_DEPTH; idx = idx + 1) begin
            rf_mem[idx] = '0;
        end
    end

    // Keep every architectural register on the CPU rising edge.  The former
    // falling-edge write made all WB-to-register-file paths half-cycle paths
    // at 200 MHz.  Explicit write-through below preserves the usual
    // write-first behavior for an instruction decoded in the same cycle as
    // its producer reaches WB, without changing pipeline latency.
    always_ff @(posedge i_clk) begin
        if (i_we && (i_w_addr != '0)) begin
            rf_mem[i_w_addr] <= i_w_data;
        end
    end

    assign o_rs1_data = (i_rs1_addr == '0) ? '0 :
                        ((i_we && (i_w_addr != '0) &&
                          (i_w_addr == i_rs1_addr)) ? i_w_data :
                         rf_mem[i_rs1_addr]);
    assign o_rs2_data = (i_rs2_addr == '0) ? '0 :
                        ((i_we && (i_w_addr != '0) &&
                          (i_w_addr == i_rs2_addr)) ? i_w_data :
                         rf_mem[i_rs2_addr]);

endmodule
