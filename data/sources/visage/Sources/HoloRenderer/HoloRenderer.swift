import CoreGraphics
import FaceAnimation
import Foundation
import Metal
import MetalKit
import simd

/// What the hologram looks like (spec, § 8.2, § 9.2).
public struct HoloSettings: Sendable {
    /// The charter's braise by default (docs/charte.md, § 3).
    public var colour = SIMD3<Float>(1.0, 0.788, 0.471)
    public var projector = true
    /// Transparent (alpha 0) for the floating windows; the charter's charbon for the classic one.
    public var background = SIMD4<Float>(0, 0, 0, 0)
    /// From 0, the hologram of points, to 1, the face as a lit, textured surface (§ 8.3). Only the heads
    /// that have surfaces take it.
    public var realism: Float = 0
    /// The layers (§ 8.2, § 9.2): the halo's strength (1 the charter's), the scanlines' and the sweeping
    /// band's (0 none), and the flicker with the rare glitch.
    public var halo: Float = 1
    public var scanlines: Float = 1
    public var glitches = true

    public init() {}

    public static let charbon = SIMD4<Float>(0.055, 0.047, 0.039, 1)
}

/// Draws a pose: the points into a light buffer, then the hologram's layers onto the target.
public final class HoloRenderer: @unchecked Sendable {
    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    private let queue: MTLCommandQueue
    private let pointPipeline: MTLRenderPipelineState
    private let occluderPipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    /// Occluders write the depth; points are tested against it without writing it.
    private let hiding: MTLDepthStencilState
    private let hidden: MTLDepthStencilState
    /// For the head that fades out: shown whole, whatever the new one hides.
    private let unhidden: MTLDepthStencilState
    private var pointBuffer: MTLBuffer
    private var occluderBuffer: MTLBuffer?
    private var scene: MTLTexture?
    private var depth: MTLTexture?
    private let surfacePipeline: MTLRenderPipelineState
    /// The surfaces' depth alone, cut-outs included, before their colour: a translucent face shows its
    /// nearest layer only, not the inside of the skull behind it.
    private let surfaceDepthPipeline: MTLRenderPipelineState
    private let nearest: MTLDepthStencilState
    /// The surfaces' buffers and textures, made the first time the realism asks for them.
    private var surfaceDraws: [SurfaceDraw]?
    private var uvBuffer: MTLBuffer?

    private struct SurfaceDraw {
        let indices: MTLBuffer
        let count: Int
        let texture: MTLTexture
        let look: SurfaceLook
        /// Closed surfaces show their outer side only (else the inside of the cut neck shows under the
        /// chin); strands, brows and lashes are cards seen from either side.
        let cull: MTLCullMode
    }

    /// Same layout as `SurfaceLook` in the shaders.
    private struct SurfaceLook {
        var shine: Float
        var sharpness: Float
        var warmth: Float
        var opacity: Float
    }
    /// The head drawn: the charter's point head, or a MakeHuman face. Set, it shows at once; `fade(to:)`
    /// changes it gently.
    public var model: HeadModel {
        didSet {
            outgoing = nil
            occluderBuffer = Self.occluderBuffer(model, device: device)
            surfaceDraws = nil
        }
    }
    /// The head fading out, and when it began to (the first frame drawn after the change).
    private var outgoing: (model: HeadModel, start: Double?)?

    /// How long a change of face takes (spec, § 8.1: a fade, even while it speaks).
    public static let fadeDuration = 0.6

    /// Changes the head over `fadeDuration`: the new one rises as the old one fades, after a brief glitch.
    public func fade(to newModel: HeadModel) {
        let old = model
        model = newModel
        outgoing = (old, nil)
    }

    /// How much of each head shows, `elapsed` seconds into a change.
    static func fade(elapsed: Double) -> (incoming: Float, outgoing: Float) {
        let progress = Float(min(max(elapsed / fadeDuration, 0), 1))
        let eased = progress * progress * (3 - 2 * progress)
        return (eased, 1 - eased)
    }

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
        var realism: Float
        var halo: Float
        var scanlines: Float
        var background: SIMD4<Float>
    }

    public init?(model: HeadModel = PointHeadModel(), pixelFormat: MTLPixelFormat = .bgra8Unorm) {
        self.model = model
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let library = try? device.makeLibrary(source: HoloShaders.source, options: Self.compileOptions)
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
        points.depthAttachmentPixelFormat = .depth32Float

        // Depth only: no fragment function, nothing written to the light.
        let occluders = MTLRenderPipelineDescriptor()
        occluders.vertexFunction = library.makeFunction(name: "occluderVertex")
        occluders.colorAttachments[0].pixelFormat = .rgba16Float
        occluders.colorAttachments[0].writeMask = []
        occluders.depthAttachmentPixelFormat = .depth32Float

        let hiding = MTLDepthStencilDescriptor()
        hiding.depthCompareFunction = .less
        hiding.isDepthWriteEnabled = true
        let hidden = MTLDepthStencilDescriptor()
        hidden.depthCompareFunction = .lessEqual
        hidden.isDepthWriteEnabled = false
        // Surfaces are painted over what is behind them, a little or wholly as the realism grows.
        let surfaces = MTLRenderPipelineDescriptor()
        surfaces.vertexFunction = library.makeFunction(name: "surfaceVertex")
        surfaces.fragmentFunction = library.makeFunction(name: "surfaceFragment")
        surfaces.colorAttachments[0].pixelFormat = .rgba16Float
        surfaces.colorAttachments[0].isBlendingEnabled = true
        surfaces.colorAttachments[0].sourceRGBBlendFactor = .one
        surfaces.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        surfaces.colorAttachments[0].sourceAlphaBlendFactor = .one
        surfaces.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        surfaces.depthAttachmentPixelFormat = .depth32Float
        let surfaceDepth = surfaces.copy() as! MTLRenderPipelineDescriptor
        surfaceDepth.colorAttachments[0].writeMask = []
        let nearest = MTLDepthStencilDescriptor()
        nearest.depthCompareFunction = .lessEqual
        nearest.isDepthWriteEnabled = false

        let unhidden = MTLDepthStencilDescriptor()
        unhidden.depthCompareFunction = .always
        unhidden.isDepthWriteEnabled = false

        let composite = MTLRenderPipelineDescriptor()
        composite.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        composite.fragmentFunction = library.makeFunction(name: "compositeFragment")
        composite.colorAttachments[0].pixelFormat = pixelFormat

        guard let pointPipeline = try? device.makeRenderPipelineState(descriptor: points),
            let occluderPipeline = try? device.makeRenderPipelineState(descriptor: occluders),
            let compositePipeline = try? device.makeRenderPipelineState(descriptor: composite),
            let surfacePipeline = try? device.makeRenderPipelineState(descriptor: surfaces),
            let surfaceDepthPipeline = try? device.makeRenderPipelineState(descriptor: surfaceDepth),
            let nearestState = device.makeDepthStencilState(descriptor: nearest),
            let hidingState = device.makeDepthStencilState(descriptor: hiding),
            let hiddenState = device.makeDepthStencilState(descriptor: hidden),
            let unhiddenState = device.makeDepthStencilState(descriptor: unhidden),
            let pointBuffer = device.makeBuffer(
                length: MemoryLayout<GPUPoint>.stride * max(model.pointCount, 1), options: .storageModeShared)
        else { return nil }
        self.pointPipeline = pointPipeline
        self.occluderPipeline = occluderPipeline
        self.compositePipeline = compositePipeline
        self.hiding = hidingState
        self.hidden = hiddenState
        self.unhidden = unhiddenState
        self.surfacePipeline = surfacePipeline
        self.surfaceDepthPipeline = surfaceDepthPipeline
        self.nearest = nearestState
        self.pointBuffer = pointBuffer
        occluderBuffer = Self.occluderBuffer(model, device: device)
    }

    /// The surfaces' two passes need the same depths to the last bit.
    private static var compileOptions: MTLCompileOptions {
        let options = MTLCompileOptions()
        options.preserveInvariance = true
        return options
    }

    /// The model's surfaces, ready to draw: made once per model, the first time they are needed.
    private func surfaces() -> [SurfaceDraw] {
        if let surfaceDraws { return surfaceDraws }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .generateMipmaps: true, .allocateMipmaps: true]
        var draws: [SurfaceDraw] = []
        for surface in model.surfaces where !surface.triangles.isEmpty {
            guard let texture = try? loader.newTexture(URL: surface.texture, options: options),
                let indices = surface.triangles.withUnsafeBytes({
                    device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
                })
            else { continue }
            let look: SurfaceLook =
                switch surface.material {
                case .skin: SurfaceLook(shine: 0.06, sharpness: 24, warmth: 0.5, opacity: 1)
                case .eye: SurfaceLook(shine: 0.9, sharpness: 300, warmth: 0, opacity: 1)
                case .hair: SurfaceLook(shine: 0.1, sharpness: 40, warmth: 0.15, opacity: 1)
                case .matte: SurfaceLook(shine: 0.02, sharpness: 10, warmth: 0.2, opacity: 1)
                }
            let cull: MTLCullMode = surface.material == .skin || surface.material == .eye ? .back : .none
            draws.append(
                SurfaceDraw(indices: indices, count: surface.triangles.count, texture: texture, look: look, cull: cull))
        }
        let uvs = model.uvs
        uvBuffer =
            uvs.isEmpty
            ? nil
            : uvs.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
        surfaceDraws = draws
        return draws
    }

    private static func occluderBuffer(_ model: HeadModel, device: MTLDevice) -> MTLBuffer? {
        let indices = model.occluders
        guard !indices.isEmpty else { return nil }
        return indices.withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }

    private func reserve(points: Int) {
        let length = MemoryLayout<GPUPoint>.stride * max(points, 1)
        if pointBuffer.length < length, let buffer = device.makeBuffer(length: length, options: .storageModeShared) {
            pointBuffer = buffer
        }
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
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
            depthDescriptor.usage = [.renderTarget]
            depthDescriptor.storageMode = .private
            depth = device.makeTexture(descriptor: depthDescriptor)
        }
        guard let scene, let depth else { return }

        var weights: (incoming: Float, outgoing: Float) = (1, 0)
        var elapsed = Double.infinity
        if let change = outgoing {
            let start = change.start ?? time
            elapsed = time - start
            weights = Self.fade(elapsed: elapsed)
            outgoing = elapsed < Self.fadeDuration ? (change.model, start) : nil
        }
        let fadingOut = weights.outgoing > 0 ? outgoing?.model : nil
        reserve(points: model.pointCount + (fadingOut?.pointCount ?? 0))

        let shaped = model.shape(pose, time: time)
        let normals = model.normals
        let count = min(shaped.count, normals.count)
        let gpu = pointBuffer.contents().bindMemory(
            to: GPUPoint.self, capacity: pointBuffer.length / MemoryLayout<GPUPoint>.stride)
        for index in 0..<count {
            var normal = normals[index]
            normal.w *= weights.incoming
            gpu[index] = GPUPoint(position: shaped[index], normal: normal)
        }
        // The old head, after the new one in the same buffer, at its own point size.
        var outgoingCount = 0
        if let fadingOut {
            let oldShaped = fadingOut.shape(pose, time: time)
            let oldNormals = fadingOut.normals
            let sizeRatio = fadingOut.pointScale / model.pointScale
            outgoingCount = min(oldShaped.count, oldNormals.count)
            for index in 0..<outgoingCount {
                var position = oldShaped[index]
                position.w *= sizeRatio
                var normal = oldNormals[index]
                normal.w *= weights.outgoing
                gpu[count + index] = GPUPoint(position: position, normal: normal)
            }
        }

        var uniforms = Uniforms(
            viewProjection: Self.viewProjection(aspect: Float(width) / Float(height)),
            model: Self.model(head: pose.head), colour: SIMD4(settings.colour, 1),
            viewport: SIMD2(Float(width), Float(height)), time: Float(time), glow: pose.glow,
            flicker: settings.glitches ? Self.flicker(time) : 1,
            pointScale: Float(height) * 0.0062 * model.pointScale,
            glitch: settings.glitches ? (elapsed < 0.1 ? 1 : Self.glitch(time)) : 0,
            projector: settings.projector ? 1 : 0, realism: model.surfaces.isEmpty ? 0 : settings.realism,
            halo: settings.halo, scanlines: settings.scanlines, background: settings.background)

        let light = MTLRenderPassDescriptor()
        light.colorAttachments[0].texture = scene
        light.colorAttachments[0].loadAction = .clear
        light.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        light.colorAttachments[0].storeAction = .store
        light.depthAttachment.texture = depth
        light.depthAttachment.loadAction = .clear
        light.depthAttachment.clearDepth = 1
        light.depthAttachment.storeAction = .dontCare
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: light) {
            encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            let draws = uniforms.realism > 0 ? surfaces() : []
            if !draws.isEmpty, let uvBuffer {
                // The surfaces hide what is behind them, as the occluders do: their depth first, then their
                // colour on the nearest layer only.
                encoder.setVertexBuffer(uvBuffer, offset: 0, index: 2)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFrontFacing(.counterClockwise)  // glTF's
                for (pipeline, state) in [(surfaceDepthPipeline, hiding), (surfacePipeline, nearest)] {
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setDepthStencilState(state)
                    for draw in draws {
                        var look = draw.look
                        look.opacity = uniforms.realism * weights.incoming
                        encoder.setCullMode(draw.cull)
                        encoder.setFragmentTexture(draw.texture, index: 0)
                        encoder.setFragmentBytes(&look, length: MemoryLayout<SurfaceLook>.stride, index: 2)
                        encoder.drawIndexedPrimitives(
                            type: .triangle, indexCount: draw.count, indexType: .uint32, indexBuffer: draw.indices,
                            indexBufferOffset: 0)
                    }
                }
                encoder.setCullMode(.none)
            } else if let occluderBuffer {
                encoder.setRenderPipelineState(occluderPipeline)
                encoder.setDepthStencilState(hiding)
                encoder.drawIndexedPrimitives(
                    type: .triangle, indexCount: occluderBuffer.length / MemoryLayout<UInt32>.stride,
                    indexType: .uint32, indexBuffer: occluderBuffer, indexBufferOffset: 0)
            }
            encoder.setRenderPipelineState(pointPipeline)
            encoder.setDepthStencilState(hidden)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            if outgoingCount > 0 {
                encoder.setDepthStencilState(unhidden)
                encoder.drawPrimitives(type: .point, vertexStart: count, vertexCount: outgoingCount)
            }
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
