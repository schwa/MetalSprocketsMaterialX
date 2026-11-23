import MaterialX
import MaterialXMetalShaders
import Metal
import Synchronization

/// The `[[stitchable]]` node implementations bundled with this package.
public final class MetalNodeLibrary: @unchecked Sendable {
    public let device: MTLDevice
    public let library: MTLLibrary
    private let functions = Mutex<[String: MTLFunction]>([:])
    /// Stitched functions by topology key (function name plus graph wiring). Constant values are not part of the key.
    private let stitchedFunctions = Mutex<[String: (MTLLibrary, MTLFunction)]>([:])

    public init(device: MTLDevice) throws {
        self.device = device
        library = try device.makeDefaultLibrary(bundle: .materialXMetalShaders())
        functionNames = Set(library.functionNames)
    }

    private let functionNames: Set<String>

    /// The Metal function name for a nodedef: `ND_add_color3` → `mx_add_color3`.
    public static func functionName(for nodeDef: NodeDef) -> String {
        "mx_" + nodeDef.name.replacingPrefix("ND_", with: "")
    }

    public func hasFunction(named name: String) -> Bool {
        functionNames.contains(name)
    }

    public func function(named name: String) throws -> MTLFunction {
        if let function = functions.withLock({ $0[name] }) {
            return function
        }
        guard let function = library.makeFunction(name: name) else {
            throw MaterialXError.unsupportedNode(name)
        }
        functions.withLock { $0[name] = function }
        return function
    }

    /// Number of stitched libraries built (cache misses).
    public var stitchCount: Int {
        stitchCounter.withLock { $0 }
    }

    private let stitchCounter = Mutex(0)

    func stitchedFunction(key: String, make: () throws -> (MTLLibrary, MTLFunction)) throws -> (MTLLibrary, MTLFunction) {
        if let cached = stitchedFunctions.withLock({ $0[key] }) {
            return cached
        }
        let made = try make()
        stitchCounter.withLock { $0 += 1 }
        return stitchedFunctions.withLock { cache in
            if let existing = cache[key] {
                return existing
            }
            cache[key] = made
            return made
        }
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
        /// The first slot in ``StitchedGraph/parameterData``.
        public var slot: Int
        /// 1, or the column count for matrices.
        public var slotCount: Int
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
    /// The unit each unit type converts to, such as `["distance": "meter"]`.
    public var targetUnits: [String: String] = ["distance": "meter", "angle": "degree"]

    public init(nodeLibrary: MetalNodeLibrary, standardLibrary: StandardLibrary = .shared) {
        self.nodeLibrary = nodeLibrary
        self.standardLibrary = standardLibrary
    }

    /// Stitches what a shader input is connected to: a nodegraph output (`nodegraph`/`output`) or a document-level
    /// node (`nodename`). Throws for unconnected inputs; read their ``Input/value`` instead.
    public func stitch(_ input: Input, in document: Document, functionName: String) throws -> StitchedGraph {
        if let graphName = input.nodeGraph {
            guard let graph = document.nodeGraph(graphName) else {
                throw MaterialXError.invalidDocument("input '\(input.name)' references missing nodegraph '\(graphName)'")
            }
            return try stitch(graph, output: input.output, functionName: functionName, documentColorSpace: document.colorSpace)
        }
        if let nodeName = input.nodeName {
            return try stitch(Self.documentLevelGraph(document, output: nodeName, type: input.type), functionName: functionName, documentColorSpace: document.colorSpace)
        }
        throw MaterialXError.invalidDocument("input '\(input.name)' is not connected")
    }

    /// The document's top-level nodes as one nodegraph whose single output reads `nodeName`.
    static func documentLevelGraph(_ document: Document, output nodeName: String, type: ValueType) throws -> NodeGraph {
        let skipped: Set<ValueType> = [.surfaceshader, .material]
        var children = document.nodes.filter { !skipped.contains($0.type) }.map(\.element)
        children.append(Element(tag: "output", attributes: ["name": "out", "type": type.rawValue, "nodename": nodeName]))
        return try NodeGraph(Element(tag: "nodegraph", attributes: ["name": "__document"], children: children))
    }

    /// Compiles `graph`'s output. Color constants tagged with a `colorspace` (on the input, its node, the graph, or
    /// `documentColorSpace`) are converted to lin_rec709; values with a `unit` are converted to ``targetUnits``.
    public func stitch(_ graph: NodeGraph, output outputName: String? = nil, functionName: String, documentColorSpace: String? = nil) throws -> StitchedGraph {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        guard let nodeName = output.nodeName else {
            throw MaterialXError.invalidDocument("output '\(output.name)' is not connected")
        }
        var builder = Builder(stitcher: self)
        let scope = Builder.Scope(graph: graph, prefix: "", bindings: nil, colorSpace: graph.element["colorspace"] ?? documentColorSpace)
        let value = try builder.resolve(nodeName: nodeName, output: output.output, in: scope)
        let outputNode = try builder.call("mx_output_" + output.type.metalSuffix(), [value, builder.texcoord, builder.parametersArgument])
        let key = functionName + "\n" + builder.topology.joined(separator: "\n")
        let (library, function) = try nodeLibrary.stitchedFunction(key: key) {
            let stitchingGraph = MTLFunctionStitchingGraph(functionName: functionName, nodes: builder.functionNodes, outputNode: outputNode, attributes: [])
            let descriptor = MTLStitchedLibraryDescriptor()
            descriptor.functionGraphs = [stitchingGraph]
            descriptor.functions = Array(builder.functions.values)
            let library = try nodeLibrary.device.makeLibrary(stitchedDescriptor: descriptor)
            guard let function = library.makeFunction(name: functionName) else {
                throw MaterialXError.invalidDocument("stitched library is missing \(functionName)")
            }
            return (library, function)
        }
        return StitchedGraph(library: library, function: function, functionName: functionName, outputType: output.type, parameters: builder.parameters, parameterData: builder.parameterData)
    }
}

private struct Builder {
    /// A graph being expanded. Functional nodegraphs are inlined in their own scope, with interface inputs bound to
    /// the calling node's arguments.
    struct Scope {
        var graph: NodeGraph
        var prefix: String
        var bindings: [String: MTLFunctionStitchingNode]?
        /// The inherited colorspace for color values. `nil` inside functional nodegraphs, whose constants are raw.
        var colorSpace: String?
    }

    let stitcher: GraphStitcher
    var functions: [String: MTLFunction] = [:]
    var functionNodes: [MTLFunctionStitchingFunctionNode] = []
    var resolved: [String: MTLFunctionStitchingNode] = [:]
    var nodeArguments: [String: [MTLFunctionStitchingNode]] = [:]
    var visiting: Set<String> = []
    var parameters: [StitchedGraph.Parameter] = []
    var parameterData: [SIMD4<Float>] = []
    var interfaceNodes: [String: MTLFunctionStitchingNode] = [:]
    let parametersArgument = MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.parameters.rawValue)
    /// The pointer to the current parameter slot.
    var slotPointer: MTLFunctionStitchingNode
    var previousSlotCount = 0
    let texcoord = MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.texcoord.rawValue)

    init(stitcher: GraphStitcher) {
        self.stitcher = stitcher
        slotPointer = parametersArgument
    }

    /// One line per function node: its name and the wiring of its arguments. Identifies the stitched function.
    var topology: [String] = []
    var nodeIndices: [ObjectIdentifier: Int] = [:]

    func topologyName(_ node: MTLFunctionStitchingNode) -> String {
        if let input = node as? MTLFunctionStitchingInputNode {
            return "arg\(input.argumentIndex)"
        }
        return "n\(nodeIndices[ObjectIdentifier(node)] ?? -1)"
    }

    mutating func call(_ name: String, _ arguments: [MTLFunctionStitchingNode]) throws -> MTLFunctionStitchingFunctionNode {
        functions[name] = try stitcher.nodeLibrary.function(named: name)
        let node = MTLFunctionStitchingFunctionNode(name: name, arguments: arguments, controlDependencies: [])
        topology.append(name + "(" + arguments.map(topologyName).joined(separator: ",") + ")")
        nodeIndices[ObjectIdentifier(node)] = functionNodes.count
        functionNodes.append(node)
        return node
    }

    /// The stitching node for `output` of `nodeName` (the only output when `nil`).
    mutating func resolve(nodeName: String, output outputName: String? = nil, in scope: Scope) throws -> MTLFunctionStitchingNode {
        let nodeKey = scope.prefix + nodeName
        let key = nodeKey + (outputName.map { "." + $0 } ?? "")
        if let node = resolved[key] {
            return node
        }
        guard !visiting.contains(key) else {
            throw MaterialXError.cycle(key)
        }
        guard let node = scope.graph.nodes[nodeName] else {
            throw MaterialXError.invalidDocument("nodegraph '\(scope.graph.name)' has no node '\(nodeName)'")
        }
        visiting.insert(key)
        defer { visiting.remove(key) }

        let stitchingNode: MTLFunctionStitchingNode
        if node.category == "texcoord" {
            // Only one UV set reaches the stitched function until the shading context grows (#22).
            if let index = node.input("index")?.value?.numbers?.first, index != 0 {
                throw MaterialXError.unsupportedNode("texcoord index \(Int(index)) on '\(nodeName)'")
            }
            stitchingNode = try call("mx_texcoord_vector2", [texcoord])
        } else {
            guard let nodeDef = stitcher.standardLibrary.nodeDef(for: node) else {
                throw MaterialXError.missingNodeDef(node: "\(node.name) (\(node.category), \(node.type))")
            }
            // Inputs are resolved once per node, so every output of a multi-output node shares them.
            let arguments: [MTLFunctionStitchingNode]
            if let cached = nodeArguments[nodeKey] {
                arguments = cached
            } else {
                arguments = try nodeDef.inputs.map { definition in
                    try resolve(input: node.input(definition.name), definition: definition, owner: nodeKey, nodeColorSpace: node.element["colorspace"] ?? scope.colorSpace, in: scope)
                }
                nodeArguments[nodeKey] = arguments
            }
            var functionName = MetalNodeLibrary.functionName(for: nodeDef)
            if nodeDef.outputs.count > 1 {
                guard let outputName, nodeDef.outputs.contains(where: { $0.name == outputName }) else {
                    throw MaterialXError.invalidDocument("multi-output node '\(nodeName)' read without a valid output (\(outputName ?? "none"))")
                }
                functionName += "_" + outputName
            }
            if stitcher.nodeLibrary.hasFunction(named: functionName) {
                stitchingNode = try call(functionName, arguments)
            } else if let implementation = stitcher.standardLibrary.nodeGraphs[nodeDef.name] {
                let bindings = Dictionary(zip(nodeDef.inputs.map(\.name), arguments)) { first, _ in first }
                stitchingNode = try inline(implementation, output: outputName, bindings: bindings, prefix: nodeKey + "/")
            } else {
                throw MaterialXError.unsupportedNode(functionName)
            }
        }
        resolved[key] = stitchingNode
        return stitchingNode
    }

    mutating func inline(_ graph: NodeGraph, output outputName: String?, bindings: [String: MTLFunctionStitchingNode], prefix: String) throws -> MTLFunctionStitchingNode {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("functional nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        if let nodeName = output.nodeName {
            return try resolve(nodeName: nodeName, output: output.output, in: Scope(graph: graph, prefix: prefix, bindings: bindings, colorSpace: nil))
        }
        // A pass-through graph: the output reads an interface input directly.
        if let interfaceName = output.element["interfacename"], let bound = bindings[interfaceName] {
            return bound
        }
        throw MaterialXError.invalidDocument("functional nodegraph '\(graph.name)' has no connected output")
    }

    mutating func resolve(input: Input?, definition: Input, owner: String, nodeColorSpace: String?, in scope: Scope) throws -> MTLFunctionStitchingNode {
        if let upstream = input?.nodeName {
            return try resolve(nodeName: upstream, output: input?.output, in: scope)
        }
        if let interfaceName = input?.interfaceName {
            if let bound = scope.bindings?[interfaceName] {
                return bound
            }
            let key = scope.prefix + interfaceName
            if let node = interfaceNodes[key] {
                return node
            }
            guard let interface = scope.graph.input(interfaceName) else {
                throw MaterialXError.invalidDocument("nodegraph '\(scope.graph.name)' has no input '\(interfaceName)'")
            }
            var node = try parameter(name: key, type: interface.type, value: converted(interface.value ?? definition.value, input: interface, definition: definition))
            node = try convertColor(node, type: interface.type, colorSpace: interface.element["colorspace"] ?? scope.colorSpace, key: key)
            interfaceNodes[key] = node
            return node
        }
        let name = "\(owner).\(definition.name)"
        let value = input.map { converted($0.value ?? definition.value, input: $0, definition: definition) } ?? definition.value
        let node = try parameter(name: name, type: definition.type, value: value)
        // Only values the document sets carry its colorspace; nodedef defaults are already linear.
        guard input?.value != nil else { return node }
        return try convertColor(node, type: definition.type, colorSpace: input?.element["colorspace"] ?? nodeColorSpace, key: name)
    }

    /// `node` converted from `colorSpace` to lin_rec709 with the cmlib nodegraph, for color3/color4 values.
    mutating func convertColor(_ node: MTLFunctionStitchingNode, type: ValueType, colorSpace: String?, key: String) throws -> MTLFunctionStitchingNode {
        guard type == .color3 || type == .color4, let colorSpace, colorSpace != "lin_rec709", colorSpace != "none" else {
            return node
        }
        let nodeDefName = "ND_\(colorSpace)_to_lin_rec709_\(type)"
        guard let graph = stitcher.standardLibrary.nodeGraphs[nodeDefName] else {
            throw MaterialXError.unsupportedNode("colorspace '\(colorSpace)' (\(nodeDefName))")
        }
        return try inline(graph, output: nil, bindings: ["in": node], prefix: key + "#colorspace/")
    }

    /// `value` converted from the input's `unit` to the stitcher's target unit of the same unit type.
    func converted(_ value: Value?, input: Input, definition: Input) -> Value? {
        guard let unit = input.element["unit"], let numbers = value?.numbers,
              let unitType = input.element["unittype"] ?? definition.element["unittype"],
              let scales = stitcher.standardLibrary.units[unitType], let from = scales[unit],
              let target = stitcher.targetUnits[unitType], let to = scales[target]
        else { return value }
        return .numbers(numbers.map { $0 * from / to })
    }

    mutating func parameter(name: String, type: ValueType, value: Value?) throws -> MTLFunctionStitchingNode {
        let reader = try "mx_parameter_" + type.metalSuffix()
        let slots = Self.slots(for: type, numbers: value?.numbers ?? [])
        // Advance lazily, past the previous parameter's slots, so the graph has no unused trailing node.
        for _ in 0..<previousSlotCount {
            slotPointer = try call("mx_parameter_next", [slotPointer])
        }
        previousSlotCount = slots.count
        parameters.append(.init(name: name, type: type, slot: parameterData.count, slotCount: slots.count))
        parameterData += slots
        return try call(reader, [slotPointer])
    }

    /// The float4 slots holding a value: one for scalars and vectors, one per column (3 or 4 floats) for matrices.
    static func slots(for type: ValueType, numbers: [Float]) -> [SIMD4<Float>] {
        let width = switch type {
        case .matrix33: 3
        case .matrix44: 4
        default: 4
        }
        let count = type == .matrix33 ? 3 : type == .matrix44 ? 4 : 1
        return (0..<count).map { column in
            var slot = SIMD4<Float>.zero
            for index in 0..<width where column * width + index < numbers.count {
                slot[index] = numbers[column * width + index]
            }
            return slot
        }
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
        case .integer: "integer"
        case .boolean: "boolean"
        case .matrix33: "matrix33"
        case .matrix44: "matrix44"
        default: throw MaterialXError.unsupportedNode("value of type \(self)")
        }
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        hasPrefix(prefix) ? replacement + dropFirst(prefix.count) : self
    }
}
