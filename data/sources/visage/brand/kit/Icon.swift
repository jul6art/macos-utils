import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The app icon, drawn with Core Graphics from the same geometry as the SVG files (app-icon.svg is its
/// reference drawing). The app's build renders this iconset and packs it with `iconutil`: like Awake and
/// Siphon, the repository holds no bitmap.
enum AppIconRenderer {
    static let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for variant in variants {
            try writePNG(render(pixels: variant.pixels), to: directory.appending(path: "\(variant.name).png"))
        }
    }

    /// Drawn in the 1024-unit grid of the macOS icon template: an 824-unit tile, 185 units of corner.
    static func render(pixels: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let scale = CGFloat(pixels) / 1024
        // Top-left origin, as in the SVG.
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)

        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Shadow offsets live in device space, where y grows upwards: a negative height falls down.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: rgba(0x000000, 0.35))
        context.addPath(shape)
        context.setFillColor(rgba(0x0E0C0A, 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()

        let ground = CGGradient(colorsSpace: space, colors: [rgba(0x4A3016, 1), rgba(0x0E0C0A, 1)] as CFArray, locations: [0, 0.75])!
        let corner = CGPoint(x: 100 + 0.15 * 824, y: 924)
        context.drawRadialGradient(ground, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: 824, options: [.drawsAfterEndLocation])

        // The projector's beam under the face.
        let beam = CGGradient(colorsSpace: space, colors: [rgba(0xFFC978, 0.35), rgba(0xFFC978, 0)] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.translateBy(x: 512, y: 860)
        context.scaleBy(x: 1, y: 50.0 / 260.0)
        context.drawRadialGradient(beam, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 260, options: [])
        context.restoreGState()

        // Scanlines, where there are pixels enough to show them.
        if pixels >= 128 {
            context.setFillColor(rgba(0xFFE9C4, 0.05))
            var y: CGFloat = 100
            while y < 924 {
                context.fill(CGRect(x: 100, y: y, width: 824, height: 1.5))
                y += 6
            }
        }

        // The glow of the dots.
        context.setShadow(offset: .zero, blur: 14 * scale, color: rgba(0xFFC978, 0.55))
        if pixels >= 64 {
            let dots = Mark.dots.map { ($0.logo, $0.logoRadius, $0.logoOpacity) }
            draw(dots, in: CGRect(x: 212, y: 150, width: 600, height: 600), unit: 100, context: context)
        } else {
            // The full mark turns to mush in a few pixels: the menu bar glyph, with fatter dots.
            let dots = MenuBarGlyph.dots.map { ($0.point, $0.radius * 1.35, $0.opacity) }
            draw(dots, in: CGRect(x: 197, y: 170, width: 630, height: 630), unit: 18, context: context)
        }
        context.restoreGState()

        return context.makeImage()!
    }

    private static func draw(_ dots: [(BrandPoint, Double, Double)], in frame: CGRect, unit: Double, context: CGContext) {
        let factor = frame.width / CGFloat(unit)
        for (point, radius, opacity) in dots where opacity > 0 {
            let centre = CGPoint(x: frame.minX + CGFloat(point.x) * factor, y: frame.minY + CGFloat(point.y) * factor)
            let size = CGFloat(radius) * factor
            context.setFillColor(rgba(0xFFC978, opacity))
            context.fillEllipse(in: CGRect(x: centre.x - size, y: centre.y - size, width: 2 * size, height: 2 * size))
        }
    }

    private static func rgba(_ hex: UInt32, _ alpha: Double) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw BrandError(description: "cannot write \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw BrandError(description: "cannot write \(url.path)")
        }
    }
}
