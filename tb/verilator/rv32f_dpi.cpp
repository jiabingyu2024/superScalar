#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>

#pragma STDC FENV_ACCESS ON

namespace {
constexpr uint32_t CANONICAL_NAN = 0x7fc00000u;

float as_float(uint32_t bits) {
    float value;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

uint32_t as_bits(float value) {
    uint32_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

uint32_t canonical_bits(float value) {
    return std::isnan(value) ? CANONICAL_NAN : as_bits(value);
}
} // namespace

// Numerical backends for the same-name Xilinx Floating-Point Operator models
// in rtl/ip.  Architectural decoding, conversions, comparisons and exception
// flags remain in synthesizable RTL; DPI is confined to simulation IP models.
extern "C" uint32_t rv32f_dpi_fma(uint32_t a_bits, uint32_t b_bits,
                                    uint32_t c_bits) {
    const int old_rounding = std::fegetround();
    std::fesetround(FE_TONEAREST);
    const volatile float a = as_float(a_bits);
    const volatile float b = as_float(b_bits);
    const volatile float c = as_float(c_bits);
    const float out = std::fma(a, b, c);
    std::fesetround(old_rounding);
    return canonical_bits(out);
}

extern "C" uint32_t rv32f_dpi_div(uint32_t a_bits, uint32_t b_bits) {
    const int old_rounding = std::fegetround();
    std::fesetround(FE_TONEAREST);
    const volatile float a = as_float(a_bits);
    const volatile float b = as_float(b_bits);
    const volatile float out = a / b;
    std::fesetround(old_rounding);
    return canonical_bits(out);
}

extern "C" uint32_t rv32f_dpi_sqrt(uint32_t a_bits) {
    const int old_rounding = std::fegetround();
    std::fesetround(FE_TONEAREST);
    const volatile float a = as_float(a_bits);
    const float out = std::sqrt(a);
    std::fesetround(old_rounding);
    return canonical_bits(out);
}
