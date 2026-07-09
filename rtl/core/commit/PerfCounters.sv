module CorePerfCounters (
    input  logic clk,
    input  logic rst,
    input  logic commit_i,
    output logic [63:0] cycle_o,
    output logic [63:0] commit_o
);
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_o <= '0;
            commit_o <= '0;
        end else begin
            cycle_o <= cycle_o + 64'd1;
            if (commit_i) begin
                commit_o <= commit_o + 64'd1;
            end
        end
    end
endmodule : CorePerfCounters
