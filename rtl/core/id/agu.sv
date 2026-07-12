`include "cpu_defines.svh"

module agu (
    input  logic [`DATA_BUS] i_base,
    input  logic [`DATA_BUS] i_offset,
    output logic [`DATA_BUS] o_addr
);
    always_comb begin
        o_addr = i_base + i_offset;
    end
endmodule

