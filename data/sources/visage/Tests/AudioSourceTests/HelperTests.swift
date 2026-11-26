import Testing

@testable import AudioSource

@Suite("Following the app's helpers")
struct HelperTests {
    private let app = "com.anthropic.claudefordesktop"
    private let helper = "com.anthropic.claudefordesktop.helper"

    @Test("a helper born after the connection calls for a new tap")
    func newHelper() {
        #expect(Connection.missesHelpers(seen: [app, helper], tapped: [app]))
    }

    @Test("the helpers already tapped, or a process with no bundle ID, change nothing")
    func known() {
        #expect(!Connection.missesHelpers(seen: [app, helper, helper], tapped: [app, helper]))
        #expect(!Connection.missesHelpers(seen: [app, ""], tapped: [app]))
        #expect(!Connection.missesHelpers(seen: [], tapped: [app]))
    }
}
