import Foundation

/// The captured sound, interleaved stereo, addressed by absolute frame number: frame `n` sits in slot
/// `n % capacity` until frame `n + capacity` overwrites it.
///
/// One writer, the IOProc, on the real-time thread; readers know how far it got through the frame count
/// it publishes. Allocated once, never resized, never locked.
final class FrameRing: @unchecked Sendable {
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: 2 * capacity)
        storage.initialize(repeating: 0, count: 2 * capacity)
    }

    deinit {
        storage.deallocate()
    }

    @inline(__always)
    func write(frame: Int, left: Float, right: Float) {
        let slot = 2 * (frame % capacity)
        storage[slot] = left
        storage[slot + 1] = right
    }

    /// Silence before the first frame.
    @inline(__always)
    func left(_ frame: Int) -> Float { frame >= 0 ? storage[2 * (frame % capacity)] : 0 }

    @inline(__always)
    func right(_ frame: Int) -> Float { frame >= 0 ? storage[2 * (frame % capacity) + 1] : 0 }

    /// Copies `count` frames from `start`, mixed down to mono. Returns false when they are not all still in
    /// the ring, given that `written` frames have been written: not written yet, or already overwritten.
    func copyMono(from start: Int, count: Int, written: Int, into destination: UnsafeMutablePointer<Float>) -> Bool {
        guard start >= 0, start + count <= written, start >= written - capacity else { return false }
        for index in 0..<count {
            let slot = 2 * ((start + index) % capacity)
            destination[index] = 0.5 * (storage[slot] + storage[slot + 1])
        }
        return true
    }
}
