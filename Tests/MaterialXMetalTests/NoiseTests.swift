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

/// #70: random nodes are deterministic per input and seed and stay in range.
@Suite(.serialized)
struct RandomNodeTests {
    func evaluate(_ node: String, type: String) throws -> SIMD4<Float> {
        try #require(try NoiseTests().evaluate(node, type: type, at: [.zero]).first)
    }

    @Test func randomFloatIsDeterministicAndInRange() throws {
        let node = { (input: String, seed: String) in
            "<randomfloat name=\"n\" type=\"float\"><input name=\"in\" type=\"float\" value=\"\(input)\" /><input name=\"min\" type=\"float\" value=\"2\" /><input name=\"max\" type=\"float\" value=\"3\" /><input name=\"seed\" type=\"integer\" value=\"\(seed)\" /></randomfloat>"
        }
        let a = try evaluate(node("1.5", "7"), type: "float").x
        #expect(try evaluate(node("1.5", "7"), type: "float").x == a)
        #expect((2...3).contains(a))
        let others = try ["2.5", "9.5", "-4.5"].map { try evaluate(node($0, "7"), type: "float").x }
        #expect(others.contains { $0 != a })
        #expect(try evaluate(node("1.5", "8"), type: "float").x != a)
    }

    @Test func randomColorStaysInItsHSVRanges() throws {
        let value = try evaluate("""
        <randomcolor name="n" type="color3">
          <input name="in" type="float" value="3.5" />
          <input name="saturationlow" type="float" value="0" /><input name="saturationhigh" type="float" value="0" />
          <input name="brightnesslow" type="float" value="0.5" /><input name="brightnesshigh" type="float" value="0.5" />
        </randomcolor>
        """, type: "color3")
        // Zero saturation at brightness 0.5 is gray 0.5 whatever the random hue.
        #expect(simd_distance(SIMD3(value.x, value.y, value.z), [0.5, 0.5, 0.5]) < 1e-6, "\(value)")
    }

    @Test func everyRandomNodeDefIsSupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        for name in ["ND_randomfloat_float", "ND_randomfloat_integer", "ND_randomcolor_float", "ND_randomcolor_integer", "ND_ceil_integer", "ND_floor_integer", "ND_round_integer"] {
            #expect(coverage[name] != .unsupported, "\(name)")
        }
    }
}

extension ReferenceNoise {
    static func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> UInt32 {
        let seed = 0xdead_beef &+ (3 << 2) &+ 13 as UInt32
        return bjfinal(seed &+ UInt32(bitPattern: x), seed &+ UInt32(bitPattern: y), seed &+ UInt32(bitPattern: z))
    }

    static func bits(_ value: UInt32) -> Float { Float(value) / Float(UInt32.max) }

    /// MaterialX's mx_worley_noise_float/vec2 for 2D points, Euclidean, distance style.
    static func worley(_ p: SIMD2<Float>, jitter: Float) -> SIMD2<Float> {
        let cellX = Int32(p.x.rounded(.down)), cellY = Int32(p.y.rounded(.down))
        let local = SIMD2(p.x - Float(cellX), p.y - Float(cellY))
        var nearest = SIMD2<Float>(1e6, 1e6)
        for x in Int32(-1)...1 {
            for y in Int32(-1)...1 {
                let ix = x + cellX, iy = y + cellY
                var offset = SIMD2(bits(hash(ix, iy, 0)), bits(hash(ix, iy, 1)))
                offset = (offset - 0.5) * jitter + 0.5
                let diff = SIMD2(Float(x), Float(y)) + offset - local
                let distance = simd_dot(diff, diff)
                if distance < nearest.x {
                    nearest = SIMD2(distance, nearest.x)
                } else if distance < nearest.y {
                    nearest.y = distance
                }
            }
        }
        return nearest.squareRoot()
    }
}

/// #68: Worley and unified noise.
@Suite(.serialized)
struct WorleyNoiseTests {
    @Test func worleyDistancesMatchTheReference() throws {
        let values = try NoiseTests().evaluate("<worleynoise2d name=\"n\" type=\"vector2\"><input name=\"jitter\" type=\"float\" value=\"0.8\" /></worleynoise2d>", type: "vector2")
        for (value, sample) in zip(values, NoiseTests.samples) {
            let expected = ReferenceNoise.worley(sample, jitter: 0.8)
            #expect(simd_distance(SIMD2(value.x, value.y), expected) < 1e-5, "\(sample): \(value) vs \(expected)")
        }
    }

    @Test func solidStyleIsConstantInsideACell() throws {
        // Two points close together usually share the nearest feature point, so the solid value repeats.
        let node = "<worleynoise2d name=\"n\" type=\"float\"><input name=\"jitter\" type=\"float\" value=\"0\" /><input name=\"style\" type=\"integer\" value=\"1\" /></worleynoise2d>"
        // With zero jitter every feature point is a cell center, so points near (2.5, 3.5) share it.
        let values = try NoiseTests().evaluate(node, at: [[2.45, 3.5], [2.55, 3.52]]).map(\.x)
        #expect(values[0] == values[1])
        #expect((0...1).contains(values[0]))
    }

    @Test func everyWorleyAndUnifiedNodeDefIsSupported() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let coverage = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device)).coverage()
        let names = StandardLibrary.shared.nodeDefs.keys.filter { $0.hasPrefix("ND_worleynoise") || $0.hasPrefix("ND_unifiednoise") }
        #expect(names.count == 8)
        let missing = names.filter { coverage[$0] == .unsupported }.sorted()
        #expect(missing.isEmpty, "\(missing)")
    }
}
