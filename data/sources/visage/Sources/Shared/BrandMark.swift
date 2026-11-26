import Foundation

// The single source of the brand's geometry: the app draws its menu bar icon from it, and the brand kit
// (brand/kit) writes the logo files and renders the app icon from it.

/// A point in the box a mark is drawn in (y grows downwards, as in SVG).
public struct BrandPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One dot of a mark. `home` is where it sits when the face is whole; `logo` is where the logo shows it:
/// `home` again, unless the dot has drifted away with the dust.
public struct BrandDot: Sendable {
    public enum Role: Sendable {
        case face, eye, nose, mouth, neck, speck
    }

    public var role: Role
    public var home: BrandPoint
    public var radius: Double
    public var logo: BrandPoint
    public var logoRadius: Double
    public var logoOpacity: Double

    /// Specks exist only in the dust: invisible while the face is whole.
    public var homeOpacity: Double { role == .speck ? 0 : 1 }
    public var drifts: Bool { role == .speck || logo != home }
}

/// The seeded draws behind the dust: mulberry32, bit for bit the generator of the identity page the
/// direction was chosen on, so every file shows the very dots that were validated.
public struct Mulberry32 {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

public func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Visage's mark, direction C4 « Poussière » (validated on 2026-11-26): a face of dots on a grid, larger
/// towards the rim like the light of an outline, coming apart into dust towards the right.
/// Drawn in a 100 × 100 box.
public enum Mark {
    public static let dots: [BrandDot] = makeDots()

    /// The whole face: a grid of dots inside an ellipse, with eyes, a nose, a mouth and a neck.
    private static func face() -> [(home: BrandPoint, radius: Double, role: BrandDot.Role)] {
        var dots: [(home: BrandPoint, radius: Double, role: BrandDot.Role)] = []
        for j in -8...8 {
            for i in -7...7 {
                let x = 50 + 3.8 * Double(i)
                let y = 46 + 3.8 * Double(j)
                let distance = hypot((x - 50) / 27, (y - 46) / 32)
                guard distance <= 1 else { continue }
                var radius = 0.4 + 1.15 * pow(distance, 3)
                var role = BrandDot.Role.face
                if j == -1, abs(i) == 2 || abs(i) == 3 {
                    radius = 1.7
                    role = .eye
                }
                if i == 0, j == 1 || j == 2 {
                    radius = 1.0
                    role = .nose
                }
                if j == 2, abs(i) == 1 {
                    radius = 0.95
                    role = .nose
                }
                if j == 4, abs(i) <= 2 {
                    radius = 1.5
                    role = .mouth
                }
                dots.append((BrandPoint(x: x, y: y), radius, role))
            }
        }
        for y in [80.2, 84.0] {
            for i in -2...2 {
                dots.append((BrandPoint(x: 50 + 3.8 * Double(i), y: y), 0.7, .neck))
            }
        }
        return dots
    }

    /// The draws happen in a fixed order: change it, and the dust moves.
    private static func makeDots() -> [BrandDot] {
        var random = Mulberry32(seed: 7)
        var dots: [BrandDot] = []
        for (home, radius, role) in face() {
            let dust = smoothstep(50, 78, home.x + (random.next() - 0.5) * 12)
            if dust > 0, random.next() < dust {
                let x = home.x + dust * (4 + 18 * random.next())
                let y = home.y - dust * (2 + 14 * random.next()) + (random.next() - 0.5) * 4
                dots.append(
                    BrandDot(
                        role: role, home: home, radius: radius,
                        logo: BrandPoint(x: x, y: y), logoRadius: radius * (1 - 0.5 * dust),
                        logoOpacity: 1 - 0.55 * dust
                    ))
            } else {
                dots.append(
                    BrandDot(role: role, home: home, radius: radius, logo: home, logoRadius: radius, logoOpacity: 1))
            }
        }
        for _ in 0..<26 {
            let x = 68 + random.next() * 27
            let y = 8 + random.next() * 62
            let radius = 0.3 + random.next() * 0.55
            let opacity = 0.2 + random.next() * 0.45
            dots.append(
                BrandDot(
                    role: .speck, home: BrandPoint(x: x, y: y + 4), radius: radius,
                    logo: BrandPoint(x: x, y: y), logoRadius: radius, logoOpacity: opacity
                ))
        }
        return dots
    }
}

/// The name, in dots: a small dot-matrix lettering drawn by the kit, in the spirit of the Doto typeface,
/// so no font travels with the files. It comes apart towards the right like the mark.
/// One unit per dot, row 0 the top of the « i », rows 2–6 the x-height, rows 7–8 the descender of the « g ».
public enum Wordmark {
    private static let letters: [[String]] = [
        [".....", ".....", "X...X", "X...X", "X...X", ".X.X.", "..X..", ".....", "....."],  // v
        ["X", ".", "X", "X", "X", "X", "X", ".", "."],  // i
        ["....", "....", ".XXX", "X...", ".XX.", "...X", "XXX.", "....", "...."],  // s
        ["....", "....", ".XX.", "...X", ".XXX", "X..X", ".XXX", "....", "...."],  // a
        ["....", "....", ".XXX", "X..X", "X..X", "X..X", ".XXX", "...X", "XXX."],  // g
        ["....", "....", ".XX.", "X..X", "XXXX", "X...", ".XXX", "....", "...."],  // e
    ]

    public static let radius = 0.36
    public static let dots: [BrandDot] = makeDots()

    private static func makeDots() -> [BrandDot] {
        var cells: [BrandPoint] = []
        var column = 0
        for letter in letters {
            for (row, line) in letter.enumerated() {
                for (offset, cell) in line.enumerated() where cell == "X" {
                    cells.append(BrandPoint(x: Double(column + offset), y: Double(row)))
                }
            }
            column += letter[0].count + 1
        }

        var random = Mulberry32(seed: 21)
        var dots: [BrandDot] = []
        // Lighter than the mark's: the name has to stay readable, only the edge of the « e » lets go.
        for home in cells {
            let dust = smoothstep(21, 31, home.x + (random.next() - 0.5) * 3)
            if dust > 0, random.next() < dust * 0.6 {
                let x = home.x + dust * (0.7 + 1.8 * random.next())
                let y = home.y - dust * (0.4 + 1.4 * random.next())
                dots.append(
                    BrandDot(
                        role: .face, home: home, radius: radius,
                        logo: BrandPoint(x: x, y: y), logoRadius: radius * (1 - 0.4 * dust), logoOpacity: 1 - 0.5 * dust
                    ))
            } else {
                dots.append(
                    BrandDot(role: .face, home: home, radius: radius, logo: home, logoRadius: radius, logoOpacity: 1))
            }
        }
        for _ in 0..<9 {
            let x = 25 + random.next() * 5
            let y = -1.5 + random.next() * 6
            let size = 0.12 + random.next() * 0.18
            let opacity = 0.25 + random.next() * 0.35
            dots.append(
                BrandDot(
                    role: .speck, home: BrandPoint(x: x, y: y + 0.6), radius: size,
                    logo: BrandPoint(x: x, y: y), logoRadius: size, logoOpacity: opacity
                ))
        }
        return dots
    }
}

/// The menu bar glyph, 18 × 18 points: an oval of dots, two eyes, a mouth, the right side drifting off.
/// Below 64 pixels, the app icon draws this one too: the full mark turns to mush.
public enum MenuBarGlyph {
    public static let dots: [(point: BrandPoint, radius: Double, opacity: Double)] = {
        var shape: [(BrandPoint, Double)] = (0..<12).map { k in
            let angle = Double(k) / 12 * 2 * Double.pi
            return (BrandPoint(x: 9 + 5.6 * cos(angle), y: 8.6 + 7 * sin(angle)), 0.85)
        }
        shape += [
            (BrandPoint(x: 7, y: 7.6), 1.05), (BrandPoint(x: 11, y: 7.6), 1.05),
            (BrandPoint(x: 7.6, y: 11.1), 0.8), (BrandPoint(x: 9, y: 11.5), 0.8), (BrandPoint(x: 10.4, y: 11.1), 0.8),
        ]
        var random = Mulberry32(seed: 3)
        return shape.map { point, radius in
            guard point.x > 10.5 else { return (point, radius, 1) }
            let x = point.x + 1 + random.next() * 2.2
            let y = point.y - 0.8 - random.next() * 2
            return (BrandPoint(x: x, y: y), radius * 0.7, 0.55)
        }
    }()
}
