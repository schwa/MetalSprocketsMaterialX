import Foundation
import Metal
import MetalSprocketsMaterialX
import simd
import Testing

/// #12: channel and conversion nodes.
@Suite(.serialized)
struct ChannelNodeTests {
    static let channelCategories: Set<String> = ["extract", "combine2", "combine3", "combine4", "convert", "separate2", "separate3", "separate4"]

    @Test func everyChannelNodeDefHasAMetalFunction() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let nodeDefs = StandardLibrary.shared.nodeDefs.values.filter {
            Self.channelCategories.contains($0.node) && $0.outputs.first?.type != .surfaceshader
        }
        #expect(nodeDefs.count > 40)
        let functionNames = nodeDefs.flatMap { nodeDef in
            let base = MetalNodeLibrary.functionName(for: nodeDef)
            return nodeDef.outputs.count > 1 ? nodeDef.outputs.map { base + "_" + $0.name } : [base]
        }
        let missing = functionNames.filter { !nodeLibrary.hasFunction(named: $0) }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }

    func evaluate(_ body: String, type: String) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let document = try Document(data: Data(xml.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        return try StitchingTests().evaluate(stitched, device: device)[0]
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
        let color = try StitchingTests().evaluate(baseColor, device: device)[0]
        #expect(abs(color.x - 0.4) < 1e-6 && abs(color.y - 0.8) < 1e-6 && abs(color.z - 1.2) < 1e-6)

        let roughness = try stitcher.stitch(try #require(shader.input("specular_roughness")), in: document, functionName: "materialx_graph")
        #expect(try StitchingTests().evaluate(roughness, device: device)[0].x == 0.75)

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

/// #25: multi-output nodes, output= references and choosing a nodegraph output.
@Suite(.serialized)
struct MultiOutputTests {
    static let source = """
    <materialx version="1.39">
      <nodedef name="ND_split_halves" node="split_halves">
        <input name="in" type="vector4" value="0, 0, 0, 0" />
        <output name="low" type="vector2" />
        <output name="high" type="vector2" />
      </nodedef>
      <nodegraph name="NG_split_halves" nodedef="ND_split_halves">
        <separate4 name="parts" type="multioutput"><input name="in" type="vector4" interfacename="in" /></separate4>
        <combine2 name="low_pair" type="vector2">
          <input name="in1" type="float" nodename="parts" output="outx" />
          <input name="in2" type="float" nodename="parts" output="outy" />
        </combine2>
        <combine2 name="high_pair" type="vector2">
          <input name="in1" type="float" nodename="parts" output="outz" />
          <input name="in2" type="float" nodename="parts" output="outw" />
        </combine2>
        <output name="low" type="vector2" nodename="low_pair" />
        <output name="high" type="vector2" nodename="high_pair" />
      </nodegraph>
      <nodegraph name="g">
        <separate3 name="parts" type="multioutput"><input name="in" type="color3" value="0.1, 0.2, 0.3" /></separate3>
        <combine3 name="swapped" type="color3">
          <input name="in1" type="float" nodename="parts" output="outb" />
          <input name="in2" type="float" nodename="parts" output="outg" />
          <input name="in3" type="float" nodename="parts" output="outr" />
        </combine3>
        <split_halves name="halves" type="multioutput"><input name="in" type="vector4" value="1, 2, 3, 4" /></split_halves>
        <output name="swapped" type="color3" nodename="swapped" />
        <output name="high" type="vector2" nodename="halves" output="high" />
      </nodegraph>
    </materialx>
    """

    func stitch(output: String) throws -> (StitchedGraph, MTLDevice) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device), standardLibrary: StandardLibrary.shared.merging([document]))
        return (try stitcher.stitch(try #require(document.nodeGraph("g")), output: output, functionName: "materialx_graph"), device)
    }

    @Test func separateOutputsShareOneInput() throws {
        let (stitched, device) = try stitch(output: "swapped")
        #expect(stitched.parameters.count == 1)
        let value = try StitchingTests().evaluate(stitched, device: device)[0]
        #expect(value == [0.3, 0.2, 0.1, 1])
    }

    @Test func functionalGraphOutputIsSelected() throws {
        let (stitched, device) = try stitch(output: "high")
        #expect(try StitchingTests().evaluate(stitched, device: device)[0] == [3, 4, 0, 1])
    }
}

/// #17: texcoord index 1 must not silently read UV set 0.
@Suite(.serialized)
struct TexcoordIndexTests {
    func uv(index: Int) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let source = """
        <materialx version="1.39"><nodegraph name="g">
          <texcoord name="n" type="vector2"><input name="index" type="integer" value="\(index)" /></texcoord>
          <output name="out" type="vector2" nodename="n" />
        </nodegraph></materialx>
        """
        let document = try Document(data: Data(source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        var context = MXShadingContext(texcoord: [0.1, 0.2])
        context.texcoord.1 = [0.7, 0.8]
        return try #require(try stitched.evaluate(contexts: [context]).first)
    }

    @Test func indexSelectsTheUVSet() throws {
        #expect(try uv(index: 0) == [0.1, 0.2, 0, 1])
        #expect(try uv(index: 1) == [0.7, 0.8, 0, 1])
    }
}

/// #27: graphs with the same topology share one stitched library; constants stay per graph.
@Suite(.serialized)
struct StitchCacheTests {
    func graph(_ color: String) -> String {
        """
        <materialx version="1.39"><nodegraph name="g">
          <multiply name="n" type="color3"><input name="in1" type="color3" value="\(color)" /><input name="in2" type="float" value="2" /></multiply>
          <output name="out" type="color3" nodename="n" />
        </nodegraph></materialx>
        """
    }

    @Test func sameTopologyReusesLibrary() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let stitcher = GraphStitcher(nodeLibrary: nodeLibrary)
        let red = try stitcher.stitch(try #require(Document(data: Data(graph("0.5, 0, 0").utf8)).nodeGraph("g")), functionName: "materialx_graph")
        let blue = try stitcher.stitch(try #require(Document(data: Data(graph("0, 0, 0.25").utf8)).nodeGraph("g")), functionName: "materialx_graph")
        #expect(red.library === blue.library)
        #expect(nodeLibrary.stitchCount == 1)
        #expect(try StitchingTests().evaluate(red, device: device)[0] == [1, 0, 0, 1])
        #expect(try StitchingTests().evaluate(blue, device: device)[0] == [0, 0, 0.5, 1])

        let renamed = try stitcher.stitch(try #require(Document(data: Data(graph("0, 0, 0.25").utf8)).nodeGraph("g")), functionName: "other_name")
        #expect(renamed.library !== red.library)
        #expect(nodeLibrary.stitchCount == 2)
    }
}

/// #13: conditional and logical nodes.
@Suite(.serialized)
struct ConditionalNodeTests {
    @Test func everyNonMatrixConditionalNodeDefHasAMetalFunction() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let categories: Set<String> = ["ifgreater", "ifgreatereq", "ifequal", "and", "or", "not"]
        let nodeDefs = StandardLibrary.shared.nodeDefs.values.filter { nodeDef in
            categories.contains(nodeDef.node) && !nodeDef.name.contains("matrix")
        }
        #expect(nodeDefs.count > 50)
        let missing = nodeDefs.map(MetalNodeLibrary.functionName).filter { !nodeLibrary.hasFunction(named: $0) }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }

    func evaluate(_ body: String, type: String) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        return try StitchingTests().evaluate(stitched, device: device)[0]
    }

    @Test func switchPicksInputByWhich() throws {
        let value = try evaluate("""
        <switch name="n" type="color3">
          <input name="in1" type="color3" value="1, 0, 0" /><input name="in2" type="color3" value="0, 1, 0" />
          <input name="in3" type="color3" value="0, 0, 1" /><input name="which" type="float" value="2" />
        </switch>
        """, type: "color3")
        #expect(value == [0, 0, 1, 1])
    }

    @Test func xorAndIfequalBoolean() throws {
        // ifequal(xor(true, false), true) ? 1 : 0
        let value = try evaluate("""
        <xor name="x" type="boolean"><input name="in1" type="boolean" value="true" /><input name="in2" type="boolean" value="false" /></xor>
        <ifequal name="n" type="float">
          <input name="value1" type="boolean" nodename="x" /><input name="value2" type="boolean" value="true" />
          <input name="in1" type="float" value="1" /><input name="in2" type="float" value="0" />
        </ifequal>
        """, type: "float")
        #expect(value.x == 1)
    }
}

/// #40: cmlib colorspace transforms stitch through their nodegraphs.
@Suite(.serialized)
struct ColorManagementTests {
    func transform(_ category: String, _ color: String) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <\(category) name="n" type="color3"><input name="in" type="color3" value="\(color)" /></\(category)>
          <output name="out" type="color3" nodename="n" />
        </nodegraph></materialx>
        """
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        return try StitchingTests().evaluate(stitched, device: device)[0]
    }

    @Test(arguments: StandardLibrary.shared.nodeDefs.values.filter { $0.name.hasSuffix("_to_lin_rec709_color3") }.map(\.node))
    func everyColorSpaceTransformStitches(category: String) throws {
        let value = try transform(category, "0.5, 0.5, 0.5")
        #expect(value.x.isFinite && value.x > 0)
    }

    @Test func srgbTextureDecodes() throws {
        let value = try transform("srgb_texture_to_lin_rec709", "0.5, 0.01, 1")
        let expected = SIMD3<Float>(pow((0.5 + 0.055) / 1.055, 2.4), 0.01 / 12.92, 1)
        #expect(simd_distance(SIMD3(value.x, value.y, value.z), expected) < 1e-5, "\(value)")
    }

    @Test func acescgMatrixIsApplied() throws {
        let value = try transform("acescg_to_lin_rec709", "1, 0, 0")
        #expect(simd_distance(SIMD3(value.x, value.y, value.z), [1.70505, -0.13026, -0.02400]) < 1e-3, "\(value)")
    }
}

/// #5: colorspace and unit attributes on values are applied.
@Suite(.serialized)
struct ColorSpaceAndUnitTests {
    func evaluate(_ xml: String, configure: (inout GraphStitcher) -> Void = { _ in }) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(xml.utf8))
        var stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        configure(&stitcher)
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph", documentColorSpace: document.colorSpace)
        return try StitchingTests().evaluate(stitched, device: device)[0]
    }

    static let decoded = pow((0.5 + 0.055) / 1.055, 2.4) as Float

    @Test func documentColorSpaceConvertsConstants() throws {
        let value = try evaluate("""
        <materialx version="1.39" colorspace="srgb_texture"><nodegraph name="g">
          <add name="n" type="color3"><input name="in1" type="color3" value="0.5, 0.5, 0.5" /></add>
          <output name="out" type="color3" nodename="n" />
        </nodegraph></materialx>
        """)
        // in1 is converted; the unset in2 default (0) is not.
        #expect(abs(value.x - Self.decoded) < 1e-5, "\(value)")
    }

    @Test func inputColorSpaceOverridesAndLinearIsUntouched() throws {
        let value = try evaluate("""
        <materialx version="1.39" colorspace="srgb_texture"><nodegraph name="g" colorspace="lin_rec709">
          <input name="tint" type="color3" value="0.5, 0.5, 0.5" colorspace="srgb_texture" />
          <add name="n" type="color3">
            <input name="in1" type="color3" interfacename="tint" />
            <input name="in2" type="color3" value="0.25, 0.25, 0.25" />
          </add>
          <output name="out" type="color3" nodename="n" />
        </nodegraph></materialx>
        """)
        #expect(abs(value.x - (Self.decoded + 0.25)) < 1e-5, "\(value)")
    }

    @Test func unitsConvertToTarget() throws {
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <multiply name="n" type="float">
            <input name="in1" type="float" value="10" unit="centimeter" unittype="distance" />
            <input name="in2" type="float" value="1" />
          </multiply>
          <output name="out" type="float" nodename="n" />
        </nodegraph></materialx>
        """
        #expect(abs(try evaluate(xml).x - 0.1) < 1e-6)
        #expect(abs(try evaluate(xml) { $0.targetUnits["distance"] = "millimeter" }.x - 100) < 1e-4)
    }
}

/// Found while measuring #28: resolving a node recursed once per upstream node, so a chain of ~40 nodes overflowed
/// the 512 KB stack of a Swift Testing (or any secondary) thread and crashed.
@Suite(.serialized)
struct DeepGraphTests {
    @Test func longChainStitches() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let count = 300
        var nodes = "<constant name=\"n0\" type=\"float\"><input name=\"value\" type=\"float\" value=\"0\" /></constant>"
        for index in 1...count {
            nodes += "<add name=\"n\(index)\" type=\"float\"><input name=\"in1\" type=\"float\" nodename=\"n\(index - 1)\" /><input name=\"in2\" type=\"float\" value=\"1\" /></add>"
        }
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(nodes)<output name=\"out\" type=\"float\" nodename=\"n\(count)\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        #expect(try StitchingTests().evaluate(stitched, device: device)[0].x == Float(count))
    }

    @Test func cycleIsReported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <add name="a" type="float"><input name="in1" type="float" nodename="b" /></add>
          <add name="b" type="float"><input name="in1" type="float" nodename="a" /></add>
          <output name="out" type="float" nodename="a" />
        </nodegraph></materialx>
        """
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let graph = try #require(try Document(data: Data(xml.utf8)).nodeGraph("g"))
        #expect {
            try stitcher.stitch(graph, functionName: "materialx_graph")
        } throws: { error in
            if case .cycle = error as? MaterialXError { true } else { false }
        }
    }
}

/// #24: typed parameter setters, checked against the parameter's type.
@Suite(.serialized)
struct ParameterSetterTests {
    @Test func setByNameWithTypeChecks() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(StitchingTests.document.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        var stitched = try stitcher.stitch(try #require(document.nodeGraph("NG_test")), functionName: "materialx_graph")

        try stitched.set("tint", to: Value.numbers([1, 1, 1]))
        try stitched.set("blend.mix", to: 1)
        #expect(try StitchingTests().evaluate(stitched, device: device)[0] == [2, 2, 2, 1])

        #expect(throws: MaterialXError.self) { try stitched.set("tint", to: 0.5) }
        #expect(throws: MaterialXError.self) { try stitched.set("missing", to: 1) }
        #expect(throws: MaterialXError.self) { try stitched.set("tint", to: Value.numbers([1, 1])) }
    }
}

/// #29: the stitching graph can be dumped for debugging.
@Suite(.serialized)
struct GraphDescriptionTests {
    @Test func descriptionNamesFunctionsAndNodes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(StitchingTests.document.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("NG_test")), functionName: "materialx_graph")
        let description = stitched.graphDescription
        #expect(description.hasPrefix("materialx_graph(arg0: context, arg1: parameters):"))
        #expect(description.contains("mx_multiply_color3FA(") && description.contains("// scaled"))
        #expect(description.contains("mx_mix_color3(") && description.contains("// blend"))
        #expect(description.contains("mx_output_vector3("))
    }
}

/// #44: parameter values survive re-stitching a reloaded document.
@Suite(.serialized)
struct CarryParametersTests {
    @Test func editedValuesCarryOver() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        var old = try stitcher.stitch(try #require(Document(data: Data(StitchingTests.document.utf8)).nodeGraph("NG_test")), functionName: "materialx_graph")
        try old.set("tint", to: SIMD3<Float>(0.1, 0.2, 0.3))
        let changed = StitchingTests.document.replacingOccurrences(of: "<input name=\"mix\" type=\"float\" value=\"0.5\" />", with: "<input name=\"mix\" type=\"float\" value=\"0.25\" />")
        var new = try stitcher.stitch(try #require(Document(data: Data(changed.utf8)).nodeGraph("NG_test")), functionName: "materialx_graph")
        new.carryParameters(from: old)
        #expect(new.parameterData[try #require(new.parameter("tint")).slot] == [0.1, 0.2, 0.3, 0])
        // mix was edited in the file, not at run time, so the file's new value wins.
        #expect(new.parameterData[try #require(new.parameter("blend.mix")).slot].x == 0.25)
    }
}

/// #58: a graph's compiled shape can be inspected without stitching or running it.
@Suite(.serialized)
struct GraphPlanTests {
    @Test func planShowsCallsWiringAndParameters() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        let stitcher = GraphStitcher(nodeLibrary: nodeLibrary)
        let document = try Document(data: Data(StitchingTests.document.utf8))
        let plan = try stitcher.plan(try #require(document.nodeGraph("NG_test")), functionName: "materialx_graph")
        #expect(nodeLibrary.stitchCount == 0)
        #expect(plan.parameters.map(\.name) == ["tint", "scaled.in2", "blend.bg", "blend.mix"])
        let multiply = try #require(plan.calls(for: "scaled").first)
        #expect(multiply.function == "mx_multiply_color3FA")
        let mix = try #require(plan.calls(for: "blend").first)
        #expect(mix.function == "mx_mix_color3")
        let multiplyIndex = try #require(plan.calls.firstIndex(of: multiply))
        #expect(mix.arguments.first == .call(multiplyIndex))
        #expect(plan.calls.last?.function == "mx_output_vector3")
        #expect(plan.calls.last?.arguments.suffix(2) == [.context, .parameters])
    }

    @Test func colorspaceConversionIsInlinedIntoThePlan() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let xml = """
        <materialx version="1.39" colorspace="srgb_texture"><nodegraph name="g">
          <add name="n" type="color3"><input name="in1" type="color3" value="0.5, 0.5, 0.5" /></add>
          <output name="out" type="color3" nodename="n" />
        </nodegraph></materialx>
        """
        let document = try Document(data: Data(xml.utf8))
        let plan = try stitcher.plan(try #require(document.nodeGraph("g")), functionName: "f", documentColorSpace: document.colorSpace)
        #expect(plan.calls.contains { ($0.origin ?? "").hasPrefix("n.in1#colorspace/") })
    }
}

/// #61: StitchedGraph.evaluate(at:) is the one way to run a graph on the GPU.
@Suite(.serialized)
struct EvaluateTests {
    @Test func evaluatesEachTexcoordAndWidensBooleans() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <texcoord name="uv" type="vector2" />
          <extract name="u" type="float"><input name="in" type="vector2" nodename="uv" /><input name="index" type="integer" value="0" /></extract>
          <ifgreater name="n" type="boolean"><input name="value1" type="float" nodename="u" /><input name="value2" type="float" value="0.5" /></ifgreater>
          <output name="out" type="boolean" nodename="n" />
        </nodegraph></materialx>
        """
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        let values = try stitched.evaluate(at: [[0.25, 0], [0.75, 0], [0.9, 0]])
        #expect(values.map(\.x) == [0, 1, 1])
        #expect(try stitched.evaluate(at: []).isEmpty)
    }
}

/// #22: graphs take an MXShadingContext; Swift and Metal agree on its layout.
@Suite(.serialized)
struct ShadingContextTests {
    @Test func contextFieldsReachTheGraph() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = """
        <materialx version="1.39"><nodegraph name="g">
          <texcoord name="n" type="vector2"><input name="index" type="integer" value="0" /></texcoord>
          <output name="out" type="vector2" nodename="n" />
        </nodegraph></materialx>
        """
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        var context = MXShadingContext(texcoord: [0.25, 0.75])
        context.time = 99
        context.vertexColor = [9, 9, 9, 9] // Fields after texcoord must not shift it.
        let value = try #require(try stitched.evaluate(contexts: [context]).first)
        #expect(value == [0.25, 0.75, 0, 1])
        #expect(stitched.graphDescription.contains("mx_texcoord_vector2(arg0,"))
    }

    @Test func signatureIsContextThenParameters() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let plan = try stitcher.plan(try #require(Document(data: Data(StitchingTests.document.utf8)).nodeGraph("NG_test")), functionName: "f")
        #expect(plan.description.hasPrefix("f(arg0: context, arg1: parameters):"))
        #expect(StitchedGraph.Argument.context.rawValue == 0)
    }
}

/// #16: geometric nodes read the shading context.
@Suite(.serialized)
struct GeometryNodeTests {
    func evaluate(_ body: String, type: String, context: MXShadingContext) throws -> SIMD4<Float> {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
        return try #require(try stitched.evaluate(contexts: [context]).first)
    }

    static var context: MXShadingContext {
        var context = MXShadingContext(texcoord: .zero)
        context.positionWorld = [1, 2, 3]
        context.positionObject = [4, 5, 6]
        context.normalWorld = [0, 0, 1]
        context.normalObject = [1, 0, 0]
        context.tangentWorld = [0, 1, 0]
        context.bitangentObject = [0, 0, -1]
        context.viewDirectionWorld = [0.6, 0.8, 0]
        context.vertexColor = [0.1, 0.2, 0.3, 0.4]
        context.frame = 48
        return context
    }

    @Test func spaceSelectsWorldOrObject() throws {
        #expect(try evaluate("<position name=\"n\" type=\"vector3\"><input name=\"space\" type=\"string\" value=\"world\" /></position>", type: "vector3", context: Self.context) == [1, 2, 3, 1])
        #expect(try evaluate("<position name=\"n\" type=\"vector3\" />", type: "vector3", context: Self.context) == [4, 5, 6, 1])
        #expect(try evaluate("<normal name=\"n\" type=\"vector3\"><input name=\"space\" type=\"string\" value=\"model\" /></normal>", type: "vector3", context: Self.context) == [1, 0, 0, 1])
        #expect(try evaluate("<tangent name=\"n\" type=\"vector3\"><input name=\"space\" type=\"string\" value=\"world\" /></tangent>", type: "vector3", context: Self.context) == [0, 1, 0, 1])
        #expect(try evaluate("<bitangent name=\"n\" type=\"vector3\" />", type: "vector3", context: Self.context) == [0, 0, -1, 1])
        #expect(try evaluate("<viewdirection name=\"n\" type=\"vector3\" />", type: "vector3", context: Self.context) == [0.6, 0.8, 0, 1])
    }

    @Test func colorTimeFrameAndGeomprop() throws {
        #expect(try evaluate("<geomcolor name=\"n\" type=\"color4\" />", type: "color4", context: Self.context) == [0.1, 0.2, 0.3, 0.4])
        #expect(try evaluate("<frame name=\"n\" type=\"float\" />", type: "float", context: Self.context).x == 48)
        #expect(try evaluate("<time name=\"n\" type=\"float\" />", type: "float", context: Self.context).x == 2) // 48 / 24 fps
        let prop = "<geompropvalue name=\"n\" type=\"color3\"><input name=\"geomprop\" type=\"string\" value=\"Cd\" /><input name=\"default\" type=\"color3\" value=\"0.5, 0.25, 1\" /></geompropvalue>"
        #expect(try evaluate(prop, type: "color3", context: Self.context) == [0.5, 0.25, 1, 1])
    }

    @Test func badSpaceThrows() throws {
        #expect(throws: MaterialXError.self) {
            try evaluate("<position name=\"n\" type=\"vector3\"><input name=\"space\" type=\"string\" value=\"screen\" /></position>", type: "vector3", context: Self.context)
        }
    }
}
