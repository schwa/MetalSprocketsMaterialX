import MaterialX
import Metal

/// A texture an `image` node reads: which file, which slot of the graph's `textures` argument, and how to sample it.
public struct TextureBinding: Hashable, Sendable {
    /// The image node (scoped key) that reads the texture.
    public var node: String
    /// The filename with `fileprefix` applied, relative to the document unless absolute.
    public var file: String
    public var slot: Int
    public var uAddressMode: String
    public var vAddressMode: String
    public var filterType: String

    public init(node: String, file: String, slot: Int, uAddressMode: String = "periodic", vAddressMode: String = "periodic", filterType: String = "linear") {
        self.node = node
        self.file = file
        self.slot = slot
        self.uAddressMode = uAddressMode
        self.vAddressMode = vAddressMode
        self.filterType = filterType
    }

    /// A sampler for this binding, with `supportArgumentBuffers` set. MaterialX's `constant` address mode (the
    /// node's default value outside 0…1) is approximated by clamping to zero.
    public var samplerDescriptor: MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = Self.addressMode(uAddressMode)
        descriptor.tAddressMode = Self.addressMode(vAddressMode)
        let filter: MTLSamplerMinMagFilter = filterType == "closest" ? .nearest : .linear
        descriptor.minFilter = filter
        descriptor.magFilter = filter
        descriptor.mipFilter = filterType == "closest" ? .notMipmapped : .linear
        descriptor.supportArgumentBuffers = true
        return descriptor
    }

    static func addressMode(_ mode: String) -> MTLSamplerAddressMode {
        switch mode {
        case "clamp": .clampToEdge
        case "mirror": .mirrorRepeat
        case "constant": .clampToZero
        default: .repeat
        }
    }
}
