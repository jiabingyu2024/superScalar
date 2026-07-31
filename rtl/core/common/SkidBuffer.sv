module CoreSkidBuffer #(
    parameter int WIDTH = 32
) (
    input  logic             clk,
    input  logic             rst,
    input  logic             clear_i,
    input  logic             in_valid_i,
    output logic             in_ready_o,
    input  logic [WIDTH-1:0] in_data_i,
    output logic             out_valid_o,
    input  logic             out_ready_i,
    output logic [WIDTH-1:0] out_data_o
);
    logic             full_q;
    logic [WIDTH-1:0] data_q;

    assign in_ready_o  = !full_q || out_ready_i;
    assign out_valid_o = full_q ? 1'b1 : in_valid_i;
    assign out_data_o  = full_q ? data_q : in_data_i;

    // data_q is selected only while full_q is set; reset only the state bit.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            full_q <= 1'b0;
        end else if (clear_i) begin
            full_q <= 1'b0;
        end else begin
            if (in_valid_i && in_ready_o && !out_ready_i) begin
                full_q <= 1'b1;
                data_q <= in_data_i;
            end else if (out_ready_i) begin
                full_q <= 1'b0;
            end
        end
    end
endmodule : CoreSkidBuffer
