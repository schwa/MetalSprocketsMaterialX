import MaterialX
import MaterialXMetalShaders
import Metal

public extension MXShadingContext {
    /// A context with `texcoord` as UV set 0 and 1, an up-facing normal and tangent frame at the origin, white vertex
    /// color, and the viewer straight above.
    init(texcoord: SIMD2<Float>) {
        self.init()
        positionWorld = .zero
        positionObject = .zero
        normalWorld = [0, 1, 0]
        normalObject = [0, 1, 0]
        tangentWorld = [1, 0, 0]
        tangentObject = [1, 0, 0]
        bitangentWorld = [0, 0, 1]
        bitangentObject = [0, 0, 1]
        viewDirectionWorld = [0, 1, 0]
        self.texcoord = (texcoord, texcoord)
        vertexColor = [1, 1, 1, 1]
    }
}

public extension StitchedGraph {
    /// Runs the graph on the GPU once per texture coordinate, with ``MXShadingContext/init(texcoord:)`` contexts.
    func evaluate(at texcoords: [SIMD2<Float>], device: MTLDevice? = nil) throws -> [SIMD4<Float>] {
        try evaluate(contexts: texcoords.map(MXShadingContext.init(texcoord:)), device: device)
    }

    /// Runs the graph on the GPU once per context and returns the results widened to `float4`: missing components
    /// are 0 and a missing fourth component is 1; booleans and integers become floats. Uses the current
    /// ``parameterData``. For debugging, tools and tests, not rendering.
    func evaluate(contexts: [MXShadingContext], device: MTLDevice? = nil) throws -> [SIMD4<Float>] {
        guard !contexts.isEmpty else { return [] }
        let device = device ?? library.device
        let shaders = try device.makeDefaultLibrary(bundle: .materialXMetalShaders())
        guard let kernel = shaders.makeFunction(name: "mx_evaluate_" + (try Self.evaluationSuffix(outputType))) else {
            throw MaterialXError.unsupportedNode("evaluating an output of type \(outputType)")
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
              let output = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * contexts.count),
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
        let width = min(contexts.count, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: contexts.count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: contexts.count)
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
