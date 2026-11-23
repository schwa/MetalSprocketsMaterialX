import MaterialX

/// The layout of a stitched graph's `parameters` buffer, in one place.
///
/// Every value takes one `float4` slot; matrices take one slot per column (3 or 4 floats used). Integers and booleans
/// use `.x`. The stitched graph walks the buffer with `mx_parameter_next` and reads a value with
/// `mx_parameter_<suffix>` (`StandardLibrary.metal`); `ParameterLayoutTests` checks the Metal readers against this.
public enum ParameterLayout {
    /// The `mx_parameter_next` function: advances the slot pointer by one slot.
    public static let advanceFunction = "mx_parameter_next"

    /// Number of slots a value of `type` takes.
    public static func slotCount(for type: ValueType) -> Int {
        switch type {
        case .matrix33: 3
        case .matrix44: 4
        default: 1
        }
    }

    /// The Metal function that reads a value of `type` from a slot pointer.
    public static func readFunction(for type: ValueType) throws -> String {
        "mx_parameter_" + (try type.metalSuffix())
    }

    /// Whether `function` reads a parameter value (as opposed to advancing the pointer).
    public static func isReadFunction(_ function: String) -> Bool {
        function.hasPrefix("mx_parameter_") && function != advanceFunction
    }

    /// `numbers` (a value's components, in MaterialX order) packed into slots.
    public static func encode(_ numbers: [Float], as type: ValueType) -> [SIMD4<Float>] {
        let width = switch type {
        case .matrix33: 3
        default: 4
        }
        return (0..<slotCount(for: type)).map { column in
            var slot = SIMD4<Float>.zero
            for index in 0..<width where column * width + index < numbers.count {
                slot[index] = numbers[column * width + index]
            }
            return slot
        }
    }

    /// The components of a value of `type` stored in `slots`, in MaterialX order.
    public static func decode<Slots>(_ slots: Slots, as type: ValueType) -> [Float] where Slots: Collection, Slots.Element == SIMD4<Float> {
        let components = switch type {
        case .matrix33: 3
        case .matrix44: 4
        default: type.componentCount ?? 4
        }
        return slots.flatMap { slot in (0..<components).map { slot[$0] } }
    }
}
