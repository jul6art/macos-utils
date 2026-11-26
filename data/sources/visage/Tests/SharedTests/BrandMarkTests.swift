import Testing

@testable import Shared

@Suite("The brand's geometry")
struct BrandMarkTests {
    @Test("The mark keeps the 223 validated dots")
    func markDotCount() {
        #expect(Mark.dots.count == 223)
        #expect(Mark.dots.filter { $0.role == .speck }.count == 26)
    }

    @Test("The first dots are those of the validated logo")
    func firstDots() {
        // brand/mark.svg, checked point by point against the identity page's generator (charter, § 7).
        let first = Mark.dots[0]
        #expect(abs(first.logo.x - 42.4) < 1e-9)
        #expect(abs(first.logo.y - 15.6) < 1e-9)
        #expect(abs(first.logoRadius - 1.52) < 0.005)
        #expect(abs(Mark.dots[1].logoRadius - 1.42) < 0.005)
    }

    @Test("The dust drifts towards the right, never the left")
    func dustDriftsRight() {
        for dot in Mark.dots where dot.role != .speck && dot.logo != dot.home {
            #expect(dot.logo.x > dot.home.x)
            #expect(dot.logoOpacity < 1)
        }
    }

    @Test("The face keeps two eyes, a nose and a mouth")
    func features() {
        #expect(Mark.dots.filter { $0.role == .eye }.count == 4)
        #expect(Mark.dots.filter { $0.role == .mouth }.count == 5)
        #expect(Mark.dots.contains { $0.role == .nose })
    }

    @Test("The menu bar glyph fits its 18 points")
    func menuBarGlyph() {
        #expect(MenuBarGlyph.dots.count == 17)
        for (point, radius, _) in MenuBarGlyph.dots {
            #expect(point.x - radius >= 0 && point.x + radius <= 18)
            #expect(point.y - radius >= 0 && point.y + radius <= 18)
        }
    }

    @Test("The draws are the same every time")
    func seededDraws() {
        var first = Mulberry32(seed: 7)
        var second = Mulberry32(seed: 7)
        for _ in 0..<100 { #expect(first.next() == second.next()) }
    }
}
