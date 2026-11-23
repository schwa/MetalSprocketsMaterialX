import CoreGraphics
import Foundation
import GoldenImage
import ImageIO
import Metal
import MetalSprockets
import MetalSprocketsMaterialX
import simd
import Testing
import UniformTypeIdentifiers

/// #47: rendered materials compared with golden images (GoldenImage), as #47-Q1 chose: one flat unlit quad per test
/// material, drawn with MaterialXUnlitSurface. Record new or changed images with `MX_RECORD_GOLDEN=1`.
@MainActor
@Suite(.serialized)
struct GoldenImageTests {
    static let psnrThreshold = 40.0
    static let goldenDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/Golden Images")

    /// Test materials: each a nodegraph `g` with a color3 output, covering different node families.
    nonisolated static let materials: [(name: String, body: String)] = [
        ("uv-gradient", """
        <texcoord name="uv" type="vector2" />
        <convert name="n" type="color3" nodedef="ND_convert_vector2_color3"><input name="in" type="vector2" nodename="uv" /></convert>
        """),
        ("checker", """
        <texcoord name="uv" type="vector2" />
        <multiply name="scaled" type="vector2"><input name="in1" type="vector2" nodename="uv" /><input name="in2" type="float" value="4" /></multiply>
        <floor name="cells" type="vector2"><input name="in" type="vector2" nodename="scaled" /></floor>
        <dotproduct name="sum" type="float"><input name="in1" type="vector2" nodename="cells" /><input name="in2" type="vector2" value="1, 1" /></dotproduct>
        <modulo name="parity" type="float"><input name="in1" type="float" nodename="sum" /><input name="in2" type="float" value="2" /></modulo>
        <mix name="n" type="color3">
          <input name="fg" type="color3" value="0.9, 0.85, 0.7" /><input name="bg" type="color3" value="0.1, 0.15, 0.3" />
          <input name="mix" type="float" nodename="parity" />
        </mix>
        """),
        ("hsv-sweep", """
        <texcoord name="uv" type="vector2" />
        <separate2 name="parts" type="multioutput"><input name="in" type="vector2" nodename="uv" /></separate2>
        <combine3 name="hsv" type="color3">
          <input name="in1" type="float" nodename="parts" output="outx" />
          <input name="in2" type="float" nodename="parts" output="outy" />
          <input name="in3" type="float" value="1" />
        </combine3>
        <hsvtorgb name="n" type="color3"><input name="in" type="color3" nodename="hsv" /></hsvtorgb>
        """),
        ("srgb-decode", """
        <texcoord name="uv" type="vector2" />
        <extract name="u" type="float"><input name="in" type="vector2" nodename="uv" /><input name="index" type="integer" value="0" /></extract>
        <convert name="gray" type="color3"><input name="in" type="float" nodename="u" /></convert>
        <srgb_texture_to_lin_rec709 name="n" type="color3"><input name="in" type="color3" nodename="gray" /></srgb_texture_to_lin_rec709>
        """),
    ]

    static let quad: [Float] = [
        -1, -1, 0, 0, 0, 1, 0, 0,
        1, -1, 0, 0, 0, 1, 1, 0,
        -1, 1, 0, 0, 0, 1, 0, 1,
        1, 1, 0, 0, 0, 1, 1, 1,
    ]

    func render(_ body: String) throws -> CGImage {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(body)<output name=\"out\" type=\"color3\" nodename=\"n\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let graph = try stitcher.stitch(try #require(MaterialXDocument(data: Data(xml.utf8)).nodeGraph("g")), functionName: "golden_material")
        let buffer = try #require(device.makeBuffer(bytes: Self.quad, length: MemoryLayout<Float>.stride * Self.quad.count))
        var uniforms = MXUnlitUniforms()
        uniforms.modelViewProjection = matrix_identity_float4x4
        uniforms.model = matrix_identity_float4x4
        uniforms.normalMatrix = matrix_identity_float3x3
        uniforms.cameraPosition = [0, 0, 1]
        let content = try RenderPass {
            try MaterialXUnlitSurface(graph: graph, uniforms: uniforms) {
                Draw { $0.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4) }
                    .vertexBuffer(buffer, index: 0)
            }
        }
        return try OffscreenRenderer(size: CGSize(width: 128, height: 128)).render(content).cgImage
    }

    func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test(arguments: materials.map(\.name))
    func materialMatchesGolden(name: String) throws {
        let body = try #require(Self.materials.first { $0.name == name }?.body)
        let image = try render(body)
        if ProcessInfo.processInfo.environment["MX_RECORD_GOLDEN"] != nil {
            try FileManager.default.createDirectory(at: Self.goldenDirectory, withIntermediateDirectories: true)
            try writePNG(image, to: Self.goldenDirectory.appendingPathComponent("\(name).png"))
            return
        }
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Golden Images")
        let outcome = try GoldenImageComparison(imageDirectory: directory, psnrThreshold: Self.psnrThreshold).compare(image: image, toGoldenImageNamed: name)
        #expect(outcome.isMatch, "PSNR \(outcome.psnr); render at \(outcome.savedImageURL?.path ?? "-")")
    }

    /// Guards against a threshold so loose that any render passes.
    @Test func differentMaterialDoesNotMatch() throws {
        let image = try render(try #require(Self.materials.first { $0.name == "checker" }?.body))
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Golden Images")
        let outcome = try GoldenImageComparison(imageDirectory: directory, psnrThreshold: Self.psnrThreshold).compare(image: image, toGoldenImageNamed: "uv-gradient")
        #expect(!outcome.isMatch)
    }
}
