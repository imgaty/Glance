//
//  BackdropTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/11/2026.
//

import Testing
import simd

@testable import Glance

@Suite("Artwork backdrop")
struct BackdropTests {
    @Test("The subdivided meshes agree with Core Animation's own subdivision of Apple's grids")
    func nativeMesh() {
        // Measured with CAMeshTransform's subdividedMesh(2) on macOS 27.3's control grids.
        let wide = BackdropMesh.make(variant: 0, wide: true)
        #expect(wide.vertices.count == 33 * 33)
        #expect(wide.indices.count == 32 * 32 * 6)
        let middle = try! #require(wide.vertices.first { abs($0.uv.x - 0.5) < 1e-6 && abs($0.uv.y - 0.5) < 1e-6 })
        #expect(abs(middle.from.x - 0.00312499935) < 1e-5 && abs(middle.from.y - 0.00312499935) < 1e-5)
        #expect(abs(middle.to.x - -0.0276798774) < 1e-5 && abs(middle.to.y - 0.058269728) < 1e-5)
        let compact = BackdropMesh.make(variant: 0, wide: false)
        #expect(compact.vertices.count == 21 * 21)
        #expect(compact.indices.count == 20 * 20 * 6)
        let inside = try! #require(compact.vertices.first { abs($0.uv.x - 0.3) < 1e-6 && abs($0.uv.y - 0.4) < 1e-6 })
        #expect(abs(inside.from.x - -0.35871613) < 1e-5 && abs(inside.from.y - -0.0805177838) < 1e-5)
        #expect(abs(inside.to.x - -0.339135289) < 1e-5 && abs(inside.to.y - 0.0835218802) < 1e-5)
        let other = try! #require(BackdropMesh.make(variant: 2, wide: true).vertices.first { abs($0.uv.x - 0.4375) < 1e-6 && abs($0.uv.y - 0.3125) < 1e-6 })
        #expect(abs(other.to.x - -0.42196238) < 1e-5 && abs(other.to.y - -0.495308697) < 1e-5)
        for mesh in [wide, compact] {
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
            #expect(mesh.vertices.contains { $0.uv == SIMD2(0, 0) && $0.from == SIMD2(-1, -1) })
        }
    }

    @MainActor
    @Test("A wide background renders in its own proportions, with the wide mesh")
    func proportions() throws {
        let renderer = try #require(ArtworkBackdrop(variant: 0, aspect: 2.5))
        #expect(renderer.wide)
        let motion = BackdropMotion()
        let uniforms = motion.uniforms(aspect: 2.5, exciting: true, size: (renderer.width, renderer.height))
        let image = try #require(renderer.frame(cover: ArtworkFlowTests.solid(0.8, 0.2, 0.1), previous: nil, uniforms: uniforms, blurSigma: 4))
        #expect(image.width == 200)
        #expect(image.height == 80)
        #expect(try #require(ArtworkBackdrop(variant: 0, aspect: 0.8)).wide == false)
    }

    @Test("The uniforms are laid out byte for byte as Apple's")
    func uniformsLayout() {
        var u = ArtworkBackdrop.Uniforms()
        u.time = 1.5
        u.saturation = 2.4
        u.blackScrim = 0.5
        u.spectrum = SIMD4(0.1, 0.2, 0.3, 0.4)
        let bytes = u.bytes
        #expect(bytes.count == 368)
        func float(_ offset: Int) -> Float { bytes.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Float.self) } }
        func short(_ offset: Int) -> Int16 { bytes.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int16.self) } }
        #expect(float(0) == 1.5 && float(340) == 2.4 && float(348) == 0.5 && float(352) == 0.1 && float(364) == 0.4)
        // The copies: the large one turning alone in 120, the small ones in 70 and 90, the last carried by the first.
        #expect(float(80) == 1.4 && short(144) == -1 && float(148) == 120)
        #expect(float(160) == 0.7 && float(160 + 48) == -0.25 && float(160 + 52) == 0.15 && short(224) == -1 && float(228) == 70)
        #expect(float(240 + 48) == 0.7 && float(240 + 52) == 0.7 && short(304) == 0 && float(308) == 90)
    }

    @Test("Apple's clock runs at half speed, ten times slower again with Reduce Motion, and the warp and fade follow it")
    func motion() {
        var motion = BackdropMotion()
        let silence = [SIMD4<Float>](repeating: .zero, count: 4)
        // A second of Apple's frames: half a second of its clock.
        for _ in 0..<30 { motion.advance(reduceMotion: false, exciting: true, wide: true, recent: silence) }
        #expect(abs(motion.time - 0.5) < 1e-4)
        // The warp's come in over 0.8 seconds, the blur's moved a point a frame toward its 120.
        #expect(motion.mode == 1)
        #expect(motion.blur == 110)
        let u = motion.uniforms(aspect: 3, exciting: true, size: (200, 67))
        #expect(abs(u.warp - (sin(0.5 / 3.5) + 1) / 2) < 1e-5)
        #expect(u.pinch == 1 && u.saturation == 2.4 && u.blackScrim == 0.5 && u.whiteScrim == 0.1 && u.downsample == 4)
        #expect(u.view.columns.1.y == 3 && u.view.columns.0.x == 1)
        var reduced = BackdropMotion()
        for _ in 0..<30 { reduced.advance(reduceMotion: true, exciting: true, wide: true, recent: silence) }
        #expect(abs(reduced.time - 0.05) < 1e-5)
        // Without lyrics: flat, more saturated and blurred, as Apple's is behind the cover.
        #expect(BackdropMotion.look(wide: true, exciting: false) == (2.9, 200))
        #expect(BackdropMotion.look(wide: false, exciting: true) == (2.0, 85))
        // A new cover fades in over 0.8 seconds on Core Animation's (0, 0, 0.3, 1).
        motion.newCover()
        for _ in 0..<12 { motion.advance(reduceMotion: false, exciting: true, wide: true, recent: silence) }
        let fading = motion.uniforms(aspect: 3, exciting: true, size: (200, 67)).textureMix
        #expect(abs(motion.fade - 0.5) < 1e-4)
        #expect(abs(fading - BackdropMotion.fadeCurve.value(at: 0.5)) < 1e-6 && fading > 0.75)
    }

    @Test("Timing curves solve as Core Animation's do")
    func curves() {
        #expect(abs(BackdropMotion.modeCurve.value(at: 0.5) - 0.5) < 1e-4)
        #expect(BackdropMotion.modeCurve.value(at: 0) == 0 && abs(BackdropMotion.modeCurve.value(at: 1) - 1) < 1e-5)
        // Core Animation's ease in and out at a quarter: 0.129.
        #expect(abs(BackdropMotion.modeCurve.value(at: 0.25) - 0.1291) < 0.002)
    }

    @Test("The music's bass swells the copies, as Apple's shader does")
    func pulse() {
        var motion = BackdropMotion()
        let hit = [SIMD4<Float>](repeating: SIMD4(0.9, 0.2, 0.05, 1), count: 4)
        for _ in 0..<10 { motion.advance(reduceMotion: false, exciting: true, wide: true, recent: hit) }
        let shown = motion.uniforms(aspect: 3, exciting: true, size: (200, 67)).spectrum
        #expect(shown.x > 0.95)
        let bass = shown.x * 0.9 + shown.y * 0.1
        // Up to a third larger at a full bass.
        #expect(abs((1 + 0.33 * bass * bass) - 1.27) < 0.05)
    }

    @Test("A hidden or paused background resumes its phase without a wall-clock jump")
    func clock() {
        var clock = ArtworkFlowClock()
        #expect(clock.read(at: 815_000_000) == 0)
        #expect(abs(clock.read(at: 815_000_000.1) - 0.1) < 0.000001)
        let paused = clock.elapsed
        #expect(clock.read(at: 815_000_100) == paused)
        #expect(abs(clock.read(at: 815_000_100.1) - 0.2) < 0.000001)
        #expect(clock.read(at: 0) == clock.elapsed)
        clock.hold(at: 815_000_200)
        #expect(abs(clock.read(at: 815_000_200.1) - 0.3) < 0.000001)
    }

    @Test("Apple's color table is read from macOS, holding back pure reds and blues")
    func colorTable() {
        let table = ArtworkBackdrop.colorTableBytes()
        #expect(table.count == 32 * 32 * 32 * 4)
        func entry(_ r: Int, _ g: Int, _ b: Int) -> (UInt8, UInt8, UInt8) {
            let offset = ((b * 32 + g) * 32 + r) * 4
            return (table[offset], table[offset + 1], table[offset + 2])
        }
        #expect(entry(16, 16, 16) == (132, 132, 132))
        #expect(entry(31, 0, 0) == (177, 14, 15))
        #expect(entry(0, 0, 31) == (9, 9, 181))
        #expect(entry(0, 31, 0) == (0, 254, 0))
    }
}
