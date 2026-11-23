import Foundation
import Metal
import MetalSprocketsMaterialX
import simd
import Testing

/// A direct Swift transcription of MaterialX's mx_noise.glsl hash and 2D Perlin noise, to check the Metal port.
enum ReferenceNoise {
    static func rotl(_ x: UInt32, _ k: UInt32) -> UInt32 { (x << k) | (x >> (32 - k)) }

    static func bjfinal(_ a0: UInt32, _ b0: UInt32, _ c0: UInt32) -> UInt32 {
        var a = a0, b = b0, c = c0
        c ^= b; c &-= rotl(b, 14)
        a ^= c; a &-= rotl(c, 11)
        b ^= a; b &-= rotl(a, 25)
        c ^= b; c &-= rotl(b, 16)
        a ^= c; a &-= rotl(c, 4)
        b ^= a; b &-= rotl(a, 14)
        c ^= b; c &-= rotl(b, 24)
        return c
    }

    static func hash(_ x: Int32, _ y: Int32) -> UInt32 {
        let seed = 0xdead_beef &+ (2 << 2) &+ 13 as UInt32
        return bjfinal(seed &+ UInt32(bitPattern: x), seed &+ UInt32(bitPattern: y), seed)
    }

    static func cellNoise(_ p: SIMD2<Float>) -> Float {
        Float(hash(Int32(p.x.rounded(.down)), Int32(p.y.rounded(.down)))) / Float(UInt32.max)
    }

    static func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    static func gradient(_ hash: UInt32, _ x: Float, _ y: Float) -> Float {
        let h = hash & 7
        let u = h < 4 ? x : y
        let v = 2 * (h < 4 ? y : x)
        return (h & 1 != 0 ? -u : u) + (h & 2 != 0 ? -v : v)
    }

    static func perlin(_ p: SIMD2<Float>) -> Float {
        let x = Int32(p.x.rounded(.down)), y = Int32(p.y.rounded(.down))
        let fx = p.x - Float(x), fy = p.y - Float(y)
        let u = fade(fx), v = fade(fy)
        let v0 = gradient(hash(x, y), fx, fy), v1 = gradient(hash(x + 1, y), fx - 1, fy)
        let v2 = gradient(hash(x, y + 1), fx, fy - 1), v3 = gradient(hash(x + 1, y + 1), fx - 1, fy - 1)
        let s1 = 1 - u
        return 0.6616 * ((1 - v) * (v0 * s1 + v1 * u) + v * (v2 * s1 + v3 * u))
    }
}

/// #67: Perlin, fractal and cell noise.
@Suite(.serialized)
struct NoiseTests {
    static let samples: [SIMD2<Float>] = [[0.3, 0.7], [1.25, -2.5], [10.1, 3.9], [-0.75, -0.2], [123.4, 56.7]]

    func evaluate(_ node: String, type: String = "float", at texcoords: [SIMD2<Float>] = samples) throws -> [SIMD4<Float>] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let xml = "<materialx version=\"1.39\"><nodegraph name=\"g\">\(node)<output name=\"out\" type=\"\(type)\" nodename=\"n\" /></nodegraph></materialx>"
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let graph = try #require(try MaterialXDocument(data: Data(xml.utf8)).nodeGraph("g"))
        return try stitcher.stitch(graph, functionName: "noise_test").evaluate(at: texcoords)
    }

    @Test func cellNoiseMatchesTheReferenceHash() throws {
        let values = try evaluate("<cellnoise2d name=\"n\" type=\"float\" />").map(\.x)
        for (value, sample) in zip(values, Self.samples) {
            #expect(value == ReferenceNoise.cellNoise(sample), "\(sample)")
        }
    }

    @Test func perlinNoiseMatchesTheReference() throws {
        let values = try evaluate("<noise2d name=\"n\" type=\"float\" />").map(\.x)
        for (value, sample) in zip(values, Self.samples) {
            #expect(abs(value - ReferenceNoise.perlin(sample)) < 1e-6, "\(sample): \(value) vs \(ReferenceNoise.perlin(sample))")
        }
        // Gradient noise is zero on the integer lattice.
        #expect(try evaluate("<noise2d name=\"n\" type=\"float\" />", at: [[3, 4]]).first?.x == 0)
    }

    @Test func amplitudePivotAndFractalOctaves() throws {
        let plain = try evaluate("<noise2d name=\"n\" type=\"float\" />").map(\.x)
        let scaled = try evaluate("<noise2d name=\"n\" type=\"float\"><input name=\"amplitude\" type=\"float\" value=\"2\" /><input name=\"pivot\" type=\"float\" value=\"0.5\" /></noise2d>").map(\.x)
        for (a, b) in zip(plain, scaled) {
            #expect(abs(b - (a * 2 + 0.5)) < 1e-6)
        }
        // One octave of fractal noise is plain noise.
        let oneOctave = try evaluate("<fractal2d name=\"n\" type=\"float\"><input name=\"octaves\" type=\"integer\" value=\"1\" /></fractal2d>").map(\.x)
        for (a, b) in zip(plain, oneOctave) {
            #expect(abs(a - b) < 1e-6)
        }
    }

    @Test func everyNoiseNodeDefIsSupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        let names = StandardLibrary.shared.nodeDefs.keys.filter { ["ND_noise2d_", "ND_noise3d_", "ND_fractal2d_", "ND_fractal3d_", "ND_cellnoise2d_", "ND_cellnoise3d_"].contains(where: $0.hasPrefix) }
        #expect(names.count == 46)
        let missing = names.filter { coverage[$0] == .unsupported }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }
}
