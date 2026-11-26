import Testing

@testable import AudioSource

@Suite("Keeping the capture alive")
struct StallTests {
    @Test("a capture that stopped under a playing app is restarted, after a moment")
    func restart() {
        #expect(Connection.stallVerdict(stalled: 0, restarts: 0) == .fine)
        #expect(Connection.stallVerdict(stalled: Connection.stallLimit - 1, restarts: 0) == .fine)
        #expect(Connection.stallVerdict(stalled: Connection.stallLimit, restarts: 0) == .restart)
    }

    @Test("restarts in vain end in a refusal, not in a loop")
    func refused() {
        #expect(
            Connection.stallVerdict(stalled: Connection.stallLimit, restarts: Connection.restartLimit - 1) == .restart)
        #expect(Connection.stallVerdict(stalled: Connection.stallLimit, restarts: Connection.restartLimit) == .refused)
    }
}
