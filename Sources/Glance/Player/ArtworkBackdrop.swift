//
//  ArtworkBackdrop.swift
//  Glance
//
//  Created by Gaty on 10/11/2026.
//

import AppKit
import Metal
import MetalKit
import MetalPerformanceShaders
import simd

/// The colors behind the player, drawn as Apple Music's own background draws them: MediaCoreUI's
/// `Backdrop.CompositeRenderer` on macOS 27.3, its passes, its constants and its shaders' arithmetic
/// read from its code and rebuilt here with public Metal.
///
/// 1. The new cover fades in over the last one (`blended_fragment`).
/// 2. Three copies of it turn, drawn small on transparent black: a large one round the middle, a
///    small one round a point left of it and up, and a small one carried round the middle by the large
///    one while it turns on its own (`rotation_vertex`). The music's bass swells them all. Each copy
///    is darkened, given contrast by the bass, and saturated, more by the treble (`rotation_fragment`).
/// 3. That's blurred, with nothing outside the picture counting.
/// 4. A subdivided mesh lays it across the picture, warping between two shapes; without lyrics it's
///    flat and zoomed 2.5 times (`pinch_vertex`). Each color is made whole again where the blur thinned
///    it at the edges, washed with a tenth of white, and passed through Apple's own color table, which
///    holds back pure reds and blues (`pinch_fragment`).
final class ArtworkBackdrop: @unchecked Sendable {
    struct Vertex {
        var uv: SIMD2<Float>
        var from: SIMD2<Float>
        var to: SIMD2<Float>
    }

    /// The shaders' uniforms, laid out byte for byte as Apple's `Uniforms` struct (368 bytes).
    struct Uniforms: Equatable {
        var time: Float = 0
        var view = matrix_identity_float4x4
        var textureMix: Float = 1
        var warp: Float = 0
        var pinch: Float = 0
        var downsample: Float = 1
        var width: Int16 = 0
        var height: Int16 = 0
        var saturation: Float = 1
        var whiteScrim: Float = 0
        var blackScrim: Float = 0
        var spectrum = SIMD4<Float>.zero

        static let size = 368

        /// The three copies: their place and size, the copy they turn with (-1 for none), and how many
        /// clock seconds each takes to turn once.
        static let models: [(matrix: simd_float4x4, parent: Int16, period: Float)] = {
            func scaled(_ s: Float, moved x: Float = 0, _ y: Float = 0) -> simd_float4x4 {
                var m = simd_float4x4(diagonal: SIMD4(s, s, 1, 1))
                m.columns.3 = SIMD4(x, y, 0, 1)
                return m
            }
            return [(scaled(1.4), -1, 120), (scaled(0.7, moved: -0.25, 0.15), -1, 70), (scaled(0.7, moved: 0.7, 0.7), 0, 90)]
        }()

        var bytes: [UInt8] {
            var data = [UInt8](repeating: 0, count: Self.size)
            data.withUnsafeMutableBytes { raw in
                func put<T>(_ value: T, _ offset: Int) { raw.storeBytes(of: value, toByteOffset: offset, as: T.self) }
                put(time, 0)
                for column in 0..<4 { put(view[column], 16 + column * 16) }
                for (index, model) in Self.models.enumerated() {
                    let base = 80 + index * 80
                    for column in 0..<4 { put(model.matrix[column], base + column * 16) }
                    put(model.parent, base + 64)
                    put(model.period, base + 68)
                }
                put(textureMix, 320)
                put(warp, 324)
                put(pinch, 328)
                put(downsample, 332)
                put(width, 336)
                put(height, 338)
                put(saturation, 340)
                put(whiteScrim, 344)
                put(blackScrim, 348)
                put(spectrum, 352)
            }
            return data
        }
    }

    private struct Pipelines {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let blend: MTLRenderPipelineState
        let rotation: MTLRenderPipelineState
        let pinch: MTLRenderPipelineState
        let quad: MTLBuffer
        let quadIndices: MTLBuffer
        let table: MTLTexture

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                let library = try? device.makeLibrary(source: ArtworkBackdrop.shader, options: nil)
            else { return nil }
            func pipeline(_ vertex: String, _ fragment: String, _ format: MTLPixelFormat) -> MTLRenderPipelineState? {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: vertex)
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                descriptor.colorAttachments[0].pixelFormat = format
                return try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            // Apple's quad: corners at ±1, the cover's top at the top.
            let corners: [Float] = [-1, -1, 0, 1, -1, 1, 0, 0, 1, 1, 1, 0, 1, -1, 1, 1]
            let order: [UInt16] = [0, 1, 2, 2, 0, 3]
            guard let blend = pipeline("backdropIdentity", "backdropBlend", .rgba8Unorm),
                let rotation = pipeline("backdropRotation", "backdropRotationColor", .rgba16Float),
                let pinch = pipeline("backdropPinch", "backdropPinchColor", .rgba8Unorm),
                let quad = device.makeBuffer(bytes: corners, length: corners.count * 4),
                let quadIndices = device.makeBuffer(bytes: order, length: order.count * 2),
                let table = ArtworkBackdrop.colorTable(device)
            else { return nil }
            self.device = device
            self.queue = queue
            self.blend = blend
            self.rotation = rotation
            self.pinch = pinch
            self.quad = quad
            self.quadIndices = quadIndices
            self.table = table
        }
    }
    private static let pipelines = Pipelines()

    /// The final picture's longer side, in pixels. The colors are soft, so it's drawn small.
    static let side = 200
    /// The cover's side in the fade pass, in pixels: the size the flow keeps it at.
    static let coverSide = 128

    private let pipelines: Pipelines
    private let vertices: MTLBuffer
    private let indices: MTLBuffer
    private let count: Int
    private let blended: MTLTexture
    private let rotated: MTLTexture
    private let blurred: MTLTexture
    private let output: MTLTexture
    private var blur: MPSImageGaussianBlur?
    private var textures: [ObjectIdentifier: MTLTexture] = [:]
    let width: Int
    let height: Int
    /// Wider than tall, which takes Apple's wide mesh and look.
    let wide: Bool

    /// `side`: the final picture's longer side, in pixels.
    init?(variant: Int, aspect: Double, side: Int = ArtworkBackdrop.side) {
        let aspect = min(max(aspect, 0.25), 8)
        width = aspect >= 1 ? side : Int((Double(side) * aspect).rounded())
        height = aspect >= 1 ? Int((Double(side) / aspect).rounded()) : side
        wide = width > height
        guard let pipelines = Self.pipelines else { return nil }
        self.pipelines = pipelines
        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(w, 4), height: max(h, 4), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            return pipelines.device.makeTexture(descriptor: descriptor)
        }
        // The copies are drawn at half the final picture's size: once blurred, a smaller copy of
        // Apple's quarter-size drawing of a full window.
        guard let blended = texture(.rgba8Unorm, Self.coverSide, Self.coverSide),
            let rotated = texture(.rgba16Float, width / 2, height / 2),
            let blurred = texture(.rgba16Float, width / 2, height / 2)
        else { return nil }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .shared
        guard let output = pipelines.device.makeTexture(descriptor: outputDescriptor) else { return nil }
        self.blended = blended
        self.rotated = rotated
        self.blurred = blurred
        self.output = output
        let mesh = BackdropMesh.make(variant: variant, wide: wide)
        guard let vertices = pipelines.device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<Vertex>.stride),
            let indices = pipelines.device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt32>.stride)
        else { return nil }
        self.vertices = vertices
        self.indices = indices
        count = mesh.indices.count
    }

    /// The blur in the small drawing's pixels, for a blur of `points` in a window `referenceWidth`
    /// points wide: the same share of the picture's width as Apple's blur of its quarter-size drawing
    /// of a full-screen window.
    func blurSigma(points: Float, referenceWidth: Double) -> Float {
        max(points * Float(rotated.width) / Float(max(referenceWidth, 1)), 0.5)
    }

    private func texture(for image: CGImage) -> MTLTexture? {
        let key = ObjectIdentifier(image)
        if let existing = textures[key] { return existing }
        let loaded = try? MTKTextureLoader(device: pipelines.device).newTexture(
            cgImage: image, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        if textures.count > 4 { textures.removeAll() }
        textures[key] = loaded
        return loaded
    }

    /// Draws one frame, on the artwork queue. No GPU wait happens on the main thread.
    func frame(cover: CGImage, previous: CGImage?, uniforms: Uniforms, blurSigma: Float) -> CGImage? {
        guard let current = texture(for: cover), let command = pipelines.queue.makeCommandBuffer() else { return nil }
        var bytes = uniforms.bytes
        func pass(_ target: MTLTexture, clear: MTLClearColor) -> MTLRenderCommandEncoder? {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = clear
            return command.makeRenderCommandEncoder(descriptor: pass)
        }
        // 1. The new cover over the last, while it fades in.
        var source = current
        if let previous, uniforms.textureMix < 1, let old = texture(for: previous),
            let encoder = pass(blended, clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1))
        {
            encoder.setRenderPipelineState(pipelines.blend)
            encoder.setVertexBuffer(pipelines.quad, offset: 0, index: 0)
            encoder.setFragmentBytes(&bytes, length: bytes.count, index: 1)
            encoder.setFragmentTexture(current, index: 0)
            encoder.setFragmentTexture(old, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: pipelines.quadIndices, indexBufferOffset: 0)
            encoder.endEncoding()
            source = blended
        }
        // 2. The three turning copies, on transparent black.
        guard let planes = pass(rotated, clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)) else { return nil }
        planes.setRenderPipelineState(pipelines.rotation)
        planes.setVertexBuffer(pipelines.quad, offset: 0, index: 0)
        planes.setVertexBytes(&bytes, length: bytes.count, index: 1)
        planes.setFragmentBytes(&bytes, length: bytes.count, index: 1)
        planes.setFragmentTexture(source, index: 0)
        planes.drawIndexedPrimitives(
            type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: pipelines.quadIndices, indexBufferOffset: 0, instanceCount: 3)
        planes.endEncoding()
        // 3. Blurred, nothing beyond the edges counting, so they thin; the last pass makes them whole.
        if blur?.sigma != blurSigma { blur = MPSImageGaussianBlur(device: pipelines.device, sigma: blurSigma) }
        blur?.encode(commandBuffer: command, sourceTexture: rotated, destinationTexture: blurred)
        // 4. Laid across the picture through the mesh.
        guard let mesh = pass(output, clear: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)) else { return nil }
        mesh.setRenderPipelineState(pipelines.pinch)
        mesh.setVertexBuffer(vertices, offset: 0, index: 0)
        mesh.setVertexBytes(&bytes, length: bytes.count, index: 1)
        mesh.setFragmentBytes(&bytes, length: bytes.count, index: 1)
        mesh.setFragmentTexture(blurred, index: 0)
        mesh.setFragmentTexture(pipelines.table, index: 1)
        mesh.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
        mesh.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let row = width * 4
        var pixels = [UInt8](repeating: 0, count: row * height)
        output.getBytes(&pixels, bytesPerRow: row, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: row, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Apple's color table

    /// Apple's own 32 by 32 by 32 color table, which the colors pass through last: grays and greens as
    /// they are, pure reds and blues held back (a full red comes out 177, 14, 15). It's read from macOS
    /// itself (MediaCoreUI's `BackdropLUT`), never copied; where it can't be read, colors pass unchanged.
    /// Red runs across each slice, green down it, blue from slice to slice.
    static func colorTableBytes() -> [UInt8] {
        let side = 32
        if let image = Bundle(path: "/System/Library/PrivateFrameworks/MediaCoreUI.framework")?.image(forResource: "BackdropLUT"),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            cgImage.width == side, cgImage.height == side * side
        {
            var pixels = [UInt8](repeating: 0, count: side * side * side * 4)
            let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard
                    let context = CGContext(
                        data: raw.baseAddress, width: side, height: side * side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                else { return false }
                context.interpolationQuality = .none
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side * side))
                return true
            }
            if drawn { return pixels }
        }
        return identityTable(side: side)
    }

    static func identityTable(side: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: side * side * side * 4)
        for blue in 0..<side {
            for green in 0..<side {
                for red in 0..<side {
                    let offset = ((blue * side + green) * side + red) * 4
                    pixels[offset] = UInt8((Double(red) / Double(side - 1) * 255).rounded())
                    pixels[offset + 1] = UInt8((Double(green) / Double(side - 1) * 255).rounded())
                    pixels[offset + 2] = UInt8((Double(blue) / Double(side - 1) * 255).rounded())
                }
            }
        }
        return pixels
    }

    private static func colorTable(_ device: MTLDevice) -> MTLTexture? {
        let side = 32
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = side
        descriptor.height = side
        descriptor.depth = side
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let pixels = colorTableBytes()
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake3D(0, 0, 0, side, side, side), mipmapLevel: 0, slice: 0, withBytes: raw.baseAddress!,
                bytesPerRow: side * 4, bytesPerImage: side * side * 4)
        }
        return texture
    }

    // MARK: Shaders

    /// Apple's shaders' arithmetic, constant for constant (MediaCoreUI's `default.metallib`).
    static let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Model { float4x4 matrix; short parent; float timeScale; };
        struct Uniforms {
            float time; float4x4 viewMatrix; Model models[3];
            float textureTransitionMix; float warpMix; float pinchMix; float downsample;
            short width; short height; float saturation; float whiteScrimAlpha; float blackScrimAlpha;
            float4 spectrumPower;
        };
        struct Corner { float2 position; float2 uv; };
        struct MeshVertex { float2 uv; float2 from; float2 to; };
        struct Plane { float4 position [[position]]; float2 uv; uint instance [[flat]]; };
        struct Surface { float4 position [[position]]; float2 uv; };
        constexpr sampler soft(coord::normalized, address::clamp_to_edge, filter::linear);

        vertex Surface backdropIdentity(uint id [[vertex_id]], constant Corner *corners [[buffer(0)]]) {
            Surface out;
            out.position = float4(corners[id].position, 0, 1);
            out.uv = corners[id].uv;
            return out;
        }
        fragment half4 backdropBlend(Surface in [[stage_in]], constant Uniforms &u [[buffer(1)]],
                                     texture2d<half> next [[texture(0)]], texture2d<half> last [[texture(1)]]) {
            return mix(last.sample(soft, in.uv), next.sample(soft, in.uv), half(u.textureTransitionMix));
        }

        vertex Plane backdropRotation(uint id [[vertex_id]], uint instance [[instance_id]],
                                      constant Corner *corners [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
            Model model = u.models[instance];
            float turns = u.time * 6.2831854820251465;
            float4x4 view = u.viewMatrix;
            if (model.parent != -1) {
                float a = turns / u.models[model.parent].timeScale;
                float c = fast::cos(a), s = fast::sin(a);
                float4 c0 = c * view[0] + (-s) * view[1];
                float4 c1 = s * view[0] + c * view[1];
                view[0] = c0;
                view[1] = c1;
            }
            float b = turns / model.timeScale;
            float sb = fast::sin(b), cb = fast::cos(b);
            float bass = mix(u.spectrumPower.x, u.spectrumPower.y, 0.10000000149011612);
            float swell = bass * bass * 0.33000001311302185 + 1.0;
            float4x4 swelled = float4x4(float4(swell, 0, 0, 0), float4(0, swell, 0, 0), float4(0, 0, 1, 0), float4(0, 0, 0, 1)) * view;
            float4x4 placed = swelled * model.matrix;
            float4 r0 = cb * placed[0] + (-sb) * placed[1];
            float4 r1 = sb * placed[0] + cb * placed[1];
            float2 p = corners[id].position;
            Plane out;
            out.position = r0 * p.x + r1 * p.y + placed[3];
            out.position.z = float(instance / 3);
            out.uv = corners[id].uv;
            out.instance = instance;
            return out;
        }
        fragment half4 backdropRotationColor(Plane in [[stage_in]], constant Uniforms &u [[buffer(1)]], texture2d<half> source [[texture(0)]]) {
            half3 color = source.sample(soft, in.uv).rgb;
            float4 power = u.spectrumPower;
            half dark = half(u.blackScrimAlpha + float(in.instance) * 0.007499999832361937);
            color = mix(color, half3(0), dark);
            half contrast = half(power.x * 0.07599999755620956 + 1.0);
            color = contrast * (color - 0.5h) + 0.5h;
            float s = float(half(u.saturation + power.z * 0.16599999368190765));
            half3 c0 = half3(float3(s * 0.7872999906539917 + 0.2125999927520752, 0.2125999927520752 - s * 0.2125999927520752, 0.2125999927520752 - s * 0.2125999927520752));
            half3 c1 = half3(float3(0.7152000069618225 - s * 0.7152000069618225, s * 0.2847999930381775 + 0.7152000069618225, 0.7152000069618225 - s * 0.7152000069618225));
            half3 c2 = half3(float3(0.0722000002861023 - s * 0.0722000002861023, 0.0722000002861023 - s * 0.0722000002861023, s * 0.9277999997138977 + 0.0722000002861023));
            return half4(color.r * c0 + color.g * c1 + color.b * c2, 1.0h);
        }

        vertex Surface backdropPinch(uint id [[vertex_id]], constant MeshVertex *vertices [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
            MeshVertex v = vertices[id];
            float2 warped = mix(v.from, v.to, u.warpMix);
            float pinch = u.pinchMix;
            float2 flat = ((1.0 - pinch) * 0.5 + 2.0) * (v.uv - 0.5);
            Surface out;
            out.position = float4(mix(flat, warped, pinch), 0, 1);
            out.uv = v.uv;
            return out;
        }
        fragment half4 backdropPinchColor(Surface in [[stage_in]], constant Uniforms &u [[buffer(1)]],
                                          texture2d<half> blurred [[texture(0)]], texture3d<half> table [[texture(1)]]) {
            half4 sampled = blurred.sample(soft, in.uv);
            half3 color = (1.0h / sampled.a) * sampled.rgb;
            color = mix(color, half3(1.0h), half(u.whiteScrimAlpha));
            half4 graded = table.sample(soft, float3(color));
            return half4(graded.rgb, 1.0h);
        }
        """
}
