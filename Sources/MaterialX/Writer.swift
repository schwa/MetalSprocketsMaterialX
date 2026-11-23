import Foundation

public extension MaterialXElement {
    /// XML for this element and its children, indented by two spaces per level.
    ///
    /// Attributes are written `name`, `type`, `nodedef`, then the rest sorted, because the parser does not keep their
    /// order. XML comments are not kept by the parser, so they are not written.
    func xmlString(indent: Int = 0) -> String {
        let padding = String(repeating: "  ", count: indent)
        let leading = ["name", "type", "nodedef"]
        let keys = leading.filter { attributes[$0] != nil } + attributes.keys.filter { !leading.contains($0) }.sorted()
        let attributeText = keys.map { " \($0)=\"\(Self.escape(attributes[$0] ?? ""))\"" }.joined()
        guard !children.isEmpty else {
            return "\(padding)<\(tag)\(attributeText) />\n"
        }
        let body = children.map { $0.xmlString(indent: indent + 1) }.joined()
        return "\(padding)<\(tag)\(attributeText)>\n\(body)\(padding)</\(tag)>\n"
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public extension MaterialXDocument {
    /// The document as `.mtlx` XML. `xi:include`s were expanded on load, so included content is written inline.
    func data() -> Data {
        Data(("<?xml version=\"1.0\"?>\n" + root.xmlString()).utf8)
    }

    func write(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }
}
