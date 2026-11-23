import Foundation

/// A MaterialX data type name, such as `color3` or `surfaceshader`.
public struct ValueType: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let float = Self(rawValue: "float")
    public static let integer = Self(rawValue: "integer")
    public static let boolean = Self(rawValue: "boolean")
    public static let vector2 = Self(rawValue: "vector2")
    public static let vector3 = Self(rawValue: "vector3")
    public static let vector4 = Self(rawValue: "vector4")
    public static let color3 = Self(rawValue: "color3")
    public static let color4 = Self(rawValue: "color4")
    public static let matrix33 = Self(rawValue: "matrix33")
    public static let matrix44 = Self(rawValue: "matrix44")
    public static let string = Self(rawValue: "string")
    public static let filename = Self(rawValue: "filename")
    public static let surfaceshader = Self(rawValue: "surfaceshader")
    public static let material = Self(rawValue: "material")
    public static let multioutput = Self(rawValue: "multioutput")

    /// Number of float components for numeric types, `nil` otherwise.
    public var componentCount: Int? {
        switch self {
        case .float, .integer, .boolean: 1
        case .vector2: 2
        case .vector3, .color3: 3
        case .vector4, .color4: 4
        case .matrix33: 9
        case .matrix44: 16
        default: nil
        }
    }

    public var description: String { rawValue }
}

/// A parsed MaterialX value. Float vectors, colors and matrices are stored as floats.
public enum MaterialXValue: Hashable, Sendable {
    case numbers([Float])
    case integer(Int)
    case boolean(Bool)
    /// Strings, filenames, arrays and other non-numeric types, unparsed.
    case string(String)

    public init(_ string: String, type: ValueType) throws {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        switch type {
        case .integer:
            guard let value = Int(trimmed) else {
                throw MaterialXError.invalidValue("'\(string)' as \(type)")
            }
            self = .integer(value)
            return
        case .boolean:
            guard trimmed == "true" || trimmed == "false" else {
                throw MaterialXError.invalidValue("'\(string)' as \(type)")
            }
            self = .boolean(trimmed == "true")
            return
        default:
            break
        }
        if type.componentCount == nil {
            self = .string(string)
            return
        }
        // Like MaterialX (ARRAY_VALID_SEPARATORS), components are separated by commas or spaces: its SimpleHair
        // example writes "1 1,1".
        let parts = string.split { $0 == "," || $0.isWhitespace }.map(String.init)
        let numbers = parts.compactMap(Float.init)
        guard numbers.count == parts.count, numbers.count == type.componentCount else {
            throw MaterialXError.invalidValue("'\(string)' as \(type)")
        }
        self = .numbers(numbers)
    }

    /// The value as floats; integers and booleans become one float. `nil` for strings, which have no numbers.
    public var numbers: [Float]? { // swiftlint:disable:this discouraged_optional_collection
        switch self {
        case let .numbers(values): values
        case let .integer(value): [Float(value)]
        case let .boolean(value): [value ? 1 : 0]
        case .string: nil
        }
    }
}

/// A `<typedef>`: a data type's semantic and context, and its members for struct types.
public struct TypeDef: Hashable, Sendable {
    public struct Member: Hashable, Sendable {
        public var name: String
        public var type: ValueType
        public var value: String?
    }

    public var name: ValueType
    /// For example `color` or `shader`.
    public var semantic: String?
    /// For shader types, for example `surface`.
    public var context: String?
    public var members: [Member]

    public init(_ element: MaterialXElement) throws {
        guard let name = element.name else {
            throw MaterialXError.invalidDocument("<typedef> without name")
        }
        self.name = ValueType(rawValue: name)
        semantic = element["semantic"]
        context = element["context"]
        members = try element.children(tag: "member").map { member in
            guard let name = member.name, let type = member["type"] else {
                throw MaterialXError.invalidDocument("<member> without name or type in typedef '\(name)'")
            }
            return Member(name: name, type: ValueType(rawValue: type), value: member["value"])
        }
    }
}
