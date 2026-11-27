import AppKit
import Foundation
import Shared

/// An app whose voice Visage gives a face to. Visage never talks to the app: it taps the sound it plays.
public struct AIApp: Identifiable, Hashable, Sendable {
    /// How Visage finds the voice.
    public enum Kind: Hashable, Sendable {
        /// An app, which Visage opens on connecting if it is not running.
        case app
        /// Siri: its voice comes from a system service born for each answer, `sirittsd`, which nothing needs
        /// to open (spec, § 4.5).
        case siri
        /// Claude Code: its replies are read aloud by Visage's helper, `visage-voice`, which its plugin runs
        /// (spec, § 4.4). Visage taps the helper; the `claude` process holds the microphone of its dictation.
        case claudeCode
    }

    public let id: String
    public let name: String
    /// Candidates, the first one installed wins. The pilot confirms them with the app at hand (test 5).
    public let bundleIDs: [String]
    public let downloadURL: URL?
    public let kind: Kind

    public init(id: String, name: String, bundleIDs: [String], downloadURL: URL?, kind: Kind = .app) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.downloadURL = downloadURL
        self.kind = kind
    }

    public static let claude = AIApp(
        id: "claude", name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"],
        downloadURL: URL(string: "https://claude.ai/download"))

    public static let chatGPT = AIApp(
        id: "chatgpt", name: "ChatGPT", bundleIDs: ["com.openai.chat", "com.openai.chatgpt"],
        downloadURL: URL(string: "https://openai.com/chatgpt/download/"))

    /// Any other app that plays sound, by bundle ID (or executable name, for a command-line tool).
    public static func other(_ identifier: String, name: String) -> AIApp {
        AIApp(id: "other:" + identifier, name: name, bundleIDs: [identifier], downloadURL: nil)
    }

    public static let claudeCode = AIApp(
        id: ClaudeCodeVoice.sourceID, name: "Claude Code", bundleIDs: [ClaudeCodeVoice.bundleID],
        downloadURL: URL(string: "https://code.claude.com/docs/en/setup"), kind: .claudeCode)

    /// Siri speaks through `sirittsd`, Siri's speech service, launched for each spoken answer and gone five
    /// seconds after (its launch agent's exit timeout); seen on macOS 27 on 2026-11-27.
    public static let siri = AIApp(
        id: "siri", name: "Siri", bundleIDs: ["com.apple.sirittsd"], downloadURL: nil, kind: .siri)

    /// Where Siri lives, on every Mac that has it.
    static let siriApp = URL(fileURLWithPath: "/System/Library/CoreServices/Siri.app")

    public static let known: [AIApp] = [.claude, .chatGPT, .siri, .claudeCode]

    /// Whether connecting opens the app when it is not running.
    public var opensOnConnect: Bool { kind == .app }

    /// Whether its sound plays as is, only analysed: Siri lowers every other sound while it speaks, and
    /// Visage's playback with it, so that nothing was heard when Visage muted it to play it back (seen on
    /// 2026-11-27). The face then follows the voice live, without the lead the delay gives (spec, § 4.5).
    public var passesThrough: Bool { kind == .siri }

    /// Where Claude Code's installers put `claude`: the native installer, Homebrew (Apple silicon, Intel),
    /// the former local install.
    public static let claudeCodeLocations = [
        "~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "~/.claude/local/claude",
    ]

    /// The installed copy's bundle ID and location, if any. Claude Code's is Visage's helper, provided
    /// `claude` is installed.
    @MainActor
    public var installation: (bundleID: String, url: URL)? {
        if kind == .siri {
            return FileManager.default.fileExists(atPath: Self.siriApp.path) ? (bundleIDs[0], Self.siriApp) : nil
        }
        if kind == .claudeCode {
            let helper = Bundle.main.bundleURL.appending(path: ClaudeCodeVoice.helperPath)
            let claude = Self.claudeCodeLocations.contains {
                FileManager.default.isExecutableFile(atPath: NSString(string: $0).expandingTildeInPath)
            }
            return claude && FileManager.default.isExecutableFile(atPath: helper.path)
                ? (ClaudeCodeVoice.bundleID, helper) : nil
        }
        for bundleID in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return (bundleID, url)
            }
        }
        return nil
    }

    @MainActor
    public var isRunning: Bool {
        bundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// Whether a process, besides the app's own, listens for it: Claude Code's dictation (`/voice`) records
    /// in the `claude` process, which the native installer names after its version
    /// (`~/.local/share/claude/versions/2.1.332`).
    public func listens(through process: AudioProcess) -> Bool {
        guard kind == .claudeCode else { return false }
        return process.executableName == "claude" || process.executable.contains("/claude/versions/")
    }
}
