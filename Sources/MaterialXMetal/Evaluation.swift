import MaterialX
import Metal

public extension StitchedGraph {
    /// Runs the graph on the GPU once per texture coordinate and returns the results widened to `float4`: missing
    /// components are 0 and a missing fourth component is 1; booleans and integers become floats. Uses the current
    /// ``parameterData``. For debugging, tools and tests, not rendering.
    func evaluate(at texcoords: [SIMD2<Float>], device: MTLDevice? = nil) throws -> [SIMD4<Float>] {
        guard !texcoords.isEmpty else { return [] }
        let device = device ?? library.device
        let kernelLibrary = try device.makeLibrary(source: Self.evaluationKernel(returnType: try Self.metalType(outputType), functionName: functionName), options: nil)
        guard let kernel = kernelLibrary.makeFunction(name: "materialx_evaluate") else {
            throw MaterialXError.stitchingFailed("evaluation kernel missing")
        }
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = kernel
        let linked = MTLLinkedFunctions()
        linked.privateFunctions = [function]
        descriptor.linkedFunctions = linked
        let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)

        // Metal rejects zero-length buffers, and copying from an empty array would over-read.
        let parameters = parameterData.isEmpty ? [SIMD4<Float>.zero] : parameterData
        guard let input = device.makeBuffer(bytes: texcoords, length: MemoryLayout<SIMD2<Float>>.stride * texcoords.count),
              let parameterBuffer = device.makeBuffer(bytes: parameters, length: MemoryLayout<SIMD4<Float>>.stride * parameters.count),
              let output = device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * texcoords.count),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw MaterialXError.stitchingFailed("could not create evaluation resources")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(parameterBuffer, offset: 0, index: 1)
        encoder.setBuffer(output, offset: 0, index: 2)
        let width = min(texcoords.count, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: texcoords.count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
        let pointer = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: texcoords.count)
        return Array(UnsafeBufferPointer(start: pointer, count: texcoords.count))
    }

    private static func metalType(_ type: ValueType) throws -> String {
        switch type {
        case .float: "float"
        case .vector2: "float2"
        case .vector3, .color3: "float3"
        case .vector4, .color4: "float4"
        case .integer: "int"
        case .boolean: "bool"
        default: throw MaterialXError.unsupportedNode("evaluating an output of type \(type)")
        }
    }

    private static func evaluationKernel(returnType: String, functionName: String) -> String {
        """
        #include <metal_stdlib>
        using namespace metal;
        static float4 widen(float v) { return float4(v, 0, 0, 1); }
        static float4 widen(float2 v) { return float4(v, 0, 1); }
        static float4 widen(float3 v) { return float4(v, 1); }
        static float4 widen(float4 v) { return v; }
        static float4 widen(int v) { return float4(float(v), 0, 0, 1); }
        static float4 widen(bool v) { return float4(v ? 1.0 : 0.0, 0, 0, 1); }
        [[visible]] \(returnType) \(functionName)(float2 texcoord, constant float4 *parameters);
        kernel void materialx_evaluate(device const float2 *texcoords [[buffer(0)]], constant float4 *parameters [[buffer(1)]],
                                       device float4 *out [[buffer(2)]], uint id [[thread_position_in_grid]]) {
            out[id] = widen(\(functionName)(texcoords[id], parameters));
        }
        """
    }
}
