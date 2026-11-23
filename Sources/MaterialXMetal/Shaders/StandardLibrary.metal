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
// Matrices take one slot per column, in MaterialX value order (as GLSL's matN constructor fills columns).
[[stitchable]] float3x3 mx_parameter_matrix33(constant float4 *slot) { return float3x3(slot[0].xyz, slot[1].xyz, slot[2].xyz); }
[[stitchable]] float4x4 mx_parameter_matrix44(constant float4 *slot) { return float4x4(slot[0], slot[1], slot[2], slot[3]); }

// MARK: Output
// Stitching drops graph arguments no node reads, which would change the function's signature. The output node takes
// every argument so the signature stays `T (float2 texcoord, constant float4 *parameters)`.

[[stitchable]] float mx_output_float(float value, float2, constant float4 *) { return value; }
[[stitchable]] float2 mx_output_vector2(float2 value, float2, constant float4 *) { return value; }
[[stitchable]] float3 mx_output_vector3(float3 value, float2, constant float4 *) { return value; }
[[stitchable]] float4 mx_output_vector4(float4 value, float2, constant float4 *) { return value; }
[[stitchable]] int mx_output_integer(int value, float2, constant float4 *) { return value; }
[[stitchable]] bool mx_output_boolean(bool value, float2, constant float4 *) { return value; }

// MARK: Procedural

[[stitchable]] float mx_constant_float(float value) { return value; }
[[stitchable]] float2 mx_constant_vector2(float2 value) { return value; }
[[stitchable]] float3 mx_constant_vector3(float3 value) { return value; }
[[stitchable]] float4 mx_constant_vector4(float4 value) { return value; }
[[stitchable]] float3 mx_constant_color3(float3 value) { return value; }
[[stitchable]] float4 mx_constant_color4(float4 value) { return value; }
[[stitchable]] int mx_constant_integer(int value) { return value; }
[[stitchable]] bool mx_constant_boolean(bool value) { return value; }
[[stitchable]] float3x3 mx_constant_matrix33(float3x3 value) { return value; }
[[stitchable]] float4x4 mx_constant_matrix44(float4x4 value) { return value; }

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

#define MX_POWER(SUFFIX, T, U) \
    [[stitchable]] T mx_power_##SUFFIX(T in1, U in2) { return pow(in1, T(in2)); }
MX_POWER(float, float, float)
MX_POWER(vector2, float2, float2)
MX_POWER(vector3, float3, float3)
MX_POWER(vector4, float4, float4)
MX_POWER(color3, float3, float3)
MX_POWER(color4, float4, float4)
MX_POWER(vector2FA, float2, float)
MX_POWER(vector3FA, float3, float)
MX_POWER(vector4FA, float4, float)
MX_POWER(color3FA, float3, float)
MX_POWER(color4FA, float4, float)

[[stitchable]] float3 mx_transformmatrix_vector3(float3 in, float3x3 mat) { return mat * in; }
[[stitchable]] float4 mx_transformmatrix_vector4(float4 in, float4x4 mat) { return mat * in; }
[[stitchable]] float2 mx_transformmatrix_vector2M3(float2 in, float3x3 mat) { return (mat * float3(in, 1)).xy; }
[[stitchable]] float3 mx_transformmatrix_vector3M4(float3 in, float4x4 mat) { return (mat * float4(in, 1)).xyz; }

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

// MARK: Conditional
// Suffix-free nodedefs compare floats, `I` integers, `B` booleans. switch and logical_xor are functional nodegraphs
// built from these.

#define MX_IF(NAME, OP, SUFFIX, T, V) \
    [[stitchable]] T mx_##NAME##_##SUFFIX(V value1, V value2, T in1, T in2) { return value1 OP value2 ? in1 : in2; }

#define MX_IF_TYPES(NAME, OP, VARIANT, V) \
    MX_IF(NAME, OP, float##VARIANT, float, V) \
    MX_IF(NAME, OP, integer##VARIANT, int, V) \
    MX_IF(NAME, OP, color3##VARIANT, float3, V) \
    MX_IF(NAME, OP, color4##VARIANT, float4, V) \
    MX_IF(NAME, OP, vector2##VARIANT, float2, V) \
    MX_IF(NAME, OP, vector3##VARIANT, float3, V) \
    MX_IF(NAME, OP, vector4##VARIANT, float4, V)

MX_IF_TYPES(ifgreater, >, , float)
MX_IF_TYPES(ifgreater, >, I, int)
MX_IF_TYPES(ifgreatereq, >=, , float)
MX_IF_TYPES(ifgreatereq, >=, I, int)
MX_IF_TYPES(ifequal, ==, , float)
MX_IF_TYPES(ifequal, ==, I, int)
MX_IF_TYPES(ifequal, ==, B, bool)

#define MX_COMPARE(NAME, OP, SUFFIX, V) \
    [[stitchable]] bool mx_##NAME##_##SUFFIX(V value1, V value2) { return value1 OP value2; }

MX_COMPARE(ifgreater, >, boolean, float)
MX_COMPARE(ifgreater, >, booleanI, int)
MX_COMPARE(ifgreatereq, >=, boolean, float)
MX_COMPARE(ifgreatereq, >=, booleanI, int)
MX_COMPARE(ifequal, ==, boolean, float)
MX_COMPARE(ifequal, ==, booleanI, int)
MX_COMPARE(ifequal, ==, booleanB, bool)

[[stitchable]] bool mx_logical_and(bool in1, bool in2) { return in1 && in2; }
[[stitchable]] bool mx_logical_or(bool in1, bool in2) { return in1 || in2; }
[[stitchable]] bool mx_logical_not(bool in) { return !in; }

// MARK: Channel

[[stitchable]] float2 mx_combine2_vector2(float in1, float in2) { return float2(in1, in2); }
[[stitchable]] float4 mx_combine2_color4CF(float3 in1, float in2) { return float4(in1, in2); }
[[stitchable]] float4 mx_combine2_vector4VF(float3 in1, float in2) { return float4(in1, in2); }
[[stitchable]] float4 mx_combine2_vector4VV(float2 in1, float2 in2) { return float4(in1, in2); }
[[stitchable]] float3 mx_combine3_color3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float3 mx_combine3_vector3(float in1, float in2, float in3) { return float3(in1, in2, in3); }
[[stitchable]] float4 mx_combine4_color4(float in1, float in2, float in3, float in4) { return float4(in1, in2, in3, in4); }
[[stitchable]] float4 mx_combine4_vector4(float in1, float in2, float in3, float in4) { return float4(in1, in2, in3, in4); }

// Multi-output nodes: one function per output, named mx_<nodedef>_<output>.
#define MX_SEPARATE(SUFFIX, T, OUT, COMPONENT) \
    [[stitchable]] float mx_##SUFFIX##_##OUT(T in) { return in.COMPONENT; }
MX_SEPARATE(separate2_vector2, float2, outx, x)
MX_SEPARATE(separate2_vector2, float2, outy, y)
MX_SEPARATE(separate3_vector3, float3, outx, x)
MX_SEPARATE(separate3_vector3, float3, outy, y)
MX_SEPARATE(separate3_vector3, float3, outz, z)
MX_SEPARATE(separate3_color3, float3, outr, r)
MX_SEPARATE(separate3_color3, float3, outg, g)
MX_SEPARATE(separate3_color3, float3, outb, b)
MX_SEPARATE(separate4_vector4, float4, outx, x)
MX_SEPARATE(separate4_vector4, float4, outy, y)
MX_SEPARATE(separate4_vector4, float4, outz, z)
MX_SEPARATE(separate4_vector4, float4, outw, w)
MX_SEPARATE(separate4_color4, float4, outr, r)
MX_SEPARATE(separate4_color4, float4, outg, g)
MX_SEPARATE(separate4_color4, float4, outb, b)
MX_SEPARATE(separate4_color4, float4, outa, a)

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
