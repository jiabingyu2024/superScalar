import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreDispatchUnit (
    input  logic [DISPATCH_WIDTH-1:0] in_valid_i,
    input  CoreRenamedUop [DISPATCH_WIDTH-1:0] in_uop_i,
    input  TubeTypePath [DISPATCH_WIDTH-1:0] in_tube_i,
    output logic [DISPATCH_WIDTH-1:0] in_ready_o,

    output logic [DISPATCH_WIDTH-1:0] int_valid_o,
    output logic [DISPATCH_WIDTH-1:0] mem_valid_o,
    output logic [DISPATCH_WIDTH-1:0] mul_valid_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] int_uop_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] mem_uop_o,
    output CoreRenamedUop [DISPATCH_WIDTH-1:0] mul_uop_o,

    input  logic [DISPATCH_WIDTH-1:0] int_ready_i,
    input  logic [DISPATCH_WIDTH-1:0] mem_ready_i,
    input  logic [DISPATCH_WIDTH-1:0] mul_ready_i
);
    logic [DISPATCH_WIDTH-1:0] lane_ready;

    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            lane_ready[i] = 1'b0;
            case (in_tube_i[i])
                TUBE_TYPE_MEM: lane_ready[i] = mem_ready_i[i];
                TUBE_TYPE_MUL: lane_ready[i] = mul_ready_i[i];
                default:       lane_ready[i] = int_ready_i[i];
            endcase

            in_ready_o[i] = lane_ready[i];
            if ((i != 0) && !in_ready_o[i-1]) begin
                in_ready_o[i] = 1'b0;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < DISPATCH_WIDTH; i = i + 1) begin
            int_valid_o[i] = 1'b0;
            mem_valid_o[i] = 1'b0;
            mul_valid_o[i] = 1'b0;
            int_uop_o[i] = in_uop_i[i];
            mem_uop_o[i] = in_uop_i[i];
            mul_uop_o[i] = in_uop_i[i];

            case (in_tube_i[i])
                TUBE_TYPE_MEM: begin
                    mem_valid_o[i] = in_valid_i[i];
                end
                TUBE_TYPE_MUL: begin
                    mul_valid_o[i] = in_valid_i[i];
                end
                default: begin
                    int_valid_o[i] = in_valid_i[i];
                end
            endcase

            if ((i != 0) && !in_ready_o[i-1]) begin
                int_valid_o[i] = 1'b0;
                mem_valid_o[i] = 1'b0;
                mul_valid_o[i] = 1'b0;
            end
        end
    end
endmodule : CoreDispatchUnit
