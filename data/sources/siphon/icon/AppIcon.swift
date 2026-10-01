// Draws Siphon's icon — a sound wave whose middle bar becomes a download arrow —
// and writes it as an .iconset, the folder `iconutil` turns into AppIcon.icns. build.sh
// runs it, so the repository holds the drawing as code and no image file.
//
//   swiftc -o render-icon AppIcon.swift && ./render-icon AppIcon.iconset
//
// Shapes are drawn by hand: Apple's SF Symbols licence forbids using them in app icons.

import CoreGraphics
import Foundation
import ImageIO

// MARK: - The macOS icon grid

/// A 1024-point canvas whose body is the 824-point rounded square centred in it. The
/// 100-point margin is not wasted: it holds the shadow, and macOS 26 shrinks an icon
/// that ignores it into a grey box of its own.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// The continuous-corner shape of macOS icons, as a superellipse: a plain rounded
/// rectangle has visibly sharper shoulders next to the system's own icons.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0..<steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let x = rect.width / 2 * copysign(pow(abs(cos(angle)), 2 / n), cos(angle))
        let y = rect.height / 2 * copysign(pow(abs(sin(angle)), 2 / n), sin(angle))
        let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ context: CGContext, clip path: CGPath, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2), transform: nil)
}

/// The rounded square, its shadow, and a faint sheen on top: the same frame for any glyph.
func drawBody(_ context: CGContext, colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let shape = squircle(in: body)

    // A gradient drawn through a clip casts no shadow, so a plain fill carries it.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(colors.last!)
    context.fillPath()
    context.restoreGState()

    linearGradient(context, clip: shape, colors: colors, from: start, to: end)
    linearGradient(
        context, clip: shape,
        colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)],
        from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 560)
    )

    // A hairline inside the edge, so a dark icon does not melt into a dark Dock.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.14))
    context.setLineWidth(6)
    context.strokePath()
    context.restoreGState()
}

// MARK: - Siphon

func roundedBar(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> CGPath {
    CGPath(
        roundedRect: CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height),
        cornerWidth: width / 2, cornerHeight: width / 2, transform: nil
    )
}

func drawIcon(_ context: CGContext) {
    // From turquoise to blue to violet, top left to bottom right.
    drawBody(
        context,
        colors: [color(0x3BE8C8), color(0x2F8BFF), color(0x6A4BF2)],
        from: CGPoint(x: 180, y: 900), to: CGPoint(x: 860, y: 120)
    )

    context.saveGState()
    context.addPath(squircle(in: body))
    context.clip()

    // One shadow for the whole glyph: drawn in a transparency layer, the parts cast
    // it together instead of shading each other.
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x10124A, 0.30))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(color(0xFFFFFF))
    context.setStrokeColor(color(0xFFFFFF))

    // A sound wave, symmetrical around the middle…
    let barWidth: CGFloat = 46
    for (offset, height) in [(CGFloat(80), CGFloat(250)), (160, 170), (240, 100)] {
        for x in [512 - offset, 512 + offset] {
            context.addPath(roundedBar(centerX: x, centerY: 640, width: barWidth, height: height))
        }
    }
    context.fillPath()

    // …whose middle bar keeps going down and becomes the arrow.
    context.addPath(roundedBar(centerX: 512, centerY: 655, width: barWidth, height: 430))
    context.fillPath()

    let head = CGMutablePath()
    head.move(to: CGPoint(x: 404, y: 480))
    head.addLine(to: CGPoint(x: 620, y: 480))
    head.addLine(to: CGPoint(x: 512, y: 312))
    head.closeSubpath()
    context.addPath(head)
    context.setLineWidth(28)
    context.setLineJoin(.round)
    // Filled, then stroked with the same white: the stroke rounds the three corners.
    context.drawPath(using: .fillStroke)

    // The tray it lands in.
    context.move(to: CGPoint(x: 292, y: 340))
    context.addLine(to: CGPoint(x: 292, y: 232))
    context.addLine(to: CGPoint(x: 732, y: 232))
    context.addLine(to: CGPoint(x: 732, y: 340))
    context.setLineWidth(48)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    context.endTransparencyLayer()
    context.restoreGState()
}

// MARK: - Writing the iconset

/// Every size macOS asks for, each drawn from the vectors rather than scaled down
/// from the largest one, so the small ones stay sharp.
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

guard CommandLine.arguments.count == 2 else {
    print("usage: render-icon <output.iconset>")
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in sizes {
    let context = CGContext(
        data: nil, width: size.pixels, height: size.pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size.pixels) / 1024, y: CGFloat(size.pixels) / 1024)
    drawIcon(context)

    let file = output.appendingPathComponent(size.name + ".png")
    let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else {
        print("could not write \(file.path)")
        exit(1)
    }
}
