//
//  BackdropTests.swift
//  GlanceTests
//
//  Created by Gaty on 10/11/2026.
//

import Testing

@testable import Glance

@Suite("Artwork backdrop")
struct BackdropTests {
    @Test("The subdivided mesh agrees with captured native vertices")
    func nativeMesh() {
        let mesh = BackdropMesh.make(variant: 0)
        #expect(mesh.vertices.count == 1681)
        #expect(mesh.indices.count == 9600)
        let sample = mesh.vertices[7]
        #expect(abs(sample.uv.x - 0.15) < 0.000001)
        #expect(abs(sample.from.x - (-0.818668)) < 0.000001)
        #expect(abs(sample.from.y - (-0.421210289)) < 0.000001)
        #expect(mesh.vertices[0].from == SIMD2(-1, -1))
        #expect(mesh.vertices[35].to == SIMD2(1, 1))
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
    }

    @MainActor
    @Test("A wide background renders in its own proportions")
    func proportions() throws {
        let renderer = try #require(ArtworkBackdrop(ArtworkFlowTests.solid(0.8, 0.2, 0.1), variant: 0, aspect: 2.5))
        let image = try #require(renderer.frame(at: 0))
        #expect(image.width == 200)
        #expect(image.height == 80)
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
    }
}
