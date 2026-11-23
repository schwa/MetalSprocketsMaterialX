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

    /// #3: a node's version attribute picks the matching nodedef; without one the default version wins.
    @Test func nodeDefVersionSelection() throws {
        func node(_ attributes: [String: String]) throws -> Node {
            try Node(Element(tag: "standard_surface", attributes: ["name": "s", "type": "surfaceshader"].merging(attributes) { $1 }))
        }
        let library = StandardLibrary.shared
        #expect(library.nodeDef(for: try node([:]))?.name == "ND_standard_surface_surfaceshader")
        #expect(library.nodeDef(for: try node(["version": "1.0.0"]))?.name == "ND_standard_surface_surfaceshader_100")
        #expect(library.nodeDef(for: try node(["version": "1.0.1"]))?.name == "ND_standard_surface_surfaceshader")
        #expect(library.nodeDef(for: try node(["version": "9.9"])) == nil)
    }

    /// #6: tokens, fileprefix inheritance and UDIM patterns.
    @Test func filenamesResolveTokensAndPrefixes() throws {
        let source = """
        <materialx version="1.39" fileprefix="root/">
          <nodegraph name="g" fileprefix="textures/">
            <token name="asset" type="string" value="wood" />
            <image name="a" type="color3"><input name="file" type="filename" value="[asset]_albedo.&lt;UDIM&gt;.png" /></image>
            <image name="b" type="color3" fileprefix="override/">
              <token name="asset" type="string" value="metal" />
              <input name="file" type="filename" value="[asset].png" />
            </image>
          </nodegraph>
          <image name="c" type="color3"><input name="file" type="filename" value="top.png" /></image>
        </materialx>
        """
        let document = try Document(data: Data(source.utf8))
        let graph = try #require(document.nodeGraph("g"))
        func resolve(_ name: String, in graph: NodeGraph?) throws -> String? {
            let node = try #require(graph?.nodes[name] ?? document.nodes.first { $0.name == name })
            return document.resolvedFilename(try #require(node.input("file")), node: node, graph: graph)
        }
        let tiled = try #require(try resolve("a", in: graph))
        #expect(tiled == "textures/wood_albedo.<UDIM>.png")
        #expect(try resolve("b", in: graph) == "override/metal.png")
        #expect(try resolve("c", in: nil) == "root/top.png")
        let pattern = FilenamePattern(tiled)
        #expect(pattern.isTiled)
        #expect(pattern.filename(u: 1, v: 2) == "textures/wood_albedo.1022.png")
        #expect(FilenamePattern("t.<UVTILE>.png").filename(u: 0, v: 0) == "t.u1_v1.png")
    }

    /// #9: validation reports broken references and type mismatches.
    @Test func validationReportsProblems() throws {
        let source = """
        <materialx version="1.39">
          <nodegraph name="g">
            <input name="tint" type="color3" value="1, 1, 1" />
            <constant name="f" type="float"><input name="value" type="float" value="1" /></constant>
            <multiply name="bad_type" type="color3">
              <input name="in1" type="color3" nodename="f" />
              <input name="in2" type="float" interfacename="missing" />
            </multiply>
            <add name="dangling" type="color3"><input name="in1" type="color3" nodename="nowhere" /></add>
            <frobnicate name="unknown" type="float" />
            <output name="out" type="color3" nodename="bad_type" />
          </nodegraph>
          <standard_surface name="s" type="surfaceshader">
            <input name="base_color" type="color3" nodegraph="g" output="nope" />
          </standard_surface>
        </materialx>
        """
        let issues = try Document(data: Data(source.utf8)).validate().map(\.description)
        #expect(issues.contains { $0.hasPrefix("g/bad_type.in1: type color3 does not match 'f'") })
        #expect(issues.contains { $0.hasPrefix("g/bad_type.in2: interface input 'missing'") })
        #expect(issues.contains { $0.hasPrefix("g/dangling.in1: node 'nowhere'") })
        #expect(issues.contains { $0.hasPrefix("g/unknown: no nodedef") })
        #expect(issues.contains { $0.hasPrefix("s.base_color: nodegraph 'g' has no output 'nope'") })
        #expect(issues.count == 5, "\(issues)")
    }

    @Test func validDocumentHasNoIssues() throws {
        let source = """
        <materialx version="1.39">
          <nodegraph name="g">
            <separate3 name="parts" type="multioutput"><input name="in" type="color3" value="1, 2, 3" /></separate3>
            <multiply name="m" type="float"><input name="in1" type="float" nodename="parts" output="outr" /></multiply>
            <output name="out" type="float" nodename="m" />
          </nodegraph>
          <standard_surface name="s" type="surfaceshader"><input name="base" type="float" nodegraph="g" output="out" /></standard_surface>
          <surfacematerial name="mat" type="material"><input name="surfaceshader" type="surfaceshader" nodename="s" /></surfacematerial>
        </materialx>
        """
        #expect(try Document(data: Data(source.utf8)).validate().isEmpty)
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
        #expect(try Value("true", type: .boolean) == .boolean(true))
        #expect(try Value("true", type: .boolean).numbers == [1])
        #expect(try Value(" 3 ", type: .integer) == .integer(3))
        #expect(try Value("1 1,1", type: .color3) == .numbers([1, 1, 1]))
        #expect(throws: MaterialXError.self) { try Value("1, 2", type: .color3) }
        #expect(throws: MaterialXError.self) { try Value("1.5", type: .integer) }
        #expect(throws: MaterialXError.self) { try Value("yes", type: .boolean) }
    }

    /// #4: typedefs, including struct members, are read.
    @Test func typeDefsAreRead() throws {
        let library = StandardLibrary.shared
        #expect(library.typeDefs[.color3]?.semantic == "color")
        #expect(library.typeDefs[.surfaceshader]?.context == "surface")
        let source = """
        <materialx version="1.39">
          <typedef name="texcoord_struct"><member name="uv" type="vector2" value="0, 0" /><member name="set" type="integer" /></typedef>
        </materialx>
        """
        let typeDef = try #require(try Document(data: Data(source.utf8)).typeDefs.first)
        #expect(typeDef.members.map(\.name) == ["uv", "set"])
        #expect(typeDef.members.map(\.type) == [.vector2, .integer])
    }

    /// Every .mtlx file shipped with the system or Reality Composer Pro parses. Without any (CI, other machines) the
    /// test is reported as skipped instead of passing with zero cases; the vendored corpus (#48) still runs there.
    @Test(.enabled(if: !SystemMaterialXFiles.urls.isEmpty, "No system or Reality Composer Pro .mtlx files installed"), arguments: SystemMaterialXFiles.urls)
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

/// #7: looks, material assignment, collections, variants and geominfo.
struct LookTests {
    static let source = """
    <materialx version="1.39">
      <surfacematerial name="M_wood" type="material" />
      <surfacematerial name="M_metal" type="material" />
      <surfacematerial name="M_default" type="material" />
      <collection name="C_hardware" includegeom="/chair/bolts,/table/legs" excludegeom="/table/legs/foot" />
      <collection name="C_all_hardware" includecollection="C_hardware" />
      <look name="L_base">
        <materialassign name="MA_all" geom="/" material="M_default" />
      </look>
      <look name="L_furniture" inherit="L_base">
        <materialassign name="MA_wood" geom="/chair/seat, /table/top" material="M_wood" />
        <materialassign name="MA_metal" collection="C_all_hardware" material="M_metal" />
        <variantassign name="VA" variantset="finish" variant="dark" />
      </look>
      <variantset name="finish">
        <variant name="dark"><input name="base_color" type="color3" value="0.1, 0.05, 0" /></variant>
        <variant name="light"><input name="base_color" type="color3" value="0.8, 0.6, 0.4" /></variant>
      </variantset>
      <geominfo name="GI_chair" geom="/chair"><token name="asset" type="string" value="chair" /></geominfo>
    </materialx>
    """

    @Test func geometryPathsMatchLikeMaterialX() {
        #expect(GeometryPath("/a/b").matches(GeometryPath("/a/b/c")))
        #expect(GeometryPath("/a/b/c").matches(GeometryPath("/a/b")))
        #expect(!GeometryPath("/a/b/c").matches(GeometryPath("/a/b"), contains: true))
        #expect(GeometryPath("/").matches(GeometryPath("/anything")))
        #expect(!GeometryPath("").matches(GeometryPath("/a")))
        #expect(!GeometryPath("/a/x").matches(GeometryPath("/a/b")))
    }

    @Test func materialAssignmentFollowsLooksAndCollections() throws {
        let document = try Document(data: Data(Self.source.utf8))
        func materials(_ geometry: String) throws -> [String] {
            try document.materialAssignments(for: geometry, look: "L_furniture").map(\.material)
        }
        #expect(try materials("/chair/seat") == ["M_default", "M_wood"])
        #expect(try materials("/chair/bolts/bolt1") == ["M_default", "M_metal"])
        #expect(try materials("/table/legs/leg1") == ["M_default", "M_metal"])
        #expect(try materials("/table/legs/foot") == ["M_default"])
        #expect(try materials("/lamp") == ["M_default"])
    }

    @Test func variantsAndGeomInfo() throws {
        let document = try Document(data: Data(Self.source.utf8))
        let finish = try #require(try document.variantSets().first)
        #expect(Set(finish.variants.keys) == ["dark", "light"])
        #expect(finish.variants["dark"]?.first?.value == .numbers([0.1, 0.05, 0]))
        #expect(document.look("L_furniture")?.variantAssigns.first?.variant == "dark")
        #expect(document.geomInfos.first?.values["asset"]?["value"] == "chair")
    }

    @Test func collectionCyclesThrow() throws {
        let source = """
        <materialx version="1.39">
          <collection name="A" includecollection="B" /><collection name="B" includecollection="A" />
        </materialx>
        """
        let document = try Document(data: Data(source.utf8))
        #expect(throws: MaterialXError.self) { try document.collection("A", contains: "/x") }
    }
}

/// #8: documents can be written back to .mtlx.
struct WriterTests {
    @Test(arguments: SystemMaterialXFiles.urls.prefix(10) + [StandardLibrary.bundledLibrariesURL.appendingPathComponent("stdlib/stdlib_defs.mtlx")])
    func roundTrip(url: URL) throws {
        let document = try Document(url: url)
        let reparsed = try Document(data: document.data())
        #expect(reparsed.root == document.root)
    }

    @Test func editAndWrite() throws {
        let source = """
        <materialx version="1.39"><nodegraph name="g">
          <constant name="c" type="color3"><input name="value" type="color3" value="1, 0, 0" /></constant>
          <output name="out" type="color3" nodename="c" />
        </nodegraph></materialx>
        """
        var root = try Document(data: Data(source.utf8)).root
        root.children[0].children[0].children[0].attributes["value"] = "0, 1, 0"
        root.children[0].children[0].attributes["note"] = "a < b & \"c\""
        let edited = try Document(root: root)
        let text = try #require(String(data: edited.data(), encoding: .utf8))
        #expect(text.hasPrefix("<?xml version=\"1.0\"?>\n<materialx version=\"1.39\">"))
        #expect(text.contains("<constant name=\"c\" type=\"color3\" note=\"a &lt; b &amp; &quot;c&quot;\">"))
        let reparsed = try Document(data: edited.data())
        #expect(reparsed.nodeGraph("g")?.nodes["c"]?.input("value")?.value == .numbers([0, 1, 0]))
        #expect(reparsed.root == root)
    }
}

/// #44: documents reload when their file (or an included file) changes.
struct DocumentWatcherTests {
    @Test func reloadsOnChangeIncludingIncludes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let main = directory.appendingPathComponent("main.mtlx")
        let included = directory.appendingPathComponent("defs.mtlx")
        try Data("<materialx version=\"1.39\"><nodegraph name=\"a\" /></materialx>".utf8).write(to: included)
        try Data("<materialx version=\"1.39\"><xi:include href=\"defs.mtlx\" /></materialx>".utf8).write(to: main)

        var events = DocumentWatcher(url: main, interval: .milliseconds(20)).events().makeAsyncIterator()
        guard case let .loaded(first) = await events.next() else { Issue.record("no first load"); return }
        #expect(first.nodeGraphs.map(\.name) == ["a"])

        try await Task.sleep(for: .milliseconds(50))
        try Data("<materialx version=\"1.39\"><nodegraph name=\"b\" /></materialx>".utf8).write(to: included, options: .atomic)
        guard case let .loaded(second) = await events.next() else { Issue.record("no reload"); return }
        #expect(second.nodeGraphs.map(\.name) == ["b"])

        try await Task.sleep(for: .milliseconds(50))
        try Data("<materialx".utf8).write(to: main, options: .atomic)
        guard case .failed = await events.next() else { Issue.record("expected a parse failure"); return }
    }
}
