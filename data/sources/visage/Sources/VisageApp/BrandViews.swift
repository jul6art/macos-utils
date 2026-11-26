import AppKit
import Shared
import SwiftUI

/// The mark, alive (docs/charte.md, § 2): every ten seconds the whole face comes apart into the logo's
/// dust, then gathers again; the dots on the right leave first and come back last. The very timing of
/// `brand/mark-animated.svg`, from the same geometry. Still when the Mac asks for less motion.
struct AnimatedMark: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, canvasSize in
                let time = reduceMotion ? nil : timeline.date.timeIntervalSinceReferenceDate
                MarkDrawing.draw(in: &context, size: canvasSize, glow: true, time: time)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Visage")
    }
}

/// Where a dot of the mark stands at `time`: 0 whole, 1 in the logo's dust (`SVG.dissolving`).
enum MarkMotion {
    static let cycle = 10.0

    static func progress(of dot: BrandDot, at time: Double) -> Double {
        guard dot.drifts else { return 0 }
        let stagger = min(max((78 - dot.home.x) / (78 - 50), 0), 1) * 0.08
        let keys = [0.18 + stagger, 0.40 + stagger, 0.70 - stagger, 0.92 - stagger]
        let t = time.truncatingRemainder(dividingBy: cycle) / cycle
        if t < keys[0] || t >= keys[3] { return 0 }
        if t < keys[1] { return bezier(0.45, 0, 0.2, 1, (t - keys[0]) / (keys[1] - keys[0])) }
        if t < keys[2] { return 1 }
        return 1 - bezier(0.5, 0, 0.3, 1, (t - keys[2]) / (keys[3] - keys[2]))
    }

    /// CSS's cubic-bezier(x1, y1, x2, y2) at `x`, as SMIL's keySplines read it.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        func curve(_ a: Double, _ b: Double, _ s: Double) -> Double {
            3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s
        }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if curve(x1, x2, middle) < x { low = middle } else { high = middle }
        }
        return curve(y1, y2, (low + high) / 2)
    }
}

/// The name in dots, as the charter writes it (§ 4): no font travels with Visage.
struct WordmarkView: View {
    let height: CGFloat

    /// The dots' bounds, their radius included.
    private static let box: CGRect = {
        let dots = Wordmark.dots.filter { $0.logoOpacity > 0 }
        let xs = dots.map(\.logo.x)
        let ys = dots.map(\.logo.y)
        let radius = Wordmark.radius
        let minX = (xs.min() ?? 0) - radius
        let minY = (ys.min() ?? 0) - radius
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) + radius - minX, height: (ys.max() ?? 0) + radius - minY)
    }()

    var body: some View {
        let box = Self.box
        Canvas { context, size in
            let scale = size.height / box.height
            for dot in Wordmark.dots where dot.logoOpacity > 0 {
                let radius = dot.logoRadius * scale
                let rect = CGRect(
                    x: (dot.logo.x - box.minX) * scale - radius, y: (dot.logo.y - box.minY) * scale - radius,
                    width: 2 * radius, height: 2 * radius)
                context.fill(Path(ellipseIn: rect), with: .color(Palette.braise.opacity(dot.logoOpacity)))
            }
        }
        .frame(width: height * box.width / box.height, height: height)
        .accessibilityLabel("Visage")
    }
}

/// A block of the branded screens: a lifted charbon surface, a fine brou edge, a title.
struct BrandCard<Content: View>: View {
    let title: String
    var number: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let number {
                    Text("\(number)")
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.braise))
                        .foregroundStyle(Color(nsColor: Palette.charbon))
                }
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.orPale)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.brou, lineWidth: 1))
    }
}

/// A window in the charter's colours: charbon, its title bar melted into it, dark controls.
@MainActor
enum BrandWindow {
    static func style(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.charbon
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
    }
}

/// The face as the settings make it, at rest, beside them: each choice shows at once.
struct FacePreview: View {
    let model: AppModel
    var width: CGFloat = 260

    var body: some View {
        VStack(spacing: 8) {
            HoloView(driver: model.previewDriver)
                .frame(width: width, height: width * 1.25)
                .background(Color(nsColor: Palette.charbon))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.brou))
            Text("Preview").font(.caption).foregroundStyle(Palette.cendreClaire)
        }
    }
}
