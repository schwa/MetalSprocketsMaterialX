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
