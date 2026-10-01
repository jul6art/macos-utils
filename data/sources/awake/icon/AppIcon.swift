// Draws Awake's icon — a warm cup of coffee in a night sky — and writes it as an
// .iconset, the folder `iconutil` turns into AppIcon.icns. build.sh runs it, so the
// repository holds the drawing as code and no image file.
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

// MARK: - Awake

func drawIcon(_ context: CGContext) {
    // Night sky, from indigo to almost black.
    drawBody(
        context,
        colors: [color(0x3B40A0), color(0x1B1D55), color(0x0B0C2A)],
        from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100)
    )

    context.saveGState()
    context.addPath(squircle(in: body))
    context.clip()

    // A few stars, clear of the steam.
    let stars: [(x: CGFloat, y: CGFloat, radius: CGFloat, alpha: CGFloat)] = [
        (250, 800, 9, 0.9), (330, 715, 5, 0.6), (205, 640, 4, 0.5),
        (770, 820, 7, 0.85), (700, 760, 4, 0.5), (820, 670, 5, 0.6),
    ]
    for star in stars {
        context.addPath(ellipse(center: CGPoint(x: star.x, y: star.y), rx: star.radius, ry: star.radius))
        context.setFillColor(color(0xFFFFFF, star.alpha))
        context.fillPath()
    }

    // The warm glow of the cup against the night.
    let glow = CGGradient(colorsSpace: sRGB, colors: [color(0xFFB347, 0.55), color(0xFFB347, 0)] as CFArray, locations: nil)!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 470), endRadius: 380,
        options: []
    )

    // Saucer: a darker underside, then the lit top.
    context.addPath(ellipse(center: CGPoint(x: 512, y: 330), rx: 270, ry: 50))
    context.setFillColor(color(0xC49A74))
    context.fillPath()
    linearGradient(
        context, clip: ellipse(center: CGPoint(x: 512, y: 342), rx: 262, ry: 42),
        colors: [color(0xFFF6EA), color(0xE6CBAE)],
        from: CGPoint(x: 250, y: 342), to: CGPoint(x: 774, y: 342)
    )

    // Handle first, so the cup covers where it joins.
    context.addArc(center: CGPoint(x: 705, y: 505), radius: 70, startAngle: -1.25, endAngle: 1.25, clockwise: false)
    context.setStrokeColor(color(0xF0DCC4))
    context.setLineWidth(40)
    context.setLineCap(.round)
    context.strokePath()

    // Cup: wide at the rim, rounding into the base.
    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: 322, y: 640))
    cup.addLine(to: CGPoint(x: 702, y: 640))
    cup.addQuadCurve(to: CGPoint(x: 612, y: 362), control: CGPoint(x: 690, y: 380))
    cup.addLine(to: CGPoint(x: 412, y: 362))
    cup.addQuadCurve(to: CGPoint(x: 322, y: 640), control: CGPoint(x: 334, y: 380))
    cup.closeSubpath()
    linearGradient(
        context, clip: cup,
        colors: [color(0xFFFFFF), color(0xF7EADB), color(0xE2C6A6)],
        from: CGPoint(x: 322, y: 500), to: CGPoint(x: 702, y: 500)
    )

    // Rim, then the coffee inside it.
    context.addPath(ellipse(center: CGPoint(x: 512, y: 640), rx: 190, ry: 36))
    context.setFillColor(color(0xFFF9F1))
    context.fillPath()
    linearGradient(
        context, clip: ellipse(center: CGPoint(x: 512, y: 640), rx: 166, ry: 26),
        colors: [color(0x8A5530), color(0x4A2A14)],
        from: CGPoint(x: 512, y: 666), to: CGPoint(x: 512, y: 614)
    )

    // Steam: three soft S-curves, the middle one tallest.
    context.setStrokeColor(color(0xFFFFFF, 0.82))
    context.setLineWidth(26)
    context.setLineCap(.round)
    for (x, top) in [(CGFloat(442), CGFloat(845)), (512, 885), (582, 845)] {
        context.move(to: CGPoint(x: x, y: 705))
        context.addCurve(
            to: CGPoint(x: x, y: top),
            control1: CGPoint(x: x - 48, y: 705 + (top - 705) * 0.35),
            control2: CGPoint(x: x + 48, y: 705 + (top - 705) * 0.65)
        )
        context.strokePath()
    }

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
