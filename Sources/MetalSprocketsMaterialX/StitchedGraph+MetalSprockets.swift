@_exported import MaterialX
@_exported import MaterialXMetal
import MetalSprockets

public extension StitchedGraph {
    /// The stitched function as a MetalSprockets ``VisibleFunction``, for a pipeline's linked functions.
    func visibleFunction(linking: VisibleFunction.Linking = .binary) throws -> VisibleFunction {
        try VisibleFunction(library: library, name: functionName).linking(linking)
    }
}
