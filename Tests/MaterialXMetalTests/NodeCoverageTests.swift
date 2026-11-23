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
        #expect(coverage["ND_noise2d_float"] == .unsupported)
    }
}
