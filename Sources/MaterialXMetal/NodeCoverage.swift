import MaterialX

/// How a nodedef is implemented for stitching.
public enum NodeImplementation: String, Hashable, Sendable, CaseIterable {
    /// A `[[stitchable]]` function in the node library.
    case metal
    /// A functional nodegraph whose nodes are all implemented.
    case nodeGraph
    /// Neither, or a nodegraph that uses an unimplemented node.
    case unsupported
}

public extension GraphStitcher {
    /// How every nodedef in ``standardLibrary`` is implemented. Shader, material and other non-data nodedefs are
    /// included, so ``NodeImplementation/unsupported`` also lists closures not yet available.
    func coverage() -> [String: NodeImplementation] {
        var memo: [String: NodeImplementation] = [:]
        for name in standardLibrary.nodeDefs.keys {
            _ = implementation(of: name, memo: &memo, visiting: [])
        }
        return memo
    }

    private func implementation(of nodeDefName: String, memo: inout [String: NodeImplementation], visiting: Set<String>) -> NodeImplementation {
        if let known = memo[nodeDefName] {
            return known
        }
        guard let nodeDef = standardLibrary.nodeDefs[nodeDefName], !visiting.contains(nodeDefName) else {
            return .unsupported
        }
        let base = MetalNodeLibrary.functionName(for: nodeDef)
        let functionNames = nodeDef.outputs.count > 1 ? nodeDef.outputs.map { base + "_" + $0.name } : [base]
        let result: NodeImplementation
        if nodeDef.node == "texcoord" || functionNames.allSatisfy(nodeLibrary.hasFunction) {
            result = .metal
        } else if let graph = standardLibrary.nodeGraphs[nodeDefName] {
            let nested = visiting.union([nodeDefName])
            let supported = graph.nodes.values.allSatisfy { node in
                guard let inner = standardLibrary.nodeDef(for: node) else { return false }
                return implementation(of: inner.name, memo: &memo, visiting: nested) != .unsupported
            }
            result = supported ? .nodeGraph : .unsupported
        } else {
            result = .unsupported
        }
        memo[nodeDefName] = result
        return result
    }
}
