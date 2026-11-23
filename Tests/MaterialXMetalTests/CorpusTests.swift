import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #48: real material documents. `Resources/Corpus` holds MaterialX 1.39.4's `resources/Materials/Examples` (.mtlx
/// only, no textures) and SceneSprockets' demo `Materials.mtlx`.
@Suite(.serialized)
struct CorpusTests {
    static let corpusURL = Bundle.module.url(forResource: "Corpus", withExtension: nil)

    static var files: [URL] {
        guard let corpusURL, let enumerator = FileManager.default.enumerator(at: corpusURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return (enumerator.allObjects as? [URL] ?? []).filter { $0.pathExtension == "mtlx" }.sorted { $0.path < $1.path }
    }

    @Test func corpusIsPresent() {
        #expect(Self.files.count >= 50)
    }

    @Test(arguments: files)
    func documentParsesAndValidates(url: URL) throws {
        let document = try MaterialXDocument(url: url)
        #expect(!document.materials.isEmpty || !document.nodeGraphs.isEmpty)
        let issues = document.validate()
        #expect(issues.isEmpty, "\(issues)")
    }

    /// Every connected shader input either stitches or fails only because a node is not implemented yet.
    @Test func connectedShaderInputsStitchOrAreUnsupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let nodeLibrary = try MetalNodeLibrary(device: device)
        var stitched = 0
        var unsupported: [String: Int] = [:]
        var errors: [String] = []
        for url in Self.files {
            let document = try MaterialXDocument(url: url)
            let stitcher = GraphStitcher(nodeLibrary: nodeLibrary, standardLibrary: StandardLibrary.shared.merging([document]))
            let shaders = document.nodes.filter { $0.type == .surfaceshader }
            for shader in shaders {
                for input in shader.inputs where input.nodeName != nil || input.nodeGraph != nil {
                    do {
                        _ = try stitcher.stitch(input, in: document, functionName: "corpus_input")
                        stitched += 1
                    } catch MaterialXError.unsupportedNode(let name) {
                        unsupported[name, default: 0] += 1
                    } catch {
                        errors.append("\(url.lastPathComponent) \(shader.name).\(input.name): \(error)")
                    }
                }
            }
        }
        print("corpus: \(stitched) inputs stitched; unsupported: \(unsupported.sorted { $0.value > $1.value })")
        #expect(stitched > 0)
        #expect(errors.isEmpty, "\(errors)")
    }
}
