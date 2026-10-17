//
//  Render.swift
//  DeviceClips
//
//  Created by Gaty on 17/10/2026.
//

import AppKit
import SceneKit

/// A device's turn, drawn from its maker's 3D model as the iPhone's Dynamic Island shows AirPods:
/// seen level, without perspective, on one disk turning about a middle a little behind earbuds, a
/// frame every degree and a half, face on first.
enum Render {
    /// How many frames make a full turn.
    static let frameCount = 240
    /// The device's height face on, in pixels: more than a notch shows it at on a 2× display.
    static let pixelHeight: CGFloat = 44
    static func turn(_ model: Model, from file: URL) -> [CGImage]? {
        guard let scene = try? SCNScene(url: file, options: [.checkConsistency: false]), let device = MTLCreateSystemDefaultDevice()
        else { return nil }
        let pair = SCNNode()
        switch model.kind {
        case .pair, .mirrored:
            guard var (left, right) = earbuds(in: scene.rootNode) else { return nil }
            if case .mirrored(let fromLeft) = model.kind {
                // Its mirror image across the middle, standing where the other would.
                let kept = fromLeft ? left : right
                let mirror = SCNNode()
                mirror.scale = SCNVector3(-1, 1, 1)
                mirror.addChildNode(kept.clone())
                let other = SCNNode()
                other.addChildNode(mirror)
                (left, right) = fromLeft ? (kept, other) : (other, kept)
            }
            // Side by side, as close as the iPhone stands AirPods, and level: some models float one
            // higher than the other above their case.
            let middles = [left, right].map { bud in
                let (low, high) = bud.boundingBox
                return (x: (low.x + high.x) / 2, y: (low.y + high.y) / 2)
            }
            let level = (middles[0].y + middles[1].y) / 2
            for (bud, middle) in zip([left, right], middles) {
                bud.position.x = middle.x * (model.spacing - 1)
                bud.position.y = level - middle.y
                pair.addChildNode(bud)
            }
        case .whole:
            for part in parts(of: scene.rootNode) {
                let copy = SCNNode(geometry: part.geometry)
                copy.transform = part.worldTransform
                pair.addChildNode(copy)
            }
        }

        let stage = SCNScene()
        stage.background.contents = NSColor.clear
        stage.lightingEnvironment.contents = studio()
        stage.lightingEnvironment.intensity = 1.5
        // The disk, turning about the device's middle.
        let spin = SCNNode()
        spin.addChildNode(pair)
        stage.rootNode.addChildNode(spin)
        let (low, high) = pair.boundingBox
        let middle = (x: (low.x + high.x) / 2, z: (low.z + high.z) / 2)
        pair.position = SCNVector3(-middle.x, 0, -middle.z)
        let reach = [low.x, high.x].flatMap { x in [low.z, high.z].map { z in hypot(x - middle.x, z - middle.z) } }.max() ?? 1

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 1000
        stage.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = stage
        renderer.pointOfView = camera
        func look(from bottom: CGFloat, to top: CGFloat) {
            camera.camera?.orthographicScale = Double(top - bottom) / 2
            camera.position = SCNVector3(0, (bottom + top) / 2, (reach + 10) * 4)
        }

        // The boxes of parts that lean are bigger than the parts, so it's measured face on, then
        // framed by how tall it really stands; turning about an upright axis, seen level, it stands
        // as tall all the way round.
        let probe = CGSize(width: (400 * reach * 2 / (high.y - low.y)).rounded(.up), height: 400)
        look(from: low.y, to: high.y)
        let seen = renderer.snapshot(atTime: 0, with: probe, antialiasingMode: .none).cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let seen, let shape = opaque(seen) else { return nil }
        let unit = (high.y - low.y) / probe.height
        let standing = (bottom: high.y - shape.maxY * unit, top: high.y - shape.minY * unit)
        let margin = (standing.top - standing.bottom) * 0.06
        let bottom = standing.bottom - margin, top = standing.top + margin
        look(from: bottom, to: top)

        // Earbuds stand a little in front of the middle they turn about, as the iPhone turns AirPods:
        // the pair drifts in and out by a fifth of its height as it turns.
        var turning = reach
        if case .whole = model.kind {} else {
            let forward = (standing.top - standing.bottom) * 0.19
            pair.position.z += forward
            turning = [low.x, high.x].flatMap { x in [low.z, high.z].map { z in hypot(x - middle.x, z - middle.z + forward) } }.max() ?? reach
        }
        let scale = pixelHeight / (standing.top - standing.bottom)
        // Even, as video wants.
        func even(_ x: CGFloat) -> CGFloat { (x / 2).rounded(.up) * 2 }
        let canvas = CGSize(width: even((turning + margin) * 2 * scale), height: even((top - bottom) * scale))
        // White AirPods lit as bright as the iPhone shows them: the models are made each their own
        // way, some brighter than others.
        if let target = model.brightness {
            for _ in 0..<2 {
                let shot = renderer.snapshot(atTime: 0, with: canvas, antialiasingMode: .multisampling4X)
                guard let level = shot.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(brightness) else { break }
                stage.lightingEnvironment.intensity *= min(max(pow(target / level, 2.2), 0.4), 3)
            }
        }
        // Each frame drawn twice as big and made smaller, so its edges and highlights are smooth.
        let big = CGSize(width: canvas.width * 2, height: canvas.height * 2)
        guard
            let small = CGContext(
                data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .high
        var frames: [CGImage] = []
        for index in 0..<frameCount {
            spin.eulerAngles.y = Double(index) / Double(frameCount) * 2 * .pi
            let image = renderer.snapshot(atTime: 0, with: big, antialiasingMode: .multisampling4X)
            guard let drawn = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            small.clear(CGRect(origin: .zero, size: canvas))
            small.draw(drawn, in: CGRect(origin: .zero, size: canvas))
            guard let frame = small.makeImage() else { return nil }
            frames.append(frame)
        }
        return frames
    }

    /// Every part of a model with something to draw, where it stands.
    private struct Part {
        let node: SCNNode
        let low: SCNVector3
        let high: SCNVector3
        var middle: SCNVector3 { SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2) }
        var size: CGFloat {
            let (x, y, z) = (high.x - low.x, high.y - low.y, high.z - low.z)
            return (x * x + y * y + z * z).squareRoot()
        }
    }

    private static func parts(of root: SCNNode) -> [SCNNode] {
        var found: [SCNNode] = []
        var nodes = [root]
        while let node = nodes.popLast() {
            nodes += node.childNodes
            if node.geometry != nil { found.append(node) }
        }
        return found
    }

    /// The two earbuds, each gathered from the model's parts where they stand. The models stand the
    /// case in the middle and the earbuds either side, but group their parts each their own way, and
    /// measure in centimetres or metres, so they're found by place: an earbud is every part off the
    /// middle on its side within reach of the biggest there, its shell; the case's own parts off the
    /// middle, such as a lanyard loop, are further away.
    static func earbuds(in root: SCNNode) -> (left: SCNNode, right: SCNNode)? {
        let parts = parts(of: root).map { node in
            let (low, high) = node.boundingBox
            let corners = [low.x, high.x].flatMap { x in
                [low.y, high.y].flatMap { y in [low.z, high.z].map { z in node.convertPosition(SCNVector3(x, y, z), to: nil) } }
            }
            return Part(
                node: node, low: SCNVector3(corners.map(\.x).min()!, corners.map(\.y).min()!, corners.map(\.z).min()!),
                high: SCNVector3(corners.map(\.x).max()!, corners.map(\.y).max()!, corners.map(\.z).max()!))
        }
        // Off the middle: by a twenty-fifth of the whole model's width, whatever it's measured in.
        guard let widest = parts.map(\.high.x).max(), let narrowest = parts.map(\.low.x).min() else { return nil }
        let off = (widest - narrowest) * 0.04
        func earbud(left: Bool) -> SCNNode? {
            let side = parts.filter { left ? $0.middle.x < -off : $0.middle.x > off }
            guard let shell = side.max(by: { $0.size < $1.size }) else { return nil }
            let reach = shell.size * 0.25
            let earbud = SCNNode()
            for part in side
            where (shell.low.x - reach...shell.high.x + reach).contains(part.middle.x)
                && (shell.low.y - reach...shell.high.y + reach).contains(part.middle.y)
                && (shell.low.z - reach...shell.high.z + reach).contains(part.middle.z)
            {
                let copy = SCNNode(geometry: part.node.geometry)
                copy.transform = part.node.worldTransform
                earbud.addChildNode(copy)
            }
            return earbud
        }
        guard let left = earbud(left: true), let right = earbud(left: false) else { return nil }
        return (left, right)
    }

    /// A picture's pixels, red, green, blue and how solid, a row at a time from the top.
    static func pixels(of image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// The middle brightness of what's solid in a picture, of 255.
    static func brightness(of image: CGImage) -> CGFloat? {
        guard let pixels = pixels(of: image) else { return nil }
        var levels: [Int] = []
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            levels.append(Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]))
        }
        levels.sort()
        return levels.isEmpty ? nil : CGFloat(levels[levels.count / 2]) / 3
    }

    /// Where a picture isn't clear, in its pixels, from the top left.
    static func opaque(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let pixels = pixels(of: image) else { return nil }
        var (minX, minY, maxX, maxY) = (width, height, -1, -1)
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
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
