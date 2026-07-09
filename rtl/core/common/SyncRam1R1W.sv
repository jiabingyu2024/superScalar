module CoreSyncRam1R1W #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 64,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  rd_en_i,
    input  logic [ADDR_WIDTH-1:0] rd_addr_i,
    output logic [WIDTH-1:0]      rd_data_o,
    input  logic                  wr_en_i,
    input  logic [ADDR_WIDTH-1:0] wr_addr_i,
    input  logic [WIDTH-1:0]      wr_data_i
);
    (* ram_style = "block" *) logic [WIDTH-1:0] mem_q [DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (wr_en_i) begin
            mem_q[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_data_o <= mem_q[rd_addr_i];
        end
    end
endmodule : CoreSyncRam1R1W
