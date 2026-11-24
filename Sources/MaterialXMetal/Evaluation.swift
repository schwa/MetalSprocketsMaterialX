import MaterialX
import MaterialXMetalShaders
import Metal

public extension MXShadingContext {
    /// A context with `texcoord` as UV set 0 and 1, an up-facing normal and tangent frame at the origin, white vertex
    /// color, and the viewer straight above.
    init(texcoord: SIMD2<Float>) {
        self.init()
        objectToWorld = matrix_identity_float4x4
        worldToObject = matrix_identity_float4x4
        positionWorld = .zero
        positionObject = .zero
        normalWorld = [0, 1, 0]
        normalObject = [0, 1, 0]
        tangentWorld = [1, 0, 0]
        tangentObject = [1, 0, 0]
        bitangentWorld = [0, 0, 1]
        bitangentObject = [0, 0, 1]
        viewDirectionWorld = [0, 1, 0]
        viewDirectionObject = [0, 1, 0]
        self.texcoord = (texcoord, texcoord)
        vertexColor = [1, 1, 1, 1]
    }
}

public extension StitchedGraph {
    /// Runs the graph on the GPU once per texture coordinate, with ``MXShadingContext/init(texcoord:)`` contexts.
    func evaluate(at texcoords: [SIMD2<Float>], textures: MTLBuffer? = nil, residentTextures: [MTLTexture] = [], device: MTLDevice? = nil) throws -> [SIMD4<Float>] {
        try evaluate(contexts: texcoords.map(MXShadingContext.init(texcoord:)), textures: textures, residentTextures: residentTextures, device: device)
    }

    /// An argument buffer of `MXTexture` slots for the graph's `textures` argument, in slot order. A `nil` slot is
    /// empty: image nodes reading it return their default. Samplers must be created with `supportArgumentBuffers`.
    /// The textures must be made resident (for example with `useResource`) by whoever encodes the draw or dispatch.
    static func makeTextureTable(_ slots: [(texture: MTLTexture, sampler: MTLSamplerState)?], device: MTLDevice) throws -> MTLBuffer {
        let entries = slots.map { slot in
            slot.map { MXTexture(texture: $0.texture.gpuResourceID._impl, sampler: $0.sampler.gpuResourceID._impl) } ?? MXTexture()
        }
        let padded = entries.isEmpty ? [MXTexture()] : entries
        guard let buffer = device.makeBuffer(bytes: padded, length: MemoryLayout<MXTexture>.stride * padded.count) else {
            throw MaterialXError.stitchingFailed("could not create texture table")
        }
        return buffer
    }

    /// Runs the graph on the GPU once per context and returns the results widened to `float4`: missing components
    /// are 0 and a missing fourth component is 1; booleans and integers become floats. Uses the current
    /// ``parameterData``. For debugging, tools and tests, not rendering.
    func evaluate(contexts: [MXShadingContext], textures: MTLBuffer? = nil, residentTextures: [MTLTexture] = [], device: MTLDevice? = nil) throws -> [SIMD4<Float>] {
        let initial = [SIMD4<Float>](repeating: .zero, count: contexts.count)
        return try run(kernel: "mx_evaluate_" + (try Self.evaluationSuffix(outputType)), contexts: contexts, initial: initial, textures: (textures, residentTextures), device: device)
    }

    /// Runs a surface function (``GraphStitcher/stitchSurface(_:in:functionName:mapping:)``) once per context,
    /// starting each from `initial`.
    func evaluateSurface(contexts: [MXShadingContext], initial: MXSurfaceInputs = .defaults, textures: MTLBuffer? = nil, residentTextures: [MTLTexture] = [], device: MTLDevice? = nil) throws -> [MXSurfaceInputs] {
        guard outputType == .surfaceshader else {
            throw MaterialXError.unsupportedNode("evaluateSurface on a graph with a \(outputType) output")
        }
        return try run(kernel: "mx_evaluate_surface", contexts: contexts, initial: [MXSurfaceInputs](repeating: initial, count: contexts.count), textures: (textures, residentTextures), device: device)
    }

    /// Dispatches `kernel` (one of the `mx_evaluate_*` kernels) with this graph in its function table. `initial` is
    /// the output buffer's starting contents, one element per context.
    private func run<Result: BitwiseCopyable>(kernel kernelName: String, contexts: [MXShadingContext], initial: [Result], textures: (table: MTLBuffer?, resident: [MTLTexture]), device: MTLDevice?) throws -> [Result] {
        guard !contexts.isEmpty else { return [] }
        let device = device ?? library.device
        let shaders = try device.makeDefaultLibrary(bundle: .materialXMetalShaders())
        guard let kernel = shaders.makeFunction(name: kernelName) else {
            throw MaterialXError.unsupportedNode("evaluation kernel \(kernelName)")
        }
        let functionDescriptor = MTLFunctionDescriptor()
        functionDescriptor.name = functionName
        functionDescriptor.options = .compileToBinary
        let binary = try library.makeFunction(descriptor: functionDescriptor)
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = kernel
        let linked = MTLLinkedFunctions()
        linked.binaryFunctions = [binary]
        descriptor.linkedFunctions = linked
        let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        let tableDescriptor = MTLVisibleFunctionTableDescriptor()
        tableDescriptor.functionCount = 1

        // Metal rejects zero-length buffers, and copying from an empty array would over-read.
        let parameters = parameterData.isEmpty ? [SIMD4<Float>.zero] : parameterData
        guard let table = pipeline.makeVisibleFunctionTable(descriptor: tableDescriptor),
              let handle = pipeline.functionHandle(function: binary),
              let input = device.makeBuffer(bytes: contexts, length: MemoryLayout<MXShadingContext>.stride * contexts.count),
              let parameterBuffer = device.makeBuffer(bytes: parameters, length: MemoryLayout<SIMD4<Float>>.stride * parameters.count),
              let output = device.makeBuffer(bytes: initial, length: MemoryLayout<Result>.stride * contexts.count),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MaterialXError.stitchingFailed("could not create evaluation resources")
        }
        table.setFunction(handle, index: 0)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(parameterBuffer, offset: 0, index: 1)
        encoder.setBuffer(output, offset: 0, index: 2)
        encoder.setVisibleFunctionTable(table, bufferIndex: 3)
        let textureTable = try textures.table ?? Self.makeTextureTable([], device: device)
        encoder.setBuffer(textureTable, offset: 0, index: 4)
        for texture in textures.resident {
            encoder.useResource(texture, usage: .read)
        }
        let width = min(contexts.count, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: contexts.count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        let pointer = output.contents().bindMemory(to: Result.self, capacity: contexts.count)
        return Array(UnsafeBufferPointer(start: pointer, count: contexts.count))
    }

    private static func evaluationSuffix(_ type: ValueType) throws -> String {
        switch type {
        case .float: "float"
        case .vector2: "vector2"
        case .vector3, .color3: "vector3"
        case .vector4, .color4: "vector4"
        case .integer: "integer"
        case .boolean: "boolean"
        default: throw MaterialXError.unsupportedNode("evaluating an output of type \(type)")
        }
    }
}
