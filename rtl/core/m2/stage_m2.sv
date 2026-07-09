//==============================================================================
// 模块: stage_m2
// 功能概述：
//   同步 DRAM 返回数据处理
//   mask/load_unsigned 对 load 数据做符号/零扩展，输出给 MEM/WB。
//==============================================================================
`include "cpu_defines.svh"

module stage_m2 (
    input  logic [3:0]                        i_mem_mask,
    input  logic                              i_load_unsigned,
    input  logic [`DATA_BUS]                  i_dram_rdata,

    output logic [`DATA_BUS]                  o_mem_rdata
);

    logic [7:0]  load_byte;
    logic [15:0] load_half;


    assign load_byte = i_dram_rdata[7:0];
    assign load_half = i_dram_rdata[15:0];

    always_comb begin
        unique case (i_mem_mask)
            `MASK_BYTE: o_mem_rdata = i_load_unsigned ? {24'b0, load_byte} : {{24{load_byte[7]}}, load_byte};
            `MASK_HALF: o_mem_rdata = i_load_unsigned ? {16'b0, load_half} : {{16{load_half[15]}}, load_half};
            default:    o_mem_rdata = i_dram_rdata;
        endcase
    end
endmodule
