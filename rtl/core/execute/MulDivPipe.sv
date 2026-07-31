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
    typedef enum logic [2:0] {
        MD_IDLE,
        MD_DIV_WAIT,
        MD_SPECIAL,
        MD_CLMUL_WAIT
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
    logic [63:0] clmul_acc_q;
    logic [63:0] clmul_multiplicand_q;
    DataPath clmul_multiplier_q;
    logic [4:0] clmul_count_q;

    logic start;
    logic start_mul;
    logic start_div;
    logic start_zb;
    logic start_zb_single;
    logic start_clmul;
    logic div_special;
    DataPath div_special_result;
    DataPath zb_single_result;
    logic [63:0] clmul_step_result;
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

    function automatic logic is_zb_op(input CoreMulDivOp op);
        begin
            is_zb_op = (op >= MULDIV_OP_SH1ADD) &&
                       (op <= MULDIV_OP_BSETI);
        end
    endfunction

    function automatic logic is_clmul_op(input CoreMulDivOp op);
        begin
            is_clmul_op = (op == MULDIV_OP_CLMUL) ||
                          (op == MULDIV_OP_CLMULH) ||
                          (op == MULDIV_OP_CLMULR);
        end
    endfunction

    function automatic DataPath reverse_bits_in_bytes(input DataPath value);
        DataPath reversed;
        begin
            reversed = '0;
            for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                    reversed[8*byte_idx + bit_idx] =
                        value[8*byte_idx + (7-bit_idx)];
                end
            end
            reverse_bits_in_bytes = reversed;
        end
    endfunction

    function automatic DataPath reverse_bytes(input DataPath value);
        begin
            reverse_bytes = {value[7:0], value[15:8],
                             value[23:16], value[31:24]};
        end
    endfunction

    function automatic DataPath count_leading_zeros(input DataPath value);
        DataPath count;
        logic found;
        begin
            count = 32'd32;
            found = 1'b0;
            for (int bit_idx = 31; bit_idx >= 0; bit_idx--) begin
                if (!found && value[bit_idx]) begin
                    count = DataPath'(31 - bit_idx);
                    found = 1'b1;
                end
            end
            count_leading_zeros = count;
        end
    endfunction

    function automatic DataPath count_trailing_zeros(input DataPath value);
        DataPath count;
        logic found;
        begin
            count = 32'd32;
            found = 1'b0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if (!found && value[bit_idx]) begin
                    count = DataPath'(bit_idx);
                    found = 1'b1;
                end
            end
            count_trailing_zeros = count;
        end
    endfunction

    function automatic DataPath population_count(input DataPath value);
        DataPath count;
        begin
            count = '0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                count = count + DataPath'(value[bit_idx]);
            end
            population_count = count;
        end
    endfunction

    function automatic DataPath or_combine_bytes(input DataPath value);
        DataPath combined;
        begin
            combined = '0;
            for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                combined[8*byte_idx +: 8] =
                    (|value[8*byte_idx +: 8]) ? 8'hff : 8'h00;
            end
            or_combine_bytes = combined;
        end
    endfunction

    function automatic DataPath rotate_left(
        input DataPath value,
        input logic [4:0] amount
    );
        logic [4:0] opposite;
        begin
            opposite = -amount;
            rotate_left = (value << amount) | (value >> opposite);
        end
    endfunction

    function automatic DataPath rotate_right(
        input DataPath value,
        input logic [4:0] amount
    );
        logic [4:0] opposite;
        begin
            opposite = -amount;
            rotate_right = (value >> amount) | (value << opposite);
        end
    endfunction

    function automatic DataPath zip_bits(input DataPath value);
        DataPath zipped;
        begin
            zipped = '0;
            for (int bit_idx = 0; bit_idx < 16; bit_idx++) begin
                zipped[2*bit_idx] = value[bit_idx];
                zipped[2*bit_idx + 1] = value[bit_idx + 16];
            end
            zip_bits = zipped;
        end
    endfunction

    function automatic DataPath unzip_bits(input DataPath value);
        DataPath unzipped;
        begin
            unzipped = '0;
            for (int bit_idx = 0; bit_idx < 16; bit_idx++) begin
                unzipped[bit_idx] = value[2*bit_idx];
                unzipped[bit_idx + 16] = value[2*bit_idx + 1];
            end
            unzip_bits = unzipped;
        end
    endfunction

    function automatic DataPath xperm4_result(
        input DataPath value,
        input DataPath index
    );
        DataPath permuted;
        logic [3:0] select;
        begin
            permuted = '0;
            for (int nibble = 0; nibble < 8; nibble++) begin
                select = index[4*nibble +: 4];
                if (select < 4'd8) begin
                    permuted[4*nibble +: 4] = value[4*select +: 4];
                end
            end
            xperm4_result = permuted;
        end
    endfunction

    function automatic DataPath xperm8_result(
        input DataPath value,
        input DataPath index
    );
        DataPath permuted;
        logic [7:0] select;
        begin
            permuted = '0;
            for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                select = index[8*byte_idx +: 8];
                if (select < 8'd4) begin
                    permuted[8*byte_idx +: 8] =
                        value[8*select +: 8];
                end
            end
            xperm8_result = permuted;
        end
    endfunction

    function automatic DataPath single_cycle_zb_result(
        input CoreMulDivOp op,
        input DataPath a,
        input DataPath b,
        input logic [4:0] immediate_index
    );
        logic [4:0] bit_index;
        begin
            bit_index = b[4:0];
            if (op == MULDIV_OP_BCLRI || op == MULDIV_OP_BEXTI ||
                op == MULDIV_OP_BINVI || op == MULDIV_OP_BSETI) begin
                bit_index = immediate_index;
            end
            unique case (op)
                MULDIV_OP_SH1ADD: single_cycle_zb_result = (a << 1) + b;
                MULDIV_OP_SH2ADD: single_cycle_zb_result = (a << 2) + b;
                MULDIV_OP_SH3ADD: single_cycle_zb_result = (a << 3) + b;
                MULDIV_OP_ANDN:   single_cycle_zb_result = a & ~b;
                MULDIV_OP_ORN:    single_cycle_zb_result = a | ~b;
                MULDIV_OP_XNOR:   single_cycle_zb_result = ~(a ^ b);
                MULDIV_OP_CLZ:    single_cycle_zb_result = count_leading_zeros(a);
                MULDIV_OP_CTZ:    single_cycle_zb_result = count_trailing_zeros(a);
                MULDIV_OP_CPOP:   single_cycle_zb_result = population_count(a);
                MULDIV_OP_MAX:    single_cycle_zb_result =
                    ($signed(a) < $signed(b)) ? b : a;
                MULDIV_OP_MAXU:   single_cycle_zb_result = (a < b) ? b : a;
                MULDIV_OP_MIN:    single_cycle_zb_result =
                    ($signed(a) < $signed(b)) ? a : b;
                MULDIV_OP_MINU:   single_cycle_zb_result = (a < b) ? a : b;
                MULDIV_OP_ORC_B:  single_cycle_zb_result = or_combine_bytes(a);
                MULDIV_OP_REV8:   single_cycle_zb_result = reverse_bytes(a);
                MULDIV_OP_ROL:    single_cycle_zb_result = rotate_left(a, b[4:0]);
                MULDIV_OP_ROR:    single_cycle_zb_result = rotate_right(a, b[4:0]);
                MULDIV_OP_RORI:   single_cycle_zb_result =
                    rotate_right(a, immediate_index);
                MULDIV_OP_SEXT_B: single_cycle_zb_result = {{24{a[7]}}, a[7:0]};
                MULDIV_OP_SEXT_H: single_cycle_zb_result = {{16{a[15]}}, a[15:0]};
                MULDIV_OP_ZEXT_H: single_cycle_zb_result = {16'b0, a[15:0]};
                MULDIV_OP_BREV8:  single_cycle_zb_result = reverse_bits_in_bytes(a);
                MULDIV_OP_PACK:   single_cycle_zb_result = {b[15:0], a[15:0]};
                MULDIV_OP_PACKH:  single_cycle_zb_result = {16'b0, b[7:0], a[7:0]};
                MULDIV_OP_ZIP:    single_cycle_zb_result = zip_bits(a);
                MULDIV_OP_UNZIP:  single_cycle_zb_result = unzip_bits(a);
                MULDIV_OP_XPERM4: single_cycle_zb_result = xperm4_result(a, b);
                MULDIV_OP_XPERM8: single_cycle_zb_result = xperm8_result(a, b);
                MULDIV_OP_BCLR,
                MULDIV_OP_BCLRI:  single_cycle_zb_result =
                    a & ~(32'b1 << bit_index);
                MULDIV_OP_BEXT,
                MULDIV_OP_BEXTI:  single_cycle_zb_result =
                    {31'b0, a[bit_index]};
                MULDIV_OP_BINV,
                MULDIV_OP_BINVI:  single_cycle_zb_result =
                    a ^ (32'b1 << bit_index);
                MULDIV_OP_BSET,
                MULDIV_OP_BSETI:  single_cycle_zb_result =
                    a | (32'b1 << bit_index);
                default:          single_cycle_zb_result = '0;
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
                     (!(valid_i && (is_div_op(uop_i.uop.muldiv_op) ||
                                    is_zb_op(uop_i.uop.muldiv_op))) ||
                      mul_pipe_empty);

    always_comb begin
        start = valid_i && ready_o;
        start_mul = start && is_mul_op(uop_i.uop.muldiv_op);
        start_div = start && is_div_op(uop_i.uop.muldiv_op);
        start_zb = start && is_zb_op(uop_i.uop.muldiv_op);
        start_clmul = start_zb && is_clmul_op(uop_i.uop.muldiv_op);
        start_zb_single = start_zb && !start_clmul;
        div_special = start_div &&
                      ((src1_i == 32'b0) ||
                       ((uop_i.uop.muldiv_op == MULDIV_OP_DIV ||
                         uop_i.uop.muldiv_op == MULDIV_OP_REM) &&
                        src0_i == 32'h8000_0000 && src1_i == 32'hffff_ffff));
        div_special_result = special_div_result(uop_i.uop.muldiv_op, src0_i, src1_i);
        zb_single_result = single_cycle_zb_result(
            uop_i.uop.muldiv_op, src0_i, src1_i, uop_i.uop.inst[24:20]
        );
        clmul_step_result = clmul_acc_q ^
            (clmul_multiplier_q[0] ? clmul_multiplicand_q : 64'b0);

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
        end else if (!clear_i && state_q == MD_CLMUL_WAIT &&
                     (clmul_count_q == 5'd31)) begin
            complete_valid_o = 1'b1;
            unique case (active_op_q)
                MULDIV_OP_CLMUL:  complete_result_o = clmul_step_result[31:0];
                MULDIV_OP_CLMULH: complete_result_o = clmul_step_result[63:32];
                MULDIV_OP_CLMULR: complete_result_o = clmul_step_result[62:31];
                default:          complete_result_o = '0;
            endcase
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
            clmul_count_q <= '0;
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
                    end else if (start_zb_single) begin
                        state_q <= MD_SPECIAL;
                    end else if (start_clmul) begin
                        state_q <= MD_CLMUL_WAIT;
                        clmul_count_q <= '0;
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
                MD_CLMUL_WAIT: begin
                    if (clmul_count_q == 5'd31) begin
                        state_q <= MD_IDLE;
                    end else begin
                        clmul_count_q <= clmul_count_q + 1'b1;
                    end
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
        if (!rst && !clear_i) begin
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
            if (start_zb) begin
                active_uop_q <= uop_i;
                active_op_q <= uop_i.uop.muldiv_op;
            end
            if (start_zb_single) begin
                special_result_q <= zb_single_result;
            end
            if (start_clmul) begin
                clmul_acc_q <= '0;
                clmul_multiplicand_q <= {32'b0, src0_i};
                clmul_multiplier_q <= src1_i;
            end else if (state_q == MD_CLMUL_WAIT) begin
                clmul_acc_q <= clmul_step_result;
                clmul_multiplicand_q <= clmul_multiplicand_q << 1;
                clmul_multiplier_q <= clmul_multiplier_q >> 1;
            end
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
