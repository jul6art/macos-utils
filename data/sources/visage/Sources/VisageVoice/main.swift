import AVFoundation
import AppKit
import Darwin
import NaturalLanguage
import Shared
import SpokenReply

// `visage-voice`: Claude Code's voice, for Visage (spec, § 4.4). Claude Code's plugin (claude-code/) runs it
// from its hooks, through the Visage that runs now:
// - `prompt` (UserPromptSubmit): hushes a reply still being read and, while Visage listens to Claude Code,
//   wakes the voice and tells Claude Code about the 🔊 line;
// - `stop` (Stop): has the reply's 🔊 line read aloud, with the Mac's voice;
// - `notify` (Notification, permission prompts): has the voice say that Claude Code waits for an answer;
// - `say <text>`: has a text read, to try the voice.
// The voice itself is `visage-voice serve`, one process that lives while Visage listens: Visage taps it by
// its process before it speaks, so that no first word is lost (a process born with each reply was caught
// late, seen on 2026-11-27). Its sound carries its own bundle ID; Visage never sees the text.

signal(SIGPIPE, SIG_IGN)
let arguments = Array(CommandLine.arguments.dropFirst())
let visage = UserDefaults(suiteName: ClaudeCodeVoice.visageDomain)
/// The Visage.app this helper ships in (Contents/Helpers/visage-voice): its translations and its faces.
let visageBundle = Bundle.main.executableURL.flatMap {
    Bundle(
        url: $0.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent())
}

/// Visage runs, connected to Claude Code. Read afresh: the voice lives long, and Visage changes it.
func visageListens() -> Bool {
    CFPreferencesAppSynchronize(ClaudeCodeVoice.visageDomain as CFString)
    return !NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeCodeVoice.visageDomain).isEmpty
        && visage?.string(forKey: ClaudeCodeVoice.sourceKey) == ClaudeCodeVoice.sourceID
}

/// The hook's input; read whole even when unused, so that Claude Code never writes into a closed pipe.
func readInput() -> HookInput {
    HookInput.read(FileHandle.standardInput.readDataToEndOfFile())
}

// MARK: - Reaching the voice

/// The voice's socket and lock, in the user's own temporary folder (private to them, and short enough for
/// a socket's path).
enum VoiceLink {
    static let folder: String = {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard length > 0 else { return NSTemporaryDirectory() }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()
    static let socketPath = (folder as NSString).appendingPathComponent(ClaudeCodeVoice.bundleID + ".socket")
    static let lockPath = (folder as NSString).appendingPathComponent(ClaudeCodeVoice.bundleID + ".lock")
    /// The session last prompted: the only one that speaks (`VoiceTurn`).
    static let sessionPath = (folder as NSString).appendingPathComponent(ClaudeCodeVoice.bundleID + ".session")

    static var lastPrompted: String? {
        (try? String(contentsOfFile: sessionPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func address() -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func socketFor(_ address: inout sockaddr_un, _ call: (Int32, UnsafePointer<sockaddr>) -> Int32) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { call(descriptor, $0) }
        }
        guard result == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Hands a message to the voice; false when no voice runs.
    static func send(_ message: VoiceMessage) -> Bool {
        guard var address = address(),
            let descriptor = socketFor(&address, { connect($0, $1, socklen_t(MemoryLayout<sockaddr_un>.size)) })
        else { return false }
        defer { close(descriptor) }
        let data = message.data
        return data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    /// Hands a message to the voice, waking it first if none runs.
    static func deliver(_ message: VoiceMessage) {
        if send(message) { return }
        wake()
        for _ in 0..<30 {
            usleep(100_000)
            if send(message) { return }
        }
    }

    /// Starts the voice, detached from the hook: its own session, and nothing of the hook's pipes, or Claude
    /// Code would wait for it.
    static func wake() {
        guard let executable = Bundle.main.executablePath else { return }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        for descriptor: Int32 in [0, 1, 2] {
            posix_spawn_file_actions_addopen(
                &actions, descriptor, "/dev/null", descriptor == 0 ? O_RDONLY : O_WRONLY, 0)
        }
        var pid = pid_t()
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable), strdup("serve"), nil]
        posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        argv.forEach { free($0) }
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attributes)
    }
}

// MARK: - The voice

/// The face's gender, from faces.json: a woman's face gets a woman's voice when one is installed.
func faceGender() -> VoiceInfo.Gender {
    struct Face: Decodable {
        let id: String
        let gender: Double?
    }
    guard let url = visageBundle?.resourceURL?.appending(path: "Faces/faces.json"),
        let data = try? Data(contentsOf: url), let faces = try? JSONDecoder().decode([Face].self, from: data)
    else { return .unspecified }
    let id = visage?.string(forKey: ClaudeCodeVoice.faceKey) ?? faces.first?.id
    return VoiceChoice.gender(fromFaceValue: faces.first { $0.id == id }?.gender)
}

func voice(for text: String) -> AVSpeechSynthesisVoice? {
    let language =
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? Locale.preferredLanguages.first ?? "en"
    let voices = AVSpeechSynthesisVoice.speechVoices().map { voice in
        VoiceInfo(
            identifier: voice.identifier, name: voice.name, language: voice.language,
            quality: voice.quality.rawValue,
            gender: voice.gender == .male ? .male : voice.gender == .female ? .female : .unspecified,
            isSpecial: voice.voiceTraits.contains(.isNoveltyVoice) || voice.voiceTraits.contains(.isPersonalVoice))
    }
    let best = VoiceChoice.best(
        among: voices, language: language, region: Locale.current.region?.identifier, gender: faceGender())
    return best.flatMap { AVSpeechSynthesisVoice(identifier: $0.identifier) }
        ?? AVSpeechSynthesisVoice(language: language)
}

/// `visage-voice serve`: one at a time, it listens on the socket and speaks what the hooks hand it, until
/// Visage stops listening to Claude Code or nothing came for a while.
final class Voice: NSObject, AVSpeechSynthesizerDelegate {
    /// Visage checks for the voice's process every second, then taps it: the first words wait that long.
    static let warmUp: TimeInterval = 2.5
    static let idleLimit: TimeInterval = 30 * 60

    private let synthesizer = AVSpeechSynthesizer()
    private let readyAt = Date().addingTimeInterval(warmUp)
    private var waiting: String?
    /// The sentence being read: the voice leaves only when it has none.
    private var current: AVSpeechUtterance?
    private var lastActivity = Date()
    private var lastCheck = Date()

    func run() -> Never {
        let lock = open(VoiceLink.lockPath, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0, var address = VoiceLink.address() else { exit(0) }
        unlink(VoiceLink.socketPath)
        guard
            let server = VoiceLink.socketFor(
                &address, { Darwin.bind($0, $1, socklen_t(MemoryLayout<sockaddr_un>.size)) }),
            Darwin.listen(server, 8) == 0
        else { exit(1) }
        chmod(VoiceLink.socketPath, 0o600)
        synthesizer.delegate = self
        openOutput()
        Thread.detachNewThread { [self] in accept(on: server) }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [self] _ in tick() }
        RunLoop.main.run()
        exit(0)
    }

    /// Opens the sound output once: Core Audio then lists the process, silent, and Visage taps it.
    private func openOutput() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        if (try? engine.start()) != nil { engine.stop() }
    }

    private func accept(on server: Int32) {
        while true {
            let client = Darwin.accept(server, nil, nil)
            guard client >= 0 else { continue }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(client, &buffer, buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            close(client)
            if let message = VoiceMessage.read(data) {
                DispatchQueue.main.async { [self] in receive(message) }
            }
        }
    }

    private func receive(_ message: VoiceMessage) {
        lastActivity = Date()
        if message.hush == true {
            waiting = nil
            synthesizer.stopSpeaking(at: .immediate)
        }
        if let text = message.say {
            // A newer reply replaces the one being read.
            synthesizer.stopSpeaking(at: .immediate)
            waiting = text
            tick()
        }
    }

    private func tick() {
        if let text = waiting, Date() >= readyAt {
            waiting = nil
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice(for: text)
            current = utterance
            synthesizer.speak(utterance)
        }
        guard current == nil, waiting == nil, Date().timeIntervalSince(lastCheck) > 5 else { return }
        lastCheck = Date()
        if !visageListens() || Date().timeIntervalSince(lastActivity) > Self.idleLimit { exit(0) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if utterance === current { current = nil }
        lastActivity = Date()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if utterance === current { current = nil }
    }
}

// MARK: - Commands

switch arguments.first {
case "serve":
    Voice().run()
case "prompt":
    if let session = readInput().sessionID {
        try? session.write(toFile: VoiceLink.sessionPath, atomically: true, encoding: .utf8)
    }
    visage?.set(Date().timeIntervalSince1970, forKey: ClaudeCodeVoice.pluginSeenKey)
    visage?.synchronize()
    if visageListens() {
        // Woken now, the voice is tapped by the time the reply comes.
        VoiceLink.deliver(.hushing)
        print(SpokenLine.context)
    } else {
        _ = VoiceLink.send(.hushing)
    }
case "stop":
    let input = readInput()
    if visageListens(), VoiceTurn.speaks(session: input.sessionID, lastPrompted: VoiceLink.lastPrompted),
        let text = input.lastAssistantMessage.flatMap(SpokenLine.speech(for:))
    {
        VoiceLink.deliver(.saying(text))
    }
case "notify":
    let input = readInput()
    if visageListens(), VoiceTurn.speaks(session: input.sessionID, lastPrompted: VoiceLink.lastPrompted) {
        let key = "Claude Code is waiting for your answer, in the terminal."
        VoiceLink.deliver(.saying(visageBundle?.localizedString(forKey: key, value: key, table: nil) ?? key))
    }
case "say" where arguments.count > 1:
    VoiceLink.deliver(.saying(arguments.dropFirst().joined(separator: " ")))
default:
    FileHandle.standardError.write(
        Data(
            """
            usage: visage-voice prompt | stop | notify   (Claude Code's hooks, the JSON on standard input)
                   visage-voice say <text>
            """.utf8))
    exit(64)
}
