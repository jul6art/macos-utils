import Testing

@testable import AudioSource

@Suite("Finding an app's audio processes")
struct MatchingTests {
    private func process(_ bundleID: String, executable: String = "/Applications/X.app/Contents/MacOS/X")
        -> AudioProcess
    {
        AudioProcess(objectID: 1, pid: 1, bundleID: bundleID, executable: executable, isRunningOutput: true)
    }

    @Test("The app and its helpers match")
    func appAndHelpers() {
        let processes = [
            process("com.anthropic.claudefordesktop"),
            process("com.anthropic.claudefordesktop.helper"),
            process("com.google.Chrome.helper"),
        ]
        let matches = AudioProcesses.matching("com.anthropic.claudefordesktop", in: processes)
        #expect(matches.map(\.bundleID) == ["com.anthropic.claudefordesktop", "com.anthropic.claudefordesktop.helper"])
    }

    @Test("A longer bundle ID that only starts the same does not match")
    func noFalsePrefix() {
        let matches = AudioProcesses.matching(
            "com.openai.chat", in: [process("com.openai.chatgpt"), process("com.openai.chat")])
        #expect(matches.map(\.bundleID) == ["com.openai.chat"])
    }

    @Test("A command-line tool matches by executable name")
    func executableName() {
        let matches = AudioProcesses.matching("afplay", in: [process("", executable: "/usr/bin/afplay")])
        #expect(matches.count == 1)
    }

    @Test("Nothing matches an empty target")
    func emptyTarget() {
        #expect(AudioProcesses.matching("", in: [process("")]).isEmpty)
    }

    @Test("The known apps and their download pages")
    func knownApps() {
        #expect(AIApp.known.map(\.id) == ["claude", "chatgpt"])
        #expect(AIApp.claude.downloadURL?.host == "claude.ai")
        #expect(AIApp.other("com.example.voice", name: "Example").id == "other:com.example.voice")
    }
}
