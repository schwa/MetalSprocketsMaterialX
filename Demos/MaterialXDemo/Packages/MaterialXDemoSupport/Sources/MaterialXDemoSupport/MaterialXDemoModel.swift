import Foundation
import Metal
import MetalSprocketsMaterialX
import Observation

/// Loads a .mtlx file, watches it, and stitches every nodegraph output that yields a color.
@MainActor
@Observable
public final class MaterialXDemoModel {
    public struct Output: Identifiable {
        public var id: String { name }
        public var name: String
        /// The stitched graph, or why it could not be stitched.
        public var result: Result<StitchedGraph, Error>
    }

    public private(set) var url: URL
    public private(set) var outputs: [Output] = []
    public private(set) var loadError: String?
    private let stitcher: GraphStitcher
    private var watchTask: Task<Void, Never>?

    public static var sampleURL: URL {
        Bundle.module.url(forResource: "Sample", withExtension: "mtlx") ?? URL(fileURLWithPath: "/dev/null")
    }

    public init(url: URL = sampleURL, device: MTLDevice) throws {
        self.url = url
        stitcher = GraphStitcher(nodeLibrary: try MetalNodeLibrary(device: device))
        watch(url)
    }

    public func open(_ url: URL) {
        self.url = url
        watch(url)
    }

    private func watch(_ url: URL) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            for await event in DocumentWatcher(url: url).events() {
                self?.apply(event)
            }
        }
    }

    func apply(_ event: DocumentWatcher.Event) {
        switch event {
        case let .loaded(document):
            loadError = nil
            outputs = Self.stitchOutputs(of: document, with: stitcher, previous: outputs)
        case let .failed(message):
            loadError = message
        }
    }

    /// One entry per color output of every nodegraph. Parameter edits made at run time survive a reload.
    static func stitchOutputs(of document: MaterialXDocument, with stitcher: GraphStitcher, previous: [Output]) -> [Output] {
        let stitcher = { () -> GraphStitcher in
            var stitcher = stitcher
            stitcher.standardLibrary = StandardLibrary.shared.merging([document])
            return stitcher
        }()
        var outputs: [Output] = []
        for graph in document.nodeGraphs where graph.nodeDefName == nil {
            for output in graph.outputs where [.color3, .color4, .vector3, .vector4].contains(output.type) {
                let name = "\(graph.name).\(output.name)"
                let functionName = "demo_" + name.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
                let result = Result {
                    var stitched = try stitcher.stitch(graph, output: output.name, functionName: functionName, documentColorSpace: document.colorSpace)
                    if case let .success(old)? = previous.first(where: { $0.name == name })?.result {
                        stitched.carryParameters(from: old)
                    }
                    return stitched
                }
                outputs.append(Output(name: name, result: result))
            }
        }
        return outputs
    }
}
