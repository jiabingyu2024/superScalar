import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreRat (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic wr_i,
    input  LgcRegNumPath wr_arch_i,
    input  PhyRegNumPath wr_phy_i,
    input  LgcRegNumPath raddr0_i,
    output PhyRegNumPath rdata0_o,
    input  LgcRegNumPath raddr1_i,
    output PhyRegNumPath rdata1_o
);
    PhyRegNumPath map_q [LOGIC_REG_NUM-1:0];

    assign rdata0_o = map_q[raddr0_i];
    assign rdata1_o = map_q[raddr1_i];

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            for (int i = 0; i < LOGIC_REG_NUM; i = i + 1) begin
                map_q[i] <= PhyRegNumPath'(i);
            end
        end else if (wr_i && (wr_arch_i != '0)) begin
            map_q[wr_arch_i] <= wr_phy_i;
        end
    end
endmodule : CoreRat
