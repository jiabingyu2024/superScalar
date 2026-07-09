module CoreCounterFreeList #(
    parameter int FIRST_FREE = 32,
    parameter int LAST_FREE  = 63,
    parameter int WIDTH = (LAST_FREE <= 1) ? 1 : $clog2(LAST_FREE + 1)
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             clear_i,
    input  logic             alloc_i,
    output logic             alloc_valid_o,
    output logic [WIDTH-1:0] alloc_id_o,
    input  logic             free_i,
    input  logic [WIDTH-1:0] free_id_i
);
    localparam int DEPTH = LAST_FREE - FIRST_FREE + 1;
    localparam int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic [WIDTH-1:0] mem_q [DEPTH-1:0];
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH:0] count_q;
    logic do_alloc;
    logic do_free;

    function automatic logic [PTR_WIDTH-1:0] ptr_inc(input logic [PTR_WIDTH-1:0] ptr);
        if (ptr == DEPTH-1) begin
            ptr_inc = '0;
        end else begin
            ptr_inc = ptr + 1'b1;
        end
    endfunction

    assign alloc_valid_o = (count_q != '0);
    assign alloc_id_o = mem_q[rd_ptr_q];
    assign do_alloc = alloc_i && alloc_valid_o;
    assign do_free = free_i && (count_q != DEPTH[PTR_WIDTH:0]);

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            rd_ptr_q <= '0;
            wr_ptr_q <= '0;
            count_q <= DEPTH[PTR_WIDTH:0];
            for (int i = 0; i < DEPTH; i = i + 1) begin
                mem_q[i] <= WIDTH'(FIRST_FREE + i);
            end
        end else begin
            if (do_alloc) begin
                rd_ptr_q <= ptr_inc(rd_ptr_q);
            end
            if (do_free) begin
                mem_q[wr_ptr_q] <= free_id_i;
                wr_ptr_q <= ptr_inc(wr_ptr_q);
            end
            unique case ({do_free, do_alloc})
                2'b10: count_q <= count_q + 1'b1;
                2'b01: count_q <= count_q - 1'b1;
                default: count_q <= count_q;
            endcase
        end
    end
endmodule : CoreCounterFreeList
