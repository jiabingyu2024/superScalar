module CorePipeReg #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             clear_i,
    input  logic             hold_i,
    input  logic             valid_i,
    input  logic [WIDTH-1:0] data_i,
    output logic             valid_o,
    output logic [WIDTH-1:0] data_o
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            valid_o <= 1'b0;
            data_o  <= '0;
        end else if (!hold_i) begin
            valid_o <= valid_i;
            data_o  <= data_i;
        end
    end
endmodule : CorePipeReg
