`timescale 1ns / 1ps
module bitmanip_unit (
    input  logic clk,
    input  logic rst,
    input  logic kill_i,
    input  logic req_valid_i,
    output logic req_ready_o,
    input  logic [core_config_pkg::TRANS_ID_W-1:0] req_trans_id_i,
    input  core_types_pkg::bitmanip_op_e req_op_i,
    input  logic [31:0] req_a_i,
    input  logic [31:0] req_b_i,
    output logic resp_valid_o,
    output logic [core_config_pkg::TRANS_ID_W-1:0] resp_trans_id_o,
    output logic [31:0] resp_result_o,
    output logic busy_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    logic resp_valid_q;
    logic [TRANS_ID_W-1:0] resp_tid_q, clmul_tid_q;
    logic [31:0] resp_result_q;
    logic clmul_busy_q;
    bitmanip_op_e clmul_op_q;
    logic [5:0] clmul_iter_q;
    logic [63:0] clmul_acc_q, clmul_multiplicand_q, clmul_acc_next_c;
    logic [31:0] clmul_multiplier_q;
    logic req_is_clmul_c;
    logic [31:0] simple_result_c;
    logic [4:0] shamt_c, inv_shamt_c;
    integer i;
    integer j;

    assign req_ready_o = CFG_ZB_ANY && !clmul_busy_q;
    assign busy_o = clmul_busy_q;
    assign resp_valid_o = resp_valid_q;
    assign resp_trans_id_o = resp_tid_q;
    assign resp_result_o = resp_result_q;
    assign req_is_clmul_c = CFG_ZBC &&
                            (req_op_i == BM_CLMUL || req_op_i == BM_CLMULH ||
                             req_op_i == BM_CLMULR);
    assign clmul_acc_next_c = clmul_acc_q ^
                              (clmul_multiplier_q[0] ? clmul_multiplicand_q : 64'd0);

    always_comb begin
        simple_result_c = 32'd0;
        shamt_c = req_b_i[4:0];
        inv_shamt_c = 5'd0 - shamt_c;
        unique case (req_op_i)
            BM_SH1ADD: if (CFG_ZBA) simple_result_c = (req_a_i << 1) + req_b_i;
            BM_SH2ADD: if (CFG_ZBA) simple_result_c = (req_a_i << 2) + req_b_i;
            BM_SH3ADD: if (CFG_ZBA) simple_result_c = (req_a_i << 3) + req_b_i;
            BM_ANDN: if (CFG_ZBB || CFG_ZBKB) simple_result_c = req_a_i & ~req_b_i;
            BM_ORN:  if (CFG_ZBB || CFG_ZBKB) simple_result_c = req_a_i | ~req_b_i;
            BM_XNOR: if (CFG_ZBB || CFG_ZBKB) simple_result_c = ~(req_a_i ^ req_b_i);
            BM_ROL: if (CFG_ZBB || CFG_ZBKB)
                simple_result_c = (req_a_i << shamt_c) | (req_a_i >> inv_shamt_c);
            BM_ROR: if (CFG_ZBB || CFG_ZBKB)
                simple_result_c = (req_a_i >> shamt_c) | (req_a_i << inv_shamt_c);
            BM_CLZ: if (CFG_ZBB) begin
                simple_result_c = 32'd32;
                for (i = 0; i < 32; i = i + 1)
                    if (req_a_i[31-i] && simple_result_c == 32'd32)
                        simple_result_c = 32'(i);
            end
            BM_CTZ: if (CFG_ZBB) begin
                simple_result_c = 32'd32;
                for (i = 0; i < 32; i = i + 1)
                    if (req_a_i[i] && simple_result_c == 32'd32)
                        simple_result_c = 32'(i);
            end
            BM_CPOP: if (CFG_ZBB) begin
                simple_result_c = 32'd0;
                for (i = 0; i < 32; i = i + 1)
                    simple_result_c = simple_result_c + req_a_i[i];
            end
            BM_MAX: if (CFG_ZBB)
                simple_result_c = ($signed(req_a_i) < $signed(req_b_i)) ? req_b_i : req_a_i;
            BM_MAXU: if (CFG_ZBB)
                simple_result_c = (req_a_i < req_b_i) ? req_b_i : req_a_i;
            BM_MIN: if (CFG_ZBB)
                simple_result_c = ($signed(req_a_i) < $signed(req_b_i)) ? req_a_i : req_b_i;
            BM_MINU: if (CFG_ZBB)
                simple_result_c = (req_a_i < req_b_i) ? req_a_i : req_b_i;
            BM_ORC_B: if (CFG_ZBB) begin
                for (i = 0; i < 4; i = i + 1)
                    simple_result_c[i*8 +: 8] =
                        (req_a_i[i*8 +: 8] == 8'd0) ? 8'h00 : 8'hff;
            end
            BM_REV8: if (CFG_ZBB)
                simple_result_c = {req_a_i[7:0], req_a_i[15:8],
                                   req_a_i[23:16], req_a_i[31:24]};
            BM_SEXT_B: if (CFG_ZBB) simple_result_c = {{24{req_a_i[7]}}, req_a_i[7:0]};
            BM_SEXT_H: if (CFG_ZBB) simple_result_c = {{16{req_a_i[15]}}, req_a_i[15:0]};
            BM_ZEXT_H: if (CFG_ZBB) simple_result_c = {16'd0, req_a_i[15:0]};
            BM_BREV8: if (CFG_ZBKB) begin
                for (i = 0; i < 4; i = i + 1)
                    for (j = 0; j < 8; j = j + 1)
                        simple_result_c[i*8+j] = req_a_i[i*8+7-j];
            end
            BM_PACK: if (CFG_ZBKB) simple_result_c = {req_b_i[15:0], req_a_i[15:0]};
            BM_PACKH: if (CFG_ZBKB) simple_result_c = {16'd0, req_b_i[7:0], req_a_i[7:0]};
            BM_UNZIP: if (CFG_ZBKB) begin
                for (i = 0; i < 16; i = i + 1) begin
                    simple_result_c[i] = req_a_i[2*i];
                    simple_result_c[i+16] = req_a_i[2*i+1];
                end
            end
            BM_ZIP: if (CFG_ZBKB) begin
                for (i = 0; i < 16; i = i + 1) begin
                    simple_result_c[2*i] = req_a_i[i];
                    simple_result_c[2*i+1] = req_a_i[i+16];
                end
            end
            BM_XPERM4: if (CFG_ZBKX) begin
                for (i = 0; i < 8; i = i + 1)
                    if (req_b_i[i*4 +: 4] < 4'd8)
                        simple_result_c[i*4 +: 4] =
                            4'(req_a_i >> {req_b_i[i*4 +: 4], 2'b00});
            end
            BM_XPERM8: if (CFG_ZBKX) begin
                for (i = 0; i < 4; i = i + 1)
                    if (req_b_i[i*8 +: 8] < 8'd4)
                        simple_result_c[i*8 +: 8] =
                            8'(req_a_i >> {req_b_i[i*8 +: 8], 3'b000});
            end
            BM_BCLR: if (CFG_ZBS) simple_result_c = req_a_i & ~(32'b1 << shamt_c);
            BM_BEXT: if (CFG_ZBS) simple_result_c = {31'd0, req_a_i[shamt_c]};
            BM_BINV: if (CFG_ZBS) simple_result_c = req_a_i ^ (32'b1 << shamt_c);
            BM_BSET: if (CFG_ZBS) simple_result_c = req_a_i | (32'b1 << shamt_c);
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            resp_valid_q <= 1'b0;
            resp_tid_q <= '0;
            resp_result_q <= '0;
            clmul_busy_q <= 1'b0;
            clmul_tid_q <= '0;
            clmul_op_q <= BM_CLMUL;
            clmul_iter_q <= '0;
            clmul_acc_q <= '0;
            clmul_multiplicand_q <= '0;
            clmul_multiplier_q <= '0;
        end else begin
            resp_valid_q <= 1'b0;
            if (kill_i) begin
                clmul_busy_q <= 1'b0;
            end else if (clmul_busy_q) begin
                clmul_acc_q <= clmul_acc_next_c;
                clmul_multiplicand_q <= clmul_multiplicand_q << 1;
                clmul_multiplier_q <= clmul_multiplier_q >> 1;
                if (clmul_iter_q == 6'd31) begin
                    clmul_busy_q <= 1'b0;
                    resp_valid_q <= 1'b1;
                    resp_tid_q <= clmul_tid_q;
                    unique case (clmul_op_q)
                        BM_CLMUL:  resp_result_q <= clmul_acc_next_c[31:0];
                        BM_CLMULH: resp_result_q <= clmul_acc_next_c[63:32];
                        default:   resp_result_q <= clmul_acc_next_c[62:31];
                    endcase
                end else begin
                    clmul_iter_q <= clmul_iter_q + 1'b1;
                end
            end else if (req_valid_i && req_ready_o) begin
                if (req_is_clmul_c) begin
                    clmul_busy_q <= 1'b1;
                    clmul_tid_q <= req_trans_id_i;
                    clmul_op_q <= req_op_i;
                    clmul_iter_q <= '0;
                    clmul_acc_q <= '0;
                    clmul_multiplicand_q <= {32'd0, req_a_i};
                    clmul_multiplier_q <= req_b_i;
                end else begin
                    resp_valid_q <= 1'b1;
                    resp_tid_q <= req_trans_id_i;
                    resp_result_q <= simple_result_c;
                end
            end
        end
    end
endmodule
