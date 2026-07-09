import CoreTypesPkg::*;

module CoreBypassNetwork (
    input  PhyRegNumPath src_i,
    input  DataPath reg_data_i,
    input  logic wb_valid_i,
    input  PhyRegNumPath wb_dst_i,
    input  DataPath wb_data_i,
    output DataPath data_o
);
    assign data_o = (wb_valid_i && (src_i == wb_dst_i) && (src_i != '0)) ? wb_data_i : reg_data_i;
endmodule : CoreBypassNetwork
