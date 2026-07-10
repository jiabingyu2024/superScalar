import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CorePhysRegFile #(
    parameter int READ_PORTS = ISSUE_WIDTH * 2,
    parameter int WRITE_PORTS = ISSUE_WIDTH
) (
    input  logic clk,

    input  PhyRegNumPath [READ_PORTS-1:0] raddr_i,
    output DataPath [READ_PORTS-1:0] rdata_o,

    input  logic [WRITE_PORTS-1:0] we_i,
    input  PhyRegNumPath [WRITE_PORTS-1:0] waddr_i,
    input  DataPath [WRITE_PORTS-1:0] wdata_i
);
    DataPath regs_q [PHY_REG_NUM-1:0];

    always_comb begin
        for (int r = 0; r < READ_PORTS; r = r + 1) begin
            rdata_o[r] = (raddr_i[r] == '0) ? '0 : regs_q[raddr_i[r]];
            for (int w = 0; w < WRITE_PORTS; w = w + 1) begin
                if (we_i[w] && (waddr_i[w] == raddr_i[r]) && (raddr_i[r] != '0)) begin
                    rdata_o[r] = wdata_i[w];
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        for (int w = 0; w < WRITE_PORTS; w = w + 1) begin
            if (we_i[w] && (waddr_i[w] != '0)) begin
                regs_q[waddr_i[w]] <= wdata_i[w];
            end
        end
        regs_q[0] <= '0;
    end
endmodule : CorePhysRegFile
