module CoreStoreDataGen (
    input  logic [31:0] raw_i,
    input  logic [1:0]  addr_low_i,
    input  logic [2:0]  funct3_i,
    output logic [31:0] data_o,
    output logic [3:0]  mask_o
);
    logic [31:0] base_data;
    logic [3:0]  base_mask;

    always_comb begin
        case (funct3_i)
            3'b000: begin
                base_data = {24'b0, raw_i[7:0]};
                base_mask = 4'b0001;
            end
            3'b001: begin
                base_data = {16'b0, raw_i[15:0]};
                base_mask = 4'b0011;
            end
            3'b010: begin
                base_data = raw_i;
                base_mask = 4'b1111;
            end
            default: begin
                base_data = 32'b0;
                base_mask = 4'b0000;
            end
        endcase
        data_o = base_data << ({addr_low_i, 3'b000});
        mask_o = base_mask << addr_low_i;
    end
endmodule : CoreStoreDataGen
