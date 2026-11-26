import Testing

@testable import AudioSource

@Suite("The ring of captured frames")
struct FrameRingTests {
    @Test("A frame reads back as written, until the ring wraps over it")
    func wrapsAround() {
        let ring = FrameRing(capacity: 8)
        for frame in 0..<12 { ring.write(frame: frame, left: Float(frame), right: -Float(frame)) }
        #expect(ring.left(11) == 11)
        #expect(ring.right(11) == -11)
        #expect(ring.left(4) == 4)
        // Frame 3 was overwritten by frame 11.
        #expect(ring.left(3) == 11)
    }

    @Test("Before the first frame is silence")
    func silenceBefore() {
        let ring = FrameRing(capacity: 8)
        ring.write(frame: 0, left: 1, right: 1)
        #expect(ring.left(-3) == 0)
        #expect(ring.right(-1) == 0)
    }

    @Test("Mono copies need frames still in the ring")
    func copyMono() {
        let ring = FrameRing(capacity: 8)
        for frame in 0..<12 { ring.write(frame: frame, left: Float(frame), right: Float(frame) + 2) }
        var buffer = [Float](repeating: 0, count: 4)
        let copied = buffer.withUnsafeMutableBufferPointer {
            ring.copyMono(from: 6, count: 4, written: 12, into: $0.baseAddress!)
        }
        #expect(copied)
        #expect(buffer == [7, 8, 9, 10])

        let overwritten = buffer.withUnsafeMutableBufferPointer {
            ring.copyMono(from: 2, count: 4, written: 12, into: $0.baseAddress!)
        }
        #expect(!overwritten)

        let notYetWritten = buffer.withUnsafeMutableBufferPointer {
            ring.copyMono(from: 10, count: 4, written: 12, into: $0.baseAddress!)
        }
        #expect(!notYetWritten)
    }
}
