import CoreGraphics
import FaceAnimation
import Foundation
import Metal
import simd

/// What the hologram looks like (spec, § 8.2, § 9.2).
public struct HoloSettings: Sendable {
    /// The charter's braise by default (docs/charte.md, § 3).
    public var colour = SIMD3<Float>(1.0, 0.788, 0.471)
    public var projector = true
    /// Transparent (alpha 0) for the floating windows; the charter's charbon for the classic one.
    public var background = SIMD4<Float>(0, 0, 0, 0)

    public init() {}

    public static let charbon = SIMD4<Float>(0.055, 0.047, 0.039, 1)
}

/// Draws a pose: the points into a light buffer, then the hologram's layers onto the target.
public final class HoloRenderer: @unchecked Sendable {
    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    private let queue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let pointBuffer: MTLBuffer
    private var scene: MTLTexture?

    private struct GPUPoint {
        var position: SIMD4<Float>
        var normal: SIMD4<Float>
    }

    /// Same layout as `Uniforms` in the shaders.
    private struct Uniforms {
        var viewProjection: simd_float4x4
        var model: simd_float4x4
        var colour: SIMD4<Float>
        var viewport: SIMD2<Float>
        var time: Float
        var glow: Float
        var flicker: Float
        var pointScale: Float
        var glitch: Float
        var projector: Float
        var background: SIMD4<Float>
    }

    public init?(pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: HoloShaders.source, options: nil)
        else { return nil }
        self.device = device
        self.queue = queue
        self.pixelFormat = pixelFormat

        let points = MTLRenderPipelineDescriptor()
        points.vertexFunction = library.makeFunction(name: "pointVertex")
        points.fragmentFunction = library.makeFunction(name: "pointFragment")
        points.colorAttachments[0].pixelFormat = .rgba16Float
        // Light adds up, as light does.
        points.colorAttachments[0].isBlendingEnabled = true
        points.colorAttachments[0].rgbBlendOperation = .add
        points.colorAttachments[0].alphaBlendOperation = .add
        points.colorAttachments[0].sourceRGBBlendFactor = .one
        points.colorAttachments[0].destinationRGBBlendFactor = .one
        points.colorAttachments[0].sourceAlphaBlendFactor = .one
        points.colorAttachments[0].destinationAlphaBlendFactor = .one

        let composite = MTLRenderPipelineDescriptor()
        composite.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        composite.fragmentFunction = library.makeFunction(name: "compositeFragment")
        composite.colorAttachments[0].pixelFormat = pixelFormat

        guard let pointPipeline = try? device.makeRenderPipelineState(descriptor: points),
            let compositePipeline = try? device.makeRenderPipelineState(descriptor: composite),
            let pointBuffer = device.makeBuffer(
                length: MemoryLayout<GPUPoint>.stride * PointHead.points.count, options: .storageModeShared)
        else { return nil }
        self.pointPipeline = pointPipeline
        self.compositePipeline = compositePipeline
        self.pointBuffer = pointBuffer
    }

    // MARK: - Drawing

    /// Encodes the face into `target`.
    public func encode(
        pose: FacePose, time: Double, settings: HoloSettings, into target: MTLTexture, commandBuffer: MTLCommandBuffer
    ) {
        let width = target.width
        let height = target.height
        if scene?.width != width || scene?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            scene = device.makeTexture(descriptor: descriptor)
        }
        guard let scene else { return }

        let shaped = PointHead.deform(pose, time: time)
        let gpu = pointBuffer.contents().bindMemory(to: GPUPoint.self, capacity: shaped.count)
        for (index, point) in PointHead.points.enumerated() {
            gpu[index] = GPUPoint(position: shaped[index], normal: SIMD4(point.normal, point.brightness))
        }

        var uniforms = Uniforms(
            viewProjection: Self.viewProjection(aspect: Float(width) / Float(height)),
            model: Self.model(head: pose.head), colour: SIMD4(settings.colour, 1),
            viewport: SIMD2(Float(width), Float(height)), time: Float(time), glow: pose.glow,
            flicker: Self.flicker(time), pointScale: Float(height) * 0.0062, glitch: Self.glitch(time),
            projector: settings.projector ? 1 : 0, background: settings.background)

        let light = MTLRenderPassDescriptor()
        light.colorAttachments[0].texture = scene
        light.colorAttachments[0].loadAction = .clear
        light.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        light.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: light) {
            encoder.setRenderPipelineState(pointPipeline)
            encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: shaped.count)
            encoder.endEncoding()
        }

        let final = MTLRenderPassDescriptor()
        final.colorAttachments[0].texture = target
        final.colorAttachments[0].loadAction = .clear
        final.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        final.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: final) {
            encoder.setRenderPipelineState(compositePipeline)
            encoder.setFragmentTexture(scene, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }

    /// Renders one frame offscreen: snapshots, and the offline video.
    public func image(pose: FacePose, time: Double, settings: HoloSettings, width: Int, height: Int) -> CGImage? {
        guard let pixels = renderPixels(pose: pose, time: time, settings: settings, width: width, height: height),
            let provider = CGDataProvider(data: pixels as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// BGRA, premultiplied, row after row.
    public func renderPixels(pose: FacePose, time: Double, settings: HoloSettings, width: Int, height: Int) -> Data? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
            let commandBuffer = queue.makeCommandBuffer()
        else { return nil }
        encode(pose: pose, time: time, settings: settings, into: target, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { bytes in
            target.getBytes(
                bytes.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return data
    }

    public func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    // MARK: - Camera and light

    /// A slightly long lens, looking at the face from the front; head and neck fill the frame.
    private static func viewProjection(aspect: Float) -> simd_float4x4 {
        let fovY: Float = 28 * .pi / 180
        let distance: Float = 6.4
        let centreY: Float = -0.35
        let scaleY = 1 / tan(fovY / 2)
        let scaleX = scaleY / aspect
        let near: Float = 1
        let far: Float = 20
        let projection = simd_float4x4(
            SIMD4(scaleX, 0, 0, 0), SIMD4(0, scaleY, 0, 0), SIMD4(0, 0, far / (near - far), -1),
            SIMD4(0, 0, far * near / (near - far), 0))
        let view = simd_float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, -centreY, -distance, 1))
        return projection * view
    }

    /// The head's rotation, about the top of the neck.
    private static func model(head: SIMD3<Float>) -> simd_float4x4 {
        let pivot = SIMD3<Float>(0, -0.4, 0)
        let rotation =
            simd_quatf(angle: head.z, axis: SIMD3(0, 0, 1)) * simd_quatf(angle: head.y, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -head.x, axis: SIMD3(1, 0, 0))
        var model = simd_float4x4(rotation)
        let moved = pivot - rotation.act(pivot)
        model.columns.3 = SIMD4(moved, 1)
        return model
    }

    /// A light that is never quite steady, and dips now and then.
    private static func flicker(_ time: Double) -> Float {
        let tick = floor(time * 30)
        let dip = fract(sin(tick * 12.9898) * 43_758.5453) > 0.95 ? 0.1 : 0
        return Float(0.97 + 0.03 * sin(time * 7.3) - dip)
    }

    /// The rare glitch: about once every 47 s, for a tenth of a second (§ 7.2: at most once a minute).
    private static func glitch(_ time: Double) -> Float {
        time.truncatingRemainder(dividingBy: 47) < 0.12 && time > 1 ? 1 : 0
    }

    private static func fract(_ value: Double) -> Double { value - floor(value) }
}
