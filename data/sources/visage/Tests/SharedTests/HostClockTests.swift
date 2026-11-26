import Testing

@testable import Shared

@Suite("The host clock")
struct HostClockTests {
    @Test("Seconds and host time convert back and forth")
    func roundTrip() {
        let host = HostClock.hostTime(seconds: 1.25)
        #expect(abs(HostClock.seconds(host) - 1.25) < 1e-6)
    }

    @Test("Time goes forward")
    func monotonic() {
        let before = HostClock.now
        let after = HostClock.now
        #expect(after >= before)
    }
}
