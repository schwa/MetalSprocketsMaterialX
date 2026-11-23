import Foundation

public extension Document {
    /// The filename an input refers to, with `[token]` substitutions and the nearest `fileprefix` applied.
    ///
    /// `fileprefix` is looked up on the input, then the node, then the graph, then the document root. Tokens come
    /// from `<token>` elements on the node, then the graph. `<UDIM>` and `<UVTILE>` are left in place; expand them
    /// per tile with ``FilenamePattern``.
    func resolvedFilename(_ input: Input, node: Node, graph: NodeGraph? = nil) -> String? {
        guard case let .string(value) = input.value else { return nil }
        let scopes = [input.element, node.element] + [graph?.element, root].compactMap(\.self)
        var tokens: [String: String] = [:]
        for scope in scopes.reversed() {
            for token in scope.children(tag: "token") {
                if let name = token.name, let value = token["value"] {
                    tokens[name] = value
                }
            }
        }
        var filename = value
        for (name, value) in tokens {
            filename = filename.replacingOccurrences(of: "[\(name)]", with: value)
        }
        let prefix = scopes.lazy.compactMap { $0["fileprefix"] }.first ?? ""
        return prefix + filename
    }
}

/// A filename that may contain the `<UDIM>` or `<UVTILE>` tile markers.
public struct FilenamePattern: Hashable, Sendable {
    public var pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
    }

    public var isTiled: Bool {
        pattern.contains("<UDIM>") || pattern.contains("<UVTILE>")
    }

    /// The filename for the tile whose lower-left UV corner is (`u`, `v`), both zero-based.
    /// `<UDIM>` becomes `1001 + u + 10 v`; `<UVTILE>` becomes `u<u+1>_v<v+1>`.
    public func filename(u: Int, v: Int) -> String {
        pattern
            .replacingOccurrences(of: "<UDIM>", with: String(1_001 + u + 10 * v))
            .replacingOccurrences(of: "<UVTILE>", with: "u\(u + 1)_v\(v + 1)")
    }
}
