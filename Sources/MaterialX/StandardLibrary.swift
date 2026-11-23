import Foundation

/// The MaterialX data libraries (stdlib, pbrlib, bxdf, …) bundled with this package. Version 1.39.4.
public struct StandardLibrary: Sendable {
    public var nodeDefs: [String: NodeDef]
    public var typeDefs: [ValueType: TypeDef]
    /// Unit scales by unit type and unit name, from `<unitdef>`: `units["distance"]["inch"] == 0.0254`.
    public var units: [String: [String: Float]]
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
    public private(set) var documents: [Document]

    public init(librariesURL: URL) throws {
        var documents: [Document] = []
        let enumerator = FileManager.default.enumerator(at: librariesURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "mtlx" else { continue }
            documents.append(try Document(url: url))
        }
        self.init(documents: documents)
    }

    /// A library of the nodedefs and functional nodegraphs in `documents`. Later documents override earlier ones.
    public init(documents: [Document]) {
        self.documents = documents
        var nodeDefs: [String: NodeDef] = [:]
        var typeDefs: [ValueType: TypeDef] = [:]
        var units: [String: [String: Float]] = [:]
        var nodeGraphs: [String: NodeGraph] = [:]
        var graphsByName: [String: NodeGraph] = [:]
        var implementations: [(nodeDef: String, nodeGraph: String)] = []
        for document in documents {
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
            for nodeDef in document.nodeDefs {
                nodeDefs[nodeDef.name] = nodeDef
            }
            for graph in document.nodeGraphs {
                graphsByName[graph.name] = graph
                if let nodeDef = graph.nodeDefName {
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
        self.nodeDefs = nodeDefs.mapValues { Self.resolveInheritance($0, in: nodeDefs) }
        self.nodeGraphs = nodeGraphs
        self.typeDefs = typeDefs
        self.units = units
        nodeDefsByCategory = Dictionary(grouping: self.nodeDefs.values, by: \.node)
    }

    /// This library plus the custom nodedefs and nodegraph implementations declared in `documents`.
    public func merging(_ documents: [Document]) -> Self {
        Self(documents: self.documents + documents)
    }

    static func resolveInheritance(_ nodeDef: NodeDef, in nodeDefs: [String: NodeDef], visited: Set<String> = []) -> NodeDef {
        guard let parentName = nodeDef.inherit, !visited.contains(parentName), let parent = nodeDefs[parentName] else {
            return nodeDef
        }
        let resolvedParent = resolveInheritance(parent, in: nodeDefs, visited: visited.union([nodeDef.name]))
        return nodeDef.inheriting(from: resolvedParent)
    }

    /// The nodedef for `node`: its explicit `nodedef`, else the one whose output type and input types match.
    public func nodeDef(for node: Node, resolveType: (Input) -> ValueType = \.type) -> NodeDef? {
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
