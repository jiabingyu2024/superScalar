module CoreLoadAligner (
    input  logic [31:0] raw_i,
    input  logic [1:0]  addr_low_i,
    input  logic [2:0]  funct3_i,
    output logic [31:0] data_o
);
    logic [31:0] shifted;

    always_comb begin
        shifted = raw_i >> ({addr_low_i, 3'b000});
        case (funct3_i)
            3'b000: data_o = {{24{shifted[7]}}, shifted[7:0]};
            3'b001: data_o = {{16{shifted[15]}}, shifted[15:0]};
            3'b010: data_o = shifted;
            3'b100: data_o = {24'b0, shifted[7:0]};
            3'b101: data_o = {16'b0, shifted[15:0]};
            default: data_o = shifted;
        endcase
    end
endmodule : CoreLoadAligner
