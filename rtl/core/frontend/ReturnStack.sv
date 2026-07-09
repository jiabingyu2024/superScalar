import CoreTypesPkg::*;

module CoreReturnStack #(
    parameter int DEPTH = 8,
    parameter int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic  clk,
    input  logic  rst,
    input  logic  clear_i,
    input  logic  push_i,
    input  PcPath push_pc_i,
    input  logic  pop_i,
    output logic  top_valid_o,
    output PcPath top_pc_o
);
    PcPath stack_q [DEPTH-1:0];
    logic [PTR_WIDTH:0] count_q;

    assign top_valid_o = (count_q != '0);
    assign top_pc_o = stack_q[(count_q == '0) ? '0 : count_q[PTR_WIDTH-1:0] - 1'b1];

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            count_q <= '0;
        end else begin
            if (push_i && (count_q < DEPTH[PTR_WIDTH:0])) begin
                stack_q[count_q[PTR_WIDTH-1:0]] <= push_pc_i;
                count_q <= count_q + 1'b1;
            end else if (pop_i && (count_q != '0)) begin
                count_q <= count_q - 1'b1;
            end
        end
    end
endmodule : CoreReturnStack
