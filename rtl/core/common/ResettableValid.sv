module CoreResettableValid #(
    parameter int ENTRIES = 8
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               clear_i,
    input  logic [ENTRIES-1:0] set_i,
    input  logic [ENTRIES-1:0] clr_i,
    output logic [ENTRIES-1:0] valid_o
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_o <= '0;
        end else if (clear_i) begin
            valid_o <= '0;
        end else begin
            valid_o <= (valid_o | set_i) & ~clr_i;
        end
    end
endmodule : CoreResettableValid
