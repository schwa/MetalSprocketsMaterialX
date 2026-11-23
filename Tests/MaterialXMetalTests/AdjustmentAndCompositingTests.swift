import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #14: adjustment and compositing nodes.
@Suite(.serialized)
struct AdjustmentAndCompositingTests {
    func stitch(_ body: String, type: String, device: MTLDevice) throws -> StitchedGraph {
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        return try stitcher.stitch(try #require(Document(data: Data(xml.utf8)).nodeGraph("g")), functionName: "materialx_graph")
    }

    @Test func everyNonShaderNodeDefStitches() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var failures: [String] = []
        for nodeDef in StandardLibrary.shared.nodeDefs.values where ["adjustment", "compositing"].contains(nodeDef.nodeGroup ?? "") {
            guard nodeDef.outputs.count == 1, let type = nodeDef.outputs.first?.type, !type.rawValue.hasSuffix("shader") else { continue }
            do {
                _ = try stitch("<\(nodeDef.node) name=\"n\" type=\"\(type)\" nodedef=\"\(nodeDef.name)\" />", type: type.rawValue, device: device)
            } catch {
                failures.append("\(nodeDef.name): \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.sorted())")
    }

    @Test func hsvRoundTripAndSaturate() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let roundTrip = try stitch("""
        <rgbtohsv name="hsv" type="color3"><input name="in" type="color3" value="0.2, 0.6, 0.4" /></rgbtohsv>
        <hsvtorgb name="n" type="color3"><input name="in" type="color3" nodename="hsv" /></hsvtorgb>
        """, type: "color3", device: device)
        let value = try StitchingTests().evaluate(roundTrip, device: device)[0]
        #expect(abs(value.x - 0.2) < 1e-5 && abs(value.y - 0.6) < 1e-5 && abs(value.z - 0.4) < 1e-5, "\(value)")

        let gray = try stitch("""
        <saturate name="n" type="color3"><input name="in" type="color3" value="1, 0, 0" /><input name="amount" type="float" value="0" /></saturate>
        """, type: "color3", device: device)
        let luminance = try StitchingTests().evaluate(gray, device: device)[0]
        #expect(abs(luminance.x - luminance.y) < 1e-6 && abs(luminance.y - luminance.z) < 1e-6 && luminance.x > 0.2, "\(luminance)")
    }
}
