#include <metal_stdlib>
using namespace metal;

// Stitchable implementations of MaterialX stdlib nodes. Each function is named after its nodedef with `ND_` replaced
// by `mx_`, and takes the nodedef's inputs in declaration order.

// MARK: Parameters
// Constant inputs live in a `constant float4 *` buffer, one slot per value. Read nodes take the slot pointer; advance
// nodes return the next slot, so the stitched graph can walk the buffer without literal offsets.

[[stitchable]] constant float4 *mx_parameter_next(constant float4 *slot) { return slot + 1; }
[[stitchable]] float mx_parameter_float(constant float4 *slot) { return slot->x; }
[[stitchable]] float2 mx_parameter_vector2(constant float4 *slot) { return slot->xy; }
[[stitchable]] float3 mx_parameter_vector3(constant float4 *slot) { return slot->xyz; }
[[stitchable]] float4 mx_parameter_vector4(constant float4 *slot) { return *slot; }

// MARK: Output
// Stitching drops graph arguments no node reads, which would change the function's signature. The output node takes
// every argument so the signature stays `T (float2 texcoord, constant float4 *parameters)`.

[[stitchable]] float mx_output_float(float value, float2, constant float4 *) { return value; }
[[stitchable]] float2 mx_output_vector2(float2 value, float2, constant float4 *) { return value; }
[[stitchable]] float3 mx_output_vector3(float3 value, float2, constant float4 *) { return value; }
[[stitchable]] float4 mx_output_vector4(float4 value, float2, constant float4 *) { return value; }

// MARK: Geometry

[[stitchable]] float2 mx_texcoord_vector2(float2 texcoord) { return texcoord; }

// MARK: Math

#define MX_BINARY(NAME, EXPR, SUFFIX, T, U) \
    [[stitchable]] T mx_##NAME##_##SUFFIX(T in1, U in2) { return EXPR; }

#define MX_BINARY_ALL(NAME, EXPR) \
    MX_BINARY(NAME, EXPR, float, float, float) \
    MX_BINARY(NAME, EXPR, vector2, float2, float2) \
    MX_BINARY(NAME, EXPR, vector3, float3, float3) \
    MX_BINARY(NAME, EXPR, vector4, float4, float4) \
    MX_BINARY(NAME, EXPR, color3, float3, float3) \
    MX_BINARY(NAME, EXPR, color4, float4, float4) \
    MX_BINARY(NAME, EXPR, vector2FA, float2, float) \
    MX_BINARY(NAME, EXPR, vector3FA, float3, float) \
    MX_BINARY(NAME, EXPR, vector4FA, float4, float) \
    MX_BINARY(NAME, EXPR, color3FA, float3, float) \
    MX_BINARY(NAME, EXPR, color4FA, float4, float)

MX_BINARY_ALL(add, in1 + in2)
MX_BINARY_ALL(subtract, in1 - in2)
MX_BINARY_ALL(multiply, in1 * in2)
MX_BINARY_ALL(divide, in1 / in2)
MX_BINARY_ALL(max, max(in1, decltype(in1)(in2)))
MX_BINARY_ALL(min, min(in1, decltype(in1)(in2)))

#define MX_MIX(SUFFIX, T, M) \
    [[stitchable]] T mx_mix_##SUFFIX(T fg, T bg, M mix) { return metal::mix(bg, fg, mix); }

MX_MIX(float, float, float)
MX_MIX(vector2, float2, float)
MX_MIX(vector3, float3, float)
MX_MIX(vector4, float4, float)
MX_MIX(color3, float3, float)
MX_MIX(color4, float4, float)
MX_MIX(vector2_vector2, float2, float2)
MX_MIX(vector3_vector3, float3, float3)
MX_MIX(vector4_vector4, float4, float4)
MX_MIX(color3_color3, float3, float3)
MX_MIX(color4_color4, float4, float4)

// MARK: Channel

[[stitchable]] float3 mx_combine3_color3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float3 mx_combine3_vector3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float3 mx_convert_float_color3(float in) { return float3(in); }
[[stitchable]] float3 mx_convert_vector2_vector3(float2 in) { return float3(in, 0); }
