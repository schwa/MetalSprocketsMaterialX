#pragma once

// The surface point a stitched MaterialX graph is evaluated at. Shared by Metal and Swift: a fragment shader fills one
// in and passes it to the stitched function `T graph(thread const MXShadingContext &context, constant float4 *parameters)`.
// Geometric nodes (texcoord, position, normal, tangent, bitangent, geomcolor, viewdirection, time, frame) read it.

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
