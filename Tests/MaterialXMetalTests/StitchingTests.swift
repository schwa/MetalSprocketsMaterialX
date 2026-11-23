import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

@Suite(.serialized)
struct StitchingTests {
    static let document = """
    <?xml version="1.0"?>
    <materialx version="1.39">
      <nodegraph name="NG_test">
        <input name="tint" type="color3" value="0.5, 0.25, 1.0" />
        <texcoord name="uv" type="vector2" />
        <convert name="uv3" type="vector3" nodedef="ND_convert_vector2_vector3">
          <input name="in" type="vector2" nodename="uv" />
        </convert>
        <multiply name="scaled" type="color3">
          <input name="in1" type="color3" interfacename="tint" />
          <input name="in2" type="float" value="2.0" />
        </multiply>
        <mix name="blend" type="color3">
          <input name="fg" type="color3" nodename="scaled" />
          <input name="bg" type="color3" value="0, 0, 0" />
          <input name="mix" type="float" value="0.5" />
        </mix>
        <output name="out" type="color3" nodename="blend" />
      </nodegraph>
    </materialx>
    """

    /// A kernel that calls the stitched graph and widens its `returnType` result to float4 (missing components 0, w 1).
    static func kernelSource(returnType: String) -> String {
        let metalType = ["float": "float", "vector2": "float2", "vector3": "float3", "color3": "float3", "vector4": "float4", "color4": "float4"][returnType] ?? returnType
        return """
        #include <metal_stdlib>
        using namespace metal;
        static float4 widen(float v) { return float4(v, 0, 0, 1); }
        static float4 widen(float2 v) { return float4(v, 0, 1); }
        static float4 widen(float3 v) { return float4(v, 1); }
        static float4 widen(float4 v) { return v; }
        [[visible]] \(metalType) materialx_graph(float2 texcoord, constant float4 *parameters);
        kernel void evaluate(device float4 *out [[buffer(0)]], constant float4 *parameters [[buffer(1)]], uint id [[thread_position_in_grid]]) {
            out[id] = widen(materialx_graph(float2(id, 0) / 4.0, parameters));
        }
        """
    }

    func evaluate(_ graph: StitchedGraph, device: MTLDevice, returnType: String = "color3") throws -> [SIMD4<Float>] {
        let library = try device.makeLibrary(source: Self.kernelSource(returnType: returnType), options: nil)
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = library.makeFunction(name: "evaluate")
        let linked = MTLLinkedFunctions()
        linked.privateFunctions = [graph.function]
        descriptor.linkedFunctions = linked
        let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        let count = 4
        let output = try #require(device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * count))
        let parameters = try #require(device.makeBuffer(bytes: graph.parameterData, length: MemoryLayout<SIMD4<Float>>.stride * max(graph.parameterData.count, 1)))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(output, offset: 0, index: 0)
        encoder.setBuffer(parameters, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: count, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        try #require(commandBuffer.status == .completed, "\(String(describing: commandBuffer.error))")
        let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
        return (0..<count).map { pointer[$0] }
    }

    @Test func stitchedGraphMatchesExpectedValues() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.document.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let graph = try #require(document.nodeGraph("NG_test"))
        var stitched = try stitcher.stitch(graph, functionName: "materialx_graph")
        #expect(stitched.outputType == .color3)
        #expect(stitched.parameters.map(\.name) == ["tint", "scaled.in2", "blend.bg", "blend.mix"])

        // mix(bg = 0, fg = tint * 2, 0.5) = tint.
        #expect(try evaluate(stitched, device: device)[0] == [0.5, 0.25, 1, 1])

        // Parameters change without re-stitching.
        let tint = try #require(stitched.parameter("tint"))
        stitched.parameterData[tint.slot] = [1, 1, 1, 0]
        #expect(try evaluate(stitched, device: device)[0] == [1, 1, 1, 1])
    }

    /// A graph that reads only the texture coordinate keeps the full signature.
    @Test func texcoordOnlyGraph() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let source = """
        <materialx version="1.39"><nodegraph name="g">
          <texcoord name="uv" type="vector2" />
          <convert name="uv3" type="vector3" nodedef="ND_convert_vector2_vector3"><input name="in" type="vector2" nodename="uv" /></convert>
          <output name="out" type="vector3" nodename="uv3" />
        </nodegraph></materialx>
        """
        let document = try Document(data: Data(source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        #expect(try evaluate(stitched, device: device).map(\.x) == [0, 0.25, 0.5, 0.75])
    }

    @Test func stitchedFunctionIsAMetalSprocketsVisibleFunction() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.document.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("NG_test")), functionName: "materialx_graph")
        let function = try stitched.visibleFunction()
        #expect(function.linking == .binary)
    }

    @Test func unsupportedNodeThrows() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let source = """
        <materialx version="1.39"><nodegraph name="g">
          <noise2d name="n" type="float" />
          <output name="out" type="float" nodename="n" />
        </nodegraph></materialx>
        """
        let document = try Document(data: Data(source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        #expect(throws: MaterialXError.self) {
            try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "f")
        }
    }
}
