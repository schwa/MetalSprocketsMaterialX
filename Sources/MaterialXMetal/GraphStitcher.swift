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
/// Signature: `T functionName(thread const MXShadingContext &context, constant float4 *parameters,
/// constant MXTexture *textures)` (see `MXShadingContext.h`), where `T` is the Metal type of
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
        case context = 0
        case parameters = 1
        case textures = 2
        /// Surface functions only: the `MXSurfaceInputs` they fill.
        case surface = 3
    }

    public let library: MTLLibrary
    public let function: MTLFunction
    public let functionName: String
    public let outputType: ValueType
    public var parameters: [Parameter]
    public var parameterData: [SIMD4<Float>]
    /// ``parameterData`` as stitched, before any changes.
    public internal(set) var initialParameterData: [SIMD4<Float>] = []
    /// The textures image nodes read, by slot of the `textures` argument.
    public internal(set) var textures: [TextureBinding] = []
    /// The stitching graph, one line per function node with its arguments and the MaterialX node it came from.
    public internal(set) var graphDescription = ""

    public func parameter(_ name: String) -> Parameter? { parameters.first { $0.name == name } }

    /// Writes `value` into the slots of parameter `name`. Throws if there is no such parameter or the value does
    /// not have the parameter type's component count.
    public mutating func set(_ name: String, to value: MaterialXValue) throws {
        guard let parameter = parameter(name) else {
            throw MaterialXError.invalidValue("no parameter '\(name)'")
        }
        guard let numbers = value.numbers, numbers.count == parameter.type.componentCount else {
            throw MaterialXError.invalidValue("\(value) for parameter '\(name)' of type \(parameter.type)")
        }
        let slots = ParameterLayout.encode(numbers, as: parameter.type)
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
    /// Evaluate constant-only subgraphs once when stitching. Off by default: folded constants can no longer be edited
    /// by name.
    public var foldConstants = false

    public init(nodeLibrary: MetalNodeLibrary, standardLibrary: StandardLibrary = .shared) {
        self.nodeLibrary = nodeLibrary
        self.standardLibrary = standardLibrary
    }

    /// Stitches what a shader input is connected to: a nodegraph output (`nodegraph`/`output`) or a document-level
    /// node (`nodename`). Throws for unconnected inputs; read their ``MaterialXInput/value`` instead.
    public func stitch(_ input: MaterialXInput, in document: MaterialXDocument, functionName: String) throws -> StitchedGraph {
        if let graphName = input.nodeGraph {
            guard let graph = document.nodeGraph(graphName) else {
                throw MaterialXError.invalidDocument("input '\(input.name)' references missing nodegraph '\(graphName)'")
            }
            return try stitch(graph, output: input.output, functionName: functionName, documentColorSpace: document.colorSpace, documentFilePrefix: document.root["fileprefix"])
        }
        if let nodeName = input.nodeName {
            return try stitch(Self.documentLevelGraph(document, output: nodeName, outputName: input.output, type: input.type), functionName: functionName, documentColorSpace: document.colorSpace, documentFilePrefix: document.root["fileprefix"])
        }
        throw MaterialXError.invalidDocument("input '\(input.name)' is not connected")
    }

    /// The document's top-level nodes as one nodegraph whose single output reads `nodeName`.
    static func documentLevelGraph(_ document: MaterialXDocument, output nodeName: String, outputName: String? = nil, type: ValueType, extraNodes: [MaterialXElement] = []) throws -> NodeGraph {
        let skipped: Set<ValueType> = [.surfaceshader, .material]
        var children = document.nodes.filter { !skipped.contains($0.type) }.map(\.element) + extraNodes
        var attributes = ["name": "out", "type": type.rawValue, "nodename": nodeName]
        attributes["output"] = outputName
        children.append(MaterialXElement(tag: "output", attributes: attributes))
        return try NodeGraph(MaterialXElement(tag: "nodegraph", attributes: ["name": "__document"], children: children))
    }

    /// Compiles `graph`'s output. Color constants tagged with a `colorspace` (on the input, its node, the graph, or
    /// `documentColorSpace`) are converted to lin_rec709; values with a `unit` are converted to ``targetUnits``.
    public func stitch(_ graph: NodeGraph, output outputName: String? = nil, functionName: String, documentColorSpace: String? = nil, documentFilePrefix: String? = nil) throws -> StitchedGraph {
        try stitch(plan(graph, output: outputName, functionName: functionName, documentColorSpace: documentColorSpace, documentFilePrefix: documentFilePrefix))
    }

    /// What ``stitch(_:output:functionName:documentColorSpace:)`` would build, without building it: the function
    /// calls, their wiring and the parameter layout. Nothing is compiled or run on the GPU.
    public func plan(_ graph: NodeGraph, output outputName: String? = nil, functionName: String, documentColorSpace: String? = nil, documentFilePrefix: String? = nil) throws -> GraphPlan {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        guard let nodeName = output.nodeName else {
            throw MaterialXError.invalidDocument("output '\(output.name)' is not connected")
        }
        var builder = Builder(stitcher: self)
        let scope = Builder.Scope(graph: graph, prefix: "", bindings: [:], colorSpace: graph.element["colorspace"] ?? documentColorSpace, strings: [:], filePrefix: graph.element["fileprefix"] ?? documentFilePrefix)
        let value = try builder.resolve(nodeName: nodeName, output: output.output, in: scope)
        _ = try builder.call("mx_output_" + output.type.metalSuffix(), [value, .context, .parameters, .textures])
        return GraphPlan(functionName: functionName, outputType: output.type, calls: builder.calls, parameters: builder.parameters, parameterData: builder.parameterData, textures: builder.textures)
    }

    /// Builds `plan` with Metal function stitching, reusing a cached library when the wiring matches. With
    /// ``foldConstants``, constant-only subgraphs are evaluated first (``foldingConstants(_:)``).
    public func stitch(_ plan: GraphPlan) throws -> StitchedGraph {
        let plan = foldConstants ? try foldingConstants(plan) : plan
        let (library, function) = try nodeLibrary.stitchedFunction(key: plan.topologyKey) {
            try nodeLibrary.makeStitchedFunction(plan)
        }
        var stitched = StitchedGraph(library: library, function: function, functionName: plan.functionName, outputType: plan.outputType, parameters: plan.parameters, parameterData: plan.parameterData)
        stitched.graphDescription = plan.description
        stitched.initialParameterData = plan.parameterData
        stitched.textures = plan.textures
        return stitched
    }
}

/// A compiled nodegraph before Metal sees it: function calls in dependency order, the last being the output.
public struct GraphPlan: Hashable, Sendable, CustomStringConvertible {
    public enum Operand: Hashable, Sendable {
        /// Argument 0 of the stitched function: the `MXShadingContext`.
        case context
        /// Argument 1 of the stitched function, or the parameter pointer before it is advanced.
        case parameters
        /// Argument 2 of the stitched function: the `MXTexture` table.
        case textures
        /// Argument 3 of a surface function: the `MXSurfaceInputs` pointer.
        case surface
        /// The result of `calls[index]`.
        case call(Int)
    }

    public struct Call: Hashable, Sendable {
        public var function: String
        public var arguments: [Operand]
        /// The MaterialX node (scoped as `graph-node/inner-node`) this call implements, if any.
        public var origin: String?
        /// The MaterialX type of the call's result, when it is a value (not a parameter pointer or surface).
        public var valueType: ValueType?
    }

    public var functionName: String
    public var outputType: ValueType
    public var calls: [Call]
    public var parameters: [StitchedGraph.Parameter]
    public var parameterData: [SIMD4<Float>]
    /// The textures image nodes read, by slot.
    public var textures: [TextureBinding] = []

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
        let surface = outputType == .surfaceshader ? ", arg3: surface" : ""
        return "\(functionName)(arg0: context, arg1: parameters, arg2: textures\(surface)):\n" + lines.joined(separator: "\n")
    }

    static func line(_ call: Call) -> String {
        let arguments = call.arguments.map { operand in
            switch operand {
            case .context: "arg0"
            case .parameters: "arg1"
            case .textures: "arg2"
            case .surface: "arg3"
            case let .call(index): "n\(index)"
            }
        }
        return call.function + "(" + arguments.joined(separator: ",") + ")"
    }
}

extension MetalNodeLibrary {
    func makeStitchedFunction(_ plan: GraphPlan) throws -> (MTLLibrary, MTLFunction) {
        let inputs = [
            GraphPlan.Operand.context: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.context.rawValue),
            .parameters: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.parameters.rawValue),
            .textures: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.textures.rawValue),
            .surface: MTLFunctionStitchingInputNode(argumentIndex: StitchedGraph.Argument.surface.rawValue),
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

struct Builder {
    /// A graph being expanded. Functional nodegraphs are inlined in their own scope, with interface inputs bound to
    /// the calling node's arguments.
    struct Scope {
        var graph: NodeGraph
        var prefix: String
        /// Interface inputs bound to the calling node's arguments. Unbound ones become parameters.
        var bindings: [String: GraphPlan.Operand]
        /// The inherited colorspace for color values. `nil` inside functional nodegraphs, whose constants are raw.
        var colorSpace: String?
        /// String and filename interface inputs bound to the calling node's values (they cannot be stitched).
        var strings: [String: MaterialXValue]
        /// The inherited `fileprefix`.
        var filePrefix: String?
    }

    var textures: [TextureBinding] = []
    /// The document's nodegraphs, for inputs with `nodegraph=` (document-level nodes and shaders).
    var documentGraphs: [String: NodeGraph] = [:]
    var documentColorSpace: String?
    var documentFilePrefix: String?

    /// Output `outputName` (or the first) of document nodegraph `name`, each graph in its own scope.
    mutating func resolve(nodeGraph name: String, output outputName: String?) throws -> GraphPlan.Operand {
        guard let graph = documentGraphs[name], let output = outputName.flatMap(graph.output) ?? graph.outputs.first, let nodeName = output.nodeName else {
            throw MaterialXError.invalidDocument("missing nodegraph output \(name).\(outputName ?? "")")
        }
        let scope = Scope(graph: graph, prefix: graph.name + "/", bindings: [:], colorSpace: graph.element["colorspace"] ?? documentColorSpace, strings: [:], filePrefix: graph.element["fileprefix"] ?? documentFilePrefix)
        return try resolve(nodeName: nodeName, output: output.output, in: scope)
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

    static func input(_ name: String, of nodeDef: NodeDef) throws -> MaterialXInput {
        guard let input = nodeDef.input(name) else {
            throw MaterialXError.invalidDocument("\(nodeDef.name) has no input '\(name)'")
        }
        return input
    }

    /// A string or filename input's value: set on the node, bound through the graph interface, or the default.
    func stringValue(_ name: String, of node: MaterialXNode, nodeDef: NodeDef, in scope: Scope) -> String? {
        let input = node.input(name)
        if case let .string(value)? = input?.value {
            return value
        }
        if let interfaceName = input?.interfaceName {
            if case let .string(value)? = scope.strings[interfaceName] {
                return value
            }
            if case let .string(value)? = stitcher.standardLibrary.interfaceInput(interfaceName, of: scope.graph)?.value {
                return value
            }
        }
        if case let .string(value)? = nodeDef.input(name)?.value {
            return value
        }
        return nil
    }

    /// The nodedef inputs a Metal function takes: stitchable values, plus `space`, which becomes an integer. Other
    /// string inputs, such as geompropvalue's `geomprop` name, are resolved by the stitcher and not passed.
    static func functionInputs(_ nodeDef: NodeDef) -> [MaterialXInput] {
        nodeDef.inputs.filter { $0.type.isStitchable || isSpaceInput($0) }
    }

    /// `space`, `fromspace` and `tospace` string inputs, passed to Metal as integers (``spaceCode(_:)``).
    static func isSpaceInput(_ input: MaterialXInput) -> Bool {
        input.type == .string && ["space", "fromspace", "tospace"].contains(input.name)
    }

    /// The integer the Metal geometry functions take for a `space` input: 0 object (and model), 1 world.
    static func spaceCode(_ value: MaterialXValue?) throws -> Int {
        guard case let .string(space) = value ?? .string("object") else {
            throw MaterialXError.invalidValue("space \(String(describing: value))")
        }
        switch space {
        case "object", "model": return 0
        case "world": return 1
        case "": return -1
        default: throw MaterialXError.invalidValue("space '\(space)'")
        }
    }

    /// Node categories whose functions take the texture table before the nodedef's inputs.
    static let textureCategories: Set<String> = ["texture_slot"]

    /// Node categories whose functions take the shading context before the nodedef's inputs.
    static let contextCategories: Set<String> = ["texcoord", "position", "normal", "tangent", "bitangent", "geomcolor", "viewdirection", "time", "frame", "realitykit_viewdirection", "transformpoint", "transformvector", "transformnormal"]

    /// `swizzle`'s `channels` string as the vector4 of indices `mx_swizzle_*` takes: 0–3 per component letter
    /// (`xyzw` or `rgba`), -1 for `0`, -2 for `1`.
    static func swizzleIndices(_ channels: String) throws -> MaterialXValue {
        var indices = [Float](repeating: -1, count: 4)
        for (position, character) in channels.prefix(4).enumerated() {
            indices[position] = switch character {
            case "x", "r": 0
            case "y", "g": 1
            case "z", "b": 2
            case "w", "a": 3
            case "0": -1
            case "1": -2
            default: throw MaterialXError.invalidValue("swizzle channel '\(character)' in '\(channels)'")
            }
        }
        return .numbers(indices)
    }

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
        func argument(_ definition: MaterialXInput) throws -> GraphPlan.Operand {
            let argumentKey = nodeKey + "." + definition.name
            if let cached = nodeArguments[argumentKey] {
                return cached
            }
            if Self.isSpaceInput(definition) {
                let argument = try parameter(name: argumentKey, type: .integer, value: .integer(Self.spaceCode(node.input(definition.name)?.value ?? definition.value)))
                nodeArguments[argumentKey] = argument
                return argument
            }
            let argument = try resolve(input: node.input(definition.name), definition: definition, owner: nodeKey, nodeColorSpace: node.element["colorspace"] ?? scope.colorSpace, in: scope)
            nodeArguments[argumentKey] = argument
            return argument
        }
        switch stitcher.resolution(of: nodeDef, output: outputName) {
        case let .function(functionName) where node.category == "texcoord":
            // MXShadingContext carries UV sets 0 and 1.
            if let index = node.input("index")?.value?.numbers?.first, !(0...1).contains(index) {
                throw MaterialXError.unsupportedNode("texcoord index \(Int(index)) on '\(nodeName)'; only UV sets 0 and 1 are available")
            }
            stitchingNode = try call(functionName, [.context] + nodeDef.inputs.map(argument))
        case let .function(functionName) where node.category == "swizzle":
            let channels = stringValue("channels", of: node, nodeDef: nodeDef, in: scope) ?? ""
            let indices = try parameter(name: nodeKey + ".channels", type: .vector4, value: Self.swizzleIndices(channels))
            stitchingNode = try call(functionName, [try argument(try Self.input("in", of: nodeDef)), indices])
        case let .function(functionName) where node.category == "image":
            let file = stringValue("file", of: node, nodeDef: nodeDef, in: scope) ?? ""
            let filePrefix = node.input("file")?.element["fileprefix"] ?? node.element["fileprefix"] ?? scope.filePrefix ?? ""
            let slot = textures.count
            textures.append(TextureBinding(
                node: nodeKey,
                file: file.isEmpty ? "" : filePrefix + file,
                slot: slot,
                uAddressMode: stringValue("uaddressmode", of: node, nodeDef: nodeDef, in: scope) ?? "periodic",
                vAddressMode: stringValue("vaddressmode", of: node, nodeDef: nodeDef, in: scope) ?? "periodic",
                filterType: stringValue("filtertype", of: node, nodeDef: nodeDef, in: scope) ?? "linear"
            ))
            let slotParameter = try parameter(name: nodeKey + ".slot", type: .integer, value: .integer(slot))
            let fallback = try argument(try Self.input("default", of: nodeDef))
            let texcoord = try argument(try Self.input("texcoord", of: nodeDef))
            stitchingNode = try call(functionName, [.textures, slotParameter, fallback, texcoord])
        case let .function(functionName) where Self.textureCategories.contains(node.category):
            stitchingNode = try call(functionName, [.textures] + Self.functionInputs(nodeDef).map(argument))
        case let .function(functionName) where Self.contextCategories.contains(node.category):
            stitchingNode = try call(functionName, [.context] + Self.functionInputs(nodeDef).map(argument))
        case let .function(functionName):
            stitchingNode = try call(functionName, Self.functionInputs(nodeDef).map(argument))
        case let .nodeGraph(implementation):
            // Inputs with no stitchable value type (filenames, strings) are left unbound; the graph only fails if it
            // reads one.
            var bindings: [String: GraphPlan.Operand] = [:]
            var strings: [String: MaterialXValue] = [:]
            for definition in nodeDef.inputs {
                if definition.type.isStitchable {
                    bindings[definition.name] = try argument(definition)
                } else if let value = stringValue(definition.name, of: node, nodeDef: nodeDef, in: scope) {
                    strings[definition.name] = .string(value)
                }
            }
            let filePrefix = node.element["fileprefix"] ?? scope.filePrefix
            stitchingNode = try inline(implementation, output: outputName, bindings: bindings, strings: strings, filePrefix: filePrefix, prefix: nodeKey + "/")
        case let .unsupported(reason):
            throw MaterialXError.unsupportedNode(reason)
        }
        if case let .call(index) = stitchingNode {
            if calls[index].origin == nil {
                calls[index].origin = key
            }
            if calls[index].valueType == nil {
                let outputType = node.type == .multioutput ? nodeDef.outputs.first { $0.name == outputName }?.type : node.type
                calls[index].valueType = outputType
            }
        }
        resolved[key] = stitchingNode
        return stitchingNode
    }

    mutating func inline(_ graph: NodeGraph, output outputName: String?, bindings: [String: GraphPlan.Operand], strings: [String: MaterialXValue] = [:], filePrefix: String? = nil, prefix: String) throws -> GraphPlan.Operand {
        guard let output = outputName.flatMap(graph.output) ?? graph.outputs.first else {
            throw MaterialXError.invalidDocument("functional nodegraph '\(graph.name)' has no output \(outputName ?? "")")
        }
        if let nodeName = output.nodeName {
            return try resolve(nodeName: nodeName, output: output.output, in: Scope(graph: graph, prefix: prefix, bindings: bindings, colorSpace: nil, strings: strings, filePrefix: filePrefix))
        }
        // A pass-through graph: the output reads an interface input directly.
        if let interfaceName = output.element["interfacename"], let bound = bindings[interfaceName] {
            return bound
        }
        throw MaterialXError.invalidDocument("functional nodegraph '\(graph.name)' has no connected output")
    }

    mutating func resolve(input: MaterialXInput?, definition: MaterialXInput, owner: String, nodeColorSpace: String?, in scope: Scope) throws -> GraphPlan.Operand {
        if let upstream = input?.nodeName {
            return try resolve(nodeName: upstream, output: input?.output, in: scope)
        }
        if let graphName = input?.nodeGraph {
            return try resolve(nodeGraph: graphName, output: input?.output)
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
        // An unset input with a defaultgeomprop (UV0, Nworld, …) reads the geometry instead of a constant.
        if input?.value == nil, let geomProp = definition.element["defaultgeomprop"] {
            return try geometry(geomProp, key: name)
        }
        let value = input.map { converted($0.value ?? definition.value, input: $0, definition: definition) } ?? definition.value
        let node = try parameter(name: name, type: definition.type, value: value)
        // Only values the document sets carry its colorspace; nodedef defaults are already linear.
        guard input?.value != nil else { return node }
        return try convertColor(node, type: definition.type, colorSpace: input?.element["colorspace"] ?? nodeColorSpace, key: name)
    }

    /// A call reading geompropdef `name` (such as `UV0` or `Nworld`) from the shading context.
    mutating func geometry(_ name: String, key: String) throws -> GraphPlan.Operand {
        guard let definition = stitcher.standardLibrary.geomPropDefs[name], let category = definition["geomprop"], let type = definition["type"] else {
            throw MaterialXError.unsupportedNode("defaultgeomprop '\(name)'")
        }
        var arguments: [GraphPlan.Operand] = [.context]
        if let space = definition["space"] {
            arguments.append(try parameter(name: key + ".space", type: .integer, value: .integer(Self.spaceCode(.string(space)))))
        }
        // Only these geometry functions take an index after the space (see StandardLibrary.metal).
        if ["texcoord", "tangent", "bitangent", "geomcolor"].contains(category) {
            arguments.append(try parameter(name: key + ".index", type: .integer, value: .integer(Int(definition["index"] ?? "0") ?? 0)))
        }
        let call = try call("mx_\(category)_\(type)", arguments)
        if case let .call(index) = call {
            calls[index].origin = key + "#" + name
            calls[index].valueType = ValueType(rawValue: type)
        }
        return call
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
    func converted(_ value: MaterialXValue?, input: MaterialXInput, definition: MaterialXInput) -> MaterialXValue? {
        guard let unit = input.element["unit"], let numbers = value?.numbers,
              let unitType = input.element["unittype"] ?? definition.element["unittype"],
              let scales = stitcher.standardLibrary.units[unitType], let from = scales[unit],
              let target = stitcher.targetUnits[unitType], let to = scales[target]
        else { return value }
        return .numbers(numbers.map { $0 * from / to })
    }

    mutating func parameter(name: String, type: ValueType, value: MaterialXValue?) throws -> GraphPlan.Operand {
        let reader = try ParameterLayout.readFunction(for: type)
        let slots = ParameterLayout.encode(value?.numbers ?? [], as: type)
        // Advance lazily, past the previous parameter's slots, so the graph has no unused trailing node.
        for _ in 0..<previousSlotCount {
            slotPointer = try call(ParameterLayout.advanceFunction, [slotPointer])
        }
        previousSlotCount = slots.count
        parameters.append(.init(name: name, type: type, slot: parameterData.count, slotCount: slots.count))
        parameterData += slots
        let read = try call(reader, [slotPointer])
        if case let .call(index) = read {
            // Readers carry their parameter's name, so constant folding can tell which parameters are still read.
            calls[index].origin = name
            calls[index].valueType = type
        }
        return read
    }
}

extension ValueType {
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
