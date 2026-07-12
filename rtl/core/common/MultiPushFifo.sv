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
    localparam int BANK_DEPTH = (DEPTH + 1) / 2;
    localparam int BANK_ADDR_WIDTH = (PTR_WIDTH <= 1) ? 1 : PTR_WIDTH - 1;
    (* ram_style = "distributed" *) logic [WIDTH-1:0]
        even_mem_q [BANK_DEPTH-1:0];
    (* ram_style = "distributed" *) logic [WIDTH-1:0]
        odd_mem_q [BANK_DEPTH-1:0];
    logic [PTR_WIDTH-1:0] rd_ptr_q;
    logic [PTR_WIDTH-1:0] wr_ptr_q;
    logic [PTR_WIDTH:0] count_q;
    logic [PTR_WIDTH:0] push_count;
    logic [PTR_WIDTH:0] pop_count;
    logic [PTR_WIDTH:0] push_offset [PUSH_WIDTH-1:0];
    logic [POP_WIDTH-1:0] pop_fire;
    logic pop_prefix_fire;
    logic even_write_valid;
    logic odd_write_valid;
    logic [BANK_ADDR_WIDTH-1:0] even_write_addr;
    logic [BANK_ADDR_WIDTH-1:0] odd_write_addr;
    logic [WIDTH-1:0] even_write_data;
    logic [WIDTH-1:0] odd_write_data;
    logic [PTR_WIDTH-1:0] pop_addr [POP_WIDTH-1:0];
    logic [BANK_ADDR_WIDTH-1:0] even_read_addr;
    logic [BANK_ADDR_WIDTH-1:0] odd_read_addr;
    logic [WIDTH-1:0] even_read_data;
    logic [WIDTH-1:0] odd_read_data;
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

    function automatic logic [BANK_ADDR_WIDTH-1:0] bank_index(
        input logic [PTR_WIDTH-1:0] addr
    );
        begin
            bank_index = BANK_ADDR_WIDTH'(addr >> 1);
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
            pop_addr[i] = wrap_add(rd_ptr_q, (PTR_WIDTH+1)'(i));
            pop_fire[i] = pop_prefix_fire && pop_ready_i[i] && pop_valid_o[i];
            if (pop_fire[i]) begin
                pop_count = pop_count + 1'b1;
            end
            pop_prefix_fire = pop_prefix_fire && pop_fire[i];
        end


        // The fetch FIFO is two-wide. Two consecutive logical addresses use
        // opposite parity banks, so each shallow bank has one async read and
        // the output only needs a parity-controlled crossbar.
        even_read_addr = pop_addr[0][0] ? bank_index(pop_addr[1]) :
                                           bank_index(pop_addr[0]);
        odd_read_addr = pop_addr[0][0] ? bank_index(pop_addr[0]) :
                                          bank_index(pop_addr[1]);
        even_read_data = even_mem_q[even_read_addr];
        odd_read_data = odd_mem_q[odd_read_addr];
        for (i = 0; i < POP_WIDTH; i = i + 1) begin
            pop_data_o[i] = pop_addr[i][0] ? odd_read_data : even_read_data;
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

    // Compact accepted pushes first, then route the two consecutive physical
    // addresses to opposite parity banks. Each bank has exactly one write
    // bundle and therefore avoids a general two-write payload array.
    always_comb begin
        even_write_valid = 1'b0;
        odd_write_valid = 1'b0;
        even_write_addr = '0;
        odd_write_addr = '0;
        even_write_data = '0;
        odd_write_data = '0;
        for (int p = 0; p < PUSH_WIDTH; p = p + 1) begin
            logic [PTR_WIDTH-1:0] write_addr;
            write_addr = wrap_add(wr_ptr_q, push_offset[p]);
            if (push_valid_i[p] && push_ready_o[p]) begin
                if (write_addr[0]) begin
                    odd_write_valid = 1'b1;
                    odd_write_addr = bank_index(write_addr);
                    odd_write_data = push_data_i[p];
                end else begin
                    even_write_valid = 1'b1;
                    even_write_addr = bank_index(write_addr);
                    even_write_data = push_data_i[p];
                end
            end
        end
    end

    // FIFO pointers/count own payload visibility; both banks are reset-free.
    always_ff @(posedge clk) begin
        if (even_write_valid) begin
            even_mem_q[even_write_addr] <= even_write_data;
        end
        if (odd_write_valid) begin
            odd_mem_q[odd_write_addr] <= odd_write_data;
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && (PUSH_WIDTH == 2) &&
            push_valid_i[0] && push_ready_o[0] &&
            push_valid_i[1] && push_ready_o[1]) begin
            assert (wrap_add(wr_ptr_q, push_offset[0])[0] !=
                    wrap_add(wr_ptr_q, push_offset[1])[0])
                else $error("two-wide FIFO push targeted one parity bank");
        end
    end
`endif
endmodule : CoreMultiPushFifo
