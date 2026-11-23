import MaterialXMetal
import MaterialXMetalShaders
import Metal
import MetalSprockets

/// Draws `content` with a stitched MaterialX graph as an unlit color: the fragment color is the graph's color3 or
/// color4 output. Lit, PBR-shaded MaterialX surfaces are the PBR renderer's job (#34, #35).
///
/// `content` is ``Draw`` elements whose vertex buffer 0 is interleaved position (float3), normal (float3) and texture
/// coordinate (float2), matching ``vertexDescriptor``. Parameters are read from the graph on every frame, so editing
/// ``StitchedGraph/parameterData`` needs no rebuild. Re-stitching a graph whose wiring did not change reuses the
/// cached library, so the pipeline is reused too.
public struct MaterialXUnlitSurface<Content>: Element where Content: Element {
    let graph: StitchedGraph
    let uniforms: MXUnlitUniforms
    let textures: [(texture: MTLTexture, sampler: MTLSamplerState)?]
    let content: Content

    /// - Parameters:
    ///   - textures: One entry per ``StitchedGraph/textures`` slot; `nil` leaves the slot empty (image default).
    public init(graph: StitchedGraph, uniforms: MXUnlitUniforms, textures: [(texture: MTLTexture, sampler: MTLSamplerState)?] = [], @ElementBuilder content: () throws -> Content) rethrows {
        self.graph = graph
        self.uniforms = uniforms
        self.textures = textures
        self.content = try content()
    }

    /// Interleaved position, normal and texture coordinate in buffer 0.
    public static var vertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = 24
        for index in 0..<3 {
            descriptor.attributes[index].bufferIndex = 0
        }
        descriptor.layouts[0].stride = 32
        return descriptor
    }

    public var body: some Element {
        get throws {
            let device = graph.library.device
            let shaders = try device.makeDefaultLibrary(bundle: .materialXMetalShaders())
            let fragmentName = switch graph.outputType {
            case .color3, .vector3: "mx_unlit_fragment_color3"
            case .color4, .vector4: "mx_unlit_fragment_color4"
            default: throw MaterialXError.unsupportedNode("MaterialXUnlitSurface needs a color3 or color4 output, not \(graph.outputType)")
            }
            let vertexShader = try VertexShader(library: shaders, name: "mx_unlit_vertex")
            let fragmentShader = try FragmentShader(library: shaders, name: fragmentName)
            let material = try graph.visibleFunction()
            let table = try StitchedGraph.makeTextureTable(textures, device: device)
            let parameterData = graph.parameterData.isEmpty ? [SIMD4<Float>.zero] : graph.parameterData
            let resident = textures.compactMap { $0?.texture }
            return try RenderPipeline(label: "MaterialX Unlit", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                content
                    .parameter("uniforms", value: uniforms)
                    .parameter("parameters", functionTypes: .fragment, values: parameterData)
                    .parameter("textures", functionTypes: .fragment, buffer: table)
                    .visibleFunctionTable("material", functionType: .fragment, functions: [material])
                    .useResources(resident, usage: .read, stages: .fragment)
            }
            .vertexDescriptor(Self.vertexDescriptor)
            .linkedFunctions([material])
        }
    }
}
