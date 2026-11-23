import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #21: every node with a Metal function and an inline MaterialX reference implementation gives the same result.
///
/// References are the `sourcecode` expressions in MaterialX's `stdlib_genglsl_impl.mtlx` (vendored test resource;
/// genmsl reuses them). Each is compiled into a Metal kernel and compared with the stitched node for fixed inputs.
@Suite(.serialized)
struct ReferenceImplementationTests {
    struct Case {
        var nodeDef: NodeDef
        var expression: String
    }

    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;
    #define vec2 float2
    #define vec3 float3
    #define vec4 float4
    template <typename T, typename U> T mx_mod(T x, U y) { return x - y * floor(x / y); }
    #define mx_sin sin
    #define mx_cos cos
    #define mx_tan tan
    #define mx_asin asin
    #define mx_acos acos
    #define mx_atan atan2
    static float4 widen(float v) { return float4(v, 0, 0, 1); }
    static float4 widen(float2 v) { return float4(v, 0, 1); }
    static float4 widen(float3 v) { return float4(v, 1); }
    static float4 widen(float4 v) { return v; }

    """

    static let metalTypes: [ValueType: String] = [
        .float: "float", .vector2: "float2", .vector3: "float3", .color3: "float3", .vector4: "float4", .color4: "float4",
        .integer: "int", .boolean: "bool",
    ]

    /// A fixed, safe input value: positive, away from zero, distinct per component and per input.
    static func value(for input: Input, index: Int) -> (xml: String, metal: String)? {
        switch input.type {
        case .integer:
            return ("1", "1")
        case .boolean:
            return ("true", "true")
        default:
            guard let count = input.type.componentCount, count <= 4 else { return nil }
            let numbers = (0..<count).map { 0.6 + 0.35 * Float(index) + 0.15 * Float($0) }
            let list = numbers.map { String($0) }.joined(separator: ", ")
            return (list, "\(metalTypes[input.type]!)(\(list))")
        }
    }

    static func cases(nodeLibrary: MetalNodeLibrary) throws -> [Case] {
        let url = try #require(Bundle.module.url(forResource: "stdlib_genglsl_impl", withExtension: "mtlx"))
        let implementations = try Document(url: url).root.children(tag: "implementation")
        let library = StandardLibrary.shared
        return implementations.compactMap { implementation in
            guard let name = implementation["nodedef"], let source = implementation["sourcecode"],
                  let nodeDef = library.nodeDefs[name], nodeDef.outputs.count == 1,
                  let outputType = nodeDef.outputs.first?.type, metalTypes[outputType] != nil, outputType != .integer, outputType != .boolean,
                  nodeLibrary.hasFunction(named: MetalNodeLibrary.functionName(for: nodeDef)),
                  nodeDef.inputs.allSatisfy({ metalTypes[$0.type] != nil })
            else { return nil }
            return Case(nodeDef: nodeDef, expression: source.trimmingCharacters(in: CharacterSet(charactersIn: "; ")))
        }
    }

    func reference(_ testCase: Case, device: MTLDevice) throws -> SIMD4<Float> {
        var expression = testCase.expression
        var declarations = ""
        for (index, input) in testCase.nodeDef.inputs.enumerated() {
            let value = try #require(Self.value(for: input, index: index))
            declarations += "    \(Self.metalTypes[input.type]!) v_\(input.name) = \(value.metal);\n"
            expression = expression.replacingOccurrences(of: "{{\(input.name)}}", with: "v_\(input.name)")
        }
        let outputType = Self.metalTypes[testCase.nodeDef.outputs[0].type]!
        let source = Self.prelude + """
        kernel void reference(device float4 *out [[buffer(0)]]) {
        \(declarations)    \(outputType) result = \(expression);
            out[0] = widen(result);
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: "reference")))
        let output = try #require(device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride))
        let queue = try #require(device.makeCommandQueue())
        let commandBuffer = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(output, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return output.contents().load(as: SIMD4<Float>.self)
    }

    func stitched(_ testCase: Case, stitcher: GraphStitcher, device: MTLDevice) throws -> SIMD4<Float> {
        let nodeDef = testCase.nodeDef
        let outputType = nodeDef.outputs[0].type
        let inputs = try nodeDef.inputs.enumerated().map { index, input in
            let value = try #require(Self.value(for: input, index: index))
            return "<input name=\"\(input.name)\" type=\"\(input.type)\" value=\"\(value.xml)\" />"
        }.joined()
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <\(nodeDef.node) name="n" type="\(outputType)" nodedef="\(nodeDef.name)">\(inputs)</\(nodeDef.node)>
          <output name="out" type="\(outputType)" nodename="n" />
        </nodegraph></materialx>
        """
        let document: Document
        do {
            document = try Document(data: Data(xml.utf8))
        } catch {
            Issue.record("\(error): \(xml)")
            throw error
        }
        let graph = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        return try StitchingTests().evaluate(graph, device: device, returnType: outputType.rawValue)[0]
    }

    @Test func nodesMatchMaterialXReferenceExpressions() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let stitcher = GraphStitcher(nodeLibrary: nodeLibrary)
        let cases = try Self.cases(nodeLibrary: nodeLibrary)
        #expect(cases.count > 50)
        var mismatches: [String] = []
        for testCase in cases {
            let expected = try reference(testCase, device: device)
            let actual = try stitched(testCase, stitcher: stitcher, device: device)
            let difference = expected - actual
            if any(difference .> SIMD4(repeating: 1e-5) .| difference .< SIMD4(repeating: -1e-5)) {
                mismatches.append("\(testCase.nodeDef.name): expected \(expected), got \(actual) [\(testCase.expression)]")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
    }
}
