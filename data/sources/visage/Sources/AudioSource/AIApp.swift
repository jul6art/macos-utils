import AppKit
import Foundation

/// An app whose voice Visage gives a face to. Visage never talks to the app: it taps the sound it plays.
public struct AIApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Candidates, the first one installed wins. The pilot confirms them with the app at hand (test 5).
    public let bundleIDs: [String]
    public let downloadURL: URL?

    public init(id: String, name: String, bundleIDs: [String], downloadURL: URL?) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.downloadURL = downloadURL
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

    public static let known: [AIApp] = [.claude, .chatGPT]

    /// The installed copy's bundle ID and location, if any.
    @MainActor
    public var installation: (bundleID: String, url: URL)? {
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
}
