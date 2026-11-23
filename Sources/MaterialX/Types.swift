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

/// A parsed MaterialX value. Numeric values are stored as floats.
public enum Value: Hashable, Sendable {
    case numbers([Float])
    case string(String)

    public init(_ string: String, type: ValueType) throws {
        if type.componentCount == nil {
            self = .string(string)
            return
        }
        if type == .boolean {
            self = .numbers([string.trimmingCharacters(in: .whitespaces) == "true" ? 1 : 0])
            return
        }
        let parts = string.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let numbers = parts.compactMap(Float.init)
        guard numbers.count == parts.count, numbers.count == type.componentCount else {
            throw MaterialXError.invalidValue("'\(string)' as \(type)")
        }
        self = .numbers(numbers)
    }

    public var numbers: [Float]? {
        if case let .numbers(values) = self { values } else { nil }
    }
}
