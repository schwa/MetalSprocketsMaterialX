#include <metal_stdlib>
#include "MXShadingContext.h"
using namespace metal;

// MaterialX's noise library (stdlib/genglsl/lib/mx_noise.glsl, MaterialX 1.39.4) ported to Metal, with the node
// wrappers. MaterialX's version is derived from Open Shading Language's oslnoise.h; see NOTICE.md for both licenses.
// Port notes: GLSL vector types become Metal's, `out`/`inout` parameters become `thread` references. Results should
// match MaterialX's GLSL and OSL.

static float mx_select(bool b, float t, float f) { return b ? t : f; }
static float mx_negate_if(float val, bool b) { return b ? -val : val; }
static int mx_floor(float x) { return int(floor(x)); }

static float mx_floorfrac(float x, thread int &i) {
    i = mx_floor(x);
    return x - float(i);
}

static float mx_bilerp(float v0, float v1, float v2, float v3, float s, float t) {
    float s1 = 1.0 - s;
    return (1.0 - t) * (v0 * s1 + v1 * s) + t * (v2 * s1 + v3 * s);
}
static float3 mx_bilerp(float3 v0, float3 v1, float3 v2, float3 v3, float s, float t) {
    float s1 = 1.0 - s;
    return (1.0 - t) * (v0 * s1 + v1 * s) + t * (v2 * s1 + v3 * s);
}
static float mx_trilerp(float v0, float v1, float v2, float v3, float v4, float v5, float v6, float v7, float s, float t, float r) {
    float s1 = 1.0 - s, t1 = 1.0 - t, r1 = 1.0 - r;
    return (r1 * (t1 * (v0 * s1 + v1 * s) + t * (v2 * s1 + v3 * s)) + r * (t1 * (v4 * s1 + v5 * s) + t * (v6 * s1 + v7 * s)));
}
static float3 mx_trilerp(float3 v0, float3 v1, float3 v2, float3 v3, float3 v4, float3 v5, float3 v6, float3 v7, float s, float t, float r) {
    float s1 = 1.0 - s, t1 = 1.0 - t, r1 = 1.0 - r;
    return (r1 * (t1 * (v0 * s1 + v1 * s) + t * (v2 * s1 + v3 * s)) + r * (t1 * (v4 * s1 + v5 * s) + t * (v6 * s1 + v7 * s)));
}

static float mx_gradient_float(uint hash, float x, float y) {
    uint h = hash & 7u;
    float u = mx_select(h < 4u, x, y);
    float v = 2.0 * mx_select(h < 4u, y, x);
    return mx_negate_if(u, bool(h & 1u)) + mx_negate_if(v, bool(h & 2u));
}
static float mx_gradient_float(uint hash, float x, float y, float z) {
    uint h = hash & 15u;
    float u = mx_select(h < 8u, x, y);
    float v = mx_select(h < 4u, y, mx_select((h == 12u) || (h == 14u), x, z));
    return mx_negate_if(u, bool(h & 1u)) + mx_negate_if(v, bool(h & 2u));
}
static float3 mx_gradient_vec3(uint3 hash, float x, float y) {
    return float3(mx_gradient_float(hash.x, x, y), mx_gradient_float(hash.y, x, y), mx_gradient_float(hash.z, x, y));
}
static float3 mx_gradient_vec3(uint3 hash, float x, float y, float z) {
    return float3(mx_gradient_float(hash.x, x, y, z), mx_gradient_float(hash.y, x, y, z), mx_gradient_float(hash.z, x, y, z));
}
static float mx_gradient_scale2d(float v) { return 0.6616 * v; }
static float mx_gradient_scale3d(float v) { return 0.9820 * v; }
static float3 mx_gradient_scale2d(float3 v) { return 0.6616 * v; }
static float3 mx_gradient_scale3d(float3 v) { return 0.9820 * v; }

static uint mx_rotl32(uint x, int k) { return (x << k) | (x >> (32 - k)); }

static void mx_bjmix(thread uint &a, thread uint &b, thread uint &c) {
    a -= c; a ^= mx_rotl32(c, 4); c += b;
    b -= a; b ^= mx_rotl32(a, 6); a += c;
    c -= b; c ^= mx_rotl32(b, 8); b += a;
    a -= c; a ^= mx_rotl32(c, 16); c += b;
    b -= a; b ^= mx_rotl32(a, 19); a += c;
    c -= b; c ^= mx_rotl32(b, 4); b += a;
}

static uint mx_bjfinal(uint a, uint b, uint c) {
    c ^= b; c -= mx_rotl32(b, 14);
    a ^= c; a -= mx_rotl32(c, 11);
    b ^= a; b -= mx_rotl32(a, 25);
    c ^= b; c -= mx_rotl32(b, 16);
    a ^= c; a -= mx_rotl32(c, 4);
    b ^= a; b -= mx_rotl32(a, 14);
    c ^= b; c -= mx_rotl32(b, 24);
    return c;
}

static float mx_bits_to_01(uint bits) { return float(bits) / float(uint(0xffffffff)); }
static float mx_fade(float t) { return t * t * t * (t * (t * 6.0 - 15.0) + 10.0); }

static uint mx_hash_int(int x) {
    uint seed = uint(0xdeadbeef) + (1u << 2u) + 13u;
    return mx_bjfinal(seed + uint(x), seed, seed);
}
static uint mx_hash_int(int x, int y) {
    uint a, b, c;
    a = b = c = uint(0xdeadbeef) + (2u << 2u) + 13u;
    a += uint(x); b += uint(y);
    return mx_bjfinal(a, b, c);
}
static uint mx_hash_int(int x, int y, int z) {
    uint a, b, c;
    a = b = c = uint(0xdeadbeef) + (3u << 2u) + 13u;
    a += uint(x); b += uint(y); c += uint(z);
    return mx_bjfinal(a, b, c);
}
static uint mx_hash_int(int x, int y, int z, int xx) {
    uint a, b, c;
    a = b = c = uint(0xdeadbeef) + (4u << 2u) + 13u;
    a += uint(x); b += uint(y); c += uint(z);
    mx_bjmix(a, b, c);
    a += uint(xx);
    return mx_bjfinal(a, b, c);
}
static uint mx_hash_int(int x, int y, int z, int xx, int yy) {
    uint a, b, c;
    a = b = c = uint(0xdeadbeef) + (5u << 2u) + 13u;
    a += uint(x); b += uint(y); c += uint(z);
    mx_bjmix(a, b, c);
    a += uint(xx); b += uint(yy);
    return mx_bjfinal(a, b, c);
}

static uint3 mx_hash_vec3(int x, int y) {
    uint h = mx_hash_int(x, y);
    return uint3(h & 0xFFu, (h >> 8) & 0xFFu, (h >> 16) & 0xFFu);
}
static uint3 mx_hash_vec3(int x, int y, int z) {
    uint h = mx_hash_int(x, y, z);
    return uint3(h & 0xFFu, (h >> 8) & 0xFFu, (h >> 16) & 0xFFu);
}

static float mx_perlin_noise_float(float2 p) {
    int X, Y;
    float fx = mx_floorfrac(p.x, X), fy = mx_floorfrac(p.y, Y);
    float u = mx_fade(fx), v = mx_fade(fy);
    float result = mx_bilerp(
        mx_gradient_float(mx_hash_int(X, Y), fx, fy),
        mx_gradient_float(mx_hash_int(X + 1, Y), fx - 1.0, fy),
        mx_gradient_float(mx_hash_int(X, Y + 1), fx, fy - 1.0),
        mx_gradient_float(mx_hash_int(X + 1, Y + 1), fx - 1.0, fy - 1.0),
        u, v);
    return mx_gradient_scale2d(result);
}

static float mx_perlin_noise_float(float3 p) {
    int X, Y, Z;
    float fx = mx_floorfrac(p.x, X), fy = mx_floorfrac(p.y, Y), fz = mx_floorfrac(p.z, Z);
    float u = mx_fade(fx), v = mx_fade(fy), w = mx_fade(fz);
    float result = mx_trilerp(
        mx_gradient_float(mx_hash_int(X, Y, Z), fx, fy, fz),
        mx_gradient_float(mx_hash_int(X + 1, Y, Z), fx - 1.0, fy, fz),
        mx_gradient_float(mx_hash_int(X, Y + 1, Z), fx, fy - 1.0, fz),
        mx_gradient_float(mx_hash_int(X + 1, Y + 1, Z), fx - 1.0, fy - 1.0, fz),
        mx_gradient_float(mx_hash_int(X, Y, Z + 1), fx, fy, fz - 1.0),
        mx_gradient_float(mx_hash_int(X + 1, Y, Z + 1), fx - 1.0, fy, fz - 1.0),
        mx_gradient_float(mx_hash_int(X, Y + 1, Z + 1), fx, fy - 1.0, fz - 1.0),
        mx_gradient_float(mx_hash_int(X + 1, Y + 1, Z + 1), fx - 1.0, fy - 1.0, fz - 1.0),
        u, v, w);
    return mx_gradient_scale3d(result);
}

static float3 mx_perlin_noise_vec3(float2 p) {
    int X, Y;
    float fx = mx_floorfrac(p.x, X), fy = mx_floorfrac(p.y, Y);
    float u = mx_fade(fx), v = mx_fade(fy);
    float3 result = mx_bilerp(
        mx_gradient_vec3(mx_hash_vec3(X, Y), fx, fy),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y), fx - 1.0, fy),
        mx_gradient_vec3(mx_hash_vec3(X, Y + 1), fx, fy - 1.0),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y + 1), fx - 1.0, fy - 1.0),
        u, v);
    return mx_gradient_scale2d(result);
}

static float3 mx_perlin_noise_vec3(float3 p) {
    int X, Y, Z;
    float fx = mx_floorfrac(p.x, X), fy = mx_floorfrac(p.y, Y), fz = mx_floorfrac(p.z, Z);
    float u = mx_fade(fx), v = mx_fade(fy), w = mx_fade(fz);
    float3 result = mx_trilerp(
        mx_gradient_vec3(mx_hash_vec3(X, Y, Z), fx, fy, fz),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y, Z), fx - 1.0, fy, fz),
        mx_gradient_vec3(mx_hash_vec3(X, Y + 1, Z), fx, fy - 1.0, fz),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y + 1, Z), fx - 1.0, fy - 1.0, fz),
        mx_gradient_vec3(mx_hash_vec3(X, Y, Z + 1), fx, fy, fz - 1.0),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y, Z + 1), fx - 1.0, fy, fz - 1.0),
        mx_gradient_vec3(mx_hash_vec3(X, Y + 1, Z + 1), fx, fy - 1.0, fz - 1.0),
        mx_gradient_vec3(mx_hash_vec3(X + 1, Y + 1, Z + 1), fx - 1.0, fy - 1.0, fz - 1.0),
        u, v, w);
    return mx_gradient_scale3d(result);
}

static float mx_cell_noise_float(float2 p) { return mx_bits_to_01(mx_hash_int(mx_floor(p.x), mx_floor(p.y))); }
static float mx_cell_noise_float(float3 p) { return mx_bits_to_01(mx_hash_int(mx_floor(p.x), mx_floor(p.y), mx_floor(p.z))); }
static float3 mx_cell_noise_vec3(float2 p) {
    int ix = mx_floor(p.x), iy = mx_floor(p.y);
    return float3(mx_bits_to_01(mx_hash_int(ix, iy, 0)), mx_bits_to_01(mx_hash_int(ix, iy, 1)), mx_bits_to_01(mx_hash_int(ix, iy, 2)));
}
static float3 mx_cell_noise_vec3(float3 p) {
    int ix = mx_floor(p.x), iy = mx_floor(p.y), iz = mx_floor(p.z);
    return float3(mx_bits_to_01(mx_hash_int(ix, iy, iz, 0)), mx_bits_to_01(mx_hash_int(ix, iy, iz, 1)), mx_bits_to_01(mx_hash_int(ix, iy, iz, 2)));
}

template <typename P>
static float mx_fractal_noise_float(P p, int octaves, float lacunarity, float diminish) {
    float result = 0.0, amplitude = 1.0;
    for (int i = 0; i < octaves; ++i) {
        result += amplitude * mx_perlin_noise_float(p);
        amplitude *= diminish;
        p *= lacunarity;
    }
    return result;
}
template <typename P>
static float3 mx_fractal_noise_vec3(P p, int octaves, float lacunarity, float diminish) {
    float3 result = float3(0.0);
    float amplitude = 1.0;
    for (int i = 0; i < octaves; ++i) {
        result += amplitude * mx_perlin_noise_vec3(p);
        amplitude *= diminish;
        p *= lacunarity;
    }
    return result;
}
// The second channel offsets of MaterialX's vec2/vec4 fractal variants.
static float2 mx_fractal_offset(float2) { return float2(19, 193); }
static float3 mx_fractal_offset(float3) { return float3(19, 193, 17); }
template <typename P>
static float2 mx_fractal_noise_vec2(P p, int octaves, float lacunarity, float diminish) {
    return float2(mx_fractal_noise_float(p, octaves, lacunarity, diminish), mx_fractal_noise_float(p + mx_fractal_offset(p), octaves, lacunarity, diminish));
}
template <typename P>
static float4 mx_fractal_noise_vec4(P p, int octaves, float lacunarity, float diminish) {
    return float4(mx_fractal_noise_vec3(p, octaves, lacunarity, diminish), mx_fractal_noise_float(p + mx_fractal_offset(p), octaves, lacunarity, diminish));
}

// Per-output-type Perlin noise, as MaterialX's mx_noise2d_<type>/mx_noise3d_<type> compose it.
static float2 mx_noise_offset4(float2) { return float2(19, 73); }
static float3 mx_noise_offset4(float3) { return float3(19, 73, 29); }
template <typename P> static float mx_noise_value(P p, float) { return mx_perlin_noise_float(p); }
template <typename P> static float2 mx_noise_value(P p, float2) { return mx_perlin_noise_vec3(p).xy; }
template <typename P> static float3 mx_noise_value(P p, float3) { return mx_perlin_noise_vec3(p); }
template <typename P> static float4 mx_noise_value(P p, float4) { return float4(mx_perlin_noise_vec3(p), mx_perlin_noise_float(p + mx_noise_offset4(p))); }

template <typename P> static float mx_fractal_value(P p, int o, float l, float d, float) { return mx_fractal_noise_float(p, o, l, d); }
template <typename P> static float2 mx_fractal_value(P p, int o, float l, float d, float2) { return mx_fractal_noise_vec2(p, o, l, d); }
template <typename P> static float3 mx_fractal_value(P p, int o, float l, float d, float3) { return mx_fractal_noise_vec3(p, o, l, d); }
template <typename P> static float4 mx_fractal_value(P p, int o, float l, float d, float4) { return mx_fractal_noise_vec4(p, o, l, d); }

// MARK: Nodes

#define MX_NOISE(DIMENSION, P, COORDINATE, SUFFIX, T, A) \
    [[stitchable]] T mx_noise##DIMENSION##_##SUFFIX(A amplitude, float pivot, P COORDINATE) { \
        return mx_noise_value(COORDINATE, T()) * T(amplitude) + pivot; \
    } \
    [[stitchable]] T mx_fractal##DIMENSION##_##SUFFIX(A amplitude, int octaves, float lacunarity, float diminish, P COORDINATE) { \
        return mx_fractal_value(COORDINATE, octaves, lacunarity, diminish, T()) * T(amplitude); \
    }

#define MX_NOISE_TYPES(DIMENSION, P, COORDINATE) \
    MX_NOISE(DIMENSION, P, COORDINATE, float, float, float) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector2, float2, float2) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector3, float3, float3) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector4, float4, float4) \
    MX_NOISE(DIMENSION, P, COORDINATE, color3, float3, float3) \
    MX_NOISE(DIMENSION, P, COORDINATE, color4, float4, float4) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector2FA, float2, float) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector3FA, float3, float) \
    MX_NOISE(DIMENSION, P, COORDINATE, vector4FA, float4, float) \
    MX_NOISE(DIMENSION, P, COORDINATE, color3FA, float3, float) \
    MX_NOISE(DIMENSION, P, COORDINATE, color4FA, float4, float)

MX_NOISE_TYPES(2d, float2, texcoord)
MX_NOISE_TYPES(3d, float3, position)

[[stitchable]] float mx_cellnoise2d_float(float2 texcoord) { return mx_cell_noise_float(texcoord); }
[[stitchable]] float mx_cellnoise3d_float(float3 position) { return mx_cell_noise_float(position); }
