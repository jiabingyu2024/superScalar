module CoreSyncRamSimpleDualPort #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 64,
    parameter int ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                  clk,
    input  logic                  a_en_i,
    input  logic [ADDR_WIDTH-1:0] a_addr_i,
    output logic [WIDTH-1:0]      a_data_o,
    input  logic                  b_en_i,
    input  logic                  b_we_i,
    input  logic [ADDR_WIDTH-1:0] b_addr_i,
    input  logic [WIDTH-1:0]      b_data_i,
    output logic [WIDTH-1:0]      b_data_o
);
    (* ram_style = "block" *) logic [WIDTH-1:0] mem_q [DEPTH-1:0];

    always_ff @(posedge clk) begin
        if (a_en_i) begin
            a_data_o <= mem_q[a_addr_i];
        end
        if (b_en_i) begin
            if (b_we_i) begin
                mem_q[b_addr_i] <= b_data_i;
            end
            b_data_o <= mem_q[b_addr_i];
        end
    end
endmodule : CoreSyncRamSimpleDualPort
