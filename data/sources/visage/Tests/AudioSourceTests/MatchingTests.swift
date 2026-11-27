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
        #expect(AIApp.known.map(\.id) == ["claude", "chatgpt", "siri", "claudecode"])
        #expect(AIApp.claude.downloadURL?.host == "claude.ai")
        #expect(AIApp.other("com.example.voice", name: "Example").id == "other:com.example.voice")
    }

    @Test("Claude Code is its voice, Visage's helper, which connecting never opens")
    func claudeCode() {
        #expect(AIApp.claudeCode.bundleIDs == ["com.devinthehood.visage.voice"])
        #expect(!AIApp.claudeCode.opensOnConnect)
        #expect(AIApp.claude.opensOnConnect)
        // The helper's sound matches it, its bundle ID ending neither a prefix nor Visage's own.
        let helper = process(
            "com.devinthehood.visage.voice", executable: "/Applications/Visage.app/Contents/Helpers/visage-voice")
        #expect(
            AudioProcesses.matching(AIApp.claudeCode.bundleIDs[0], in: [helper, process("com.devinthehood.visage")])
                == [helper])
    }

    @Test("Siri is its speech service, which connecting never opens")
    func siri() {
        #expect(AIApp.siri.bundleIDs == ["com.apple.sirittsd"])
        #expect(!AIApp.siri.opensOnConnect)
        let service = process(
            "com.apple.sirittsd", executable: "/System/Library/PrivateFrameworks/SiriTTSService.framework/sirittsd")
        #expect(AudioProcesses.matching("com.apple.sirittsd", in: [service, process("com.apple.Siri")]) == [service])
    }

    @Test("Claude Code's dictation listens through the claude process, whatever installed it")
    func claudeCodeListens() {
        let native = process("", executable: "/Users/me/.local/share/claude/versions/2.1.332")
        let homebrew = process("", executable: "/opt/homebrew/Caskroom/claude-code/2.1.332/claude")
        let other = process("com.anthropic.claudefordesktop")
        #expect(AIApp.claudeCode.listens(through: native))
        #expect(AIApp.claudeCode.listens(through: homebrew))
        #expect(!AIApp.claudeCode.listens(through: other))
        #expect(!AIApp.claude.listens(through: native))
    }
}
