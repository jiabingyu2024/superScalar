module CorePriorityEncoder #(
    parameter int WIDTH = 8,
    parameter int INDEX_WIDTH = (WIDTH <= 1) ? 1 : $clog2(WIDTH)
) (
    input  logic [WIDTH-1:0]       req_i,
    output logic                   valid_o,
    output logic [INDEX_WIDTH-1:0] index_o,
    output logic [WIDTH-1:0]       onehot_o
);
    integer i;

    always_comb begin
        valid_o  = 1'b0;
        index_o  = '0;
        onehot_o = '0;
        for (i = 0; i < WIDTH; i = i + 1) begin
            if (!valid_o && req_i[i]) begin
                valid_o = 1'b1;
                index_o = i[INDEX_WIDTH-1:0];
                onehot_o[i] = 1'b1;
            end
        end
    end
endmodule : CorePriorityEncoder
