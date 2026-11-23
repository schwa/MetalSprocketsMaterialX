import MaterialX
import Metal

/// The `[[stitchable]]` node implementations bundled with this package.
public final class MetalNodeLibrary: @unchecked Sendable {
    public let device: MTLDevice
    public let library: MTLLibrary
    private var cache: [String: MTLFunction] = [:]

    public init(device: MTLDevice) throws {
        self.device = device
        library = try device.makeDefaultLibrary(bundle: .module)
    }

    /// The Metal function name for a nodedef: `ND_add_color3` → `mx_add_color3`.
    public static func functionName(for nodeDef: NodeDef) -> String {
        "mx_" + nodeDef.name.replacingPrefix("ND_", with: "")
    }

    public func function(named name: String) throws -> MTLFunction {
        if let function = cache[name] {
            return function
        }
        guard let function = library.makeFunction(name: name) else {
            throw MaterialXError.unsupportedNode(name)
        }
        cache[name] = function
        return function
    }
}

/// A nodegraph output compiled into one visible function with `MTLFunctionStitchingGraph`.
///
/// Signature: `T functionName(float2 texcoord, constant float4 *parameters)`, where `T` is the Metal type of
/// ``outputType``. ``parameterData`` holds the constant inputs; edit it (by ``parameters``) to change values without
/// re-stitching.
public struct StitchedGraph: @unchecked Sendable {
    public struct Parameter: Hashable, Sendable {
        /// `node.input` for node inputs, or the graph interface input's name.
        public var name: String
        public var type: ValueType
        public var slot: Int
    }

    public enum Argument: Int, CaseIterable, Sendable {
        case texcoord = 0
        case parameters = 1
    }

    public let library: MTLLibrary
    public let function: MTLFunction
    public let functionName: String
    public let outputType: ValueType
    public var parameters: [Parameter]
    public var parameterData: [SIMD4<Float>]

    public func parameter(_ name: String) -> Parameter? { parameters.first { $0.name == name } }
}

/// Compiles MaterialX nodegraphs into stitched Metal functions.
public struct GraphStitcher {
    public var nodeLibrary: MetalNodeLibrary
    public var standardLibrary: StandardLibrary

    public init(nodeLibrary: MetalNodeLibrary, standardLibrary: StandardLibrary = .shared) {
        self.nodeLibrary = nodeLibrary
        self.standardLibrary = standardLibrary
    }

    public func stitch(_ graph: NodeGraph, output outputName: String? = nil, functionName: String) throws -> StitchedGraph {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        guard let nodeName = output.nodeName else {
            throw MaterialXError.invalidDocument("output '\(output.name)' is not connected")
        }
        var builder = Builder(graph: graph, stitcher: self)
        let value = try builder.resolve(nodeName: nodeName)
        let outputNode = try builder.call("mx_output_" + output.type.metalSuffix(), [value, builder.texcoord, builder.parametersArgument])
        let stitchingGraph = MTLFunctionStitchingGraph(functionName: functionName, nodes: builder.functionNodes, outputNode: outputNode, attributes: [])
        let descriptor = MTLStitchedLibraryDescriptor()
        descriptor.functionGraphs = [stitchingGraph]
        descriptor.functions = Array(builder.functions.values)
        let library = try nodeLibrary.device.makeLibrary(stitchedDescriptor: descriptor)
        guard let function = library.makeFunction(name: functionName) else {
            throw MaterialXError.invalidDocument("stitched library is missing \(functionName)")
        }
        return StitchedGraph(library: library, function: function, functionName: functionName, outputType: output.type, parameters: builder.parameters, parameterData: builder.parameterData)
    }
}

private struct Builder {
    let graph: NodeGraph
    let stitcher: GraphStitcher
    var functions: [String: MTLFunction] = [:]
    var functionNodes: [MTLFunctionStitchingFunctionNode] = []
    var resolved: [String: MTLFunctionStitchingNode] = [:]
    var visiting: Set<String> = []
    var parameters: [StitchedGraph.Parameter] = []
    var parameterData: [SIMD4<Float>] = []
    var interfaceNodes: [String: MTLFunctionStitchingNode] = [:]
    let parametersArgument = MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.parameters.rawValue)
    /// The pointer to the current parameter slot.
    var slotPointer: MTLFunctionStitchingNode
    let texcoord = MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.texcoord.rawValue)

    init(graph: NodeGraph, stitcher: GraphStitcher) {
        self.graph = graph
        self.stitcher = stitcher
        slotPointer = parametersArgument
    }

    mutating func call(_ name: String, _ arguments: [MTLFunctionStitchingNode]) throws -> MTLFunctionStitchingFunctionNode {
        functions[name] = try stitcher.nodeLibrary.function(named: name)
        let node = MTLFunctionStitchingFunctionNode(name: name, arguments: arguments, controlDependencies: [])
        functionNodes.append(node)
        return node
    }

    mutating func resolve(nodeName: String) throws -> MTLFunctionStitchingNode {
        if let node = resolved[nodeName] {
            return node
        }
        guard !visiting.contains(nodeName) else {
            throw MaterialXError.cycle(nodeName)
        }
        guard let node = graph.nodes[nodeName] else {
            throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no node '\(nodeName)'")
        }
        visiting.insert(nodeName)
        defer { visiting.remove(nodeName) }

        let stitchingNode: MTLFunctionStitchingNode
        if node.category == "texcoord" {
            stitchingNode = try call("mx_texcoord_vector2", [texcoord])
        } else {
            guard let nodeDef = stitcher.standardLibrary.nodeDef(for: node) else {
                throw MaterialXError.missingNodeDef(node: "\(node.name) (\(node.category), \(node.type))")
            }
            let arguments = try nodeDef.inputs.map { definition in
                try resolve(input: node.input(definition.name), definition: definition, owner: node.name)
            }
            stitchingNode = try call(MetalNodeLibrary.functionName(for: nodeDef), arguments)
        }
        resolved[nodeName] = stitchingNode
        return stitchingNode
    }

    mutating func resolve(input: Input?, definition: Input, owner: String) throws -> MTLFunctionStitchingNode {
        if let upstream = input?.nodeName {
            return try resolve(nodeName: upstream)
        }
        if let interfaceName = input?.interfaceName {
            if let node = interfaceNodes[interfaceName] {
                return node
            }
            guard let interface = graph.input(interfaceName) else {
                throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no input '\(interfaceName)'")
            }
            let node = try parameter(name: interfaceName, type: interface.type, value: interface.value ?? definition.value)
            interfaceNodes[interfaceName] = node
            return node
        }
        return try parameter(name: "\(owner).\(definition.name)", type: definition.type, value: input?.value ?? definition.value)
    }

    mutating func parameter(name: String, type: ValueType, value: Value?) throws -> MTLFunctionStitchingNode {
        let reader = try "mx_parameter_" + type.metalSuffix()
        var slot = SIMD4<Float>.zero
        for (index, number) in (value?.numbers ?? []).prefix(4).enumerated() {
            slot[index] = number
        }
        // Advance lazily so the graph has no unused trailing node.
        if !parameterData.isEmpty {
            slotPointer = try call("mx_parameter_next", [slotPointer])
        }
        parameters.append(.init(name: name, type: type, slot: parameterData.count))
        parameterData.append(slot)
        return try call(reader, [slotPointer])
    }
}

private extension ValueType {
    /// The suffix of the type-generic helper functions (`mx_parameter_*`, `mx_output_*`).
    func metalSuffix() throws -> String {
        switch self {
        case .float: "float"
        case .vector2: "vector2"
        case .vector3, .color3: "vector3"
        case .vector4, .color4: "vector4"
        default: throw MaterialXError.unsupportedNode("value of type \(self)")
        }
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        hasPrefix(prefix) ? replacement + dropFirst(prefix.count) : self
    }
}
