import Foundation
import Metal
import MetalSprocketsMaterialX
import Testing

/// #28: stitch cost, pipeline link cost and GPU time of stitched graphs, against the same math written by hand.
/// Prints a table; run with `MX_STITCHING_TIMINGS=1`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MX_STITCHING_TIMINGS"] != nil))
struct StitchingPerformanceTests {
    static let threadCount = 1 << 20

    /// A chain of `count` nodes alternating multiply and add on a color, starting from the texture coordinate.
    static func graph(count: Int) -> (xml: String, metal: String) {
        var nodes = "<texcoord name=\"uv\" type=\"vector2\" /><convert name=\"n0\" type=\"color3\" nodedef=\"ND_convert_vector2_color3\"><input name=\"in\" type=\"vector2\" nodename=\"uv\" /></convert>"
        var metal = "float3 v = float3(texcoord, 0);\n"
        for index in 1...count {
            let category = index.isMultiple(of: 2) ? "add" : "multiply"
            let constant = 1.0 + Float(index % 7) * 0.001
            nodes += "<\(category) name=\"n\(index)\" type=\"color3\"><input name=\"in1\" type=\"color3\" nodename=\"n\(index - 1)\" /><input name=\"in2\" type=\"float\" value=\"\(constant)\" /></\(category)>"
            metal += "    v = v \(category == "add" ? "+" : "*") \(constant);\n"
        }
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(nodes)<output name=\"out\" type=\"color3\" nodename=\"n\(count)\" /></nodegraph></materialx>"
        return (xml, metal)
    }

    static let kernel = """
    #include <metal_stdlib>
    using namespace metal;
    [[visible]] float3 materialx_graph(float2 texcoord, constant float4 *parameters);
    kernel void evaluate(device float4 *out [[buffer(0)]], constant float4 *parameters [[buffer(1)]], uint id [[thread_position_in_grid]]) {
        out[id] = float4(materialx_graph(float2(id & 1023, id >> 10) / 1024.0, parameters), 1);
    }
    """

    /// Calls the graph through a visible function table, as MetalSprockets' `.binary` linking does. Binary functions
    /// cannot satisfy a direct `[[visible]]` call ("unresolved visible function reference").
    static let tableKernel = """
    #include <metal_stdlib>
    using namespace metal;
    using Graph = float3(float2, constant float4 *);
    kernel void evaluate(device float4 *out [[buffer(0)]], constant float4 *parameters [[buffer(1)]],
                         visible_function_table<Graph> table [[buffer(2)]], uint id [[thread_position_in_grid]]) {
        out[id] = float4(table[0](float2(id & 1023, id >> 10) / 1024.0, parameters), 1);
    }
    """

    static func handWritten(_ body: String) -> String {
        """
        #include <metal_stdlib>
        using namespace metal;
        kernel void evaluate(device float4 *out [[buffer(0)]], constant float4 *parameters [[buffer(1)]], uint id [[thread_position_in_grid]]) {
            float2 texcoord = float2(id & 1023, id >> 10) / 1024.0;
            \(body)    out[id] = float4(v, 1);
        }
        """
    }

    func gpuMilliseconds(_ pipeline: MTLComputePipelineState, parameters: [SIMD4<Float>], table: MTLVisibleFunctionTable? = nil, device: MTLDevice) throws -> Double {
        let output = try #require(device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * Self.threadCount, options: .storageModePrivate))
        // Pad to one slot: Metal rejects zero-length buffers, and copying 16 bytes from an empty array over-reads.
        let padded = parameters.isEmpty ? [SIMD4<Float>.zero] : parameters
        let parameterBuffer = try #require(device.makeBuffer(bytes: padded, length: MemoryLayout<SIMD4<Float>>.stride * padded.count))
        let queue = try #require(device.makeCommandQueue())
        var times: [Double] = []
        for _ in 0..<20 {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(output, offset: 0, index: 0)
            encoder.setBuffer(parameterBuffer, offset: 0, index: 1)
            if let table {
                encoder.setVisibleFunctionTable(table, bufferIndex: 2)
            }
            encoder.dispatchThreads(MTLSize(width: Self.threadCount, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            times.append((commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000)
        }
        return times.sorted()[times.count / 2]
    }

    func milliseconds<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = ContinuousClock.now
        let result = try body()
        let elapsed = ContinuousClock.now - start
        return (result, Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000)
    }

    @Test func timings() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let kernelLibrary = try device.makeLibrary(source: Self.kernel, options: nil)
        let kernelFunction = try #require(kernelLibrary.makeFunction(name: "evaluate"))
        let tableFunction = try #require(try device.makeLibrary(source: Self.tableKernel, options: nil).makeFunction(name: "evaluate"))
        var rows = ["nodes | stitch ms | link private ms | link binary+table ms | GPU private ms | GPU binary+table ms | GPU hand-written ms"]
        for count in [10, 50, 200] {
            let (xml, body) = Self.graph(count: count)
            let document = try Document(data: Data(xml.utf8))
            let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
            let (stitched, stitchTime) = try milliseconds { try stitcher.stitch(try #require(document.nodeGraph("g")), functionName: "materialx_graph") }

            let (privatePipeline, privateLink) = try milliseconds {
                let descriptor = MTLComputePipelineDescriptor()
                descriptor.computeFunction = kernelFunction
                let linked = MTLLinkedFunctions()
                linked.privateFunctions = [stitched.function]
                descriptor.linkedFunctions = linked
                return try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
            }
            let ((binaryPipeline, table), binaryLink) = try milliseconds {
                let functionDescriptor = MTLFunctionDescriptor()
                functionDescriptor.name = stitched.functionName
                functionDescriptor.options = .compileToBinary
                let binary = try stitched.library.makeFunction(descriptor: functionDescriptor)
                let descriptor = MTLComputePipelineDescriptor()
                descriptor.computeFunction = tableFunction
                let linked = MTLLinkedFunctions()
                linked.binaryFunctions = [binary]
                descriptor.linkedFunctions = linked
                let pipeline = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
                let tableDescriptor = MTLVisibleFunctionTableDescriptor()
                tableDescriptor.functionCount = 1
                let table = try #require(pipeline.makeVisibleFunctionTable(descriptor: tableDescriptor))
                table.setFunction(try #require(pipeline.functionHandle(function: binary)), index: 0)
                return (pipeline, table)
            }
            let handLibrary = try device.makeLibrary(source: Self.handWritten(body), options: nil)
            let handPipeline = try device.makeComputePipelineState(function: try #require(handLibrary.makeFunction(name: "evaluate")))

            let row = [
                "\(count)",
                String(format: "%.2f", stitchTime),
                String(format: "%.2f", privateLink),
                String(format: "%.2f", binaryLink),
                String(format: "%.3f", try gpuMilliseconds(privatePipeline, parameters: stitched.parameterData, device: device)),
                String(format: "%.3f", try gpuMilliseconds(binaryPipeline, parameters: stitched.parameterData, table: table, device: device)),
                String(format: "%.3f", try gpuMilliseconds(handPipeline, parameters: [], device: device)),
            ]
            rows.append(row.joined(separator: " | "))
        }
        print(rows.joined(separator: "\n"))
    }
}
