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

/// How one output of a nodedef is stitched. The single source of these rules for ``GraphStitcher/stitch`` and
/// ``GraphStitcher/coverage()``.
public enum NodeResolution: Sendable {
    /// Call this `[[stitchable]]` function with the nodedef's inputs in order.
    case function(String)
    /// Inline this functional nodegraph, binding its interface inputs to the node's inputs.
    case nodeGraph(NodeGraph)
    case unsupported(String)
}

public extension GraphStitcher {
    /// How `output` of `nodeDef` is stitched: its Metal function (`ND_x` → `mx_x`, multi-output nodes as
    /// `mx_x_<output>`), else its functional nodegraph, else unsupported.
    func resolution(of nodeDef: NodeDef, output: String? = nil) -> NodeResolution {
        var functionName = MetalNodeLibrary.functionName(for: nodeDef)
        if nodeDef.outputs.count > 1 {
            guard let output, nodeDef.outputs.contains(where: { $0.name == output }) else {
                return .unsupported("multi-output node \(nodeDef.name) read without a valid output (\(output ?? "none"))")
            }
            functionName += "_" + output
        }
        if nodeLibrary.hasFunction(named: functionName) {
            return .function(functionName)
        }
        if let graph = standardLibrary.nodeGraphs[nodeDef.name] {
            return .nodeGraph(graph)
        }
        return .unsupported(functionName)
    }

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
        let outputs: [String?] = nodeDef.outputs.count > 1 ? nodeDef.outputs.map(\.name) : [nil]
        var result = NodeImplementation.metal
        for output in outputs {
            switch resolution(of: nodeDef, output: output) {
            case .function:
                continue
            case let .nodeGraph(graph):
                let nested = visiting.union([nodeDefName])
                let supported = graph.nodes.values.allSatisfy { node in
                    guard let inner = standardLibrary.nodeDef(for: node) else { return false }
                    return implementation(of: inner.name, memo: &memo, visiting: nested) != .unsupported
                }
                result = supported ? .nodeGraph : .unsupported
            case .unsupported:
                result = .unsupported
            }
            if result == .unsupported {
                break
            }
        }
        memo[nodeDefName] = result
        return result
    }
}
