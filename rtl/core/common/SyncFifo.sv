module CoreSyncFifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 8,
    parameter int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             clear_i,
    input  logic             push_i,
    input  logic [WIDTH-1:0] push_data_i,
    output logic             full_o,
    input  logic             pop_i,
    output logic [WIDTH-1:0] pop_data_o,
    output logic             empty_o,
    output logic [PTR_WIDTH:0] count_o
);
    logic [WIDTH-1:0] mem_q [DEPTH-1:0];
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH:0]   count_q;

    assign full_o = (count_q == DEPTH[PTR_WIDTH:0]);
    assign empty_o = (count_q == '0);
    assign count_o = count_q;
    assign pop_data_o = mem_q[rd_ptr_q];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            count_q  <= '0;
        end else if (clear_i) begin
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            count_q  <= '0;
        end else begin
            if (push_i && !full_o) begin
                mem_q[wr_ptr_q] <= push_data_i;
                wr_ptr_q <= (wr_ptr_q == DEPTH-1) ? '0 : wr_ptr_q + 1'b1;
            end
            if (pop_i && !empty_o) begin
                rd_ptr_q <= (rd_ptr_q == DEPTH-1) ? '0 : rd_ptr_q + 1'b1;
            end
            unique case ({push_i && !full_o, pop_i && !empty_o})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end
endmodule : CoreSyncFifo
