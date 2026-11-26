import Testing

@testable import HoloRenderer

@Suite("Changing faces")
struct FadeTests {
    @Test("the new face rises as the old one fades, in fadeDuration, never both dark nor both whole")
    func fade() {
        let start = HoloRenderer.fade(elapsed: 0)
        #expect(start.incoming == 0 && start.outgoing == 1)
        let end = HoloRenderer.fade(elapsed: HoloRenderer.fadeDuration)
        #expect(end.incoming == 1 && end.outgoing == 0)
        var last: Float = -1
        for step in 0...60 {
            let weights = HoloRenderer.fade(elapsed: HoloRenderer.fadeDuration * Double(step) / 60)
            #expect(weights.incoming >= last)
            #expect(abs(weights.incoming + weights.outgoing - 1) < 1e-6)
            last = weights.incoming
        }
    }
}
