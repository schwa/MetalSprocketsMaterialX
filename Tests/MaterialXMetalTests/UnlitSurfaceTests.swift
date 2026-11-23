import CoreGraphics
import Foundation
import Metal
import MetalSprockets
import MetalSprocketsMaterialX
import simd
import Testing

/// #41: MaterialXUnlitSurface draws a stitched graph's color.
@MainActor
@Suite(.serialized)
struct UnlitSurfaceTests {
    static let source = """
    <materialx version="1.39"><nodegraph name="g">
      <input name="tint" type="color3" value="1, 0, 0" />
      <texcoord name="uv" type="vector2" />
      <extract name="u" type="float"><input name="in" type="vector2" nodename="uv" /><input name="index" type="integer" value="0" /></extract>
      <ifgreater name="n" type="color3">
        <input name="value1" type="float" nodename="u" />
        <input name="value2" type="float" value="0.5" />
        <input name="in1" type="color3" interfacename="tint" />
        <input name="in2" type="color3" value="0, 0, 1" />
      </ifgreater>
      <output name="out" type="color3" nodename="n" />
    </nodegraph></materialx>
    """

    /// A quad covering clip space, interleaved position, normal, texcoord.
    static let quad: [Float] = [
        -1, -1, 0, 0, 0, 1, 0, 0,
        1, -1, 0, 0, 0, 1, 1, 0,
        -1, 1, 0, 0, 0, 1, 0, 1,
        1, 1, 0, 0, 0, 1, 1, 1,
    ]

    func render(_ graph: StitchedGraph) throws -> CGImage {
        let device = graph.library.device
        let buffer = try #require(device.makeBuffer(bytes: Self.quad, length: MemoryLayout<Float>.stride * Self.quad.count))
        let uniforms = MXUnlitUniforms(model: matrix_identity_float4x4)
        let content = try RenderPass {
            try MaterialXUnlitSurface(graph: graph, uniforms: uniforms) {
                Draw { $0.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4) }
                    .vertexBuffer(buffer, index: 0)
            }
        }
        return try OffscreenRenderer(size: CGSize(width: 8, height: 8)).render(content).cgImage
    }

    func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return bytes
    }

    @Test func drawsTheGraphColorAndFollowsParameterEdits() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        var graph = try stitcher.stitch(try #require(MaterialXDocument(data: Data(Self.source.utf8)).nodeGraph("g")), functionName: "materialx_unlit_test")
        let image = try render(graph)
        // u < 0.5 on the left: blue; right: tint (red).
        #expect(try pixel(image, x: 1, y: 4) == [0, 0, 255, 255])
        #expect(try pixel(image, x: 6, y: 4) == [255, 0, 0, 255])

        try graph.set("tint", to: SIMD3<Float>(0, 1, 0))
        #expect(try pixel(render(graph), x: 6, y: 4) == [0, 255, 0, 255])
    }
}
