import Foundation

/// An input on a nodedef, node or nodegraph.
public struct Input: Hashable, Sendable {
    public var name: String
    public var type: ValueType
    public var value: Value?
    /// Upstream node in the same graph.
    public var nodeName: String?
    /// Output on a multi-output upstream node or nodegraph.
    public var output: String?
    /// Graph interface input this input reads.
    public var interfaceName: String?
    public var nodeGraph: String?
    public var element: Element

    public init(_ element: Element) throws {
        guard let name = element.name, let type = element["type"] else {
            throw MaterialXError.invalidDocument("<\(element.tag)> without name or type")
        }
        let valueType = ValueType(rawValue: type)
        self.name = name
        self.type = valueType
        value = try element["value"].map { try Value($0, type: valueType) }
        nodeName = element["nodename"]
        output = element["output"]
        interfaceName = element["interfacename"]
        nodeGraph = element["nodegraph"]
        self.element = element
    }
}

public struct Output: Hashable, Sendable {
    public var name: String
    public var type: ValueType
    public var nodeName: String?
    public var output: String?
    public var element: Element

    public init(_ element: Element) throws {
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
    public var inputs: [Input]
    public var outputs: [Output]

    public init(_ element: Element) throws {
        guard let name = element.name, let node = element["node"] else {
            throw MaterialXError.invalidDocument("<nodedef> without name or node")
        }
        self.name = name
        self.node = node
        nodeGroup = element["nodegroup"]
        inherit = element["inherit"]
        version = element["version"]
        isDefaultVersion = element["isdefaultversion"] == "true"
        inputs = try element.children(tag: "input").map(Input.init)
        outputs = try element.children(tag: "output").map(Output.init)
    }

    public func input(_ name: String) -> Input? { inputs.first { $0.name == name } }

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
public struct Node: Hashable, Sendable {
    public var name: String
    public var category: String
    public var type: ValueType
    public var nodeDefName: String?
    /// The requested nodedef version, if any.
    public var version: String?
    public var inputs: [Input]
    public var element: Element

    public init(_ element: Element) throws {
        guard let name = element.name, let type = element["type"] else {
            throw MaterialXError.invalidDocument("<\(element.tag)> node without name or type")
        }
        self.element = element
        self.name = name
        category = element.tag
        self.type = ValueType(rawValue: type)
        nodeDefName = element["nodedef"]
        version = element["version"]
        inputs = try element.children(tag: "input").map(Input.init)
    }

    public func input(_ name: String) -> Input? { inputs.first { $0.name == name } }
}

public struct NodeGraph: Hashable, Sendable {
    public var name: String
    public var nodeDefName: String?
    public var inputs: [Input]
    public var outputs: [Output]
    public var nodes: [String: Node]

    static let nonNodeTags: Set<String> = ["input", "output", "token", "backdrop", "comment"]

    public init(_ element: Element) throws {
        guard let name = element.name else {
            throw MaterialXError.invalidDocument("<nodegraph> without name")
        }
        self.name = name
        nodeDefName = element["nodedef"]
        inputs = try element.children(tag: "input").map(Input.init)
        outputs = try element.children(tag: "output").map(Output.init)
        let nodes = try element.children.filter { !Self.nonNodeTags.contains($0.tag) }.map(Node.init)
        self.nodes = Dictionary(nodes.map { ($0.name, $0) }) { first, _ in first }
    }

    public func output(_ name: String) -> Output? { outputs.first { $0.name == name } }
    public func input(_ name: String) -> Input? { inputs.first { $0.name == name } }
}

/// A MaterialX document.
public struct Document: Sendable {
    public var root: Element
    public var version: String?
    public var colorSpace: String?
    public var nodeDefs: [NodeDef]
    public var nodeGraphs: [NodeGraph]
    /// Top-level nodes (shaders, materials, loose nodes).
    public var nodes: [Node]

    /// Loads `url`, following `xi:include` hrefs relative to each including file.
    public init(url: URL) throws {
        try self.init(root: Self.load(url.standardizedFileURL, including: []))
    }

    /// Parses `data`. Relative `xi:include` hrefs resolve against `baseURL`; without one they are left unresolved.
    public init(data: Data, baseURL: URL? = nil) throws {
        var root = try Element.parse(data)
        if let baseURL {
            root = try Self.resolveIncludes(root, baseURL: baseURL, including: [])
        }
        try self.init(root: root)
    }

    private static func load(_ url: URL, including: Set<URL>) throws -> Element {
        guard !including.contains(url) else {
            throw MaterialXError.invalidDocument("xi:include cycle at \(url.path)")
        }
        let root = try Element.parse(Data(contentsOf: url))
        return try resolveIncludes(root, baseURL: url.deletingLastPathComponent(), including: including.union([url]))
    }

    /// Replaces each top-level `xi:include` with the children of the included document's root.
    private static func resolveIncludes(_ root: Element, baseURL: URL, including: Set<URL>) throws -> Element {
        var result = root
        result.children = try root.children.flatMap { child -> [Element] in
            guard child.tag == "xi:include" else { return [child] }
            guard let href = child["href"] else {
                throw MaterialXError.invalidDocument("xi:include without href")
            }
            let url = URL(fileURLWithPath: href, relativeTo: baseURL).standardizedFileURL
            return try load(url, including: including).children
        }
        return result
    }

    private init(root: Element) throws {
        guard root.tag == "materialx" else {
            throw MaterialXError.invalidDocument("root is <\(root.tag)>, not <materialx>")
        }
        self.root = root
        version = root["version"]
        colorSpace = root["colorspace"]
        nodeDefs = try root.children(tag: "nodedef").map(NodeDef.init)
        nodeGraphs = try root.children(tag: "nodegraph").map(NodeGraph.init)
        let skipped: Set<String> = ["nodedef", "nodegraph", "implementation", "typedef", "unitdef", "unittypedef", "look", "collection", "geominfo", "propertyset", "variantset", "xi:include", "backdrop", "comment", "token"]
        nodes = try root.children.filter { !skipped.contains($0.tag) && $0["type"] != nil }.map(Node.init)
    }

    public func nodeGraph(_ name: String) -> NodeGraph? { nodeGraphs.first { $0.name == name } }

    /// Nodes of type `material`.
    public var materials: [Node] { nodes.filter { $0.type == .material } }
}
