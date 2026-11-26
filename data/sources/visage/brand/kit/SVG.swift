import Foundation

/// The brand files, as SVG. The animated ones use SMIL: it plays in every browser and in a GitHub README,
/// with no script.
enum BrandSVG {
    enum Colour {
        static let charbon = "#0E0C0A"
        static let braise = "#FFC978"
        static let orPale = "#FFE9C4"
        static let brou = "#3A2612"
        static let black = "#000000"
    }

    static func files() -> [(name: String, content: String)] {
        let markBox = "0 0 100 100"
        let wordBox = Bounds(Wordmark.dots).viewBox
        return [
            ("mark.svg", document(viewBox: markBox, width: 512, height: 512, body: still(Mark.dots, fill: Colour.braise))),
            ("mark-light.svg", document(viewBox: markBox, width: 512, height: 512, body: still(Mark.dots, fill: Colour.brou))),
            ("mark-mono.svg", document(viewBox: markBox, width: 512, height: 512, body: still(Mark.dots, fill: Colour.black))),
            ("mark-animated.svg", document(viewBox: markBox, width: 512, height: 512, body: dissolving(Mark.dots, fill: Colour.braise, from: 50, to: 78))),
            ("mark-speaking.svg", document(viewBox: markBox, width: 512, height: 512, body: speaking())),
            ("wordmark.svg", document(viewBox: wordBox, width: 480, height: 480 * Bounds(Wordmark.dots).ratio, body: still(Wordmark.dots, fill: Colour.braise))),
            ("lockup.svg", lockup(fill: Colour.braise)),
            ("lockup-light.svg", lockup(fill: Colour.brou)),
            ("banner.svg", banner(animated: false)),
            ("banner-animated.svg", banner(animated: true)),
            ("app-icon.svg", appIcon()),
            ("menubar.svg", menuBar()),
        ]
    }

    // MARK: - Documents

    private static func document(viewBox: String, width: Double, height: Double, defs: [String] = [], body: [String]) -> String {
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\" width=\"\(number(width))\" height=\"\(number(height))\" role=\"img\" aria-label=\"Visage\">",
            "  <title>Visage</title>",
        ]
        if !defs.isEmpty {
            lines.append("  <defs>")
            lines += defs.map { "    " + $0 }
            lines.append("  </defs>")
        }
        lines += body.map { "  " + $0 }
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func lockup(fill: String) -> String {
        // The name's x-height (rows 2–6) sits on the face's eyes-to-mouth band.
        let body = ["<g>"] + still(Mark.dots, fill: fill).map { "  " + $0 } + ["</g>"]
            + ["<g transform=\"translate(112 33) scale(3.6)\">"] + still(Wordmark.dots, fill: fill).map { "  " + $0 } + ["</g>"]
        return document(viewBox: "0 0 226 100", width: 678, height: 300, body: body)
    }

    /// The README banner: the mark over its projector, the name, scanlines; animated, the mark comes
    /// apart and back, a scan band sweeps down, the light flickers.
    private static func banner(animated: Bool) -> String {
        let defs = [
            "<clipPath id=\"card\"><rect width=\"960\" height=\"320\" rx=\"28\"/></clipPath>",
            "<radialGradient id=\"ground\" cx=\".2\" cy=\"1\" r=\".9\"><stop offset=\"0\" stop-color=\"#3A2612\"/><stop offset=\"1\" stop-color=\"\(Colour.charbon)\"/></radialGradient>",
            "<radialGradient id=\"beam\"><stop offset=\"0\" stop-color=\"\(Colour.braise)\" stop-opacity=\".35\"/><stop offset=\"1\" stop-color=\"\(Colour.braise)\" stop-opacity=\"0\"/></radialGradient>",
            "<pattern id=\"scan\" width=\"4\" height=\"4\" patternUnits=\"userSpaceOnUse\"><rect width=\"4\" height=\"1\" fill=\"\(Colour.orPale)\" opacity=\".05\"/></pattern>",
            "<linearGradient id=\"sweep\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"\(Colour.braise)\" stop-opacity=\"0\"/><stop offset=\".5\" stop-color=\"\(Colour.braise)\" stop-opacity=\".1\"/><stop offset=\"1\" stop-color=\"\(Colour.braise)\" stop-opacity=\"0\"/></linearGradient>",
            glowFilter(id: "glow-mark", deviation: 0.8),
            glowFilter(id: "glow-word", deviation: 0.22),
        ]
        let mark = animated ? dissolving(Mark.dots, fill: Colour.braise, from: 50, to: 78) : still(Mark.dots, fill: Colour.braise)
        var light = ["<g>"]
        if animated {
            light.append("  <animate attributeName=\"opacity\" dur=\"6s\" repeatCount=\"indefinite\" calcMode=\"discrete\" keyTimes=\"0;.41;.42;.77;.78\" values=\"1;.86;1;.93;1\"/>")
        }
        light += ["  <g transform=\"translate(90 34) scale(2.4)\" filter=\"url(#glow-mark)\">"] + mark.map { "    " + $0 } + ["  </g>"]
        light += ["  <g transform=\"translate(380 104) scale(15)\" filter=\"url(#glow-word)\">"] + still(Wordmark.dots, fill: Colour.braise).map { "    " + $0 } + ["  </g>"]
        light.append("</g>")

        var body = ["<g clip-path=\"url(#card)\">", "  <rect width=\"960\" height=\"320\" fill=\"url(#ground)\"/>", "  <ellipse cx=\"210\" cy=\"292\" rx=\"140\" ry=\"28\" fill=\"url(#beam)\"/>"]
        body += light.map { "  " + $0 }
        body.append("  <rect width=\"960\" height=\"320\" fill=\"url(#scan)\"/>")
        if animated {
            body.append("  <rect y=\"-140\" width=\"960\" height=\"140\" fill=\"url(#sweep)\"><animate attributeName=\"y\" values=\"-140;320\" dur=\"5s\" repeatCount=\"indefinite\"/></rect>")
        }
        body.append("</g>")
        return document(viewBox: "0 0 960 320", width: 960, height: 320, defs: defs, body: body)
    }

    /// The reference drawing of the app icon. The app's build renders the .icns from the same geometry,
    /// with Core Graphics (Icon.swift).
    private static func appIcon() -> String {
        let defs = [
            "<clipPath id=\"tile\"><rect x=\"100\" y=\"100\" width=\"824\" height=\"824\" rx=\"185\"/></clipPath>",
            "<radialGradient id=\"ground\" cx=\".15\" cy=\"1\" r=\"1\"><stop offset=\"0\" stop-color=\"#4A3016\"/><stop offset=\".75\" stop-color=\"\(Colour.charbon)\"/></radialGradient>",
            "<radialGradient id=\"beam\"><stop offset=\"0\" stop-color=\"\(Colour.braise)\" stop-opacity=\".35\"/><stop offset=\"1\" stop-color=\"\(Colour.braise)\" stop-opacity=\"0\"/></radialGradient>",
            "<pattern id=\"scan\" width=\"6\" height=\"6\" patternUnits=\"userSpaceOnUse\"><rect width=\"6\" height=\"1.5\" fill=\"\(Colour.orPale)\" opacity=\".05\"/></pattern>",
            "<filter id=\"shadow\" x=\"-10%\" y=\"-10%\" width=\"120%\" height=\"125%\"><feDropShadow dx=\"0\" dy=\"10\" stdDeviation=\"12\" flood-color=\"#000\" flood-opacity=\".35\"/></filter>",
            glowFilter(id: "glow", deviation: 1.2),
        ]
        var body = [
            "<rect x=\"100\" y=\"100\" width=\"824\" height=\"824\" rx=\"185\" fill=\"url(#ground)\" filter=\"url(#shadow)\"/>",
            "<g clip-path=\"url(#tile)\">",
            "  <ellipse cx=\"512\" cy=\"860\" rx=\"260\" ry=\"50\" fill=\"url(#beam)\"/>",
            "  <rect x=\"100\" y=\"100\" width=\"824\" height=\"824\" fill=\"url(#scan)\"/>",
            "  <g transform=\"translate(212 150) scale(6)\" filter=\"url(#glow)\">",
        ]
        body += still(Mark.dots, fill: Colour.braise).map { "    " + $0 }
        body += ["  </g>", "</g>"]
        return document(viewBox: "0 0 1024 1024", width: 1024, height: 1024, defs: defs, body: body)
    }

    /// The menu bar glyph, black: macOS draws template images in the menu bar's own colour.
    private static func menuBar() -> String {
        var body = ["<g fill=\"\(Colour.black)\">"]
        for (point, radius, opacity) in MenuBarGlyph.dots {
            body.append("  " + circle(point, radius, opacity))
        }
        body.append("</g>")
        return document(viewBox: "0 0 18 18", width: 18, height: 18, body: body)
    }

    // MARK: - Dots

    /// The logo as it stands: the face, and its dust.
    private static func still(_ dots: [BrandDot], fill: String) -> [String] {
        ["<g fill=\"\(fill)\">"] + dots.map { "  " + circle($0.logo, $0.logoRadius, $0.logoOpacity) } + ["</g>"]
    }

    private static let cycle = "10s"
    private static let splines = "0 0 1 1;.45 0 .2 1;0 0 1 1;.5 0 .3 1;0 0 1 1"

    /// Whole, then coming apart into the logo's dust, then whole again, every ten seconds. The dots on the
    /// right leave first and come back last.
    private static func dissolving(_ dots: [BrandDot], fill: String, from: Double, to: Double) -> [String] {
        var lines = ["<g fill=\"\(fill)\">"]
        for dot in dots {
            guard dot.drifts else {
                lines.append("  " + circle(dot.home, dot.radius, 1))
                continue
            }
            let stagger = min(max((to - dot.home.x) / (to - from), 0), 1) * 0.08
            let times = [0, 0.18 + stagger, 0.40 + stagger, 0.70 - stagger, 0.92 - stagger, 1].map(number).joined(separator: ";")
            let animate = { (attribute: String, whole: Double, logo: Double) -> String in
                let values = [whole, whole, logo, logo, whole, whole].map(number).joined(separator: ";")
                return "    <animate attributeName=\"\(attribute)\" dur=\"\(cycle)\" repeatCount=\"indefinite\" calcMode=\"spline\" keyTimes=\"\(times)\" keySplines=\"\(splines)\" values=\"\(values)\"/>"
            }
            lines.append("  " + circle(dot.home, dot.radius, dot.homeOpacity, open: true))
            lines.append(animate("cx", dot.home.x, dot.logo.x))
            lines.append(animate("cy", dot.home.y, dot.logo.y))
            if dot.radius != dot.logoRadius { lines.append(animate("r", dot.radius, dot.logoRadius)) }
            if dot.homeOpacity != dot.logoOpacity { lines.append(animate("opacity", dot.homeOpacity, dot.logoOpacity)) }
            lines.append("  </circle>")
        }
        lines.append("</g>")
        return lines
    }

    /// The whole face, talking: the mouth opens and closes on an irregular rhythm, the eyes blink on
    /// their own, slower one, so the two never fall into step.
    private static func speaking() -> [String] {
        let mouth = [1, 1.8, 1.13, 2.0, 1.07, 1.53, 1, 1.87, 1.07, 1]
        let mouthTimes = (0..<mouth.count).map { number(Double($0) / Double(mouth.count - 1)) }.joined(separator: ";")
        let mouthSplines = Array(repeating: ".4 0 .6 1", count: mouth.count - 1).joined(separator: ";")

        var lines = [
            "<g fill=\"\(Colour.braise)\">",
            "  <animate attributeName=\"opacity\" dur=\"2.4s\" repeatCount=\"indefinite\" values=\".9;1;.94;1;.9\"/>",
        ]
        for dot in Mark.dots where dot.role != .speck {
            let x = number(dot.home.x)
            let y = number(dot.home.y)
            let r = number(dot.radius)
            switch dot.role {
            case .mouth:
                // The middle of the mouth opens most.
                let weight = 1 - 0.12 * abs(dot.home.x - 50) / 3.8
                let heights = mouth.map { dot.radius * (1 + ($0 - 1) * weight) }
                lines.append("  <ellipse cx=\"\(x)\" cy=\"\(y)\" rx=\"\(r)\" ry=\"\(r)\">")
                lines.append("    <animate attributeName=\"ry\" dur=\"2.4s\" repeatCount=\"indefinite\" calcMode=\"spline\" keyTimes=\"\(mouthTimes)\" keySplines=\"\(mouthSplines)\" values=\"\(heights.map(number).joined(separator: ";"))\"/>")
                lines.append("    <animate attributeName=\"cy\" dur=\"2.4s\" repeatCount=\"indefinite\" calcMode=\"spline\" keyTimes=\"\(mouthTimes)\" keySplines=\"\(mouthSplines)\" values=\"\(heights.map { number(dot.home.y + ($0 - dot.radius) * 0.6) }.joined(separator: ";"))\"/>")
                lines.append("  </ellipse>")
            case .eye:
                let closed = number(dot.radius * 0.18)
                lines.append("  <ellipse cx=\"\(x)\" cy=\"\(y)\" rx=\"\(r)\" ry=\"\(r)\">")
                lines.append("    <animate attributeName=\"ry\" dur=\"4.6s\" repeatCount=\"indefinite\" keyTimes=\"0;.88;.91;.95;1\" values=\"\(r);\(r);\(closed);\(r);\(r)\"/>")
                lines.append("  </ellipse>")
            default:
                lines.append("  " + circle(dot.home, dot.radius, 1))
            }
        }
        lines.append("</g>")
        return lines
    }

    // MARK: - Helpers

    private static func circle(_ point: BrandPoint, _ radius: Double, _ opacity: Double, open: Bool = false) -> String {
        let fade = opacity < 1 ? " opacity=\"\(number(opacity))\"" : ""
        return "<circle cx=\"\(number(point.x))\" cy=\"\(number(point.y))\" r=\"\(number(radius))\"\(fade)\(open ? ">" : "/>")"
    }

    private static func glowFilter(id: String, deviation: Double) -> String {
        "<filter id=\"\(id)\" x=\"-20%\" y=\"-20%\" width=\"140%\" height=\"140%\"><feGaussianBlur stdDeviation=\"\(number(deviation))\" result=\"blur\"/><feMerge><feMergeNode in=\"blur\"/><feMergeNode in=\"SourceGraphic\"/></feMerge></filter>"
    }

    /// Two decimals at most, no trailing zeros.
    static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// The box the dots of a mark fill, with a little margin.
    private struct Bounds {
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double

        init(_ dots: [BrandDot]) {
            var left: [Double] = []
            var top: [Double] = []
            var right: [Double] = []
            var bottom: [Double] = []
            for dot in dots {
                for (point, radius) in [(dot.home, dot.radius), (dot.logo, dot.logoRadius)] {
                    left.append(point.x - radius)
                    top.append(point.y - radius)
                    right.append(point.x + radius)
                    bottom.append(point.y + radius)
                }
            }
            minX = left.min()! - 0.3
            minY = top.min()! - 0.3
            maxX = right.max()! + 0.3
            maxY = bottom.max()! + 0.3
        }

        var viewBox: String { [minX, minY, maxX - minX, maxY - minY].map(BrandSVG.number).joined(separator: " ") }
        var ratio: Double { (maxY - minY) / (maxX - minX) }
    }
}
