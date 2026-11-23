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
    /// ``parameterData`` as stitched, before any changes.
    public internal(set) var initialParameterData: [SIMD4<Float>] = []
    /// The stitching graph, one line per function node with its arguments and the MaterialX node it came from.
    public internal(set) var graphDescription = ""

    public func parameter(_ name: String) -> Parameter? { parameters.first { $0.name == name } }

    /// Writes `value` into the slots of parameter `name`. Throws if there is no such parameter or the value does
    /// not have the parameter type's component count.
    public mutating func set(_ name: String, to value: Value) throws {
        guard let parameter = parameter(name) else {
            throw MaterialXError.invalidValue("no parameter '\(name)'")
        }
        guard let numbers = value.numbers, numbers.count == parameter.type.componentCount else {
            throw MaterialXError.invalidValue("\(value) for parameter '\(name)' of type \(parameter.type)")
        }
        let slots = Builder.slots(for: parameter.type, numbers: numbers)
        parameterData.replaceSubrange(parameter.slot..<(parameter.slot + parameter.slotCount), with: slots)
    }

    /// Copies the values `old`'s parameters were changed to at run time (different from what `old` was stitched
    /// with) into parameters here with the same name and type. Values edited in the file win otherwise.
    public mutating func carryParameters(from old: Self) {
        for parameter in parameters {
            guard let previous = old.parameter(parameter.name), previous.type == parameter.type, previous.slotCount == parameter.slotCount else { continue }
            let range = previous.slot..<(previous.slot + previous.slotCount)
            guard old.initialParameterData.indices.contains(range.upperBound - 1), old.parameterData[range] != old.initialParameterData[range] else { continue }
            parameterData.replaceSubrange(parameter.slot..<(parameter.slot + parameter.slotCount), with: old.parameterData[range])
        }
    }

    public mutating func set(_ name: String, to value: Float) throws {
        try set(name, to: .numbers([value]))
    }

    public mutating func set(_ name: String, to value: SIMD3<Float>) throws {
        try set(name, to: .numbers([value.x, value.y, value.z]))
    }

    public mutating func set(_ name: String, to value: SIMD4<Float>) throws {
        try set(name, to: .numbers([value.x, value.y, value.z, value.w]))
    }
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
        try stitch(plan(graph, output: outputName, functionName: functionName, documentColorSpace: documentColorSpace))
    }

    /// What ``stitch(_:output:functionName:documentColorSpace:)`` would build, without building it: the function
    /// calls, their wiring and the parameter layout. Nothing is compiled or run on the GPU.
    public func plan(_ graph: NodeGraph, output outputName: String? = nil, functionName: String, documentColorSpace: String? = nil) throws -> GraphPlan {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        guard let nodeName = output.nodeName else {
            throw MaterialXError.invalidDocument("output '\(output.name)' is not connected")
        }
        var builder = Builder(stitcher: self)
        let scope = Builder.Scope(graph: graph, prefix: "", bindings: [:], colorSpace: graph.element["colorspace"] ?? documentColorSpace)
        let value = try builder.resolve(nodeName: nodeName, output: output.output, in: scope)
        _ = try builder.call("mx_output_" + output.type.metalSuffix(), [value, .texcoord, .parameters])
        return GraphPlan(functionName: functionName, outputType: output.type, calls: builder.calls, parameters: builder.parameters, parameterData: builder.parameterData)
    }

    /// Builds `plan` with Metal function stitching, reusing a cached library when the wiring matches.
    public func stitch(_ plan: GraphPlan) throws -> StitchedGraph {
        let (library, function) = try nodeLibrary.stitchedFunction(key: plan.topologyKey) {
            try nodeLibrary.makeStitchedFunction(plan)
        }
        var stitched = StitchedGraph(library: library, function: function, functionName: plan.functionName, outputType: plan.outputType, parameters: plan.parameters, parameterData: plan.parameterData)
        stitched.graphDescription = plan.description
        stitched.initialParameterData = plan.parameterData
        return stitched
    }
}

/// A compiled nodegraph before Metal sees it: function calls in dependency order, the last being the output.
public struct GraphPlan: Hashable, Sendable, CustomStringConvertible {
    public enum Operand: Hashable, Sendable {
        /// Argument 0 of the stitched function.
        case texcoord
        /// Argument 1 of the stitched function, or the parameter pointer before it is advanced.
        case parameters
        /// The result of `calls[index]`.
        case call(Int)
    }

    public struct Call: Hashable, Sendable {
        public var function: String
        public var arguments: [Operand]
        /// The MaterialX node (scoped as `graph-node/inner-node`) this call implements, if any.
        public var origin: String?
    }

    public var functionName: String
    public var outputType: ValueType
    public var calls: [Call]
    public var parameters: [StitchedGraph.Parameter]
    public var parameterData: [SIMD4<Float>]

    /// The calls made for MaterialX node `origin`.
    public func calls(for origin: String) -> [Call] {
        calls.filter { $0.origin == origin }
    }

    /// Function name plus wiring. Graphs that differ only in constant values share it.
    var topologyKey: String {
        ([functionName] + calls.map(Self.line)).joined(separator: "\n")
    }

    public var description: String {
        let lines = calls.enumerated().map { index, call in
            "  n\(index) = \(Self.line(call))" + (call.origin.map { "  // \($0)" } ?? "")
        }
        return "\(functionName)(arg0: texcoord, arg1: parameters):\n" + lines.joined(separator: "\n")
    }

    static func line(_ call: Call) -> String {
        let arguments = call.arguments.map { operand in
            switch operand {
            case .texcoord: "arg0"
            case .parameters: "arg1"
            case let .call(index): "n\(index)"
            }
        }
        return call.function + "(" + arguments.joined(separator: ",") + ")"
    }
}

extension MetalNodeLibrary {
    func makeStitchedFunction(_ plan: GraphPlan) throws -> (MTLLibrary, MTLFunction) {
        let inputs = [
            GraphPlan.Operand.texcoord: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.texcoord.rawValue),
            .parameters: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.parameters.rawValue),
        ]
        var nodes: [MTLFunctionStitchingFunctionNode] = []
        var functions: [String: MTLFunction] = [:]
        for call in plan.calls {
            functions[call.function] = try function(named: call.function)
            let arguments: [MTLFunctionStitchingNode] = call.arguments.map { operand in
                if case let .call(index) = operand {
                    return nodes[index]
                }
                return inputs[operand] ?? MTLFunctionStitchingInputNode(argumentIndex: 0)
            }
            nodes.append(MTLFunctionStitchingFunctionNode(name: call.function, arguments: arguments, controlDependencies: []))
        }
        guard let outputNode = nodes.last else {
            throw MaterialXError.stitchingFailed("empty plan\n\(plan)")
        }
        let descriptor = MTLStitchedLibraryDescriptor()
        descriptor.functionGraphs = [MTLFunctionStitchingGraph(functionName: plan.functionName, nodes: nodes, outputNode: outputNode, attributes: [])]
        descriptor.functions = Array(functions.values)
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(stitchedDescriptor: descriptor)
        } catch {
            throw MaterialXError.stitchingFailed("\(error.localizedDescription)\n\(plan)")
        }
        guard let function = library.makeFunction(name: plan.functionName) else {
            throw MaterialXError.stitchingFailed("stitched library is missing \(plan.functionName)\n\(plan)")
        }
        return (library, function)
    }
}

private struct Builder {
    /// A graph being expanded. Functional nodegraphs are inlined in their own scope, with interface inputs bound to
    /// the calling node's arguments.
    struct Scope {
        var graph: NodeGraph
        var prefix: String
        /// Interface inputs bound to the calling node's arguments. Unbound ones become parameters.
        var bindings: [String: GraphPlan.Operand]
        /// The inherited colorspace for color values. `nil` inside functional nodegraphs, whose constants are raw.
        var colorSpace: String?
    }

    let stitcher: GraphStitcher
    var calls: [GraphPlan.Call] = []
    var resolved: [String: GraphPlan.Operand] = [:]
    var nodeArguments: [String: GraphPlan.Operand] = [:]
    var visiting: Set<String> = []
    var parameters: [StitchedGraph.Parameter] = []
    var parameterData: [SIMD4<Float>] = []
    var interfaceNodes: [String: GraphPlan.Operand] = [:]
    /// The pointer to the current parameter slot.
    var slotPointer = GraphPlan.Operand.parameters
    var previousSlotCount = 0

    init(stitcher: GraphStitcher) {
        self.stitcher = stitcher
    }

    mutating func call(_ name: String, _ arguments: [GraphPlan.Operand]) throws -> GraphPlan.Operand {
        guard stitcher.nodeLibrary.hasFunction(named: name) else {
            throw MaterialXError.unsupportedNode(name)
        }
        calls.append(.init(function: name, arguments: arguments))
        return .call(calls.count - 1)
    }

    /// Resolves `nodeName`'s upstream nodes first, deepest first, with an explicit stack. Each ``resolve`` then finds
    /// its inputs already cached, so recursion depth stays small however long a chain is.
    mutating func resolveUpstream(of nodeName: String, in scope: Scope) throws {
        var order: [(name: String, output: String?)] = []
        var visited: Set<String> = []
        var stack: [(name: String, output: String?, expanded: Bool)] = [(nodeName, nil, false)]
        while let (name, output, expanded) = stack.popLast() {
            if expanded {
                order.append((name, output))
                continue
            }
            let key = name + "." + (output ?? "")
            guard !visited.contains(key), let node = scope.graph.nodes[name] else { continue }
            visited.insert(key)
            stack.append((name, output, true))
            for input in node.inputs {
                if let upstream = input.nodeName {
                    stack.append((upstream, input.output, false))
                }
            }
        }
        // The last entry is `nodeName` itself; the caller resolves it.
        for (name, output) in order.dropLast() where scope.graph.nodes[name] != nil {
            _ = try resolve(nodeName: name, output: output, in: scope, resolvingUpstream: false)
        }
    }

    /// The stitching node for `output` of `nodeName` (the only output when `nil`).
    mutating func resolve(nodeName: String, output outputName: String? = nil, in scope: Scope, resolvingUpstream: Bool = true) throws -> GraphPlan.Operand {
        if resolvingUpstream, resolved[scope.prefix + nodeName + (outputName.map { "." + $0 } ?? "")] == nil {
            try resolveUpstream(of: nodeName, in: scope)
        }
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

        let stitchingNode: GraphPlan.Operand
        guard let nodeDef = stitcher.standardLibrary.nodeDef(for: node) else {
            throw MaterialXError.missingNodeDef(node: "\(node.name) (\(node.category), \(node.type))")
        }
        // Inputs are resolved once per node, so every output of a multi-output node shares them.
        func argument(_ definition: Input) throws -> GraphPlan.Operand {
            let argumentKey = nodeKey + "." + definition.name
            if let cached = nodeArguments[argumentKey] {
                return cached
            }
            let argument = try resolve(input: node.input(definition.name), definition: definition, owner: nodeKey, nodeColorSpace: node.element["colorspace"] ?? scope.colorSpace, in: scope)
            nodeArguments[argumentKey] = argument
            return argument
        }
        switch stitcher.resolution(of: nodeDef, output: outputName) {
        case let .function(functionName) where node.category == "texcoord":
            // Only one UV set reaches the stitched function until the shading context grows (#22).
            if let index = node.input("index")?.value?.numbers?.first, index != 0 {
                throw MaterialXError.unsupportedNode("texcoord index \(Int(index)) on '\(nodeName)'")
            }
            stitchingNode = try call(functionName, [.texcoord])
        case let .function(functionName):
            stitchingNode = try call(functionName, nodeDef.inputs.map(argument))
        case let .nodeGraph(implementation):
            // Inputs with no stitchable value type (filenames, strings) are left unbound; the graph only fails if it
            // reads one.
            var bindings: [String: GraphPlan.Operand] = [:]
            for definition in nodeDef.inputs where definition.type.isStitchable {
                bindings[definition.name] = try argument(definition)
            }
            stitchingNode = try inline(implementation, output: outputName, bindings: bindings, prefix: nodeKey + "/")
        case let .unsupported(reason):
            throw MaterialXError.unsupportedNode(reason)
        }
        if case let .call(index) = stitchingNode, calls[index].origin == nil {
            calls[index].origin = key
        }
        resolved[key] = stitchingNode
        return stitchingNode
    }

    mutating func inline(_ graph: NodeGraph, output outputName: String?, bindings: [String: GraphPlan.Operand], prefix: String) throws -> GraphPlan.Operand {
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

    mutating func resolve(input: Input?, definition: Input, owner: String, nodeColorSpace: String?, in scope: Scope) throws -> GraphPlan.Operand {
        if let upstream = input?.nodeName {
            return try resolve(nodeName: upstream, output: input?.output, in: scope)
        }
        if let interfaceName = input?.interfaceName {
            if let bound = scope.bindings[interfaceName] {
                return bound
            }
            let key = scope.prefix + interfaceName
            if let node = interfaceNodes[key] {
                return node
            }
            guard let interface = stitcher.standardLibrary.interfaceInput(interfaceName, of: scope.graph) else {
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
    mutating func convertColor(_ node: GraphPlan.Operand, type: ValueType, colorSpace: String?, key: String) throws -> GraphPlan.Operand {
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

    mutating func parameter(name: String, type: ValueType, value: Value?) throws -> GraphPlan.Operand {
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
    /// Whether values of this type can be passed between stitched functions.
    var isStitchable: Bool {
        (try? metalSuffix()) != nil
    }

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
