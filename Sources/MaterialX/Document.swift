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
public struct MaterialXDocument: Sendable {
    public var root: MaterialXElement
    public var version: String?
    public var colorSpace: String?
    public var typeDefs: [TypeDef]
    public var nodeDefs: [NodeDef]
    public var nodeGraphs: [NodeGraph]
    /// Top-level nodes (shaders, materials, loose nodes).
    public var nodes: [MaterialXNode]

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
        self.root = root
        version = root["version"]
        colorSpace = root["colorspace"]
        typeDefs = try root.children(tag: "typedef").map(TypeDef.init)
        nodeDefs = try root.children(tag: "nodedef").map(NodeDef.init)
        nodeGraphs = try root.children(tag: "nodegraph").map(NodeGraph.init)
        let skipped: Set<String> = ["nodedef", "nodegraph", "implementation", "typedef", "unitdef", "unittypedef", "look", "collection", "geominfo", "propertyset", "variantset", "xi:include", "backdrop", "comment", "token"]
        nodes = try root.children.filter { !skipped.contains($0.tag) && $0["type"] != nil }.map(MaterialXNode.init)
    }

    public func nodeGraph(_ name: String) -> NodeGraph? { nodeGraphs.first { $0.name == name } }

    /// Nodes of type `material`.
    public var materials: [MaterialXNode] { nodes.filter { $0.type == .material } }
}
