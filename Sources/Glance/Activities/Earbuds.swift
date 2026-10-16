//
//  Earbuds.swift
//  Glance
//
//  Created by Gaty on 16/10/2026.
//

import AppKit
import SceneKit
import SwiftUI
import UniformTypeIdentifiers
import simd

/// AirPods that sit in the ear, modelled in 3D so they turn as the Dynamic Island turns them when
/// they connect: the pair side by side, the right earbud face on and the left one from behind, both
/// stems on the left. Each earbud is one smooth shape, its head and stem melted together, white,
/// with its black grilles, and AirPods Pro's silicone ear tip.
enum Earbuds: Hashable {
    /// AirPods Pro: a short stem and an ear tip.
    case pro
    /// AirPods 3 and 4: a rounder head, with no tip.
    case open
    /// AirPods 1 and 2: a small head on a long stem.
    case classic

    /// By the model's product ID, or the model macOS names for it; none for AirPods Max, Beats and
    /// the rest, which aren't earbuds of this shape.
    init?(product: Int) {
        switch product {
        case 0x200E, 0x2014, 0x2024, 0x2027: self = .pro
        case 0x2013, 0x2019, 0x201B: self = .open
        case 0x2002, 0x200F: self = .classic
        default:
            let tag = UTTagClass(rawValue: "com.apple.device-model-code")
            guard let model = UTType(tag: "Device1,\(product)", tagClass: tag, conformingTo: nil)?.identifier,
                model.contains("airpods"), !model.contains("airpods-max")
            else { return nil }
            self = model.contains("airpods-pro") ? .pro : .open
        }
    }

    /// The right earbud's shape, in millimetres, face on: its stem standing on the origin, its head
    /// reaching right, toward the ear, where the tip points.
    var shape: EarbudShape {
        switch self {
        case .pro:
            EarbudShape(
                stemTop: [0.4, 25, 0.3], stemRadius: 2.6, head: [8.4, 23.6, -0.4], headRadii: [9, 6.9, 7.8], headTilt: 18,
                tip: EarbudShape.Tip(direction: [0.8, -0.42, 0.55], reach: 8.2, drop: 1, length: 2.8, width: 5.2), spacing: 20)
        case .open:
            EarbudShape(
                stemTop: [0.4, 24, 0.3], stemRadius: 2.6, head: [8.4, 23.4, -0.4], headRadii: [9.2, 7.4, 8], headTilt: 16, tip: nil,
                spacing: 20)
        case .classic:
            EarbudShape(
                stemTop: [0.4, 33, 0.3], stemRadius: 2.4, head: [7.4, 33, -0.4], headRadii: [8.2, 7, 7.4], headTilt: 16, tip: nil,
                spacing: 19)
        }
    }
}

/// One earbud as distances to its surface: a stem, an oval in section, rounded at its end, melted
/// into an egg of a head; and the ear tip, apart, since it's silicone.
struct EarbudShape {
    struct Tip {
        /// Where it points, out of the head.
        var direction: SIMD3<Float>
        /// How far its middle is from the head's, out, and below it.
        var reach: Float
        var drop: Float
        /// Its half-length along where it points, and its half-width across.
        var length: Float
        var width: Float
    }

    var stemTop: SIMD3<Float>
    var stemRadius: Float
    var head: SIMD3<Float>
    var headRadii: SIMD3<Float>
    /// Degrees the head leans down toward the ear.
    var headTilt: Float
    var tip: Tip?
    /// Between the two stems, side by side.
    var spacing: Float
    /// How thick the stem is front to back, of its width.
    var stemDepth: Float = 0.85
    /// How softly the head and the stem melt together.
    var blend: Float = 4

    var height: Float { head.y + headRadii.y }

    func shell(_ p: SIMD3<Float>) -> Float {
        let lean = simd_quatf(angle: headTilt * .pi / 180, axis: [0, 0, 1])
        return Self.smoothUnion(stem(p), Self.ellipsoid(lean.act(p - head), headRadii), blend)
    }

    func stem(_ p: SIMD3<Float>) -> Float {
        let length = simd_length(stemTop)
        let axis = stemTop / length
        let along = simd_dot(p, axis)
        var across = p - axis * along
        across.z /= stemDepth
        let round: Float = 1.3
        let d = SIMD2<Float>(simd_length(across) - (stemRadius - round), abs(along - length / 2) - (length / 2 - round))
        return min(max(d.x, d.y), 0) + simd_length(simd_max(d, .zero)) - round
    }

    func tipDistance(_ p: SIMD3<Float>) -> Float {
        guard let tip else { return .greatestFiniteMagnitude }
        let axis = simd_normalize(tip.direction)
        let q = p - (head + axis * tip.reach - [0, tip.drop, 0])
        // A soft puck: flat across its end, round at its rim.
        let along = simd_dot(q, axis)
        let across = simd_length(q - axis * along)
        let round = tip.length * 0.75
        let d = SIMD2<Float>(across - (tip.width - round), abs(along) - (tip.length - round))
        return min(max(d.x, d.y), 0) + simd_length(simd_max(d, .zero)) - round
    }

    /// The black of the grilles, and the stem's end: by where a point is and which way it faces.
    func shade(at p: SIMD3<Float>, facing n: SIMD3<Float>) -> Float {
        // The vent at the top of the stem, facing out: a slot.
        let slot = SIMD2<Float>(max(abs(p.y - (stemTop.y - 4.6)) - 2.4, 0), p.z - 0.8)
        if n.x < -0.2, p.x < stemTop.x, simd_length(slot) < 1.3 { return 0.06 }
        // The microphone at the end of the stem.
        if p.y < 1.5 { return 0.3 }
        return 1
    }

    static func ellipsoid(_ p: SIMD3<Float>, _ r: SIMD3<Float>) -> Float {
        let k0 = simd_length(p / r), k1 = simd_length(p / (r * r))
        return k0 * (k0 - 1) / max(k1, 1e-6)
    }

    static func smoothUnion(_ a: Float, _ b: Float, _ k: Float) -> Float {
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
}

/// A surface, as triangles, found where distances to it cross zero on a grid: a point in each cell
/// the surface passes through, joined to its neighbours'.
struct SurfaceMesh {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    init(_ distance: (SIMD3<Float>) -> Float, from low: SIMD3<Float>, to high: SIMD3<Float>, cell: Float) {
        let count = SIMD3<Int>(((high - low) / cell).rounded(.up))
        let (nx, ny, nz) = (count.x, count.y, count.z)
        func point(_ i: Int, _ j: Int, _ k: Int) -> SIMD3<Float> { low + SIMD3<Float>(Float(i), Float(j), Float(k)) * cell }
        func corner(_ i: Int, _ j: Int, _ k: Int) -> Int { i + (nx + 1) * (j + (ny + 1) * k) }
        func cellIndex(_ i: Int, _ j: Int, _ k: Int) -> Int { i + nx * (j + ny * k) }

        var values = [Float](repeating: 0, count: (nx + 1) * (ny + 1) * (nz + 1))
        for k in 0...nz { for j in 0...ny { for i in 0...nx { values[corner(i, j, k)] = distance(point(i, j, k)) } } }

        // A point in each cell the surface crosses: where it crosses the cell's edges, on average,
        // then pulled onto it.
        let edges: [(Int, Int)] = (0..<8).flatMap { a in [1, 2, 4].filter { a & $0 == 0 }.map { (a, a | $0) } }
        var vertex = [Int32](repeating: -1, count: nx * ny * nz)
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    var d = [Float](repeating: 0, count: 8)
                    var inside = 0
                    for c in 0..<8 {
                        d[c] = values[corner(i + c & 1, j + (c >> 1) & 1, k + (c >> 2) & 1)]
                        if d[c] < 0 { inside += 1 }
                    }
                    guard inside > 0, inside < 8 else { continue }
                    var sum = SIMD3<Float>.zero
                    var crossings: Float = 0
                    for (a, b) in edges where (d[a] < 0) != (d[b] < 0) {
                        let pa = point(i + a & 1, j + (a >> 1) & 1, k + (a >> 2) & 1)
                        let pb = point(i + b & 1, j + (b >> 1) & 1, k + (b >> 2) & 1)
                        sum += pa + (pb - pa) * (d[a] / (d[a] - d[b]))
                        crossings += 1
                    }
                    var p = sum / crossings
                    let g = Self.gradient(distance, at: p)
                    p -= g * distance(p) / max(simd_length_squared(g), 1e-6)
                    vertex[cellIndex(i, j, k)] = Int32(positions.count)
                    positions.append(p)
                    normals.append(simd_normalize(Self.gradient(distance, at: p)))
                }
            }
        }

        // Each grid edge the surface crosses joins the four cells around it, listed around the edge
        // so the quad faces along it, and turned to face out; split across its shorter diagonal, so
        // it never folds.
        func quad(_ cells: [(Int, Int, Int)], reversed: Bool) {
            var v = cells.map { vertex[cellIndex($0.0, $0.1, $0.2)] }
            guard v.allSatisfy({ $0 >= 0 }) else { return }
            if reversed { v.reverse() }
            let p = v.map { positions[Int($0)] }
            let corners = simd_distance_squared(p[0], p[2]) <= simd_distance_squared(p[1], p[3]) ? [0, 1, 2, 0, 2, 3] : [1, 2, 3, 1, 3, 0]
            indices += corners.map { UInt32(v[$0]) }
        }
        for k in 0...nz {
            for j in 0...ny {
                for i in 0...nx {
                    let here = values[corner(i, j, k)] < 0
                    if i < nx, j > 0, j < ny, k > 0, k < nz, here != (values[corner(i + 1, j, k)] < 0) {
                        quad([(i, j - 1, k - 1), (i, j, k - 1), (i, j, k), (i, j - 1, k)], reversed: !here)
                    }
                    // Around a vertical edge, the cells go the other way round.
                    if j < ny, i > 0, i < nx, k > 0, k < nz, here != (values[corner(i, j + 1, k)] < 0) {
                        quad([(i - 1, j, k - 1), (i, j, k - 1), (i, j, k), (i - 1, j, k)], reversed: here)
                    }
                    if k < nz, i > 0, i < nx, j > 0, j < ny, here != (values[corner(i, j, k + 1)] < 0) {
                        quad([(i - 1, j - 1, k), (i, j - 1, k), (i, j, k), (i - 1, j, k)], reversed: !here)
                    }
                }
            }
        }
    }

    static func gradient(_ distance: (SIMD3<Float>) -> Float, at p: SIMD3<Float>) -> SIMD3<Float> {
        let e: Float = 0.01
        return SIMD3<Float>(
            distance(p + [e, 0, 0]) - distance(p - [e, 0, 0]),
            distance(p + [0, e, 0]) - distance(p - [0, e, 0]),
            distance(p + [0, 0, e]) - distance(p - [0, 0, e])) / (2 * e)
    }

    /// Seen from behind: front and back swapped, which turns the faces inside out, so they're
    /// turned back.
    func mirroredFrontToBack() -> SurfaceMesh {
        var mirrored = self
        mirrored.positions = positions.map { [$0.x, $0.y, -$0.z] }
        mirrored.normals = normals.map { [$0.x, $0.y, -$0.z] }
        for t in stride(from: 0, to: indices.count, by: 3) { mirrored.indices.swapAt(t + 1, t + 2) }
        return mirrored
    }

    func geometry(colors: [SIMD4<Float>]? = nil, material: SCNMaterial) -> SCNGeometry {
        var sources = [
            SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
            SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) }),
        ]
        if let colors {
            let data = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            sources.append(
                SCNGeometrySource(
                    data: data, semantic: .color, vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4,
                    bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride))
        }
        let geometry = SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }
}

/// The pair turning, drawn once, a frame every few degrees of a full turn, so the notch only
/// shows pictures: a 3D scene never runs in it.
struct EarbudTurn {
    /// A full turn, from face on.
    let frames: [CGImage]
    /// The pair face on, in the frames' pixels: what the notch lays out.
    let rest: CGRect
    /// The frames' size, in pixels.
    let canvas: CGSize

    func frame(at degrees: Double) -> CGImage {
        let step = 360 / Double(frames.count)
        let index = Int((degrees / step).rounded()) % frames.count
        return frames[(index + frames.count) % frames.count]
    }

    @MainActor private static var turns: [Earbuds: EarbudTurn] = [:]

    @MainActor static func cached(_ earbuds: Earbuds) -> EarbudTurn? { turns[earbuds] }

    /// Draws the pair turning, away from the main thread, the first time it's needed.
    @MainActor static func prepare(_ earbuds: Earbuds) async -> EarbudTurn? {
        if let turn = turns[earbuds] { return turn }
        let turn = await Task.detached(priority: .userInitiated) { render(earbuds) }.value
        turns[earbuds] = turn
        return turn
    }

    /// Degrees each earbud of the pair is turned, face on.
    private static let yaw: Float = 45
    /// How many frames make a full turn.
    static let frameCount = 120
    /// The pair's height in the frames, in pixels: more than a notch shows it at on a 2× display.
    static let pixelHeight: CGFloat = 56

    static func render(_ earbuds: Earbuds) -> EarbudTurn? {
        let shape = earbuds.shape
        let reach = shape.tip.map { shape.head.x + $0.reach + $0.length + 1 } ?? shape.head.x + shape.headRadii.x + 1
        let low = SIMD3<Float>(-shape.stemRadius - 1, -1, -shape.headRadii.z - 2)
        let high = SIMD3<Float>(reach + 1, shape.height + 1, shape.headRadii.z + 4)
        let shell = SurfaceMesh(shape.shell, from: low, to: high, cell: 0.32)
        let tip = shape.tip == nil ? nil : SurfaceMesh(shape.tipDistance, from: low, to: high, cell: 0.32)
        guard !shell.indices.isEmpty else { return nil }

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = studio()
        scene.lightingEnvironment.intensity = 0.8

        let plastic = SCNMaterial()
        plastic.lightingModel = .physicallyBased
        plastic.diffuse.contents = NSColor(white: 0.96, alpha: 1)
        plastic.roughness.contents = 0.45
        plastic.metalness.contents = 0
        let silicone = SCNMaterial()
        silicone.lightingModel = .physicallyBased
        silicone.diffuse.contents = NSColor(white: 0.86, alpha: 1)
        silicone.roughness.contents = 0.7
        silicone.metalness.contents = 0

        // The right earbud on the left, face on; the left one beside it, from behind. Both turn a
        // little toward their stem, so their vents show.
        let gap = shape.spacing
        let pair = SCNNode()
        var restLow = SIMD2<Float>(repeating: .greatestFiniteMagnitude), restHigh = -restLow
        var radius: Float = 0
        for (mirrored, offset) in [(false, SIMD3<Float>(-gap / 2, 0, 2)), (true, [gap / 2, 0, -2])] {
            let turn = simd_quatf(angle: Self.yaw * .pi / 180, axis: [0, 1, 0])
            let parts = [Optional(shell), tip].compactMap { $0 }.map { mirrored ? $0.mirroredFrontToBack() : $0 }
            let bud = SCNNode()
            // The grilles where each shows face on, the vents beside the camera.
            let colors = zip(parts[0].positions, parts[0].normals).map { p, n in
                let shade = shape.shade(at: p, facing: n)
                return SIMD4<Float>(shade, shade, shade, 1)
            }
            bud.addChildNode(SCNNode(geometry: parts[0].geometry(colors: colors, material: plastic)))
            if parts.count > 1 { bud.addChildNode(SCNNode(geometry: parts[1].geometry(material: silicone))) }
            bud.simdOrientation = turn
            bud.simdPosition = offset
            pair.addChildNode(bud)
            // The pair face on: its box on screen, and how far it reaches from the middle as it turns.
            for part in parts {
                for local in part.positions {
                    let p = turn.act(local) + offset
                    restLow = simd_min(restLow, [p.x, p.y])
                    restHigh = simd_max(restHigh, [p.x, p.y])
                    radius = max(radius, simd_length(SIMD2(p.x, p.z)))
                }
            }
        }
        scene.rootNode.addChildNode(pair)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 750
        key.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(key)

        // Straight on, without perspective, so the frames line up by the pair's box.
        let margin: Float = 1.5
        let bottom = restLow.y - margin, top = restHigh.y + margin
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(top - bottom) / 2
        camera.camera?.zNear = 1
        camera.camera?.zFar = 200
        camera.position = SCNVector3(0, CGFloat(bottom + top) / 2, 100)
        scene.rootNode.addChildNode(camera)

        let scale = pixelHeight / CGFloat(restHigh.y - restLow.y)
        let canvas = CGSize(width: (CGFloat(radius + margin) * 2 * scale).rounded(.up), height: CGFloat(top - bottom) * scale)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        var frames: [CGImage] = []
        for index in 0..<frameCount {
            pair.eulerAngles.y = CGFloat(Double(index) / Double(frameCount) * 2 * .pi)
            let image = renderer.snapshot(atTime: 0, with: canvas, antialiasingMode: .multisampling4X)
            guard let frame = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            frames.append(frame)
        }
        let rest = CGRect(
            x: (CGFloat(restLow.x) + CGFloat(radius + margin)) * scale, y: CGFloat(top - restHigh.y) * scale,
            width: CGFloat(restHigh.x - restLow.x) * scale, height: pixelHeight)
        return EarbudTurn(frames: frames, rest: rest, canvas: canvas)
    }

    /// A photo studio's light, all around: bright above and in front, dark below.
    private static func studio() -> CGImage? {
        let width = 256, height = 128
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [CGColor(gray: 0.05, alpha: 1), CGColor(gray: 0.35, alpha: 1), CGColor(gray: 0.9, alpha: 1)] as CFArray,
            locations: [0, 0.45, 1])!
        // Bottom of the picture is below the floor.
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        // Two soft boxes: above in front, and to the left.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 4 - 20, y: height * 5 / 8, width: 40, height: 28))
        context.fill(CGRect(x: width / 8 - 10, y: height / 2 - 6, width: 20, height: 26))
        return context.makeImage()
    }
}
