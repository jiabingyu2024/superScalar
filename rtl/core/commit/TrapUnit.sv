import CoreTypesPkg::*;

module CoreTrapUnit (
    input  logic trap_valid_i,
    input  PcPath trap_vector_i,
    input  PcPath trap_epc_i,
    output logic recovery_valid_o,
    output PcPath recovery_pc_o,
    output PcPath trap_epc_o
);
    assign recovery_valid_o = trap_valid_i;
    assign recovery_pc_o = trap_vector_i;
    assign trap_epc_o = trap_epc_i;
endmodule : CoreTrapUnit
