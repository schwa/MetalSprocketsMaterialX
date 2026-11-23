#pragma once

// The inputs of a stitched MaterialX graph, shared by Metal and Swift:
//
//     T graph(thread const MXShadingContext &context, constant float4 *parameters, constant MXTexture *textures)
//
// A fragment shader fills in the context; geometric nodes (texcoord, position, normal, tangent, bitangent, geomcolor,
// viewdirection, time, frame) read it. `textures` is an argument buffer of texture/sampler pairs; image nodes read
// the slot their parameter names.

#ifdef __METAL_VERSION__
#include <metal_stdlib>
typedef metal::float2 MXFloat2;
typedef metal::float3 MXFloat3;
typedef metal::float4 MXFloat4;
#else
#include <simd/simd.h>
typedef simd_float2 MXFloat2;
typedef simd_float3 MXFloat3;
typedef simd_float4 MXFloat4;
#endif

typedef struct MXShadingContext {
    MXFloat3 positionWorld;
    MXFloat3 positionObject;
    MXFloat3 normalWorld;
    MXFloat3 normalObject;
    MXFloat3 tangentWorld;
    MXFloat3 tangentObject;
    MXFloat3 bitangentWorld;
    MXFloat3 bitangentObject;
    /// From the surface point towards the viewer, normalized.
    MXFloat3 viewDirectionWorld;
    MXFloat3 viewDirectionObject;
    /// UV sets 0 and 1.
    MXFloat2 texcoord[2];
    MXFloat4 vertexColor;
    /// Seconds. MaterialX's <time> node is frame / fps instead; this is for host-specific nodes.
    float time;
    float frame;
} MXShadingContext;

// One texture slot. In Swift, write the texture's and sampler's gpuResourceID (the sampler needs
// supportArgumentBuffers).
#ifdef __METAL_VERSION__
struct MXTexture {
    metal::texture2d<float> texture;
    metal::sampler sampler;
};
#else
#include <stdint.h>
typedef struct MXTexture {
    uint64_t texture;
    uint64_t sampler;
} MXTexture;
#endif
