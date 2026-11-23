import Foundation

/// A generic MaterialX XML element. Typed views (``NodeDef``, ``MaterialXNode``, ``NodeGraph``) read from it.
public struct MaterialXElement: Sendable, Hashable {
    public var tag: String
    public var attributes: [String: String]
    public var children: [Self]

    public init(tag: String, attributes: [String: String] = [:], children: [Self] = []) {
        self.tag = tag
        self.attributes = attributes
        self.children = children
    }

    public subscript(attribute: String) -> String? { attributes[attribute] }

    public var name: String? { attributes["name"] }

    public func children(tag: String) -> [Self] {
        children.filter { $0.tag == tag }
    }

    public func child(named name: String) -> Self? {
        children.first { $0.name == name }
    }
}

public enum MaterialXError: Error, Equatable, CustomStringConvertible {
    case parse(String)
    case invalidDocument(String)
    case missingNodeDef(node: String)
    case unsupportedNode(String)
    case invalidValue(String)
    case cycle(String)
    /// Metal rejected the stitching graph. The message includes a dump of the graph.
    case stitchingFailed(String)

    public var description: String {
        switch self {
        case let .parse(message): "MaterialX parse error: \(message)"
        case let .invalidDocument(message): "Invalid MaterialX document: \(message)"
        case let .missingNodeDef(node): "No nodedef matches node '\(node)'"
        case let .unsupportedNode(name): "MaterialXNode has no Metal implementation: \(name)"
        case let .invalidValue(value): "Invalid value: \(value)"
        case let .cycle(node): "Nodegraph cycle at '\(node)'"
        case let .stitchingFailed(message): "Function stitching failed: \(message)"
        }
    }
}

extension MaterialXElement {
    static func parse(_ data: Data) throws -> Self {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw MaterialXError.parse(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return root
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    var stack: [MaterialXElement] = []
    var root: MaterialXElement?

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String] = [:]) {
        stack.append(MaterialXElement(tag: elementName, attributes: attributes))
    }

    func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        let element = stack.removeLast()
        if stack.isEmpty {
            root = element
        } else {
            stack[stack.count - 1].children.append(element)
        }
    }
}
