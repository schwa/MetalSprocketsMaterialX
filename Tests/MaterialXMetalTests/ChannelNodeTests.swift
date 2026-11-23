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
        #expect(description.hasPrefix("materialx_graph(arg0: context, arg1: parameters, arg2: textures):"))
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
        #expect(plan.calls.last?.arguments.suffix(3) == [.context, .parameters, .textures])
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
        #expect(plan.description.hasPrefix("f(arg0: context, arg1: parameters, arg2: textures):"))
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

/// #23: textures reach stitched graphs through the MXTexture argument buffer.
@Suite(.serialized)
struct TextureTableTests {
    static let source = """
    <materialx version="1.39">
      <nodedef name="ND_texture_slot_color4" node="texture_slot">
        <input name="slot" type="integer" value="0" />
        <input name="texcoord" type="vector2" value="0, 0" />
        <output name="out" type="color4" />
      </nodedef>
      <nodegraph name="g">
        <texcoord name="uv" type="vector2" />
        <texture_slot name="n" type="color4">
          <input name="slot" type="integer" value="1" />
          <input name="texcoord" type="vector2" nodename="uv" />
        </texture_slot>
        <output name="out" type="color4" nodename="n" />
      </nodegraph>
    </materialx>
    """

    func solidTexture(_ color: SIMD4<UInt8>, device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let pixels = [SIMD4<UInt8>](repeating: color, count: 4)
        texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
        return texture
    }

    @Test func graphSamplesTheTextureInItsSlot() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device), standardLibrary: StandardLibrary.shared.merging([document]))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph")
        #expect(stitched.graphDescription.contains("mx_texture_slot_color4(arg2,"))

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.supportArgumentBuffers = true
        let sampler = try #require(device.makeSamplerState(descriptor: samplerDescriptor))
        let red = try solidTexture([255, 0, 0, 255], device: device)
        let blue = try solidTexture([0, 0, 255, 255], device: device)
        let table = try StitchedGraph.makeTextureTable([(red, sampler), (blue, sampler)], device: device)
        let values = try stitched.evaluate(at: [[0.5, 0.5]], textures: table, residentTextures: [red, blue], device: device)
        #expect(values == [[0, 0, 1, 1]])
    }
}

/// #18: image nodes read a texture slot per file; tiledimage goes through its nodegraph.
@Suite(.serialized)
struct ImageNodeTests {
    static let source = """
    <materialx version="1.39" fileprefix="textures/">
      <nodegraph name="g">
        <tiledimage name="tiled" type="color3">
          <input name="file" type="filename" value="checker.png" />
          <input name="uvtiling" type="vector2" value="2, 2" />
          <input name="filtertype" type="string" value="closest" />
        </tiledimage>
        <image name="plain" type="float" fileprefix="masks/">
          <input name="file" type="filename" value="mask.png" />
          <input name="default" type="float" value="0.25" />
        </image>
        <multiply name="n" type="color3">
          <input name="in1" type="color3" nodename="tiled" />
          <input name="in2" type="float" nodename="plain" />
        </multiply>
        <output name="out" type="color3" nodename="n" />
      </nodegraph>
    </materialx>
    """

    /// 2×2: top row red, bottom row green (Metal's row 0 is the top).
    func texture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 2, mipmapped: false)
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let pixels: [SIMD4<UInt8>] = [[255, 0, 0, 255], [255, 0, 0, 255], [0, 255, 0, 255], [0, 255, 0, 255]]
        texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
        return texture
    }

    @Test func imagesBindSlotsAndSample() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let stitched = try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph", documentFilePrefix: document.root["fileprefix"])

        #expect(Set(stitched.textures.map(\.file)) == ["textures/checker.png", "masks/mask.png"])
        #expect(Set(stitched.textures.map(\.slot)) == [0, 1])
        let tiled = try #require(stitched.textures.first { $0.file == "textures/checker.png" })
        #expect(tiled.filterType == "closest")
        #expect(tiled.samplerDescriptor.minFilter == .nearest)
        #expect(tiled.node.hasPrefix("tiled/"))

        let checker = try texture(device: device)
        let sampler = try #require(device.makeSamplerState(descriptor: tiled.samplerDescriptor))
        // The mask's slot stays empty, so that image returns its default 0.25.
        var slots = [(texture: MTLTexture, sampler: MTLSamplerState)?](repeating: nil, count: 2)
        slots[tiled.slot] = (checker, sampler)
        let table = try StitchedGraph.makeTextureTable(slots, device: device)
        // UV (0.1, 0.1) tiled ×2 is (0.2, 0.2): near the bottom in MaterialX, so the bottom (green) row.
        let values = try stitched.evaluate(at: [[0.1, 0.1], [0.1, 0.4]], textures: table, residentTextures: [checker], device: device)
        #expect(values[0] == [0, 0.25, 0, 1])
        // (0.1, 0.4) ×2 = (0.2, 0.8): the top (red) row.
        #expect(values[1] == [0.25, 0, 0, 1])
    }
}

/// Found with #18: a shader input reading one output of a document-level multi-output node lost its `output=`.
@Suite(.serialized)
struct DocumentLevelMultiOutputTests {
    @Test func shaderInputKeepsOutputName() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = """
        <materialx version="1.39">
          <separate3 name="parts" type="multioutput"><input name="in" type="color3" value="0.1, 0.2, 0.3" /></separate3>
          <standard_surface name="s" type="surfaceshader"><input name="base" type="float" nodename="parts" output="outg" /></standard_surface>
        </materialx>
        """
        let document = try Document(data: Data(xml.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let input = try #require(document.nodes.first { $0.name == "s" }?.input("base"))
        let stitched = try stitcher.stitch(input, in: document, functionName: "materialx_graph")
        #expect(try stitched.evaluate(at: [.zero]).first?.x == 0.2)
    }
}

/// #34: a surface shader compiles to one function filling MXSurfaceInputs.
@Suite(.serialized)
struct SurfaceStitchingTests {
    static let source = """
    <materialx version="1.39">
      <nodegraph name="NG_rough">
        <texcoord name="uv" type="vector2" />
        <extract name="u" type="float"><input name="in" type="vector2" nodename="uv" /><input name="index" type="integer" value="0" /></extract>
        <output name="out" type="float" nodename="u" />
      </nodegraph>
      <constant name="green" type="color3"><input name="value" type="color3" value="0, 1, 0" /></constant>
      <gltf_pbr name="pbr" type="surfaceshader">
        <input name="base_color" type="color3" nodename="green" />
        <input name="metallic" type="float" value="0.25" />
        <input name="roughness" type="float" nodegraph="NG_rough" output="out" />
        <input name="emissive" type="color3" value="0.5, 0.5, 0" />
      </gltf_pbr>
      <surfacematerial name="M" type="material"><input name="surfaceshader" type="surfaceshader" nodename="pbr" /></surfacematerial>
    </materialx>
    """

    @Test func gltfPbrFillsSurfaceInputs() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(Self.source.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let shader = try #require(document.nodes.first { $0.name == "pbr" })
        var material = try stitcher.stitchSurface(shader, in: document, functionName: "materialx_surface")
        #expect(material.parameter("pbr.metallic") != nil)

        var context = MXShadingContext(texcoord: [0.75, 0])
        context.normalWorld = [0, 1, 0]
        let surface = try #require(try material.evaluateSurface(contexts: [context]).first)
        #expect(surface.baseColor == [0, 1, 0])
        #expect(surface.metallic == 0.25)
        #expect(surface.roughness == 0.75)
        #expect(surface.emissive == [0.5, 0.5, 0])
        #expect(surface.normal == [0, 1, 0]) // defaultgeomprop Nworld
        #expect(surface.occlusion == 1) // nodedef default
        #expect(surface.ior == 1.5) // not a gltf_pbr input: keeps the initial value

        try material.set("pbr.metallic", to: 1)
        #expect(try material.evaluateSurface(contexts: [context]).first?.metallic == 1)
    }

    @Test func unmappedShaderThrows() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data("<materialx version=\"1.39\"><surface_unlit name=\"s\" type=\"surfaceshader\" /></materialx>".utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let shader = try #require(document.nodes.first)
        #expect(throws: MaterialXError.self) { try stitcher.stitchSurface(shader, in: document, functionName: "f") }
    }
}

/// #36: standard_surface and open_pbr_surface go through MaterialX's translation graphs to MXSurfaceInputs.
@Suite(.serialized)
struct SurfaceTranslationTests {
    func surface(_ xml: String, shader: String) throws -> MXSurfaceInputs {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try Document(data: Data(xml.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let node = try #require(document.nodes.first { $0.name == shader })
        let material = try stitcher.stitchSurface(node, in: document, functionName: "materialx_surface")
        return try #require(try material.evaluateSurface(contexts: [MXShadingContext(texcoord: .zero)]).first)
    }

    @Test func standardSurfaceTranslates() throws {
        let value = try surface("""
        <materialx version="1.39">
          <standard_surface name="s" type="surfaceshader">
            <input name="base" type="float" value="1" />
            <input name="base_color" type="color3" value="0.8, 0.2, 0.1" />
            <input name="metalness" type="float" value="0.7" />
            <input name="specular_roughness" type="float" value="0.3" />
            <input name="specular_IOR" type="float" value="1.4" />
            <input name="emission" type="float" value="1" />
            <input name="emission_color" type="color3" value="0, 0.5, 0" />
          </standard_surface>
        </materialx>
        """, shader: "s")
        #expect(simd_distance(value.baseColor, [0.8, 0.2, 0.1]) < 1e-5)
        #expect(abs(value.metallic - 0.7) < 1e-6)
        #expect(abs(value.roughness - 0.3) < 1e-6)
        #expect(abs(value.ior - 1.4) < 1e-6)
        #expect(simd_distance(value.emissive, [0, 0.5, 0]) < 1e-5)
    }

    @Test func openPBRTranslatesThroughStandardSurface() throws {
        let value = try surface("""
        <materialx version="1.39">
          <open_pbr_surface name="s" type="surfaceshader">
            <input name="base_color" type="color3" value="0.1, 0.2, 0.9" />
            <input name="base_metalness" type="float" value="0.5" />
            <input name="specular_roughness" type="float" value="0.4" />
          </open_pbr_surface>
        </materialx>
        """, shader: "s")
        #expect(simd_distance(value.baseColor, [0.1, 0.2, 0.9]) < 1e-5)
        #expect(abs(value.metallic - 0.5) < 1e-6)
        #expect(abs(value.roughness - 0.4) < 1e-6)
        #expect(value.clearcoat == 0)
    }

    /// MaterialX's OpenPBR translation lets a full coat replace the specular roughness with the coat's
    /// (`mix(specular_roughness, coat_roughness, coat_weight)`) and darkens the base by the coat's internal reflection.
    @Test func openPBRCoatFollowsTheTranslation() throws {
        let value = try surface("""
        <materialx version="1.39">
          <open_pbr_surface name="s" type="surfaceshader">
            <input name="base_color" type="color3" value="0.1, 0.2, 0.9" />
            <input name="specular_roughness" type="float" value="0.4" />
            <input name="coat_weight" type="float" value="1" />
            <input name="coat_roughness" type="float" value="0.25" />
          </open_pbr_surface>
        </materialx>
        """, shader: "s")
        #expect(abs(value.clearcoat - 1) < 1e-6)
        #expect(abs(value.clearcoatRoughness - 0.25) < 1e-6)
        #expect(abs(value.roughness - 0.25) < 1e-6)
        #expect(value.baseColor.z < 0.9 && value.baseColor.z > 0.5)
    }

    /// Every surface shader in the corpus either stitches or fails only on an unimplemented node.
    @Test func corpusShadersStitchOrAreUnsupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        var stitched = 0
        var errors: [String] = []
        for url in CorpusTests.files {
            let document = try Document(url: url)
            let stitcher = GraphStitcher(nodeLibrary: nodeLibrary, standardLibrary: StandardLibrary.shared.merging([document]))
            for shader in document.nodes where shader.type == .surfaceshader && SurfaceMapping.builtIn[shader.category] != nil {
                do {
                    _ = try stitcher.stitchSurface(shader, in: document, functionName: "corpus_surface")
                    stitched += 1
                } catch MaterialXError.unsupportedNode {
                } catch {
                    errors.append("\(url.lastPathComponent) \(shader.name): \(error)")
                }
            }
        }
        print("corpus surfaces stitched: \(stitched)")
        #expect(stitched > 20)
        #expect(errors.isEmpty, "\(errors)")
    }
}
