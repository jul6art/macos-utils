import AVFoundation
import QuartzCore
import Vision

/// The camera option (spec, § 7.1, point 7; § 8.2, point 7): where the person in front of the screen is,
/// found by Vision ten times a second. Nothing is recorded: each image is read, then dropped.
final class CameraTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Access: Sendable {
        case allowed
        case denied
        case noCamera
    }

    /// Where the person is, seen from the screen (`position(of:)`); nil while none is seen, after a second and
    /// a half.
    var position: SIMD2<Float>? { lock.withLock { latest } }

    private let lock = NSLock()
    private var latest: SIMD2<Float>?
    private var lastSeen: CFTimeInterval = 0
    private var lastAnalysis: CFTimeInterval = 0
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "visage.camera")

    /// Asks for the camera if need be, then starts.
    func start() async -> Access {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device)
        else { return .noCamera }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        let session = session
        queue.sync {
            session.beginConfiguration()
            session.sessionPreset = .low
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            // The image as the camera sees it, never mirrored: macOS mirrored the built-in camera's frames on
            // its own, and the face looked away from the person, to the other side (2026-11-28).
            if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            session.commitConfiguration()
            session.startRunning()
        }
        return .allowed
    }

    func stop() {
        let session = session
        queue.async {
            session.stopRunning()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
        }
        lock.withLock { latest = nil }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastAnalysis >= 0.1, let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: image, orientation: .up).perform([request])
        let face = request.results?.max { $0.boundingBox.width < $1.boundingBox.width }
        lock.withLock {
            if let face {
                let found = Self.position(of: face.boundingBox)
                latest = latest.map { $0 + (found - $0) * 0.5 } ?? found
                lastSeen = now
            } else if now - lastSeen > 1.5 {
                latest = nil
            }
        }
    }

    /// A face's box in the camera's image (Vision's: from 0 to 1, origin at the bottom left, never mirrored)
    /// to where the person stands, seen from the screen: x to the screen's right, y up, each from −1 to 1.
    /// The camera faces them: their right is the image's left.
    static func position(of box: CGRect) -> SIMD2<Float> {
        SIMD2(Float(0.5 - box.midX) * 2, Float(box.midY - 0.5) * 2)
    }
}
