import CoreTypesPkg::*;

module CoreCsrFile (
    input  logic clk,
    input  logic rst,
    input  logic we_i,
    input  logic [11:0] addr_i,
    input  DataPath wdata_i,
    output DataPath rdata_o,
    output PcPath mtvec_o,
    output PcPath mepc_o
);
    DataPath mstatus_q;
    PcPath mtvec_q;
    PcPath mepc_q;
    DataPath mcause_q;

    assign mtvec_o = mtvec_q;
    assign mepc_o = mepc_q;

    always_comb begin
        unique case (addr_i)
            12'h300: rdata_o = mstatus_q;
            12'h305: rdata_o = mtvec_q;
            12'h341: rdata_o = mepc_q;
            12'h342: rdata_o = mcause_q;
            default: rdata_o = 32'b0;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus_q <= '0;
            mtvec_q <= '0;
            mepc_q <= '0;
            mcause_q <= '0;
        end else if (we_i) begin
            unique case (addr_i)
                12'h300: mstatus_q <= wdata_i;
                12'h305: mtvec_q <= wdata_i;
                12'h341: mepc_q <= wdata_i;
                12'h342: mcause_q <= wdata_i;
                default: begin end
            endcase
        end
    end
endmodule : CoreCsrFile
