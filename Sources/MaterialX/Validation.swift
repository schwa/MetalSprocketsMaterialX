import Foundation

/// A problem found by ``Document/validate(library:)``.
public struct ValidationIssue: Hashable, Sendable, CustomStringConvertible {
    /// Path of the element, such as `NG_wood/mix1.fg`.
    public var path: String
    public var message: String

    public var description: String { "\(path): \(message)" }
}

public extension Document {
    /// Checks connections and types without compiling anything. An empty result means no problems were found.
    ///
    /// Reports dangling `nodename`, `nodegraph`, `output` and `interfacename` references, node categories with no
    /// nodedef, and connections whose upstream type differs from the input's type.
    func validate(library: StandardLibrary = .shared) -> [ValidationIssue] {
        let merged = library.merging([self])
        var issues: [ValidationIssue] = []
        for graph in nodeGraphs {
            issues += validate(nodes: graph.nodes, graph: graph, scope: graph.name, library: merged)
            for output in graph.outputs {
                guard let nodeName = output.nodeName else { continue }
                issues += checkConnection(path: "\(graph.name)/\(output.name)", type: output.type, upstream: (nodeName, output.output), nodes: graph.nodes, library: merged)
            }
        }
        let topLevel = Dictionary(nodes.map { ($0.name, $0) }) { first, _ in first }
        issues += validate(nodes: topLevel, graph: nil, scope: "", library: merged)
        return issues.sorted { $0.path < $1.path }
    }

    private func validate(nodes: [String: Node], graph: NodeGraph?, scope: String, library: StandardLibrary) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for node in nodes.values {
            let nodePath = scope.isEmpty ? node.name : "\(scope)/\(node.name)"
            if node.type != .material, library.nodeDef(for: node) == nil {
                issues.append(.init(path: nodePath, message: "no nodedef for <\(node.category)> of type \(node.type)"))
            }
            for input in node.inputs {
                let path = "\(nodePath).\(input.name)"
                if let nodeName = input.nodeName {
                    issues += checkConnection(path: path, type: input.type, upstream: (nodeName, input.output), nodes: nodes, library: library)
                }
                if let interfaceName = input.interfaceName {
                    if let graph {
                        if let interface = library.interfaceInput(interfaceName, of: graph) {
                            if interface.type != input.type {
                                issues.append(.init(path: path, message: "type \(input.type) does not match interface input '\(interfaceName)' of type \(interface.type)"))
                            }
                        } else {
                            issues.append(.init(path: path, message: "interface input '\(interfaceName)' does not exist"))
                        }
                    } else {
                        issues.append(.init(path: path, message: "interfacename used outside a nodegraph"))
                    }
                }
                if let graphName = input.nodeGraph {
                    if let target = nodeGraph(graphName) {
                        let output = input.output.flatMap(target.output) ?? (input.output == nil ? target.outputs.first : nil)
                        if let output {
                            if output.type != input.type {
                                issues.append(.init(path: path, message: "type \(input.type) does not match \(graphName).\(output.name) of type \(output.type)"))
                            }
                        } else {
                            issues.append(.init(path: path, message: "nodegraph '\(graphName)' has no output '\(input.output ?? "")'"))
                        }
                    } else {
                        issues.append(.init(path: path, message: "nodegraph '\(graphName)' does not exist"))
                    }
                }
            }
        }
        return issues
    }

    private func checkConnection(path: String, type: ValueType, upstream connection: (nodeName: String, output: String?), nodes: [String: Node], library: StandardLibrary) -> [ValidationIssue] {
        let (nodeName, output) = connection
        guard let upstream = nodes[nodeName] else {
            return [.init(path: path, message: "node '\(nodeName)' does not exist")]
        }
        let upstreamType: ValueType?
        if upstream.type == .multioutput {
            let nodeDef = library.nodeDef(for: upstream)
            guard let output else {
                return [.init(path: path, message: "multi-output node '\(nodeName)' connected without an output")]
            }
            upstreamType = nodeDef?.outputs.first { $0.name == output }?.type
            if nodeDef != nil, upstreamType == nil {
                return [.init(path: path, message: "node '\(nodeName)' has no output '\(output)'")]
            }
        } else {
            upstreamType = upstream.type
        }
        if let upstreamType, upstreamType != type {
            return [.init(path: path, message: "type \(type) does not match '\(nodeName)' of type \(upstreamType)")]
        }
        return []
    }
}
