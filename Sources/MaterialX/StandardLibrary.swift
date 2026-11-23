import Foundation

/// The MaterialX data libraries (stdlib, pbrlib, bxdf, …) bundled with this package. Version 1.39.4.
public struct StandardLibrary: Sendable {
    public var nodeDefs: [String: NodeDef]
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

    public init(librariesURL: URL) throws {
        var nodeDefs: [String: NodeDef] = [:]
        var nodeGraphs: [String: NodeGraph] = [:]
        var graphsByName: [String: NodeGraph] = [:]
        var implementations: [(nodeDef: String, nodeGraph: String)] = []
        let enumerator = FileManager.default.enumerator(at: librariesURL, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "mtlx" else { continue }
            let document = try Document(url: url)
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
        nodeDefsByCategory = Dictionary(grouping: self.nodeDefs.values, by: \.node)
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
        let candidates = (nodeDefsByCategory[node.category] ?? []).filter { $0.outputs.first?.type == node.type }
        let matching = candidates.filter { nodeDef in
            node.inputs.allSatisfy { input in nodeDef.input(input.name)?.type == resolveType(input) }
        }
        // Prefer the nodedef with the fewest inputs the node did not set, then by name for stability.
        return matching.min { lhs, rhs in
            (lhs.inputs.count, lhs.name) < (rhs.inputs.count, rhs.name)
        }
    }
}
