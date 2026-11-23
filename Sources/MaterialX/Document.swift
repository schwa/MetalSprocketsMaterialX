import Foundation

/// An input on a nodedef, node or nodegraph.
public struct MaterialXInput: Hashable, Sendable {
    public var name: String
    public var type: ValueType
    public var value: MaterialXValue?
    /// Upstream node in the same graph.
    public var nodeName: String?
    /// Output on a multi-output upstream node or nodegraph.
    public var output: String?
    /// Graph interface input this input reads.
    public var interfaceName: String?
    public var nodeGraph: String?
    public var element: MaterialXElement

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name, let type = element["type"] else {
            throw MaterialXError.invalidDocument("<\(element.tag)> without name or type")
        }
        let valueType = ValueType(rawValue: type)
        self.name = name
        self.type = valueType
        value = try element["value"].map { try MaterialXValue($0, type: valueType) }
        nodeName = element["nodename"]
        output = element["output"]
        interfaceName = element["interfacename"]
        nodeGraph = element["nodegraph"]
        self.element = element
    }
}

public struct MaterialXOutput: Hashable, Sendable {
    public var name: String
    public var type: ValueType
    public var nodeName: String?
    public var output: String?
    public var element: MaterialXElement

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name, let type = element["type"] else {
            throw MaterialXError.invalidDocument("<output> without name or type")
        }
        self.name = name
        self.type = ValueType(rawValue: type)
        nodeName = element["nodename"]
        output = element["output"]
        self.element = element
    }
}

public struct NodeDef: Hashable, Sendable {
    public var name: String
    /// The node category this defines, such as `add`.
    public var node: String
    public var nodeGroup: String?
    /// The nodedef this one inherits inputs and outputs from.
    public var inherit: String?
    public var version: String?
    public var isDefaultVersion: Bool
    public var inputs: [MaterialXInput]
    public var outputs: [MaterialXOutput]

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name, let node = element["node"] else {
            throw MaterialXError.invalidDocument("<nodedef> without name or node")
        }
        self.name = name
        self.node = node
        nodeGroup = element["nodegroup"]
        inherit = element["inherit"]
        version = element["version"]
        isDefaultVersion = element["isdefaultversion"] == "true"
        inputs = try element.children(tag: "input").map(MaterialXInput.init)
        outputs = try element.children(tag: "output").map(MaterialXOutput.init)
    }

    public func input(_ name: String) -> MaterialXInput? { inputs.first { $0.name == name } }

    /// This nodedef with `parent`'s inputs and outputs merged in. Own entries override the parent's and keep the
    /// parent's order.
    func inheriting(from parent: Self) -> Self {
        var result = self
        result.inputs = Self.merge(parent.inputs, inputs, name: \.name)
        result.outputs = Self.merge(parent.outputs, outputs, name: \.name)
        return result
    }

    private static func merge<T>(_ parent: [T], _ own: [T], name: KeyPath<T, String>) -> [T] {
        var merged = parent.map { item in own.first { $0[keyPath: name] == item[keyPath: name] } ?? item }
        merged += own.filter { item in !parent.contains { $0[keyPath: name] == item[keyPath: name] } }
        return merged
    }
}

/// A node instance. Its tag is the node category.
public struct MaterialXNode: Hashable, Sendable {
    public var name: String
    public var category: String
    public var type: ValueType
    public var nodeDefName: String?
    /// The requested nodedef version, if any.
    public var version: String?
    public var inputs: [MaterialXInput]
    public var element: MaterialXElement

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name, let type = element["type"] else {
            throw MaterialXError.invalidDocument("<\(element.tag)> node without name or type")
        }
        self.element = element
        self.name = name
        category = element.tag
        self.type = ValueType(rawValue: type)
        nodeDefName = element["nodedef"]
        version = element["version"]
        inputs = try element.children(tag: "input").map(MaterialXInput.init)
    }

    public func input(_ name: String) -> MaterialXInput? { inputs.first { $0.name == name } }
}

public struct NodeGraph: Hashable, Sendable {
    public var name: String
    public var nodeDefName: String?
    public var inputs: [MaterialXInput]
    public var outputs: [MaterialXOutput]
    public var nodes: [String: MaterialXNode]
    public var element: MaterialXElement

    static let nonNodeTags: Set<String> = ["input", "output", "token", "backdrop", "comment"]

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name else {
            throw MaterialXError.invalidDocument("<nodegraph> without name")
        }
        self.element = element
        self.name = name
        nodeDefName = element["nodedef"]
        inputs = try element.children(tag: "input").map(MaterialXInput.init)
        outputs = try element.children(tag: "output").map(MaterialXOutput.init)
        let nodes = try element.children.filter { !Self.nonNodeTags.contains($0.tag) }.map(MaterialXNode.init)
        self.nodes = Dictionary(nodes.map { ($0.name, $0) }) { first, _ in first }
    }

    public func output(_ name: String) -> MaterialXOutput? { outputs.first { $0.name == name } }
    public func input(_ name: String) -> MaterialXInput? { inputs.first { $0.name == name } }
}

/// A MaterialX document.
///
/// ``root`` is the only stored state: the typed views (``nodeDefs``, ``nodeGraphs``, ``nodes``, …) are read from it
/// on access, so edits to the tree, or through ``setValue(_:input:node:graph:type:)``, show up in them. Malformed
/// elements are rejected when the document is created; elements made invalid by later direct edits are skipped.
public struct MaterialXDocument: Sendable {
    public var root: MaterialXElement

    public var version: String? { root["version"] }
    public var colorSpace: String? { root["colorspace"] }
    public var typeDefs: [TypeDef] { root.children(tag: "typedef").compactMap { try? TypeDef($0) } }
    public var nodeDefs: [NodeDef] { root.children(tag: "nodedef").compactMap { try? NodeDef($0) } }
    public var nodeGraphs: [NodeGraph] { root.children(tag: "nodegraph").compactMap { try? NodeGraph($0) } }
    /// Top-level nodes (shaders, materials, loose nodes).
    public var nodes: [MaterialXNode] { Self.nodeElements(of: root).compactMap { try? MaterialXNode($0) } }

    static let nonNodeTags: Set<String> = ["nodedef", "nodegraph", "implementation", "typedef", "unitdef", "unittypedef", "look", "collection", "geominfo", "propertyset", "variantset", "xi:include", "backdrop", "comment", "token", "geompropdef"]

    static func nodeElements(of root: MaterialXElement) -> [MaterialXElement] {
        root.children.filter { !nonNodeTags.contains($0.tag) && $0["type"] != nil }
    }

    /// Loads `url`, following `xi:include` hrefs relative to each including file.
    public init(url: URL) throws {
        try self.init(root: Self.load(url.standardizedFileURL, including: []))
    }

    /// Parses `data`. Relative `xi:include` hrefs resolve against `baseURL`; without one they are left unresolved.
    public init(data: Data, baseURL: URL? = nil) throws {
        var root = try MaterialXElement.parse(data)
        if let baseURL {
            root = try Self.resolveIncludes(root, baseURL: baseURL, including: [])
        }
        try self.init(root: root)
    }

    private static func load(_ url: URL, including: Set<URL>) throws -> MaterialXElement {
        guard !including.contains(url) else {
            throw MaterialXError.invalidDocument("xi:include cycle at \(url.path)")
        }
        let root = try MaterialXElement.parse(Data(contentsOf: url))
        return try resolveIncludes(root, baseURL: url.deletingLastPathComponent(), including: including.union([url]))
    }

    /// Replaces each top-level `xi:include` with the children of the included document's root.
    private static func resolveIncludes(_ root: MaterialXElement, baseURL: URL, including: Set<URL>) throws -> MaterialXElement {
        var result = root
        result.children = try root.children.flatMap { child -> [MaterialXElement] in
            guard child.tag == "xi:include" else { return [child] }
            guard let href = child["href"] else {
                throw MaterialXError.invalidDocument("xi:include without href")
            }
            let url = URL(fileURLWithPath: href, relativeTo: baseURL).standardizedFileURL
            return try load(url, including: including).children
        }
        return result
    }

    /// A document from an element tree, for example an edited copy of another document's ``root``.
    public init(root: MaterialXElement) throws {
        guard root.tag == "materialx" else {
            throw MaterialXError.invalidDocument("root is <\(root.tag)>, not <materialx>")
        }
        // Parse every typed view once so malformed documents are rejected up front.
        _ = try root.children(tag: "typedef").map(TypeDef.init)
        _ = try root.children(tag: "nodedef").map(NodeDef.init)
        _ = try root.children(tag: "nodegraph").map(NodeGraph.init)
        _ = try Self.nodeElements(of: root).map(MaterialXNode.init)
        self.root = root
    }

    /// Sets input `input` of node `node` (top-level, or inside nodegraph `graph`) to `value`, written as MaterialX
    /// writes values (`"0.1, 0.2, 0.3"`). Adds the input, with `type`, when the node does not set it yet. Throws if
    /// the node is missing or the value does not parse as the input's type.
    public mutating func setValue(_ value: String, input: String, node: String, graph: String? = nil, type: ValueType? = nil) throws {
        let graphIndex: Int? = try graph.map { name in
            guard let index = root.children.firstIndex(where: { $0.tag == "nodegraph" && $0.name == name }) else {
                throw MaterialXError.invalidDocument("no nodegraph '\(name)'")
            }
            return index
        }
        let container = graphIndex.map { root.children[$0] } ?? root
        guard let nodeIndex = container.children.firstIndex(where: { $0.name == node && $0["type"] != nil && $0.tag != "input" && $0.tag != "output" }) else {
            throw MaterialXError.invalidDocument("no node '\(node)'\(graph.map { " in nodegraph '\($0)'" } ?? "")")
        }
        var nodeElement = container.children[nodeIndex]
        if let inputIndex = nodeElement.children.firstIndex(where: { $0.tag == "input" && $0.name == input }) {
            let inputType = ValueType(rawValue: nodeElement.children[inputIndex]["type"] ?? "")
            _ = try MaterialXValue(value, type: inputType)
            nodeElement.children[inputIndex].attributes["value"] = value
            // A value replaces a connection.
            for key in ["nodename", "nodegraph", "output", "interfacename"] {
                nodeElement.children[inputIndex].attributes[key] = nil
            }
        } else {
            guard let type else {
                throw MaterialXError.invalidDocument("node '\(node)' has no input '\(input)'; pass its type to add it")
            }
            _ = try MaterialXValue(value, type: type)
            nodeElement.children.append(MaterialXElement(tag: "input", attributes: ["name": input, "type": type.rawValue, "value": value]))
        }
        if let graphIndex {
            root.children[graphIndex].children[nodeIndex] = nodeElement
        } else {
            root.children[nodeIndex] = nodeElement
        }
    }

    public func nodeGraph(_ name: String) -> NodeGraph? { nodeGraphs.first { $0.name == name } }

    /// Nodes of type `material`.
    public var materials: [MaterialXNode] { nodes.filter { $0.type == .material } }
}
