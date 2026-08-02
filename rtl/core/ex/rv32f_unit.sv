`include "cpu_defines.svh"

// RV32F execution unit shared by simulation and FPGA builds.
//
// Expensive IEEE-754 operations are issued to Xilinx Floating-Point Operator
// module names.  Vivado creates those modules in create_vivado_project.tcl;
// Simulation gets same-name behavioural models from rtl/ip.  Keeping the IP
// boundary here prevents floating-point arithmetic from entering integer EX
// timing cones.
module rv32f_unit(
    input  logic             i_clk,
    input  logic             i_rst_n,
    input  logic             i_start,
    input  logic             i_flush,
    input  logic [`INST_BUS] i_instr,
    input  logic [`DATA_BUS] i_frs1,
    input  logic [`DATA_BUS] i_frs2,
    input  logic [`DATA_BUS] i_frs3,
    input  logic [`DATA_BUS] i_xrs1,
    input  logic [2:0]       i_frm,
    output logic             o_busy,
    output logic             o_done,
    output logic [`DATA_BUS] o_result,
    output logic [4:0]       o_fflags
);
    localparam logic [4:0] FFLAG_NX = 5'b00001;
    localparam logic [4:0] FFLAG_UF = 5'b00010;
    localparam logic [4:0] FFLAG_OF = 5'b00100;
    localparam logic [4:0] FFLAG_DZ = 5'b01000;
    localparam logic [4:0] FFLAG_NV = 5'b10000;

    typedef enum logic [2:0] {
        F_KIND_NONE,
        F_KIND_LOCAL,
        F_KIND_FMA,
        F_KIND_DIV,
        F_KIND_SQRT
    } f_kind_t;

    function automatic logic fp_is_nan(input logic [31:0] value);
        fp_is_nan = (&value[30:23]) && (|value[22:0]);
    endfunction

    function automatic logic fp_is_snan(input logic [31:0] value);
        fp_is_snan = fp_is_nan(value) && !value[22];
    endfunction

    function automatic logic fp_is_inf(input logic [31:0] value);
        fp_is_inf = (&value[30:23]) && !(|value[22:0]);
    endfunction

    function automatic logic fp_is_zero(input logic [31:0] value);
        fp_is_zero = !(|value[30:0]);
    endfunction

    function automatic logic fp_eq(input logic [31:0] a, input logic [31:0] b);
        fp_eq = (a == b) || (fp_is_zero(a) && fp_is_zero(b));
    endfunction

    function automatic logic fp_lt(input logic [31:0] a, input logic [31:0] b);
        if (fp_eq(a, b)) begin
            fp_lt = 1'b0;
        end else if (a[31] != b[31]) begin
            fp_lt = a[31];
        end else if (!a[31]) begin
            fp_lt = (a[30:0] < b[30:0]);
        end else begin
            fp_lt = (a[30:0] > b[30:0]);
        end
    endfunction

    function automatic logic [31:0] fp_class(input logic [31:0] value);
        logic sign;
        logic [7:0] exp;
        logic [22:0] frac;
        begin
            sign = value[31];
            exp  = value[30:23];
            frac = value[22:0];
            fp_class = '0;
            if (exp == 8'hff) begin
                if (frac == 0) fp_class[sign ? 0 : 7] = 1'b1;
                else if (frac[22]) fp_class[9] = 1'b1;
                else fp_class[8] = 1'b1;
            end else if (exp == 0) begin
                if (frac == 0) fp_class[sign ? 3 : 4] = 1'b1;
                else fp_class[sign ? 2 : 5] = 1'b1;
            end else begin
                fp_class[sign ? 1 : 6] = 1'b1;
            end
        end
    endfunction

    function automatic logic round_up(
        input logic [2:0] rm,
        input logic sign,
        input logic inexact,
        input logic greater_half,
        input logic exactly_half,
        input logic lsb
    );
        case (rm)
            3'b000: round_up = greater_half || (exactly_half && lsb); // RNE
            3'b001: round_up = 1'b0;                                 // RTZ
            3'b010: round_up = sign && inexact;                       // RDN
            3'b011: round_up = !sign && inexact;                      // RUP
            3'b100: round_up = greater_half || exactly_half;          // RMM
            default: round_up = greater_half || (exactly_half && lsb);
        endcase
    endfunction

    // Returns {fflags, integer result}.
    function automatic logic [36:0] fp_to_int(
        input logic [31:0] value,
        input logic is_unsigned,
        input logic [2:0] rm
    );
        logic sign;
        logic [7:0] exp;
        logic [22:0] frac;
        logic [23:0] mant;
        logic signed [10:0] unbiased_exp;
        logic [63:0] mag;
        logic [63:0] rem;
        logic [63:0] half;
        logic [63:0] rounded_mag;
        logic inexact, greater_half, exactly_half, increment, invalid;
        logic [31:0] result;
        logic [4:0] flags;
        integer shift;
        begin
            sign = value[31];
            exp  = value[30:23];
            frac = value[22:0];
            mant = (exp == 0) ? {1'b0, frac} : {1'b1, frac};
            unbiased_exp = (exp == 0) ? -11'sd126 : $signed({3'b000, exp}) - 11'sd127;
            mag = '0;
            rem = '0;
            half = '0;
            inexact = 1'b0;
            greater_half = 1'b0;
            exactly_half = 1'b0;
            invalid = 1'b0;
            result = '0;
            flags = '0;

            if (exp == 8'hff) begin
                invalid = 1'b1;
                if (is_unsigned) result = sign && !fp_is_nan(value) ? 32'h00000000 : 32'hffffffff;
                else result = sign && !fp_is_nan(value) ? 32'h80000000 : 32'h7fffffff;
            end else begin
                if (unbiased_exp < 0) begin
                    inexact = |value[30:0];
                    if ((unbiased_exp == -1) && (exp != 0)) begin
                        exactly_half = (mant == 24'h800000);
                        greater_half = (mant > 24'h800000);
                    end
                end else if (unbiased_exp >= 23) begin
                    shift = $signed({{21{unbiased_exp[10]}}, unbiased_exp});
                    shift = shift - 23;
                    if (shift < 40) mag = {40'b0, mant} << shift;
                    else mag = 64'hffffffffffffffff;
                end else begin
                    shift = $signed({{21{unbiased_exp[10]}}, unbiased_exp});
                    shift = 23 - shift;
                    mag = {40'b0, mant} >> shift;
                    rem = {40'b0, mant} & ((64'h1 << shift) - 1);
                    half = 64'h1 << (shift - 1);
                    inexact = (rem != 0);
                    greater_half = (rem > half);
                    exactly_half = (rem == half);
                end

                increment = round_up(rm, sign, inexact, greater_half,
                                     exactly_half, mag[0]);
                rounded_mag = mag + {63'b0, increment};
                if (is_unsigned) begin
                    if ((sign && (rounded_mag != 0)) || (rounded_mag > 64'hffffffff)) begin
                        invalid = 1'b1;
                        result = sign ? 32'h00000000 : 32'hffffffff;
                    end else begin
                        result = rounded_mag[31:0];
                    end
                end else if (!sign && (rounded_mag > 64'h7fffffff)) begin
                    invalid = 1'b1;
                    result = 32'h7fffffff;
                end else if (sign && (rounded_mag > 64'h80000000)) begin
                    invalid = 1'b1;
                    result = 32'h80000000;
                end else begin
                    result = sign ? (~rounded_mag[31:0] + 32'd1) : rounded_mag[31:0];
                end
            end

            if (invalid) flags = FFLAG_NV;
            else if (inexact) flags = FFLAG_NX;
            fp_to_int = {flags, result};
        end
    endfunction

    // Returns {fflags, IEEE-754 single result}.
    function automatic logic [36:0] int_to_fp(
        input logic [31:0] value,
        input logic is_unsigned,
        input logic [2:0] rm
    );
        logic sign;
        logic [31:0] mag;
        logic [23:0] sig;
        logic [24:0] rounded_sig;
        logic [31:0] rem;
        logic [31:0] half;
        logic [7:0] exponent;
        logic inexact, greater_half, exactly_half, increment, found;
        logic [31:0] result;
        integer msb, shift, idx;
        begin
            sign = !is_unsigned && value[31];
            mag = sign ? (~value + 32'd1) : value;
            sig = '0;
            rem = '0;
            half = '0;
            exponent = '0;
            inexact = 1'b0;
            greater_half = 1'b0;
            exactly_half = 1'b0;
            increment = 1'b0;
            found = 1'b0;
            msb = 0;
            result = '0;

            for (idx = 31; idx >= 0; idx = idx - 1) begin
                if (!found && mag[idx]) begin
                    msb = idx;
                    found = 1'b1;
                end
            end

            if (mag != 0) begin
                exponent = 8'(msb + 127);
                if (msb <= 23) begin
                    sig = 24'(mag << (23 - msb));
                end else begin
                    shift = msb - 23;
                    sig = 24'(mag >> shift);
                    rem = mag & ((32'h1 << shift) - 1);
                    half = 32'h1 << (shift - 1);
                    inexact = (rem != 0);
                    greater_half = (rem > half);
                    exactly_half = (rem == half);
                    increment = round_up(rm, sign, inexact, greater_half,
                                         exactly_half, sig[0]);
                end
                rounded_sig = {1'b0, sig} + {24'b0, increment};
                if (rounded_sig[24]) begin
                    exponent = exponent + 1'b1;
                    sig = rounded_sig[24:1];
                end else begin
                    sig = rounded_sig[23:0];
                end
                result = {sign, exponent, sig[22:0]};
            end
            int_to_fp = {inexact ? FFLAG_NX : 5'b0, result};
        end
    endfunction

    function automatic logic [36:0] local_exec(
        input logic [31:0] instr,
        input logic [31:0] frs1,
        input logic [31:0] frs2,
        input logic [31:0] xrs1,
        input logic [2:0] frm
    );
        logic [6:0] funct7;
        logic [2:0] funct3;
        logic [4:0] rs2;
        logic [2:0] rm;
        logic [31:0] result;
        logic [4:0] flags;
        logic nan_a, nan_b, invalid;
        begin
            funct7 = instr[31:25];
            funct3 = instr[14:12];
            rs2 = instr[24:20];
            rm = (funct3 == 3'b111) ? frm : funct3;
            result = 32'h7fc00000;
            flags = FFLAG_NV;
            nan_a = fp_is_nan(frs1);
            nan_b = fp_is_nan(frs2);
            invalid = 1'b0;

            case (funct7)
                7'h10: begin // FSGNJ/FSGNJN/FSGNJX
                    flags = '0;
                    case (funct3)
                        3'b000: result = {frs2[31], frs1[30:0]};
                        3'b001: result = {~frs2[31], frs1[30:0]};
                        default: result = {frs1[31] ^ frs2[31], frs1[30:0]};
                    endcase
                end
                7'h14: begin // FMIN/FMAX
                    flags = (fp_is_snan(frs1) || fp_is_snan(frs2)) ? FFLAG_NV : 5'b0;
                    if (nan_a && nan_b) result = 32'h7fc00000;
                    else if (nan_a) result = frs2;
                    else if (nan_b) result = frs1;
                    else if (fp_eq(frs1, frs2)) begin
                        result = (funct3 == 0) ? (frs1 | frs2) : (frs1 & frs2);
                    end else if (funct3 == 0) begin
                        result = fp_lt(frs1, frs2) ? frs1 : frs2;
                    end else begin
                        result = fp_lt(frs1, frs2) ? frs2 : frs1;
                    end
                end
                7'h50: begin // FEQ/FLT/FLE
                    invalid = ((funct3 != 3'b010) && (nan_a || nan_b)) ||
                              fp_is_snan(frs1) || fp_is_snan(frs2);
                    flags = invalid ? FFLAG_NV : 5'b0;
                    if (nan_a || nan_b) result = 0;
                    else if (funct3 == 3'b010) result = {31'b0, fp_eq(frs1, frs2)};
                    else if (funct3 == 3'b001) result = {31'b0, fp_lt(frs1, frs2)};
                    else result = {31'b0, fp_lt(frs1, frs2) || fp_eq(frs1, frs2)};
                end
                7'h60: local_exec = fp_to_int(frs1, rs2 == 1, rm);
                7'h68: local_exec = int_to_fp(xrs1, rs2 == 1, rm);
                7'h70: begin
                    flags = '0;
                    result = (funct3 == 0) ? frs1 : fp_class(frs1);
                end
                7'h78: begin
                    flags = '0;
                    result = xrs1;
                end
                default: begin end
            endcase

            if ((funct7 != 7'h60) && (funct7 != 7'h68))
                local_exec = {flags, result};
        end
    endfunction

    function automatic logic [4:0] fma_input_flags(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] c
    );
        logic invalid;
        logic product_inf;
        begin
            product_inf = (fp_is_inf(a) && !fp_is_zero(b) && !fp_is_nan(b)) ||
                          (fp_is_inf(b) && !fp_is_zero(a) && !fp_is_nan(a));
            invalid = fp_is_snan(a) || fp_is_snan(b) || fp_is_snan(c) ||
                      (fp_is_inf(a) && fp_is_zero(b)) ||
                      (fp_is_inf(b) && fp_is_zero(a)) ||
                      (product_inf && fp_is_inf(c) && ((a[31] ^ b[31]) != c[31]));
            fma_input_flags = invalid ? FFLAG_NV : 5'b0;
        end
    endfunction

    function automatic logic [23:0] fp_mantissa(input logic [31:0] value);
        fp_mantissa = (value[30:23] == 0) ? {1'b0, value[22:0]} :
                                                  {1'b1, value[22:0]};
    endfunction

    // value = mantissa * 2**scale for every finite IEEE-754 single value.
    function automatic integer fp_scale(input logic [31:0] value);
        if (value[30:23] == 0) begin
            fp_scale = -149;
        end else begin
            fp_scale = {24'b0, value[30:23]};
            fp_scale = fp_scale - 150;
        end
    endfunction

    // Exact real-number check for a*b == target.  Canonicalizing powers of two
    // avoids a wide exponent-alignment shifter and keeps DIV/SQRT NX checking
    // compact (one 24x24 product plus priority encoders).
    function automatic logic fp_mul_matches(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] target
    );
        logic [47:0] product;
        logic [47:0] product_canon;
        logic [23:0] target_mant;
        logic [23:0] target_canon;
        logic found_product, found_target;
        integer product_shift, target_shift;
        integer product_scale, target_scale;
        integer idx;
        begin
            if (fp_is_nan(a) || fp_is_nan(b) || fp_is_nan(target) ||
                fp_is_inf(a) || fp_is_inf(b) || fp_is_inf(target)) begin
                fp_mul_matches = 1'b1;
            end else if (fp_is_zero(a) || fp_is_zero(b)) begin
                fp_mul_matches = fp_is_zero(target);
            end else if (fp_is_zero(target)) begin
                fp_mul_matches = 1'b0;
            end else begin
                product = fp_mantissa(a) * fp_mantissa(b);
                target_mant = fp_mantissa(target);
                product_shift = 0;
                target_shift = 0;
                found_product = 1'b0;
                found_target = 1'b0;
                for (idx = 0; idx < 48; idx = idx + 1) begin
                    if (!found_product && product[idx]) begin
                        product_shift = idx;
                        found_product = 1'b1;
                    end
                end
                for (idx = 0; idx < 24; idx = idx + 1) begin
                    if (!found_target && target_mant[idx]) begin
                        target_shift = idx;
                        found_target = 1'b1;
                    end
                end
                product_canon = product >> product_shift;
                target_canon = target_mant >> target_shift;
                product_scale = fp_scale(a) + fp_scale(b) + product_shift;
                target_scale = fp_scale(target) + target_shift;
                fp_mul_matches = ((a[31] ^ b[31]) == target[31]) &&
                                 (product_canon == {24'b0, target_canon}) &&
                                 (product_scale == target_scale);
            end
        end
    endfunction

    // Exact real-number check for a*b+c == target.  Exponent gaps larger than
    // the bounded alignment window cannot fit in a 24-bit result when both
    // terms are non-zero, so they are immediately classified as inexact.
    function automatic logic fp_fma_matches(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] c,
        input logic [31:0] target
    );
        logic [47:0] product;
        logic [23:0] c_mant, target_mant;
        logic signed [127:0] product_term, c_term, exact_sum;
        logic [127:0] sum_mag, sum_canon;
        logic [23:0] target_canon;
        logic found_sum, found_target;
        integer product_scale, c_scale, base_scale;
        integer product_delta, c_delta;
        integer sum_shift, target_shift, target_scale;
        integer idx;
        begin
            if (fp_is_nan(a) || fp_is_nan(b) || fp_is_nan(c) || fp_is_nan(target) ||
                fp_is_inf(a) || fp_is_inf(b) || fp_is_inf(c)) begin
                fp_fma_matches = 1'b1;
            end else if (fp_is_inf(target)) begin
                fp_fma_matches = 1'b0;
            end else begin
                product = fp_mantissa(a) * fp_mantissa(b);
                c_mant = fp_mantissa(c);
                target_mant = fp_mantissa(target);
                if (product == 0) begin
                    fp_fma_matches = fp_eq(c, target);
                end else if (c_mant == 0) begin
                    fp_fma_matches = fp_mul_matches(a, b, target);
                end else begin
                    product_scale = fp_scale(a) + fp_scale(b);
                    c_scale = fp_scale(c);
                    base_scale = (product_scale < c_scale) ? product_scale : c_scale;
                    product_delta = product_scale - base_scale;
                    c_delta = c_scale - base_scale;

                if ((product_delta > 79) || (c_delta > 79)) begin
                    fp_fma_matches = 1'b0;
                end else begin
                    product_term = $signed({80'b0, product});
                    c_term = $signed({104'b0, c_mant});
                    if (a[31] ^ b[31]) product_term = -product_term;
                    if (c[31]) c_term = -c_term;
                    product_term = product_term <<< product_delta;
                    c_term = c_term <<< c_delta;
                    exact_sum = product_term + c_term;
                    sum_mag = exact_sum[127] ? -exact_sum : exact_sum;

                    if (sum_mag == 0) begin
                        fp_fma_matches = fp_is_zero(target);
                    end else if (fp_is_zero(target)) begin
                        fp_fma_matches = 1'b0;
                    end else begin
                        sum_shift = 0;
                        target_shift = 0;
                        found_sum = 1'b0;
                        found_target = 1'b0;
                        for (idx = 0; idx < 128; idx = idx + 1) begin
                            if (!found_sum && sum_mag[idx]) begin
                                sum_shift = idx;
                                found_sum = 1'b1;
                            end
                        end
                        for (idx = 0; idx < 24; idx = idx + 1) begin
                            if (!found_target && target_mant[idx]) begin
                                target_shift = idx;
                                found_target = 1'b1;
                            end
                        end
                        sum_canon = sum_mag >> sum_shift;
                        target_canon = target_mant >> target_shift;
                        target_scale = fp_scale(target) + target_shift;
                        fp_fma_matches = (exact_sum[127] == target[31]) &&
                                         (sum_canon == {104'b0, target_canon}) &&
                                         ((base_scale + sum_shift) == target_scale);
                    end
                end
                end
            end
        end
    endfunction

    logic [6:0] opcode;
    logic [6:0] funct7;
    f_kind_t issue_kind;
    f_kind_t active_kind_q;
    f_kind_t drain_kind_q;
    logic busy_q;
    logic local_pending_q;
    logic [36:0] local_payload_q;
    logic [4:0] arithmetic_flags_q;
    logic [31:0] arithmetic_a_q, arithmetic_b_q, arithmetic_c_q;

    logic [31:0] fma_a, fma_b, fma_c;
    logic fma_in_valid, div_in_valid, sqrt_in_valid;
    logic fma_out_valid, div_out_valid, sqrt_out_valid;
    logic [31:0] fma_out, div_out, sqrt_out;
    logic fma_exact, div_exact, sqrt_exact;
    logic [4:0] fma_result_flags, div_result_flags, sqrt_result_flags;

    assign opcode = i_instr[6:0];
    assign funct7 = i_instr[31:25];

    always_comb begin
        issue_kind = F_KIND_LOCAL;
        if ((opcode == `OP_F_MADD) || (opcode == `OP_F_MSUB) ||
            (opcode == `OP_F_NMSUB) || (opcode == `OP_F_NMADD)) begin
            issue_kind = F_KIND_FMA;
        end else if (opcode == `OP_F_TYPE) begin
            case (funct7)
                7'h00, 7'h04, 7'h08: issue_kind = F_KIND_FMA;
                7'h0c: issue_kind = F_KIND_DIV;
                7'h2c: issue_kind = F_KIND_SQRT;
                default: issue_kind = F_KIND_LOCAL;
            endcase
        end
    end

    // One FMA datapath is shared by add, subtract, multiply and all four fused
    // operations.  This is the main area-saving choice; sign changes happen
    // before the registered IP boundary.
    always_comb begin
        fma_a = i_frs1;
        fma_b = i_frs2;
        fma_c = i_frs3;
        if ((opcode == `OP_F_TYPE) && (funct7 == 7'h00)) begin
            fma_b = 32'h3f800000;
            fma_c = i_frs2;
        end else if ((opcode == `OP_F_TYPE) && (funct7 == 7'h04)) begin
            fma_b = 32'h3f800000;
            fma_c = {~i_frs2[31], i_frs2[30:0]};
        end else if ((opcode == `OP_F_TYPE) && (funct7 == 7'h08)) begin
            fma_c = {i_frs1[31] ^ i_frs2[31], 31'b0};
        end else if (opcode == `OP_F_MSUB) begin
            fma_c = {~i_frs3[31], i_frs3[30:0]};
        end else if (opcode == `OP_F_NMSUB) begin
            fma_a = {~i_frs1[31], i_frs1[30:0]};
        end else if (opcode == `OP_F_NMADD) begin
            fma_a = {~i_frs1[31], i_frs1[30:0]};
            fma_c = {~i_frs3[31], i_frs3[30:0]};
        end
    end

    assign fma_in_valid  = i_start && (issue_kind == F_KIND_FMA);
    assign div_in_valid  = i_start && (issue_kind == F_KIND_DIV);
    assign sqrt_in_valid = i_start && (issue_kind == F_KIND_SQRT);
    assign fma_exact = fp_fma_matches(arithmetic_a_q, arithmetic_b_q,
                                      arithmetic_c_q, fma_out);
    assign div_exact = fp_mul_matches(div_out, arithmetic_b_q, arithmetic_a_q);
    assign sqrt_exact = fp_mul_matches(sqrt_out, sqrt_out, arithmetic_a_q);

    always_comb begin
        fma_result_flags = arithmetic_flags_q;
        if (!fma_exact) fma_result_flags = fma_result_flags | FFLAG_NX;
        if (!arithmetic_flags_q[4] && fp_is_inf(fma_out) &&
            !fp_is_inf(arithmetic_a_q) && !fp_is_inf(arithmetic_b_q) &&
            !fp_is_inf(arithmetic_c_q))
            fma_result_flags = fma_result_flags | FFLAG_OF | FFLAG_NX;
        if (!arithmetic_flags_q[4] && !fma_exact && (fma_out[30:23] == 0))
            fma_result_flags = fma_result_flags | FFLAG_UF;

        div_result_flags = arithmetic_flags_q;
        if (!div_exact) div_result_flags = div_result_flags | FFLAG_NX;
        if (!(|arithmetic_flags_q[4:3]) && fp_is_inf(div_out) &&
            !fp_is_inf(arithmetic_a_q) && !fp_is_inf(arithmetic_b_q))
            div_result_flags = div_result_flags | FFLAG_OF | FFLAG_NX;
        if (!(|arithmetic_flags_q[4:3]) && !div_exact && (div_out[30:23] == 0))
            div_result_flags = div_result_flags | FFLAG_UF;

        sqrt_result_flags = arithmetic_flags_q;
        if (!sqrt_exact) sqrt_result_flags = sqrt_result_flags | FFLAG_NX;
        if (!arithmetic_flags_q[4] && !sqrt_exact && (sqrt_out[30:23] == 0))
            sqrt_result_flags = sqrt_result_flags | FFLAG_UF;
    end

    FP_FMA_0 u_fp_fma (
        .aclk                  (i_clk),
        .aresetn               (i_rst_n),
        .s_axis_a_tvalid       (fma_in_valid),
        .s_axis_a_tdata        (fma_a),
        .s_axis_b_tvalid       (fma_in_valid),
        .s_axis_b_tdata        (fma_b),
        .s_axis_c_tvalid       (fma_in_valid),
        .s_axis_c_tdata        (fma_c),
        .m_axis_result_tvalid  (fma_out_valid),
        .m_axis_result_tdata   (fma_out)
    );

    FP_DIV_0 u_fp_div (
        .aclk                  (i_clk),
        .aresetn               (i_rst_n),
        .s_axis_a_tvalid       (div_in_valid),
        .s_axis_a_tdata        (i_frs1),
        .s_axis_b_tvalid       (div_in_valid),
        .s_axis_b_tdata        (i_frs2),
        .m_axis_result_tvalid  (div_out_valid),
        .m_axis_result_tdata   (div_out)
    );

    FP_SQRT_0 u_fp_sqrt (
        .aclk                  (i_clk),
        .aresetn               (i_rst_n),
        .s_axis_a_tvalid       (sqrt_in_valid),
        .s_axis_a_tdata        (i_frs1),
        .m_axis_result_tvalid  (sqrt_out_valid),
        .m_axis_result_tdata   (sqrt_out)
    );

    assign o_busy = busy_q || (drain_kind_q != F_KIND_NONE);

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            busy_q            <= 1'b0;
            local_pending_q   <= 1'b0;
            active_kind_q     <= F_KIND_NONE;
            drain_kind_q      <= F_KIND_NONE;
            local_payload_q   <= '0;
            arithmetic_flags_q <= '0;
            arithmetic_a_q     <= '0;
            arithmetic_b_q     <= '0;
            arithmetic_c_q     <= '0;
            o_done            <= 1'b0;
            o_result          <= '0;
            o_fflags          <= '0;
        end else begin
            o_done <= 1'b0;

            if ((drain_kind_q == F_KIND_FMA) && fma_out_valid)
                drain_kind_q <= F_KIND_NONE;
            else if ((drain_kind_q == F_KIND_DIV) && div_out_valid)
                drain_kind_q <= F_KIND_NONE;
            else if ((drain_kind_q == F_KIND_SQRT) && sqrt_out_valid)
                drain_kind_q <= F_KIND_NONE;

            if (i_flush) begin
                if (busy_q && (active_kind_q == F_KIND_FMA) && !fma_out_valid)
                    drain_kind_q <= F_KIND_FMA;
                else if (busy_q && (active_kind_q == F_KIND_DIV) && !div_out_valid)
                    drain_kind_q <= F_KIND_DIV;
                else if (busy_q && (active_kind_q == F_KIND_SQRT) && !sqrt_out_valid)
                    drain_kind_q <= F_KIND_SQRT;
                busy_q          <= 1'b0;
                local_pending_q <= 1'b0;
                active_kind_q   <= F_KIND_NONE;
            end else if (i_start && !o_busy) begin
                busy_q        <= 1'b1;
                active_kind_q <= issue_kind;
                if (issue_kind == F_KIND_LOCAL) begin
                    local_payload_q <= local_exec(i_instr, i_frs1, i_frs2,
                                                  i_xrs1, i_frm);
                    local_pending_q <= 1'b1;
                end else if (issue_kind == F_KIND_FMA) begin
                    arithmetic_flags_q <= fma_input_flags(fma_a, fma_b, fma_c);
                    arithmetic_a_q <= fma_a;
                    arithmetic_b_q <= fma_b;
                    arithmetic_c_q <= fma_c;
                end else if (issue_kind == F_KIND_DIV) begin
                    arithmetic_a_q <= i_frs1;
                    arithmetic_b_q <= i_frs2;
                    arithmetic_c_q <= '0;
                    arithmetic_flags_q <=
                        (fp_is_snan(i_frs1) || fp_is_snan(i_frs2) ||
                         (fp_is_zero(i_frs1) && fp_is_zero(i_frs2)) ||
                         (fp_is_inf(i_frs1) && fp_is_inf(i_frs2))) ? FFLAG_NV :
                        ((!fp_is_nan(i_frs1) && !fp_is_inf(i_frs1) &&
                          !fp_is_zero(i_frs1) && fp_is_zero(i_frs2)) ? FFLAG_DZ : 5'b0);
                end else begin
                    arithmetic_a_q <= i_frs1;
                    arithmetic_b_q <= '0;
                    arithmetic_c_q <= '0;
                    arithmetic_flags_q <=
                        (fp_is_snan(i_frs1) ||
                         (i_frs1[31] && !fp_is_zero(i_frs1) && !fp_is_nan(i_frs1))) ?
                        FFLAG_NV : 5'b0;
                end
            end else if (local_pending_q) begin
                o_result          <= local_payload_q[31:0];
                o_fflags          <= local_payload_q[36:32];
                o_done            <= 1'b1;
                busy_q            <= 1'b0;
                local_pending_q   <= 1'b0;
                active_kind_q     <= F_KIND_NONE;
            end else if (busy_q && (active_kind_q == F_KIND_FMA) && fma_out_valid) begin
                o_result      <= fp_is_nan(fma_out) ? 32'h7fc00000 : fma_out;
                o_fflags      <= fma_result_flags;
                o_done        <= 1'b1;
                busy_q        <= 1'b0;
                active_kind_q <= F_KIND_NONE;
            end else if (busy_q && (active_kind_q == F_KIND_DIV) && div_out_valid) begin
                o_result      <= fp_is_nan(div_out) ? 32'h7fc00000 : div_out;
                o_fflags      <= div_result_flags;
                o_done        <= 1'b1;
                busy_q        <= 1'b0;
                active_kind_q <= F_KIND_NONE;
            end else if (busy_q && (active_kind_q == F_KIND_SQRT) && sqrt_out_valid) begin
                o_result      <= fp_is_nan(sqrt_out) ? 32'h7fc00000 : sqrt_out;
                o_fflags      <= sqrt_result_flags;
                o_done        <= 1'b1;
                busy_q        <= 1'b0;
                active_kind_q <= F_KIND_NONE;
            end
        end
    end
endmodule
