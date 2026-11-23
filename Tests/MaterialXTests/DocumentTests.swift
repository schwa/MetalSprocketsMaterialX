import Foundation
@testable import MaterialX
import Testing

struct DocumentTests {
    @Test func bundledStandardLibraryLoads() {
        let library = StandardLibrary.shared
        #expect(library.nodeDefs.count > 700)
        #expect(library.nodeDefs["ND_add_color3"]?.inputs.map(\.name) == ["in1", "in2"])
        #expect(library.nodeDefs["ND_standard_surface_surfaceshader"] != nil)
        #expect(library.nodeDefs["ND_open_pbr_surface_surfaceshader"] != nil)
        #expect(library.nodeDefs["ND_gltf_pbr_surfaceshader"] != nil)
        #expect(library.nodeGraphs["ND_standard_surface_surfaceshader"] != nil)
    }

    /// #2: a nodedef with `inherit` gets the parent's inputs and outputs; its own inputs override the parent's.
    @Test func nodeDefInheritance() throws {
        let nodeDef = try #require(StandardLibrary.shared.nodeDefs["ND_standard_surface_surfaceshader"])
        #expect(nodeDef.input("specular_roughness") != nil)
        #expect(nodeDef.input("base")?.value == .numbers([1]))
        #expect(nodeDef.outputs.map(\.name) == ["out"])
        #expect(nodeDef.inputs.filter { $0.name == "base" }.count == 1)
    }

    /// #1: xi:include pulls in elements from other files, relative to the including file. Cycles are an error.
    @Test func xiIncludeIsFollowed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ body: String) throws {
            try Data("<?xml version=\"1.0\"?><materialx version=\"1.39\" xmlns:xi=\"http://www.w3.org/2001/XInclude\">\(body)</materialx>".utf8).write(to: directory.appendingPathComponent(name))
        }
        try write("main.mtlx", "<xi:include href=\"sub/defs.mtlx\" /><nodegraph name=\"main_graph\" />")
        try write("sub/defs.mtlx", "<xi:include href=\"more.mtlx\" /><nodedef name=\"ND_a\" node=\"a\"><output name=\"out\" type=\"float\" /></nodedef>")
        try write("sub/more.mtlx", "<nodegraph name=\"included_graph\" />")
        let document = try Document(url: directory.appendingPathComponent("main.mtlx"))
        #expect(document.nodeDefs.map(\.name) == ["ND_a"])
        #expect(Set(document.nodeGraphs.map(\.name)) == ["main_graph", "included_graph"])

        try write("loop.mtlx", "<xi:include href=\"loop.mtlx\" />")
        #expect(throws: MaterialXError.self) { try Document(url: directory.appendingPathComponent("loop.mtlx")) }
    }

    @Test func nodeDefMatchesFloatArgumentVariant() throws {
        let node = try Node(Element(tag: "multiply", attributes: ["name": "m", "type": "color3"], children: [
            Element(tag: "input", attributes: ["name": "in1", "type": "color3", "value": "1, 1, 1"]),
            Element(tag: "input", attributes: ["name": "in2", "type": "float", "value": "0.5"]),
        ]))
        #expect(StandardLibrary.shared.nodeDef(for: node)?.name == "ND_multiply_color3FA")
    }

    @Test func parsesValues() throws {
        #expect(try Value("0.1, 0.2, 0.3", type: .color3) == .numbers([0.1, 0.2, 0.3]))
        #expect(try Value("true", type: .boolean) == .numbers([1]))
        #expect(throws: MaterialXError.self) { try Value("1, 2", type: .color3) }
    }

    /// Every .mtlx file shipped with the system or Reality Composer Pro parses. Skipped when none are installed.
    @Test(arguments: SystemMaterialXFiles.urls)
    func systemFileParses(url: URL) throws {
        let document = try Document(url: url)
        #expect(document.root.tag == "materialx")
    }
}

enum SystemMaterialXFiles {
    static let roots = [
        "/Applications/RealityComposerPro.app/Contents/SystemFrameworks/ShaderGraph.framework/Versions/A/Resources/MaterialX",
        "/System/Library/SubFrameworks/ShaderGraph.framework/Versions/A/Resources/MaterialX",
        "/System/Library/PrivateFrameworks/CoreUSDEdit.framework/Versions/A/Resources/MaterialX",
    ]

    static var urls: [URL] {
        roots.flatMap { root -> [URL] in
            let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)
            return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "mtlx" }
        }
    }
}
