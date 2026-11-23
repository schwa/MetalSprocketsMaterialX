import Foundation

/// A geometry path as MaterialX matches them (`GeomPath` in MaterialXCore): `/` matches everything, an empty string
/// matches nothing, and two paths match when one is a prefix of the other, component by component.
public struct GeometryPath: Hashable, Sendable {
    public var components: [String]
    public var isEmpty: Bool

    public init(_ string: String) {
        isEmpty = string.isEmpty
        components = string.split(separator: "/").map(String.init)
    }

    /// With `contains`, `self` must contain `other`: it may not be longer.
    public func matches(_ other: Self, contains: Bool = false) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        if contains, components.count > other.components.count {
            return false
        }
        return zip(components, other.components).allSatisfy { $0 == $1 }
    }

    /// Whether any path in the comma- or space-separated list `lhs` matches any in `rhs`.
    public static func listsMatch(_ lhs: String, _ rhs: String, contains: Bool = false) -> Bool {
        let separators: (Character) -> Bool = { $0 == "," || $0.isWhitespace }
        let left = lhs.split(whereSeparator: separators).map { Self(String($0)) }
        return rhs.split(whereSeparator: separators).contains { name in
            let path = Self(String(name))
            return left.contains { $0.matches(path, contains: contains) }
        }
    }
}

/// A `<collection>` of geometry. Named to avoid Swift's `Collection`.
public struct GeometryCollection: Hashable, Sendable {
    public var name: String
    public var includeGeometry: String
    public var excludeGeometry: String
    public var includeCollections: [String]

    init(_ element: Element) {
        name = element.name ?? ""
        includeGeometry = element["includegeom"] ?? ""
        excludeGeometry = element["excludegeom"] ?? ""
        includeCollections = (element["includecollection"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

public struct MaterialAssign: Hashable, Sendable {
    public var name: String
    public var material: String
    public var geometry: String
    public var collection: String?
    public var exclusive: Bool

    init(_ element: Element) {
        name = element.name ?? ""
        material = element["material"] ?? ""
        geometry = element["geom"] ?? ""
        collection = element["collection"]
        exclusive = element["exclusive"] != "false"
    }
}

public struct VariantAssign: Hashable, Sendable {
    public var name: String
    public var variantSet: String
    public var variant: String
}

public struct Look: Hashable, Sendable {
    public var name: String
    /// Looks this one inherits assignments from (`inherit`).
    public var inherit: String?
    public var materialAssigns: [MaterialAssign]
    public var variantAssigns: [VariantAssign]

    init(_ element: Element) {
        name = element.name ?? ""
        inherit = element["inherit"]
        materialAssigns = element.children(tag: "materialassign").map(MaterialAssign.init)
        variantAssigns = element.children(tag: "variantassign").map { child in
            VariantAssign(name: child.name ?? "", variantSet: child["variantset"] ?? "", variant: child["variant"] ?? "")
        }
    }
}

/// A `<variantset>`: named variants, each a set of input values.
public struct VariantSet: Hashable, Sendable {
    public var name: String
    /// Variant name → its `<input>` elements.
    public var variants: [String: [Input]]

    init(_ element: Element) throws {
        name = element.name ?? ""
        var variants: [String: [Input]] = [:]
        for variant in element.children(tag: "variant") {
            variants[variant.name ?? ""] = try variant.children(tag: "input").map(Input.init)
        }
        self.variants = variants
    }
}

/// A `<geominfo>` or `<propertyset>`: values attached to geometry, such as `geomprop`s and tokens.
public struct PropertyGroup: Hashable, Sendable {
    public var name: String
    public var geometry: String?
    /// Child elements (`geomprop`, `token`, `property`) by name.
    public var values: [String: Element]

    init(_ element: Element) {
        name = element.name ?? ""
        geometry = element["geom"]
        values = Dictionary(element.children.compactMap { child in child.name.map { ($0, child) } }) { first, _ in first }
    }
}

public extension Document {
    var looks: [Look] { root.children(tag: "look").map(Look.init) }
    var collections: [GeometryCollection] { root.children(tag: "collection").map(GeometryCollection.init) }
    var geomInfos: [PropertyGroup] { root.children(tag: "geominfo").map(PropertyGroup.init) }
    var propertySets: [PropertyGroup] { root.children(tag: "propertyset").map(PropertyGroup.init) }

    func variantSets() throws -> [VariantSet] {
        try root.children(tag: "variantset").map(VariantSet.init)
    }

    func look(_ name: String) -> Look? { looks.first { $0.name == name } }
    func collection(_ name: String) -> GeometryCollection? { collections.first { $0.name == name } }

    /// Whether `geometry` is in collection `name`: matched by its include list or included collections and not by its
    /// exclude list. Throws on collection cycles.
    func collection(_ name: String, contains geometry: String) throws -> Bool {
        try collection(name, contains: geometry, visiting: [])
    }

    private func collection(_ name: String, contains geometry: String, visiting: Set<String>) throws -> Bool {
        guard let collection = collection(name) else { return false }
        guard !visiting.contains(name) else {
            throw MaterialXError.cycle("collection \(name)")
        }
        if GeometryPath.listsMatch(collection.excludeGeometry, geometry, contains: true) {
            return false
        }
        if GeometryPath.listsMatch(collection.includeGeometry, geometry) {
            return true
        }
        return try collection.includeCollections.contains { included in
            try self.collection(included, contains: geometry, visiting: visiting.union([name]))
        }
    }

    /// The material assignments in look `name` (and the looks it inherits, inherited first) that apply to
    /// `geometry`, in document order.
    func materialAssignments(for geometry: String, look name: String) throws -> [MaterialAssign] {
        var chain: [Look] = []
        var current = look(name)
        while let look = current, !chain.contains(look) {
            chain.insert(look, at: 0)
            current = look.inherit.flatMap(self.look)
        }
        return try chain.flatMap(\.materialAssigns).filter { assign in
            if GeometryPath.listsMatch(assign.geometry, geometry) {
                return true
            }
            if let collection = assign.collection {
                return try self.collection(collection, contains: geometry)
            }
            return false
        }
    }
}
