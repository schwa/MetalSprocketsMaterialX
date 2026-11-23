#include <metal_stdlib>
#include "MXShadingContext.h"
using namespace metal;

// An unlit pipeline: the fragment color is a stitched MaterialX graph's color3 (or color4) output.
// Vertex layout: position (attribute 0), normal (1), texcoord (2), one interleaved buffer at index 0.

struct MXUnlitVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texcoord [[attribute(2)]];
};

struct MXUnlitVertexOut {
    float4 clipPosition [[position]];
    float3 positionWorld;
    float3 positionObject;
    float3 normalWorld;
    float3 normalObject;
    float2 texcoord;
};

[[vertex]] MXUnlitVertexOut mx_unlit_vertex(MXUnlitVertexIn in [[stage_in]], constant MXUnlitUniforms &uniforms [[buffer(1)]]) {
    MXUnlitVertexOut out;
    out.clipPosition = uniforms.modelViewProjection * float4(in.position, 1);
    out.positionWorld = (uniforms.model * float4(in.position, 1)).xyz;
    out.positionObject = in.position;
    out.normalWorld = normalize(uniforms.normalMatrix * in.normal);
    out.normalObject = in.normal;
    out.texcoord = in.texcoord;
    return out;
}

static MXShadingContext mx_unlit_context(MXUnlitVertexOut in, constant MXUnlitUniforms &uniforms) {
    MXShadingContext context = {};
    context.objectToWorld = uniforms.model;
    context.worldToObject = uniforms.inverseModel;
    context.positionWorld = in.positionWorld;
    context.positionObject = in.positionObject;
    context.normalWorld = normalize(in.normalWorld);
    context.normalObject = normalize(in.normalObject);
    // No tangent attribute: build a frame from the normal.
    float3 up = abs(context.normalWorld.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    context.tangentWorld = normalize(cross(up, context.normalWorld));
    context.bitangentWorld = cross(context.normalWorld, context.tangentWorld);
    context.tangentObject = context.tangentWorld;
    context.bitangentObject = context.bitangentWorld;
    context.viewDirectionWorld = normalize(uniforms.cameraPosition - in.positionWorld);
    context.viewDirectionObject = context.viewDirectionWorld;
    context.texcoord[0] = in.texcoord;
    context.texcoord[1] = in.texcoord;
    context.vertexColor = float4(1);
    context.time = uniforms.time;
    context.frame = uniforms.frame;
    return context;
}

using MXColor3Graph = float3(thread const MXShadingContext &, constant float4 *, constant MXTexture *);
using MXColor4Graph = float4(thread const MXShadingContext &, constant float4 *, constant MXTexture *);

[[fragment]] float4 mx_unlit_fragment_color3(MXUnlitVertexOut in [[stage_in]], constant MXUnlitUniforms &uniforms [[buffer(1)]],
                                            constant float4 *parameters [[buffer(2)]], constant MXTexture *textures [[buffer(3)]],
                                            visible_function_table<MXColor3Graph> material [[buffer(4)]]) {
    MXShadingContext context = mx_unlit_context(in, uniforms);
    return float4(material[0](context, parameters, textures), 1);
}

[[fragment]] float4 mx_unlit_fragment_color4(MXUnlitVertexOut in [[stage_in]], constant MXUnlitUniforms &uniforms [[buffer(1)]],
                                            constant float4 *parameters [[buffer(2)]], constant MXTexture *textures [[buffer(3)]],
                                            visible_function_table<MXColor4Graph> material [[buffer(4)]]) {
    MXShadingContext context = mx_unlit_context(in, uniforms);
    return material[0](context, parameters, textures);
}
