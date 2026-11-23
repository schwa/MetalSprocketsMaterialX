import Foundation

/// The MaterialX data libraries (stdlib, pbrlib, bxdf, …) bundled with this package. Version 1.39.4.
public struct StandardLibrary: Sendable {
    public var nodeDefs: [String: NodeDef]
    public var typeDefs: [ValueType: TypeDef]
    /// Unit scales by unit type and unit name, from `<unitdef>`: `units["distance"]["inch"] == 0.0254`.
    public var units: [String: [String: Float]]
    /// `<geompropdef>`s by name, such as `UV0` or `Nworld`, used by inputs with a `defaultgeomprop`.
    public var geomPropDefs: [String: MaterialXElement]
    /// Functional nodegraphs (`*_ng.mtlx`) keyed by the nodedef they implement.
    public var nodeGraphs: [String: NodeGraph]
    private var nodeDefsByCategory: [String: [NodeDef]]

    public static let bundledLibrariesURL: URL = {
        guard let url = Bundle.module.url(forResource: "libraries", withExtension: nil) else {
            fatalError("MaterialX libraries resource missing")
        }
        return url
    }()

    public static let shared: Self = {
        do {
            return try Self(librariesURL: bundledLibrariesURL)
        } catch {
            fatalError("Could not load bundled MaterialX libraries: \(error)")
        }
    }()

    /// The documents the library was built from, in load order.
    public private(set) var documents: [MaterialXDocument]

    public init(librariesURL: URL) throws {
        var documents: [MaterialXDocument] = []
        let enumerator = FileManager.default.enumerator(at: librariesURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "mtlx" else { continue }
            documents.append(try MaterialXDocument(url: url))
        }
        self.init(documents: documents)
    }

    /// Nodedefs before inheritance is resolved, and nodegraphs by name, kept so ``merging(_:)`` only reads the new
    /// documents.
    private var unresolvedNodeDefs: [String: NodeDef] = [:]
    private var graphsByName: [String: NodeGraph] = [:]

    /// A library of the nodedefs and functional nodegraphs in `documents`. Later documents override earlier ones.
    public init(documents: [MaterialXDocument]) {
        self.documents = []
        nodeDefs = [:]
        typeDefs = [:]
        units = [:]
        geomPropDefs = [:]
        nodeGraphs = [:]
        nodeDefsByCategory = [:]
        add(documents)
    }

    /// This library plus the custom nodedefs and nodegraph implementations declared in `documents`. Only the new
    /// documents are read; inheritance and lookup tables are then rebuilt.
    public func merging(_ documents: [MaterialXDocument]) -> Self {
        var library = self
        library.add(documents)
        return library
    }

    /// Apple's ShaderGraph MaterialX folder on this Mac, if present. Its files are Apple's and are not bundled.
    public static let appleShaderGraphURL = URL(fileURLWithPath: "/System/Library/SubFrameworks/ShaderGraph.framework/Versions/A/Resources/MaterialX")

    /// This library plus the nodedefs RealityKit / Reality Composer Pro documents use, read from Apple's ShaderGraph
    /// framework on this Mac (opt-in; #46): `Apple/apple_nodedefs` (`realitykit_*`, `MTL_*`, …) and, from MaterialX
    /// 1.38, only nodedefs this library lacks (such as `swizzle`). Many have no Metal implementation yet; they parse,
    /// validate and report as unsupported. Throws if the framework is missing.
    public func addingAppleShaderGraphNodes(from url: URL = appleShaderGraphURL) throws -> Self {
        func documents(in folder: URL) throws -> [MaterialXDocument] {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            return try files.filter { $0.pathExtension == "mtlx" }.sorted { $0.path < $1.path }.map { try MaterialXDocument(url: $0) }
        }
        var library = self
        let legacy = try documents(in: url.appendingPathComponent("MaterialX-1.38/MaterialX_NodeDefs"))
        library.add(legacy, replacingExisting: false)
        library.add(try documents(in: url.appendingPathComponent("Apple/apple_nodedefs")), replacingExisting: false)
        return library
    }

    private mutating func add(_ newDocuments: [MaterialXDocument], replacingExisting: Bool = true) {
        documents += newDocuments
        var implementations: [(nodeDef: String, nodeGraph: String)] = []
        for document in newDocuments {
            for geomPropDef in document.root.children(tag: "geompropdef") {
                if let name = geomPropDef.name {
                    geomPropDefs[name] = geomPropDef
                }
            }
            for unitDef in document.root.children(tag: "unitdef") {
                guard let unitType = unitDef["unittype"] else { continue }
                for unit in unitDef.children(tag: "unit") {
                    if let name = unit.name, let scale = unit["scale"].flatMap(Float.init) {
                        units[unitType, default: [:]][name] = scale
                    }
                }
            }
            for typeDef in document.typeDefs {
                typeDefs[typeDef.name] = typeDef
            }
            for nodeDef in document.nodeDefs where replacingExisting || unresolvedNodeDefs[nodeDef.name] == nil {
                unresolvedNodeDefs[nodeDef.name] = nodeDef
            }
            for graph in document.nodeGraphs where replacingExisting || graphsByName[graph.name] == nil {
                graphsByName[graph.name] = graph
                if let nodeDef = graph.nodeDefName, replacingExisting || nodeGraphs[nodeDef] == nil {
                    nodeGraphs[nodeDef] = graph
                }
            }
            for implementation in document.root.children(tag: "implementation") {
                if let nodeDef = implementation["nodedef"], let graph = implementation["nodegraph"] {
                    implementations.append((nodeDef, graph))
                }
            }
        }
        for (nodeDef, graphName) in implementations {
            nodeGraphs[nodeDef] = nodeGraphs[nodeDef] ?? graphsByName[graphName]
        }
        let unresolved = unresolvedNodeDefs
        nodeDefs = unresolved.mapValues { Self.resolveInheritance($0, in: unresolved) }
        nodeDefsByCategory = Dictionary(grouping: nodeDefs.values, by: \.node)
    }

    /// The interface input `name` of `graph`: its own `<input>`, or for a functional nodegraph, its nodedef's input.
    public func interfaceInput(_ name: String, of graph: NodeGraph) -> MaterialXInput? {
        graph.input(name) ?? graph.nodeDefName.flatMap { nodeDefs[$0]?.input(name) }
    }

    static func resolveInheritance(_ nodeDef: NodeDef, in nodeDefs: [String: NodeDef], visited: Set<String> = []) -> NodeDef {
        guard let parentName = nodeDef.inherit, !visited.contains(parentName), let parent = nodeDefs[parentName] else {
            return nodeDef
        }
        let resolvedParent = resolveInheritance(parent, in: nodeDefs, visited: visited.union([nodeDef.name]))
        return nodeDef.inheriting(from: resolvedParent)
    }

    /// The nodedef for `node`: its explicit `nodedef`, else the one whose output type and input types match.
    public func nodeDef(for node: MaterialXNode, resolveType: (MaterialXInput) -> ValueType = \.type) -> NodeDef? {
        if let name = node.nodeDefName {
            return nodeDefs[name]
        }
        let candidates = (nodeDefsByCategory[node.category] ?? []).filter { nodeDef in
            let typeMatches = node.type == .multioutput ? nodeDef.outputs.count > 1 : nodeDef.outputs.first?.type == node.type
            // A requested version must match exactly. Without one, any version may match; the default is preferred.
            let versionMatches = node.version.map { $0 == nodeDef.version } ?? true
            return typeMatches && versionMatches
        }
        let matching = candidates.filter { nodeDef in
            node.inputs.allSatisfy { input in nodeDef.input(input.name)?.type == resolveType(input) }
        }
        // Prefer the default version, then the fewest inputs, then by name for stability.
        return matching.min { lhs, rhs in
            (lhs.isDefaultVersion ? 0 : 1, lhs.inputs.count, lhs.name) < (rhs.isDefaultVersion ? 0 : 1, rhs.inputs.count, rhs.name)
        }
    }
}
