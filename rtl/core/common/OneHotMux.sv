module CoreOneHotMux #(
    parameter int WIDTH = 32,
    parameter int INPUTS = 4
) (
    input  logic [INPUTS-1:0]             sel_i,
    input  logic [INPUTS-1:0][WIDTH-1:0] data_i,
    output logic [WIDTH-1:0]             data_o
);
    integer i;

    always_comb begin
        data_o = '0;
        for (i = 0; i < INPUTS; i = i + 1) begin
            if (sel_i[i]) begin
                data_o = data_o | data_i[i];
            end
        end
    end
endmodule : CoreOneHotMux
