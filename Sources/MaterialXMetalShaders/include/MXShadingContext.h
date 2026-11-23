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
typedef metal::float3x3 MXFloat3x3;
typedef metal::float4x4 MXFloat4x4;
#else
#include <simd/simd.h>
typedef simd_float2 MXFloat2;
typedef simd_float3 MXFloat3;
typedef simd_float4 MXFloat4;
typedef simd_float3x3 MXFloat3x3;
typedef simd_float4x4 MXFloat4x4;
#endif

typedef struct MXShadingContext {
    /// For transformpoint/transformvector/transformnormal.
    MXFloat4x4 objectToWorld;
    MXFloat4x4 worldToObject;
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

// What a surface shader (gltf_pbr, UsdPreviewSurface, …) resolves to at a surface point: the inputs a metallic-
// roughness PBR shader needs, named after glTF's. Filled by a stitched surface function
//
//     void material(thread const MXShadingContext &context, constant float4 *parameters, constant MXTexture *textures,
//                   thread MXSurfaceInputs *surface)
//
// Inputs a shader does not have keep the values the caller put in `surface` (see MXSurfaceInputs defaults in Swift).
typedef struct MXSurfaceInputs {
    MXFloat3 baseColor;
    MXFloat3 emissive;
    MXFloat3 specularColor;
    MXFloat3 sheenColor;
    /// World space; the shading context's normal unless the material sets one.
    MXFloat3 normal;
    MXFloat3 clearcoatNormal;
    float opacity;
    float metallic;
    float roughness;
    float occlusion;
    float specular;
    float ior;
    float transmission;
    float clearcoat;
    float clearcoatRoughness;
    float sheenRoughness;
    float iridescence;
    float iridescenceThickness;
} MXSurfaceInputs;

// Per-draw values for the unlit MaterialX pipeline (MaterialXUnlitSurface).
typedef struct MXUnlitUniforms {
    MXFloat4x4 modelViewProjection;
    MXFloat4x4 model;
    MXFloat4x4 inverseModel;
    /// Inverse transpose of the model matrix's upper 3×3.
    MXFloat3x3 normalMatrix;
    MXFloat3 cameraPosition;
    float time;
    float frame;
} MXUnlitUniforms;

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
