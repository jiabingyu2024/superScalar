module CoreSyncRam1R1WByteMask #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 1024,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int BYTE_NUM = WIDTH / 8
) (
    input  logic                  clk,
    input  logic                  rd_en_i,
    input  logic [ADDR_WIDTH-1:0] rd_addr_i,
    output logic [WIDTH-1:0]      rd_data_o,
    input  logic                  wr_en_i,
    input  logic [ADDR_WIDTH-1:0] wr_addr_i,
    input  logic [WIDTH-1:0]      wr_data_i,
    input  logic [BYTE_NUM-1:0]   wr_mask_i
);
    (* ram_style = "block" *) logic [WIDTH-1:0] mem_q [DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (wr_en_i) begin
            for (int b = 0; b < BYTE_NUM; b = b + 1) begin
                if (wr_mask_i[b]) begin
                    mem_q[wr_addr_i][8*b +: 8] <= wr_data_i[8*b +: 8];
                end
            end
        end
        if (rd_en_i) begin
            rd_data_o <= mem_q[rd_addr_i];
        end
    end
endmodule : CoreSyncRam1R1WByteMask
