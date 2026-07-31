import CoreTypesPkg::*;

module CoreMemPipe (
    input  CoreDecodeUop uop_i,
    input  DataPath base_i,
    input  DataPath store_data_i,
    output AddrPath addr_o,
    output DataPath store_data_o
);
    assign addr_o = base_i + (uop_i.is_store ? uop_i.imm_s : uop_i.imm_i);
    assign store_data_o = store_data_i;
endmodule : CoreMemPipe
