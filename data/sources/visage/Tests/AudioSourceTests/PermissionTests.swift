import Testing

@testable import AudioSource

@Suite("Telling a missing permission from a silent app")
struct PermissionTests {
    @Test("a silent app is no sign of anything: Visage just listens")
    func silent() {
        #expect(!Connection.permissionLooksMissing(heardSomething: false, playingFor: 0))
    }

    @Test("an app playing for a while with nothing heard: macOS keeps its sound from Visage")
    func kept() {
        #expect(!Connection.permissionLooksMissing(heardSomething: false, playingFor: Connection.silentPlayLimit - 1))
        #expect(Connection.permissionLooksMissing(heardSomething: false, playingFor: Connection.silentPlayLimit))
    }

    @Test("once anything is heard, the permission is proven, whatever plays after")
    func proven() {
        #expect(!Connection.permissionLooksMissing(heardSomething: true, playingFor: 600))
    }
}
