module CoreMultiPushFifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 8,
    parameter int PUSH_WIDTH = 2,
    parameter int POP_WIDTH = 2,
    parameter int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear_i,
    input  logic [PUSH_WIDTH-1:0]        push_valid_i,
    input  logic [PUSH_WIDTH-1:0][WIDTH-1:0] push_data_i,
    output logic [PUSH_WIDTH-1:0]        push_ready_o,
    input  logic [POP_WIDTH-1:0]         pop_ready_i,
    output logic [POP_WIDTH-1:0]         pop_valid_o,
    output logic [POP_WIDTH-1:0][WIDTH-1:0] pop_data_o,
    output logic [PTR_WIDTH:0]           count_o
);
    logic [WIDTH-1:0] mem_q [DEPTH-1:0];
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH:0] count_q;
    logic [PTR_WIDTH:0] push_count;
    logic [PTR_WIDTH:0] pop_count;
    logic [PTR_WIDTH:0] push_offset [PUSH_WIDTH-1:0];
    logic [POP_WIDTH-1:0] pop_fire;
    logic pop_prefix_fire;
    integer i;

    function automatic logic [PTR_WIDTH-1:0] wrap_add(
        input logic [PTR_WIDTH-1:0] base,
        input logic [PTR_WIDTH:0] inc
    );
        logic [PTR_WIDTH:0] sum;
        begin
            sum = {1'b0, base} + inc;
            if (sum >= DEPTH[PTR_WIDTH:0]) begin
                sum = sum - DEPTH[PTR_WIDTH:0];
            end
            if (sum >= DEPTH[PTR_WIDTH:0]) begin
                sum = sum - DEPTH[PTR_WIDTH:0];
            end
            wrap_add = sum[PTR_WIDTH-1:0];
        end
    endfunction

    always_comb begin
        push_count = '0;
        for (i = 0; i < PUSH_WIDTH; i = i + 1) begin
            push_offset[i] = push_count;
            push_ready_o[i] = (count_q + push_count < DEPTH[PTR_WIDTH:0]);
            if (push_valid_i[i] && push_ready_o[i]) begin
                push_count = push_count + 1'b1;
            end
        end

        pop_count = '0;
        pop_prefix_fire = 1'b1;
        for (i = 0; i < POP_WIDTH; i = i + 1) begin
            pop_valid_o[i] = (count_q > (PTR_WIDTH+1)'(i));
            pop_data_o[i] = mem_q[wrap_add(rd_ptr_q, (PTR_WIDTH+1)'(i))];
            pop_fire[i] = pop_prefix_fire && pop_ready_i[i] && pop_valid_o[i];
            if (pop_fire[i]) begin
                pop_count = pop_count + 1'b1;
            end
            pop_prefix_fire = pop_prefix_fire && pop_fire[i];
        end
    end

    assign count_o = count_q;

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
            rd_ptr_q <= wrap_add(rd_ptr_q, pop_count);
            wr_ptr_q <= wrap_add(wr_ptr_q, push_count);
            count_q <= count_q + push_count - pop_count;
        end
    end

    // FIFO pointers/count own the payload. Keeping mem_q in a reset-free
    // process prevents the payload from inheriting the async reset control set.
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            for (int p = 0; p < PUSH_WIDTH; p = p + 1) begin
                if (push_valid_i[p] && push_ready_o[p]) begin
                    mem_q[wrap_add(wr_ptr_q, push_offset[p])] <= push_data_i[p];
                end
            end
        end
    end
endmodule : CoreMultiPushFifo
