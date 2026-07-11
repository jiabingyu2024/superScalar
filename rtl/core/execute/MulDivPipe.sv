import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreMulDivPipe #(
    parameter int MUL_LATENCY = 2
) (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    output logic ready_o,
    input  logic valid_i,
    input  CoreRenamedUop uop_i,
    input  DataPath src0_i,
    input  DataPath src1_i,

    output logic complete_valid_o,
    output CoreRenamedUop complete_uop_o,
    output DataPath complete_result_o
);
    typedef enum logic [1:0] {
        MD_IDLE,
        MD_DIV_WAIT,
        MD_SPECIAL
    } MdState;

    MdState state_q;
    CoreRenamedUop active_uop_q;
    CoreMulDivOp active_op_q;
    logic [MUL_LATENCY-1:0] mul_valid_q;
    CoreRenamedUop mul_uop_q [MUL_LATENCY-1:0];
    CoreMulDivOp mul_op_q [MUL_LATENCY-1:0];
    DataPath div_abs_a_q;
    DataPath div_abs_b_q;
    logic div_start_q;
    logic div_quot_neg_q;
    logic div_rem_neg_q;
    logic div_drain_q;
    DataPath special_result_q;

    logic start;
    logic start_mul;
    logic start_div;
    logic div_special;
    DataPath div_special_result;
    logic signed [32:0] mul_a;
    logic signed [32:0] mul_b;
    logic signed [65:0] mul_product;
    DataPath div_abs_a;
    DataPath div_abs_b;
    logic div_start;
    logic div_valid;
    logic [63:0] div_data;
    DataPath div_quot_u;
    DataPath div_rem_u;
    DataPath div_result;
    logic mul_pipe_empty;

    function automatic DataPath abs32(input DataPath value);
        begin
            abs32 = value[31] ? (~value + 32'd1) : value;
        end
    endfunction

    function automatic logic is_mul_op(input CoreMulDivOp op);
        begin
            unique case (op)
                MULDIV_OP_MUL,
                MULDIV_OP_MULH,
                MULDIV_OP_MULHSU,
                MULDIV_OP_MULHU: is_mul_op = 1'b1;
                default: is_mul_op = 1'b0;
            endcase
        end
    endfunction

    function automatic logic is_div_op(input CoreMulDivOp op);
        begin
            unique case (op)
                MULDIV_OP_DIV,
                MULDIV_OP_DIVU,
                MULDIV_OP_REM,
                MULDIV_OP_REMU: is_div_op = 1'b1;
                default: is_div_op = 1'b0;
            endcase
        end
    endfunction

    function automatic DataPath special_div_result(
        input CoreMulDivOp op,
        input DataPath a,
        input DataPath b
    );
        begin
            unique case (op)
                MULDIV_OP_DIV,
                MULDIV_OP_DIVU: special_div_result = (b == 32'b0) ? 32'hffff_ffff :
                                                      32'h8000_0000;
                MULDIV_OP_REM,
                MULDIV_OP_REMU: special_div_result = (b == 32'b0) ? a : 32'b0;
                default: special_div_result = 32'b0;
            endcase
        end
    endfunction

    assign mul_pipe_empty = !(|mul_valid_q);
    assign ready_o = (state_q == MD_IDLE) && !clear_i && !div_drain_q &&
                     (!(valid_i && is_div_op(uop_i.uop.muldiv_op)) ||
                      mul_pipe_empty);

    always_comb begin
        start = valid_i && ready_o;
        start_mul = start && is_mul_op(uop_i.uop.muldiv_op);
        start_div = start && is_div_op(uop_i.uop.muldiv_op);
        div_special = start_div &&
                      ((src1_i == 32'b0) ||
                       ((uop_i.uop.muldiv_op == MULDIV_OP_DIV ||
                         uop_i.uop.muldiv_op == MULDIV_OP_REM) &&
                        src0_i == 32'h8000_0000 && src1_i == 32'hffff_ffff));
        div_special_result = special_div_result(uop_i.uop.muldiv_op, src0_i, src1_i);

        unique case (uop_i.uop.muldiv_op)
            MULDIV_OP_MUL,
            MULDIV_OP_MULH: begin
                mul_a = {src0_i[31], src0_i};
                mul_b = {src1_i[31], src1_i};
            end
            MULDIV_OP_MULHSU: begin
                mul_a = {src0_i[31], src0_i};
                mul_b = {1'b0, src1_i};
            end
            default: begin
                mul_a = {1'b0, src0_i};
                mul_b = {1'b0, src1_i};
            end
        endcase

        div_abs_a = ((uop_i.uop.muldiv_op == MULDIV_OP_DIV ||
                      uop_i.uop.muldiv_op == MULDIV_OP_REM) && src0_i[31]) ?
                    abs32(src0_i) : src0_i;
        div_abs_b = ((uop_i.uop.muldiv_op == MULDIV_OP_DIV ||
                      uop_i.uop.muldiv_op == MULDIV_OP_REM) && src1_i[31]) ?
                    abs32(src1_i) : src1_i;
        div_start = start_div && !div_special;

        div_quot_u = div_data[63:32];
        div_rem_u = div_data[31:0];
        unique case (active_op_q)
            MULDIV_OP_DIV:  div_result = div_quot_neg_q ? (~div_quot_u + 32'd1) : div_quot_u;
            MULDIV_OP_DIVU: div_result = div_quot_u;
            MULDIV_OP_REM:  div_result = div_rem_neg_q ? (~div_rem_u + 32'd1) : div_rem_u;
            MULDIV_OP_REMU: div_result = div_rem_u;
            default:        div_result = 32'b0;
        endcase

        complete_valid_o = 1'b0;
        complete_uop_o = active_uop_q;
        complete_result_o = 32'b0;

        if (!clear_i && mul_valid_q[MUL_LATENCY-1]) begin
            complete_valid_o = 1'b1;
            complete_uop_o = mul_uop_q[MUL_LATENCY-1];
            unique case (mul_op_q[MUL_LATENCY-1])
                MULDIV_OP_MUL:    complete_result_o = mul_product[31:0];
                MULDIV_OP_MULH,
                MULDIV_OP_MULHSU,
                MULDIV_OP_MULHU:  complete_result_o = mul_product[63:32];
                default:          complete_result_o = 32'b0;
            endcase
        end else if (!clear_i && state_q == MD_DIV_WAIT && div_valid) begin
            complete_valid_o = 1'b1;
            complete_result_o = div_result;
        end else if (!clear_i && state_q == MD_SPECIAL) begin
            complete_valid_o = 1'b1;
            complete_result_o = special_result_q;
        end
    end

    MUL_0 u_mul (
        .CLK(clk),
        .A(mul_a),
        .B(mul_b),
        .P(mul_product)
    );

    DIV_0 u_div (
        .aclk(clk),
        .s_axis_dividend_tvalid(div_start_q),
        .s_axis_dividend_tready(),
        .s_axis_dividend_tdata(div_abs_a_q),
        .s_axis_divisor_tvalid(div_start_q),
        .s_axis_divisor_tready(),
        .s_axis_divisor_tdata(div_abs_b_q),
        .m_axis_dout_tvalid(div_valid),
        .m_axis_dout_tdata(div_data)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= MD_IDLE;
            mul_valid_q <= '0;
            div_start_q <= 1'b0;
            div_drain_q <= 1'b0;
        end else if (clear_i) begin
            state_q <= MD_IDLE;
            mul_valid_q <= '0;
            div_start_q <= 1'b0;
            div_drain_q <= ((div_drain_q || (state_q == MD_DIV_WAIT)) && !div_valid);
        end else begin
            div_start_q <= 1'b0;
            mul_valid_q[0] <= start_mul;
            for (int i = 1; i < MUL_LATENCY; i = i + 1) begin
                mul_valid_q[i] <= mul_valid_q[i-1];
            end
            if (div_drain_q && div_valid) begin
                div_drain_q <= 1'b0;
            end
            unique case (state_q)
                MD_IDLE: begin
                    if (start_div) begin
                        if (div_special) begin
                            state_q <= MD_SPECIAL;
                        end else begin
                            state_q <= MD_DIV_WAIT;
                            div_start_q <= div_start;
                        end
                    end
                end
                MD_DIV_WAIT: begin
                    if (div_valid) begin
                        state_q <= MD_IDLE;
                    end
                end
                MD_SPECIAL: begin
                    state_q <= MD_IDLE;
                end
                default: begin
                    state_q <= MD_IDLE;
                end
            endcase
        end
    end

    // Wide uop/data payload has no reset. State and valid bits above own the
    // payload lifetime, avoiding an asynchronous reset tree across the
    // multiplier metadata pipeline.
    always_ff @(posedge clk) begin
        for (int i = 1; i < MUL_LATENCY; i = i + 1) begin
            mul_uop_q[i] <= mul_uop_q[i-1];
            mul_op_q[i] <= mul_op_q[i-1];
        end
        if (start_mul) begin
            mul_uop_q[0] <= uop_i;
            mul_op_q[0] <= uop_i.uop.muldiv_op;
        end
        if (start_div) begin
            active_uop_q <= uop_i;
            active_op_q <= uop_i.uop.muldiv_op;
            div_abs_a_q <= div_abs_a;
            div_abs_b_q <= div_abs_b;
            div_quot_neg_q <= (uop_i.uop.muldiv_op == MULDIV_OP_DIV) &&
                              (src0_i[31] ^ src1_i[31]);
            div_rem_neg_q <= (uop_i.uop.muldiv_op == MULDIV_OP_REM) &&
                             src0_i[31];
            special_result_q <= div_special_result;
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && !clear_i) begin
            assert (!(mul_valid_q[MUL_LATENCY-1] &&
                      (((state_q == MD_DIV_WAIT) && div_valid) ||
                       (state_q == MD_SPECIAL))))
                else $error("MulDiv completion collision");
        end
    end
`endif
endmodule : CoreMulDivPipe
