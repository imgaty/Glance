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

/// Three rotating artwork planes, blurred before a subdivided mesh bends them.
/// The renderer uses public Metal APIs and its own shader implementation.
final class ArtworkBackdrop: @unchecked Sendable {
    struct Vertex {
        var uv: SIMD2<Float>
        var from: SIMD2<Float>
        var to: SIMD2<Float>
    }
    private struct Pipelines {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let rotation: MTLRenderPipelineState
        let pinch: MTLRenderPipelineState

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
                let library = try? device.makeLibrary(source: ArtworkBackdrop.shader, options: nil)
            else { return nil }
            func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: vertex)
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
                return try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            guard let rotation = pipeline("artworkPlanes", "artworkColor"),
                let pinch = pipeline("artworkMesh", "backdropColor")
            else { return nil }
            self.device = device
            self.queue = queue
            self.rotation = rotation
            self.pinch = pinch
        }
    }
    private static let pipelines = Pipelines()
    private let pipelines: Pipelines
    private let source: MTLTexture
    private let rotated: MTLTexture
    private let blurred: MTLTexture
    private let output: MTLTexture
    private let vertices: MTLBuffer
    private let indices: MTLBuffer
    private let count: Int
    private let blur: MPSImageGaussianBlur
    static let side = 200
    let width: Int
    let height: Int

    init?(_ image: CGImage, variant: Int = Int.random(in: 0..<5), aspect: Double = 1) {
        let aspect = min(max(aspect, 0.25), 8)
        let width = aspect >= 1 ? Self.side : Int((Double(Self.side) * aspect).rounded())
        let height = aspect >= 1 ? Int((Double(Self.side) / aspect).rounded()) : Self.side
        self.width = width
        self.height = height
        guard let pipelines = Self.pipelines,
            let source = try? MTKTextureLoader(device: pipelines.device).newTexture(
                cgImage: image, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        else { return nil }
        self.pipelines = pipelines
        self.source = source
        func texture() -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            return pipelines.device.makeTexture(descriptor: descriptor)
        }
        guard let rotated = texture(), let blurred = texture(), let output = texture() else { return nil }
        self.rotated = rotated
        self.blurred = blurred
        self.output = output
        let mesh = BackdropMesh.make(variant: variant)
        guard let vertices = pipelines.device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<Vertex>.stride),
            let indices = pipelines.device.makeBuffer(bytes: mesh.indices, length: mesh.indices.count * MemoryLayout<UInt32>.stride)
        else { return nil }
        self.vertices = vertices
        self.indices = indices
        count = mesh.indices.count
        // The native blur is floor(diagonal * factor), in the render texture's pixels.
        blur = MPSImageGaussianBlur(device: pipelines.device, sigma: Float(floor(hypot(Double(width), Double(height)) * 0.04539470697716646)))
    }

    /// Called on the artwork queue. No GPU completion wait occurs on the main thread.
    func frame(at time: Double) -> CGImage? {
        guard let command = pipelines.queue.makeCommandBuffer() else { return nil }
        func encoder(_ target: MTLTexture) -> MTLRenderCommandEncoder? {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            return command.makeRenderCommandEncoder(descriptor: pass)
        }
        var seconds = Float(time)
        var motion = SIMD2(seconds, Float(width) / Float(height))
        guard let planes = encoder(rotated) else { return nil }
        planes.setRenderPipelineState(pipelines.rotation)
        planes.setVertexBytes(&motion, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        planes.setFragmentTexture(source, index: 0)
        planes.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: 3)
        planes.endEncoding()
        blur.encode(commandBuffer: command, sourceTexture: rotated, destinationTexture: blurred)
        guard let mesh = encoder(output) else { return nil }
        mesh.setRenderPipelineState(pipelines.pinch)
        mesh.setVertexBuffer(vertices, offset: 0, index: 0)
        mesh.setVertexBytes(&seconds, length: 4, index: 1)
        mesh.setFragmentTexture(blurred, index: 0)
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

    static let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct Plane { float4 position [[position]]; float2 textureCoordinates; uint instanceId [[flat]]; };
        struct Surface { float4 position [[position]]; float2 textureCoordinates; };
        struct MeshVertex { float2 uv; float2 from; float2 to; };
        constexpr sampler coverSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        half3 saturated(half3 rgb, half amount) {
            half luminance = dot(rgb, half3(0.3h, 0.59h, 0.11h));
            return luminance + (rgb - luminance) * amount;
        }
        vertex Plane artworkPlanes(uint id [[vertex_id]], uint instance [[instance_id]], constant float2 &motion [[buffer(1)]]) {
            float time = motion.x;
            constexpr float2 positions[] = { {-1,-1}, {-1,1}, {1,1}, {1,1}, {1,-1}, {-1,-1} };
            constexpr float2 translations[] = { {0,0}, {-0.5,0.7}, {-0.95,-0.7} };
            constexpr float periods[] = {60,45,35};
            float2 p = positions[id];
            float angle = time * 2 * M_PI_F / periods[instance];
            float s = sin(angle), c = cos(angle);
            float2 translated = float2(c * p.x + s * p.y, -s * p.x + c * p.y) + translations[instance];
            Plane out;
            out.position = float4(c * translated.x + s * translated.y, -s * translated.x + c * translated.y, 0, 1);
            out.position.y *= motion.y;
        out.textureCoordinates = float2((p.x + 1) * 0.5, (1 - p.y) * 0.5);
            out.instanceId = instance;
            return out;
        }
        fragment half4 artworkColor(Plane in [[stage_in]], texture2d<half> source [[texture(0)]]) {
            return half4(saturated(source.sample(coverSampler, in.textureCoordinates).rgb, 1.3h), 1);
        }
        vertex Surface artworkMesh(uint id [[vertex_id]], constant MeshVertex *vertices [[buffer(0)]], constant float &time [[buffer(1)]]) {
            MeshVertex v = vertices[id];
            float phase = acos(sin(time * M_PI_F / 1.75f)) / M_PI_F;
            float eased = phase * phase * (3 - 2 * phase);
            Surface out;
            out.position = float4(mix(v.from, v.to, eased), 0, 1);
            out.textureCoordinates = (v.uv - 0.5f) * 0.8f + 0.5f;
            return out;
        }
        fragment half4 backdropColor(Surface in [[stage_in]], texture2d<half> source [[texture(0)]]) {
            half3 color = min(saturated(source.sample(coverSampler, in.textureCoordinates).rgb, 2.0h), half3(0.9951171875h));
            color = mix(color, half3(0), 0.25h) - half(0.1f * 0.2f);
            return half4(clamp(color, half3(0.07h), half3(0.97h)), 1);
        }
        """
}
