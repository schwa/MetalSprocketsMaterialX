#include <metal_stdlib>
#include "MXShadingContext.h"
using namespace metal;

// Stitched graphs have the signature
// `T graph(thread const MXShadingContext &context, constant float4 *parameters, constant MXTexture *textures)`.
typedef thread const MXShadingContext &MXContext;
typedef constant MXTexture *MXTextures;

constant float MX_FLOAT_EPS = 1e-8;

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
// every argument so the signature stays the same.

[[stitchable]] float mx_output_float(float value, MXContext, constant float4 *, MXTextures) { return value; }
[[stitchable]] float2 mx_output_vector2(float2 value, MXContext, constant float4 *, MXTextures) { return value; }
[[stitchable]] float3 mx_output_vector3(float3 value, MXContext, constant float4 *, MXTextures) { return value; }
[[stitchable]] float4 mx_output_vector4(float4 value, MXContext, constant float4 *, MXTextures) { return value; }
[[stitchable]] int mx_output_integer(int value, MXContext, constant float4 *, MXTextures) { return value; }
[[stitchable]] bool mx_output_boolean(bool value, MXContext, constant float4 *, MXTextures) { return value; }

// MARK: Textures
// Texture-reading functions take the texture table first. `slot` comes from the parameter buffer.

[[stitchable]] float4 mx_texture_slot_color4(MXTextures textures, int slot, float2 texcoord) {
    return textures[slot].texture.sample(textures[slot].sampler, texcoord);
}

// image: the stitcher passes the texture table, the slot it assigned to the file, then `default` and `texcoord`.
// An empty slot (null texture) returns `default`. MaterialX's V runs up, Metal's down, so V is flipped.
#define MX_IMAGE(SUFFIX, T, SWIZZLE) \
    [[stitchable]] T mx_image_##SUFFIX(MXTextures textures, int slot, T fallback, float2 texcoord) { \
        if (is_null_texture(textures[slot].texture)) { return fallback; } \
        float4 sample = textures[slot].texture.sample(textures[slot].sampler, float2(texcoord.x, 1.0 - texcoord.y)); \
        return SWIZZLE; \
    }
MX_IMAGE(float, float, sample.r)
MX_IMAGE(vector2, float2, sample.rg)
MX_IMAGE(vector3, float3, sample.rgb)
MX_IMAGE(color3, float3, sample.rgb)
MX_IMAGE(vector4, float4, sample)
MX_IMAGE(color4, float4, sample)

// MARK: Surface inputs
// A surface function sets each MXSurfaceInputs field with one setter. Setters return the pointer so the next setter
// depends on it, which orders them and keeps them in the stitched graph. The last call takes every argument so the
// signature stays `void (context, parameters, textures, surface)`.

typedef thread MXSurfaceInputs *MXSurface;

#define MX_SURFACE_SET(FIELD, T) \
    [[stitchable]] MXSurface mx_surface_set_##FIELD(MXSurface surface, T value) { surface->FIELD = value; return surface; }
MX_SURFACE_SET(baseColor, float3)
MX_SURFACE_SET(emissive, float3)
MX_SURFACE_SET(specularColor, float3)
MX_SURFACE_SET(sheenColor, float3)
MX_SURFACE_SET(normal, float3)
MX_SURFACE_SET(clearcoatNormal, float3)
MX_SURFACE_SET(opacity, float)
MX_SURFACE_SET(metallic, float)
MX_SURFACE_SET(roughness, float)
MX_SURFACE_SET(occlusion, float)
MX_SURFACE_SET(specular, float)
MX_SURFACE_SET(ior, float)
MX_SURFACE_SET(transmission, float)
MX_SURFACE_SET(clearcoat, float)
MX_SURFACE_SET(clearcoatRoughness, float)
MX_SURFACE_SET(sheenRoughness, float)
MX_SURFACE_SET(iridescence, float)
MX_SURFACE_SET(iridescenceThickness, float)

[[stitchable]] void mx_surface_output(MXSurface, MXContext, constant float4 *, MXTextures) {}

kernel void mx_evaluate_surface(device const MXShadingContext *contexts [[buffer(0)]], constant float4 *parameters [[buffer(1)]],
                                device MXSurfaceInputs *out [[buffer(2)]],
                                visible_function_table<void(MXContext, constant float4 *, MXTextures, MXSurface)> material [[buffer(3)]],
                                MXTextures textures [[buffer(4)]], uint id [[thread_position_in_grid]]) {
    MXShadingContext context = contexts[id];
    MXSurfaceInputs surface = out[id];
    material[0](context, parameters, textures, &surface);
    out[id] = surface;
}

// MARK: Evaluation
// Kernels that call a stitched graph through a visible function table, one result per context. Used by
// StitchedGraph.evaluate for tools and tests.

#define MX_EVALUATE(SUFFIX, T, WIDEN) \
    kernel void mx_evaluate_##SUFFIX(device const MXShadingContext *contexts [[buffer(0)]], constant float4 *parameters [[buffer(1)]], \
                                     device float4 *out [[buffer(2)]], visible_function_table<T(MXContext, constant float4 *, MXTextures)> graph [[buffer(3)]], \
                                     MXTextures textures [[buffer(4)]], uint id [[thread_position_in_grid]]) { \
        MXShadingContext context = contexts[id]; \
        T value = graph[0](context, parameters, textures); \
        out[id] = WIDEN; \
    }
MX_EVALUATE(float, float, float4(value, 0, 0, 1))
MX_EVALUATE(vector2, float2, float4(value, 0, 1))
MX_EVALUATE(vector3, float3, float4(value, 1))
MX_EVALUATE(vector4, float4, value)
MX_EVALUATE(integer, int, float4(float(value), 0, 0, 1))
MX_EVALUATE(boolean, bool, float4(value ? 1.0 : 0.0, 0, 0, 1))

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

// Geometric nodes take the shading context as their first argument, before the nodedef's inputs.
[[stitchable]] float2 mx_texcoord_vector2(MXContext context, int index) { return context.texcoord[clamp(index, 0, 1)]; }

// `space` arrives as an integer: 0 object (and model), 1 world. See Builder.spaceCode.
[[stitchable]] float3 mx_position_vector3(MXContext context, int space) { return space == 1 ? context.positionWorld : context.positionObject; }
[[stitchable]] float3 mx_normal_vector3(MXContext context, int space) { return space == 1 ? context.normalWorld : context.normalObject; }
// The context has one tangent frame, so `index` (UV set) is ignored.
[[stitchable]] float3 mx_tangent_vector3(MXContext context, int space, int) { return space == 1 ? context.tangentWorld : context.tangentObject; }
[[stitchable]] float3 mx_bitangent_vector3(MXContext context, int space, int) { return space == 1 ? context.bitangentWorld : context.bitangentObject; }
[[stitchable]] float3 mx_viewdirection_vector3(MXContext context, int space) { return space == 1 ? context.viewDirectionWorld : context.viewDirectionObject; }
// One vertex color set.
[[stitchable]] float mx_geomcolor_float(MXContext context, int) { return context.vertexColor.r; }
[[stitchable]] float3 mx_geomcolor_color3(MXContext context, int) { return context.vertexColor.rgb; }
[[stitchable]] float4 mx_geomcolor_color4(MXContext context, int) { return context.vertexColor; }
[[stitchable]] float mx_frame_float(MXContext context) { return context.frame; }
// MaterialX defines time as frame / fps.
[[stitchable]] float mx_time_float(MXContext context, float fps) { return context.frame / fps; }

// Named geometric properties are not in the context, so geompropvalue returns its default, as MaterialX does when
// the property is missing. The `geomprop` name is dropped by the stitcher.
[[stitchable]] float mx_geompropvalue_float(float fallback) { return fallback; }
[[stitchable]] int mx_geompropvalue_integer(int fallback) { return fallback; }
[[stitchable]] bool mx_geompropvalue_boolean(bool fallback) { return fallback; }
[[stitchable]] float2 mx_geompropvalue_vector2(float2 fallback) { return fallback; }
[[stitchable]] float3 mx_geompropvalue_vector3(float3 fallback) { return fallback; }
[[stitchable]] float4 mx_geompropvalue_vector4(float4 fallback) { return fallback; }
[[stitchable]] float3 mx_geompropvalue_color3(float3 fallback) { return fallback; }
[[stitchable]] float4 mx_geompropvalue_color4(float4 fallback) { return fallback; }

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
MX_BINARY_ALL(modulo, in1 - in2 * floor(in1 / in2))

#define MX_INVERT(SUFFIX, T, U) \
    [[stitchable]] T mx_invert_##SUFFIX(T in, U amount) { return T(amount) - in; }
MX_INVERT(float, float, float)
MX_INVERT(vector2, float2, float2)
MX_INVERT(vector3, float3, float3)
MX_INVERT(vector4, float4, float4)
MX_INVERT(color3, float3, float3)
MX_INVERT(color4, float4, float4)
MX_INVERT(vector2FA, float2, float)
MX_INVERT(vector3FA, float3, float)
MX_INVERT(vector4FA, float4, float)
MX_INVERT(color3FA, float3, float)
MX_INVERT(color4FA, float4, float)
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

#define MX_UNARY(NAME, EXPR) \
    [[stitchable]] float mx_##NAME##_float(float in) { return EXPR; } \
    [[stitchable]] float2 mx_##NAME##_vector2(float2 in) { return EXPR; } \
    [[stitchable]] float3 mx_##NAME##_vector3(float3 in) { return EXPR; } \
    [[stitchable]] float4 mx_##NAME##_vector4(float4 in) { return EXPR; } \
    [[stitchable]] float3 mx_##NAME##_color3(float3 in) { return EXPR; } \
    [[stitchable]] float4 mx_##NAME##_color4(float4 in) { return EXPR; }
MX_UNARY(absval, abs(in))
MX_UNARY(sign, sign(in))
MX_UNARY(sqrt, sqrt(in))
MX_UNARY(floor, floor(in))
MX_UNARY(ceil, ceil(in))
MX_UNARY(round, round(in))
MX_UNARY(fract, fract(in))
MX_UNARY(sin, sin(in))
MX_UNARY(cos, cos(in))
MX_UNARY(tan, tan(in))
MX_UNARY(ln, log(in))
MX_UNARY(exp, exp(in))
MX_UNARY(dot, in)
[[stitchable]] int mx_dot_integer(int in) { return in; }
[[stitchable]] bool mx_dot_boolean(bool in) { return in; }
[[stitchable]] float3x3 mx_dot_matrix33(float3x3 in) { return in; }
[[stitchable]] float4x4 mx_dot_matrix44(float4x4 in) { return in; }

// pbrlib, from MaterialX's mx_roughness_anisotropy.glsl.
[[stitchable]] float2 mx_roughness_anisotropy(float roughness, float anisotropy) {
    float roughnessSquared = clamp(roughness * roughness, MX_FLOAT_EPS, 1.0);
    if (anisotropy > 0.0) {
        float aspect = sqrt(1.0 - clamp(anisotropy, 0.0, 0.98));
        return float2(min(roughnessSquared / aspect, 1.0), roughnessSquared * aspect);
    }
    return float2(roughnessSquared);
}

[[stitchable]] float3 mx_crossproduct_vector3(float3 in1, float3 in2) { return cross(in1, in2); }

#define MX_SAFEPOWER(SUFFIX, T, U) \
    [[stitchable]] T mx_safepower_##SUFFIX(T in1, U in2) { return sign(in1) * pow(abs(in1), T(in2)); }
MX_SAFEPOWER(float, float, float)
MX_SAFEPOWER(vector2, float2, float2)
MX_SAFEPOWER(vector3, float3, float3)
MX_SAFEPOWER(vector4, float4, float4)
MX_SAFEPOWER(color3, float3, float3)
MX_SAFEPOWER(color4, float4, float4)
MX_SAFEPOWER(vector2FA, float2, float)
MX_SAFEPOWER(vector3FA, float3, float)
MX_SAFEPOWER(vector4FA, float4, float)
MX_SAFEPOWER(color3FA, float3, float)
MX_SAFEPOWER(color4FA, float4, float)

// MARK: swizzle (MaterialX 1.38, used by RealityKit documents)
// The stitcher turns `channels` ("rgb", "xxy1", …) into a vector4 of indices: 0–3 for a component, -1 for '0', -2
// for '1'.

static float mx_channel(float4 v, float index) {
    return index >= 0 ? v[int(index)] : (index < -1.5 ? 1.0 : 0.0);
}
static float4 mx_widen4(float v) { return float4(v, 0, 0, 0); }
static float4 mx_widen4(float2 v) { return float4(v, 0, 0); }
static float4 mx_widen4(float3 v) { return float4(v, 0); }
static float4 mx_widen4(float4 v) { return v; }
static float mx_pick(float4 v, float4 i, float) { return mx_channel(v, i.x); }
static float2 mx_pick(float4 v, float4 i, float2) { return float2(mx_channel(v, i.x), mx_channel(v, i.y)); }
static float3 mx_pick(float4 v, float4 i, float3) { return float3(mx_channel(v, i.x), mx_channel(v, i.y), mx_channel(v, i.z)); }
static float4 mx_pick(float4 v, float4 i, float4) { return float4(mx_channel(v, i.x), mx_channel(v, i.y), mx_channel(v, i.z), mx_channel(v, i.w)); }

#define MX_SWIZZLE(FROM, T, TO, U) \
    [[stitchable]] U mx_swizzle_##FROM##_##TO(T in, float4 channels) { return mx_pick(mx_widen4(in), channels, U()); }
#define MX_SWIZZLE_TO(FROM, T) \
    MX_SWIZZLE(FROM, T, float, float) \
    MX_SWIZZLE(FROM, T, vector2, float2) \
    MX_SWIZZLE(FROM, T, vector3, float3) \
    MX_SWIZZLE(FROM, T, color3, float3) \
    MX_SWIZZLE(FROM, T, vector4, float4) \
    MX_SWIZZLE(FROM, T, color4, float4)
MX_SWIZZLE_TO(float, float)
MX_SWIZZLE_TO(vector2, float2)
MX_SWIZZLE_TO(vector3, float3)
MX_SWIZZLE_TO(color3, float3)
MX_SWIZZLE_TO(vector4, float4)
MX_SWIZZLE_TO(color4, float4)

// MARK: RealityKit (Apple's ShaderGraph nodedefs, loaded with StandardLibrary.addingAppleShaderGraphNodes)

MX_UNARY(realitykit_oneminus, 1.0 - in)
[[stitchable]] float3 mx_realitykit_viewdirection_vector3(MXContext context, int space) {
    return space == 1 ? context.viewDirectionWorld : context.viewDirectionObject;
}

[[stitchable]] float mx_magnitude_vector2(float2 in) { return length(in); }
[[stitchable]] float mx_magnitude_vector3(float3 in) { return length(in); }
[[stitchable]] float mx_magnitude_vector4(float4 in) { return length(in); }
[[stitchable]] float2 mx_normalize_vector2(float2 in) { return normalize(in); }
[[stitchable]] float3 mx_normalize_vector3(float3 in) { return normalize(in); }
[[stitchable]] float4 mx_normalize_vector4(float4 in) { return normalize(in); }

[[stitchable]] float mx_dotproduct_vector2(float2 in1, float2 in2) { return dot(in1, in2); }
[[stitchable]] float mx_dotproduct_vector3(float3 in1, float3 in2) { return dot(in1, in2); }
[[stitchable]] float mx_dotproduct_vector4(float4 in1, float4 in2) { return dot(in1, in2); }

#define MX_CLAMP(SUFFIX, T, U) \
    [[stitchable]] T mx_clamp_##SUFFIX(T in, U low, U high) { return clamp(in, T(low), T(high)); }
MX_CLAMP(float, float, float)
MX_CLAMP(vector2, float2, float2)
MX_CLAMP(vector3, float3, float3)
MX_CLAMP(vector4, float4, float4)
MX_CLAMP(color3, float3, float3)
MX_CLAMP(color4, float4, float4)
MX_CLAMP(vector2FA, float2, float)
MX_CLAMP(vector3FA, float3, float)
MX_CLAMP(vector4FA, float4, float)
MX_CLAMP(color3FA, float3, float)
MX_CLAMP(color4FA, float4, float)

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

// MARK: Adjustment
// Ported from MaterialX's genglsl implementations. range, colorcorrect, hsvadjust and saturate are functional
// nodegraphs built from these.

#define MX_REMAP(SUFFIX, T, U) \
    [[stitchable]] T mx_remap_##SUFFIX(T in, U inlow, U inhigh, U outlow, U outhigh) { \
        return T(outlow) + (in - T(inlow)) * (T(outhigh) - T(outlow)) / (T(inhigh) - T(inlow)); }
MX_REMAP(float, float, float)
MX_REMAP(vector2, float2, float2)
MX_REMAP(vector3, float3, float3)
MX_REMAP(vector4, float4, float4)
MX_REMAP(color3, float3, float3)
MX_REMAP(color4, float4, float4)
MX_REMAP(vector2FA, float2, float)
MX_REMAP(vector3FA, float3, float)
MX_REMAP(vector4FA, float4, float)
MX_REMAP(color3FA, float3, float)
MX_REMAP(color4FA, float4, float)

[[stitchable]] float mx_smoothstep_float(float in, float low, float high) {
    return in >= high ? 1.0 : in <= low ? 0.0 : smoothstep(low, high, in);
}

[[stitchable]] float3 mx_luminance_color3(float3 in, float3 lumacoeffs) { return float3(dot(in, lumacoeffs)); }
[[stitchable]] float4 mx_luminance_color4(float4 in, float3 lumacoeffs) { return float4(float3(dot(in.rgb, lumacoeffs)), in.a); }

static float3 mx_hsvtorgb(float3 hsv) {
    float h = hsv.x, s = hsv.y, v = hsv.z;
    if (s < 0.0001) {
        return float3(v);
    }
    h = 6.0 * (h - floor(h));
    int hi = int(trunc(h));
    float f = h - float(hi);
    float p = v * (1.0 - s);
    float q = v * (1.0 - s * f);
    float t = v * (1.0 - s * (1.0 - f));
    switch (hi) {
    case 0: return float3(v, t, p);
    case 1: return float3(q, v, p);
    case 2: return float3(p, v, t);
    case 3: return float3(p, q, v);
    case 4: return float3(t, p, v);
    default: return float3(v, p, q);
    }
}

static float3 mx_rgbtohsv(float3 c) {
    float r = c.x, g = c.y, b = c.z;
    float mincomp = min(r, min(g, b));
    float maxcomp = max(r, max(g, b));
    float delta = maxcomp - mincomp;
    float h = 0, s = maxcomp > 0.0 ? delta / maxcomp : 0.0;
    if (s > 0.0) {
        if (r >= maxcomp) h = (g - b) / delta;
        else if (g >= maxcomp) h = 2.0 + (b - r) / delta;
        else h = 4.0 + (r - g) / delta;
        h *= 1.0 / 6.0;
        if (h < 0.0) h += 1.0;
    }
    return float3(h, s, maxcomp);
}

[[stitchable]] float3 mx_hsvtorgb_color3(float3 in) { return mx_hsvtorgb(in); }
[[stitchable]] float4 mx_hsvtorgb_color4(float4 in) { return float4(mx_hsvtorgb(in.rgb), in.a); }
[[stitchable]] float3 mx_rgbtohsv_color3(float3 in) { return mx_rgbtohsv(in); }
[[stitchable]] float4 mx_rgbtohsv_color4(float4 in) { return float4(mx_rgbtohsv(in.rgb), in.a); }

// MARK: Compositing

static float mx_burn(float fg, float bg, float mix) {
    return abs(fg) < MX_FLOAT_EPS ? 0.0 : mix * (1.0 - ((1.0 - bg) / fg)) + ((1.0 - mix) * bg);
}
static float mx_dodge(float fg, float bg, float mix) {
    return abs(1.0 - fg) < MX_FLOAT_EPS ? 0.0 : mix * (bg / (1.0 - fg)) + ((1.0 - mix) * bg);
}

#define MX_PER_COMPONENT(NAME) \
    [[stitchable]] float mx_##NAME##_float(float fg, float bg, float mix) { return mx_##NAME(fg, bg, mix); } \
    [[stitchable]] float3 mx_##NAME##_color3(float3 fg, float3 bg, float mix) { \
        return float3(mx_##NAME(fg.x, bg.x, mix), mx_##NAME(fg.y, bg.y, mix), mx_##NAME(fg.z, bg.z, mix)); } \
    [[stitchable]] float4 mx_##NAME##_color4(float4 fg, float4 bg, float mix) { \
        return float4(mx_##NAME(fg.x, bg.x, mix), mx_##NAME(fg.y, bg.y, mix), mx_##NAME(fg.z, bg.z, mix), mx_##NAME(fg.w, bg.w, mix)); }
MX_PER_COMPONENT(burn)
MX_PER_COMPONENT(dodge)

#define MX_BLEND(NAME, EXPR) \
    [[stitchable]] float mx_##NAME##_float(float fg, float bg, float mix) { return EXPR; } \
    [[stitchable]] float3 mx_##NAME##_color3(float3 fg, float3 bg, float mix) { return EXPR; } \
    [[stitchable]] float4 mx_##NAME##_color4(float4 fg, float4 bg, float mix) { return EXPR; }
MX_BLEND(plus, (mix * (bg + fg)) + ((1.0 - mix) * bg))
MX_BLEND(minus, (mix * (bg - fg)) + ((1.0 - mix) * bg))
MX_BLEND(difference, (mix * abs(bg - fg)) + ((1.0 - mix) * bg))
MX_BLEND(screen, (mix * (1.0 - (1.0 - fg) * (1.0 - bg))) + ((1.0 - mix) * bg))

#define MX_MASKED(NAME, EXPR) \
    [[stitchable]] float mx_##NAME##_float(float in, float mask) { return EXPR; } \
    [[stitchable]] float3 mx_##NAME##_color3(float3 in, float mask) { return EXPR; } \
    [[stitchable]] float4 mx_##NAME##_color4(float4 in, float mask) { return EXPR; }
MX_MASKED(inside, in * mask)
MX_MASKED(outside, in * (1.0 - mask))

[[stitchable]] float4 mx_over_color4(float4 fg, float4 bg, float mix) { return (fg + bg * (1.0 - fg.a)) * mix + bg * (1.0 - mix); }
[[stitchable]] float4 mx_in_color4(float4 fg, float4 bg, float mix) { return fg * bg.a * mix + bg * (1.0 - mix); }
[[stitchable]] float4 mx_mask_color4(float4 fg, float4 bg, float mix) { return bg * fg.a * mix + bg * (1.0 - mix); }
[[stitchable]] float4 mx_out_color4(float4 fg, float4 bg, float mix) { return fg * (1.0 - bg.a) * mix + bg * (1.0 - mix); }
[[stitchable]] float4 mx_matte_color4(float4 fg, float4 bg, float mix) {
    return float4(fg.xyz * fg.w + bg.xyz * (1.0 - fg.w), fg.w + bg.w * (1.0 - fg.w)) * mix + bg * (1.0 - mix);
}
[[stitchable]] float4 mx_disjointover_color4(float4 fg, float4 bg, float mix) {
    float summedAlpha = fg.w + bg.w;
    float4 result;
    if (summedAlpha <= 1.0) {
        result.xyz = fg.xyz + bg.xyz;
    } else if (abs(bg.w) < MX_FLOAT_EPS) {
        result.xyz = float3(0.0);
    } else {
        result.xyz = fg.xyz + bg.xyz * ((1.0 - fg.w) / bg.w);
    }
    result.w = min(summedAlpha, 1.0);
    return result * mix + (1.0 - mix) * bg;
}
[[stitchable]] float4 mx_premult_color4(float4 in) { return float4(in.rgb * in.a, in.a); }
[[stitchable]] float4 mx_unpremult_color4(float4 in) { return float4(in.rgb / in.a, in.a); }

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
