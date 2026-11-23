import Foundation
@testable import MaterialXDemoSupport
import Metal
import MetalSprocketsMaterialX
import Testing

@MainActor
struct MaterialXDemoSupportTests {
    @Test func sampleDocumentStitchesEveryOutput() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let document = try MaterialXDocument(url: MaterialXDemoModel.sampleURL)
        let stitcher = GraphStitcher(nodeLibrary: try MetalNodeLibrary(device: device))
        let outputs = MaterialXDemoModel.stitchOutputs(of: document, with: stitcher, previous: [])
        #expect(outputs.map(\.name) == ["checker.out", "rainbow.out", "rings.out"])
        for output in outputs {
            if case let .failure(error) = output.result {
                Issue.record("\(output.name): \(error)")
            }
        }
    }
}
