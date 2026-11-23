import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #12: channel and conversion nodes.
@Suite(.serialized)
struct ChannelNodeTests {
    static let channelCategories: Set<String> = ["extract", "combine2", "combine3", "combine4", "convert"]

    @Test func everyChannelNodeDefHasAMetalFunction() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let nodeDefs = StandardLibrary.shared.nodeDefs.values.filter {
            Self.channelCategories.contains($0.node) && $0.outputs.first?.type != .surfaceshader
        }
        #expect(nodeDefs.count > 40)
        let missing = nodeDefs.map(MetalNodeLibrary.functionName).filter { (try? nodeLibrary.function(named: $0)) == nil }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }

    func evaluate(_ body: String, type: String) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let document = try Document(data: Data(xml.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        return try StitchingTests().evaluate(stitched, device: device, returnType: type)[0]
    }

    @Test func extractReadsIndexedComponent() throws {
        let value = try evaluate("""
        <extract name="n" type="float"><input name="in" type="color3" value="0.1, 0.2, 0.3" /><input name="index" type="integer" value="1" /></extract>
        """, type: "float")
        #expect(value.x == 0.2)
    }

    @Test func combineVector4FromTwoVector2() throws {
        let value = try evaluate("""
        <combine2 name="n" type="vector4"><input name="in1" type="vector2" value="1, 2" /><input name="in2" type="vector2" value="3, 4" /></combine2>
        """, type: "vector4")
        #expect(value == [1, 2, 3, 4])
    }

    @Test func convertWideningSetsFourthComponentToOne() throws {
        let value = try evaluate("""
        <convert name="n" type="vector4"><input name="in" type="vector2" value="1, 2" /></convert>
        """, type: "vector4")
        #expect(value == [1, 2, 0, 1])
    }

    @Test func convertBooleanSplats() throws {
        let value = try evaluate("""
        <convert name="n" type="color3"><input name="in" type="boolean" value="true" /></convert>
        """, type: "color3")
        #expect(value.x == 1 && value.y == 1 && value.z == 1)
    }
}

/// #26: shader inputs connected to nodegraph outputs or to document-level nodes can be stitched.
@Suite(.serialized)
struct ShaderInputStitchingTests {
    static let source = """
    <materialx version="1.39">
      <nodegraph name="NG_colors">
        <multiply name="m" type="color3">
          <input name="in1" type="color3" value="0.2, 0.4, 0.6" />
          <input name="in2" type="float" value="2" />
        </multiply>
        <output name="tinted" type="color3" nodename="m" />
        <output name="other" type="color3" nodename="m" />
      </nodegraph>
      <constant name="rough_base" type="float"><input name="value" type="float" value="0.25" /></constant>
      <add name="rough" type="float">
        <input name="in1" type="float" nodename="rough_base" />
        <input name="in2" type="float" value="0.5" />
      </add>
      <standard_surface name="shader" type="surfaceshader">
        <input name="base_color" type="color3" nodegraph="NG_colors" output="tinted" />
        <input name="specular_roughness" type="float" nodename="rough" />
        <input name="metalness" type="float" value="1" />
      </standard_surface>
      <surfacematerial name="material" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="shader" />
      </surfacematerial>
    </materialx>
    """

    @Test func stitchesShaderInputs() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let shader = try #require(document.nodes.first { $0.name == "shader" })

        let baseColor = try stitcher.stitch(try #require(shader.input("base_color")), in: document, functionName: "materialx_graph")
        let color = try StitchingTests().evaluate(baseColor, device: device, returnType: "color3")[0]
        #expect(abs(color.x - 0.4) < 1e-6 && abs(color.y - 0.8) < 1e-6 && abs(color.z - 1.2) < 1e-6)

        let roughness = try stitcher.stitch(try #require(shader.input("specular_roughness")), in: document, functionName: "materialx_graph")
        #expect(try StitchingTests().evaluate(roughness, device: device, returnType: "float")[0].x == 0.75)

        #expect(throws: MaterialXError.self) {
            try stitcher.stitch(try #require(shader.input("metalness")), in: document, functionName: "materialx_graph")
        }
    }
}

/// #19: nodes without a Metal function are expanded from their functional nodegraph.
@Suite(.serialized)
struct FunctionalNodeGraphTests {
    static let source = """
    <materialx version="1.39">
      <nodedef name="ND_scale_and_bias_color3" node="scale_and_bias">
        <input name="in" type="color3" value="0, 0, 0" />
        <input name="scale" type="float" value="2" />
        <output name="out" type="color3" />
      </nodedef>
      <nodegraph name="NG_scale_and_bias_color3" nodedef="ND_scale_and_bias_color3">
        <multiply name="scaled" type="color3">
          <input name="in1" type="color3" interfacename="in" />
          <input name="in2" type="float" interfacename="scale" />
        </multiply>
        <add name="biased" type="color3">
          <input name="in1" type="color3" nodename="scaled" />
          <input name="in2" type="float" value="0.5" />
        </add>
        <output name="out" type="color3" nodename="biased" />
      </nodegraph>
      <nodegraph name="g">
        <scale_and_bias name="first" type="color3">
          <input name="in" type="color3" value="0.1, 0.2, 0.3" />
        </scale_and_bias>
        <scale_and_bias name="n" type="color3">
          <input name="in" type="color3" nodename="first" />
          <input name="scale" type="float" value="1" />
        </scale_and_bias>
        <output name="out" type="color3" nodename="n" />
      </nodegraph>
    </materialx>
    """

    @Test func customNodeDefIsInlinedTwice() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device), standardLibrary: StandardLibrary.shared.merging([document]))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        // ((0.1, 0.2, 0.3) * 2 + 0.5) * 1 + 0.5
        let value = try StitchingTests().evaluate(stitched, device: device)[0]
        #expect(abs(value.x - 1.2) < 1e-5 && abs(value.y - 1.4) < 1e-5 && abs(value.z - 1.6) < 1e-5)
    }
}
