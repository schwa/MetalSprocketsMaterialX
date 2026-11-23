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
[[stitchable]] int mx_parameter_integer(constant float4 *slot) { return int(slot->x); }
[[stitchable]] bool mx_parameter_boolean(constant float4 *slot) { return slot->x != 0; }

// MARK: Output
// Stitching drops graph arguments no node reads, which would change the function's signature. The output node takes
// every argument so the signature stays `T (float2 texcoord, constant float4 *parameters)`.

[[stitchable]] float mx_output_float(float value, float2, constant float4 *) { return value; }
[[stitchable]] float2 mx_output_vector2(float2 value, float2, constant float4 *) { return value; }
[[stitchable]] float3 mx_output_vector3(float3 value, float2, constant float4 *) { return value; }
[[stitchable]] float4 mx_output_vector4(float4 value, float2, constant float4 *) { return value; }

// MARK: Procedural

[[stitchable]] float mx_constant_float(float value) { return value; }
[[stitchable]] float2 mx_constant_vector2(float2 value) { return value; }
[[stitchable]] float3 mx_constant_vector3(float3 value) { return value; }
[[stitchable]] float4 mx_constant_vector4(float4 value) { return value; }
[[stitchable]] float3 mx_constant_color3(float3 value) { return value; }
[[stitchable]] float4 mx_constant_color4(float4 value) { return value; }
[[stitchable]] int mx_constant_integer(int value) { return value; }
[[stitchable]] bool mx_constant_boolean(bool value) { return value; }

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

[[stitchable]] float2 mx_combine2_vector2(float in1, float in2) { return float2(in1, in2); }
[[stitchable]] float4 mx_combine2_color4CF(float3 in1, float in2) { return float4(in1, in2); }
[[stitchable]] float4 mx_combine2_vector4VF(float3 in1, float in2) { return float4(in1, in2); }
[[stitchable]] float4 mx_combine2_vector4VV(float2 in1, float2 in2) { return float4(in1, in2); }
[[stitchable]] float3 mx_combine3_color3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float3 mx_combine3_vector3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float4 mx_combine4_color4(float in1, float in2, float in3, float in4) { return float4(in1, in2, in3, in4); }
[[stitchable]] float4 mx_combine4_vector4(float in1, float in2, float in3, float in4) { return float4(in1, in2, in3, in4); }

#define MX_EXTRACT(SUFFIX, T, N) \
    [[stitchable]] float mx_extract_##SUFFIX(T in, int index) { return in[clamp(index, 0, N - 1)]; }
MX_EXTRACT(vector2, float2, 2)
MX_EXTRACT(vector3, float3, 3)
MX_EXTRACT(vector4, float4, 4)
MX_EXTRACT(color3, float3, 3)
MX_EXTRACT(color4, float4, 4)

// Conversion follows stdlib_ng.mtlx: scalars splat, widening pads with 0 and sets a fourth component to 1,
// narrowing drops trailing components.
static inline float2 mx_resize2(float3 v) { return v.xy; }
static inline float2 mx_resize2(float4 v) { return v.xy; }
static inline float3 mx_resize3(float2 v) { return float3(v, 0); }
static inline float3 mx_resize3(float3 v) { return v; }
static inline float3 mx_resize3(float4 v) { return v.xyz; }
static inline float4 mx_resize4(float2 v) { return float4(v, 0, 1); }
static inline float4 mx_resize4(float3 v) { return float4(v, 1); }
static inline float4 mx_resize4(float4 v) { return v; }

#define MX_CONVERT(FROM, TO, T, U, EXPR) \
    [[stitchable]] U mx_convert_##FROM##_##TO(T in) { return EXPR; }

#define MX_CONVERT_SCALAR(FROM, T, CAST) \
    MX_CONVERT(FROM, color3, T, float3, float3(CAST(in))) \
    MX_CONVERT(FROM, color4, T, float4, float4(CAST(in))) \
    MX_CONVERT(FROM, vector2, T, float2, float2(CAST(in))) \
    MX_CONVERT(FROM, vector3, T, float3, float3(CAST(in))) \
    MX_CONVERT(FROM, vector4, T, float4, float4(CAST(in)))

MX_CONVERT_SCALAR(float, float, )
MX_CONVERT_SCALAR(boolean, bool, float)
MX_CONVERT_SCALAR(integer, int, float)
MX_CONVERT(boolean, float, bool, float, float(in))
MX_CONVERT(boolean, integer, bool, int, int(in))
MX_CONVERT(integer, float, int, float, float(in))
MX_CONVERT(integer, boolean, int, bool, in != 0)

MX_CONVERT(color3, color4, float3, float4, mx_resize4(in))
MX_CONVERT(color3, vector2, float3, float2, mx_resize2(in))
MX_CONVERT(color3, vector3, float3, float3, in)
MX_CONVERT(color3, vector4, float3, float4, mx_resize4(in))
MX_CONVERT(color4, color3, float4, float3, mx_resize3(in))
MX_CONVERT(color4, vector2, float4, float2, mx_resize2(in))
MX_CONVERT(color4, vector3, float4, float3, mx_resize3(in))
MX_CONVERT(color4, vector4, float4, float4, in)
MX_CONVERT(vector2, color3, float2, float3, mx_resize3(in))
MX_CONVERT(vector2, color4, float2, float4, mx_resize4(in))
MX_CONVERT(vector2, vector3, float2, float3, mx_resize3(in))
MX_CONVERT(vector2, vector4, float2, float4, mx_resize4(in))
MX_CONVERT(vector3, color3, float3, float3, in)
MX_CONVERT(vector3, color4, float3, float4, mx_resize4(in))
MX_CONVERT(vector3, vector2, float3, float2, mx_resize2(in))
MX_CONVERT(vector3, vector4, float3, float4, mx_resize4(in))
MX_CONVERT(vector4, color3, float4, float3, mx_resize3(in))
MX_CONVERT(vector4, color4, float4, float4, in)
MX_CONVERT(vector4, vector2, float4, float2, mx_resize2(in))
MX_CONVERT(vector4, vector3, float4, float3, mx_resize3(in))
