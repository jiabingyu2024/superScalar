`timescale 1ns / 1ps

module MulDivUnit (
    input  logic        clk,
    input  logic        rst,

    input  logic        start,
    input  logic [2:0]  funct3,
    input  logic [31:0] lhs,
    input  logic [31:0] rhs,

    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    typedef enum logic [1:0] {
        MD_IDLE,
        MD_MUL_WAIT,
        MD_DIV_WAIT,
        MD_SPECIAL
    } state_e;

    state_e state_q;
    logic [2:0] funct3_q;
    logic [1:0] mul_count_q;
    logic [31:0] special_result_q;

    logic signed [32:0] mul_a_c;
    logic signed [32:0] mul_b_c;
    logic signed [65:0] mul_product;

    logic        div_start_c;
    logic [31:0] div_lhs_abs_c;
    logic [31:0] div_rhs_abs_c;
    logic        div_lhs_neg_q;
    logic        div_rhs_neg_q;
    logic        div_valid;
    logic [63:0] div_data;
    logic [31:0] div_quot_u;
    logic [31:0] div_rem_u;
    logic [31:0] div_quot_s;
    logic [31:0] div_rem_s;

    assign busy = (state_q != MD_IDLE);

    always_comb begin
        unique case (funct3)
            3'b000,
            3'b001: begin
                mul_a_c = {lhs[31], lhs};
                mul_b_c = {rhs[31], rhs};
            end
            3'b010: begin
                mul_a_c = {lhs[31], lhs};
                mul_b_c = {1'b0, rhs};
            end
            default: begin
                mul_a_c = {1'b0, lhs};
                mul_b_c = {1'b0, rhs};
            end
        endcase
    end

    MUL_0 mul_ip (
        .CLK(clk),
        .A  (mul_a_c),
        .B  (mul_b_c),
        .P  (mul_product)
    );

    always_comb begin
        div_lhs_abs_c = lhs;
        div_rhs_abs_c = rhs;
        if ((funct3 == 3'b100 || funct3 == 3'b110) && lhs[31]) begin
            div_lhs_abs_c = (~lhs) + 32'd1;
        end
        if (funct3 == 3'b100 && rhs[31]) begin
            div_rhs_abs_c = (~rhs) + 32'd1;
        end else if (funct3 == 3'b110 && rhs[31]) begin
            div_rhs_abs_c = (~rhs) + 32'd1;
        end
    end

    assign div_start_c = start && (funct3[2] == 1'b1) && (rhs != 32'd0) &&
                         !(lhs == 32'h8000_0000 && rhs == 32'hffff_ffff &&
                           (funct3 == 3'b100 || funct3 == 3'b110));

    DIV_0 div_ip (
        .aclk                  (clk),
        .s_axis_dividend_tvalid(div_start_c),
        .s_axis_dividend_tready(),
        .s_axis_dividend_tdata (div_lhs_abs_c),
        .s_axis_divisor_tvalid (div_start_c),
        .s_axis_divisor_tready (),
        .s_axis_divisor_tdata  (div_rhs_abs_c),
        .m_axis_dout_tvalid    (div_valid),
        .m_axis_dout_tdata     (div_data)
    );

    assign div_quot_u = div_data[31:0];
    assign div_rem_u = div_data[63:32];
    assign div_quot_s = (div_lhs_neg_q ^ div_rhs_neg_q) ? ((~div_quot_u) + 32'd1) : div_quot_u;
    assign div_rem_s = div_lhs_neg_q ? ((~div_rem_u) + 32'd1) : div_rem_u;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= MD_IDLE;
            funct3_q <= 3'd0;
            mul_count_q <= 2'd0;
            div_lhs_neg_q <= 1'b0;
            div_rhs_neg_q <= 1'b0;
            special_result_q <= 32'd0;
            done <= 1'b0;
            result <= 32'd0;
        end else begin
            done <= 1'b0;

            unique case (state_q)
                MD_IDLE: begin
                    if (start) begin
                        funct3_q <= funct3;
                        if (funct3[2] == 1'b0) begin
                            mul_count_q <= 2'd2;
                            state_q <= MD_MUL_WAIT;
                        end else if (rhs == 32'd0) begin
                            unique case (funct3)
                                3'b100,
                                3'b101: special_result_q <= 32'hffff_ffff;
                                default: special_result_q <= lhs;
                            endcase
                            state_q <= MD_SPECIAL;
                        end else if (lhs == 32'h8000_0000 && rhs == 32'hffff_ffff &&
                                     (funct3 == 3'b100 || funct3 == 3'b110)) begin
                            special_result_q <= (funct3 == 3'b100) ? 32'h8000_0000 : 32'd0;
                            state_q <= MD_SPECIAL;
                        end else begin
                            div_lhs_neg_q <= (funct3 == 3'b100 || funct3 == 3'b110) && lhs[31];
                            div_rhs_neg_q <= (funct3 == 3'b100) && rhs[31];
                            state_q <= MD_DIV_WAIT;
                        end
                    end
                end

                MD_MUL_WAIT: begin
                    if (mul_count_q == 2'd0) begin
                        done <= 1'b1;
                        unique case (funct3_q)
                            3'b000: result <= mul_product[31:0];
                            3'b001,
                            3'b010,
                            3'b011: result <= mul_product[63:32];
                            default: result <= 32'd0;
                        endcase
                        state_q <= MD_IDLE;
                    end else begin
                        mul_count_q <= mul_count_q - 2'd1;
                    end
                end

                MD_DIV_WAIT: begin
                    if (div_valid) begin
                        done <= 1'b1;
                        unique case (funct3_q)
                            3'b100: result <= div_quot_s;
                            3'b101: result <= div_quot_u;
                            3'b110: result <= div_rem_s;
                            3'b111: result <= div_rem_u;
                            default: result <= 32'd0;
                        endcase
                        state_q <= MD_IDLE;
                    end
                end

                MD_SPECIAL: begin
                    done <= 1'b1;
                    result <= special_result_q;
                    state_q <= MD_IDLE;
                end

                default: state_q <= MD_IDLE;
            endcase
        end
    end
endmodule
