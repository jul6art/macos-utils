import Testing
import simd

@testable import FaceAnimation

@Suite("The gaze, and the camera")
struct GazeTests {
    @Test("without the camera the gaze rests on it; with it, on the person, within the eyes' reach")
    func target() {
        #expect(FaceAnimator.gazeTarget(for: nil) == .zero)
        #expect(FaceAnimator.gazeTarget(for: SIMD2(0.5, -0.5)) == SIMD2(0.4, -0.3))
        #expect(FaceAnimator.gazeTarget(for: SIMD2(5, -5)) == SIMD2(0.8, -0.6))
    }

    @Test("the gaze goes to the person the camera finds, and the head turns a little that way")
    func follows() {
        let animator = FaceAnimator(seed: 7)
        animator.lookAt = SIMD2(1, 0)
        var gaze: Float = 0
        var yaw: Float = 0
        let frames = 4 * 60
        for frame in 0..<frames {
            let pose = animator.update(dt: 1.0 / 60, voice: nil, moment: .listening)
            if frame >= frames / 2 {
                gaze += pose.gaze.x / Float(frames / 2)
                yaw += pose.head.y / Float(frames / 2)
            }
        }
        #expect(gaze > 0.5)
        #expect(yaw > 0.03)
    }
}
