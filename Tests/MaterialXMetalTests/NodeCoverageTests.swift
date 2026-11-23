import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #20: node coverage is tracked against a checked-in baseline.
///
/// `Resources/node-coverage.txt` lists every supported nodedef as `name implementation`. The test fails when one
/// of them loses support. Regenerate it with `MX_UPDATE_COVERAGE=1` after adding nodes.
struct NodeCoverageTests {
    static let baselineURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/node-coverage.txt")

    static func report(_ coverage: [String: NodeImplementation]) -> String {
        coverage.filter { $0.value != .unsupported }.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.rawValue)" }.joined(separator: "\n") + "\n"
    }

    @Test func coverageDoesNotRegress() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        #expect(coverage.count == StandardLibrary.shared.nodeDefs.count)
        if ProcessInfo.processInfo.environment["MX_UPDATE_COVERAGE"] != nil {
            try Self.report(coverage).write(to: Self.baselineURL, atomically: true, encoding: .utf8)
            return
        }
        let baseline = try String(contentsOf: Self.baselineURL, encoding: .utf8).split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) }
        let lost = baseline.filter { (coverage[$0] ?? .unsupported) == .unsupported }
        #expect(lost.isEmpty, "Nodedefs that lost support: \(lost)")
        let supported = coverage.values.filter { $0 != .unsupported }.count
        #expect(supported >= baseline.count, "Coverage has new entries; regenerate with MX_UPDATE_COVERAGE=1")
    }

    @Test func classifiesKnownNodes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        #expect(coverage["ND_add_color3"] == .metal)
        #expect(coverage["ND_separate3_color3"] == .metal)
        #expect(coverage["ND_switch_color3"] == .nodeGraph)
        #expect(coverage["ND_noise2d_float"] == .metal)
        #expect(coverage["ND_heighttonormal_vector3"] == .unsupported) // #77
    }
}

/// #57: coverage() and stitch() must agree, because both use the same node resolution.
@Suite(.serialized)
struct CoverageAgreesWithStitchingTests {
    @Test func everyNodeDefStitchesExactlyWhenCoverageSaysSo() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let coverage = stitcher.coverage()
        var disagreements: [String] = []
        for nodeDef in StandardLibrary.shared.nodeDefs.values {
            // Only single-output data nodes can be stitched as a graph output.
            guard nodeDef.outputs.count == 1, let type = nodeDef.outputs.first?.type,
                  [ValueType.float, .vector2, .vector3, .vector4, .color3, .color4, .integer, .boolean].contains(type) else { continue }
            let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\"><\(nodeDef.node) name=\"n\" type=\"\(type)\" nodedef=\"\(nodeDef.name)\" /><output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
            let graph = try #require(try MaterialXDocument(data: Data(xml.utf8)).nodeGraph("g"))
            let stitched = (try? stitcher.stitch(graph, functionName: "f")) != nil
            let supported = coverage[nodeDef.name] != .unsupported
            if stitched != supported {
                disagreements.append("\(nodeDef.name): coverage \(coverage[nodeDef.name]?.rawValue ?? "nil"), stitched \(stitched)")
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.sorted())")
    }
}

/// #63: inverse trigonometry.
struct InverseTrigonometryTests {
    @Test func inverseTrigNodeDefsHaveMetalFunctions() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        for category in ["asin", "acos", "atan2"] {
            for type in ["float", "vector2", "vector3", "vector4"] {
                #expect(coverage["ND_\(category)_\(type)"] == .metal, "ND_\(category)_\(type)")
            }
        }
    }
}

/// #11: with its subtasks done, no non-shader stdlib math or geometry node is left unsupported.
struct MathCoverageTests {
    @Test func remainingMathNodesAreSupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        for name in ["ND_add_integer", "ND_subtract_integer", "ND_texcoord_vector3", "ND_trianglewave_float", "ND_distance_vector3", "ND_reflect_vector3", "ND_refract_vector3"] where StandardLibrary.shared.nodeDefs[name] != nil {
            #expect(coverage[name] != .unsupported, "\(name)")
        }
    }
}
