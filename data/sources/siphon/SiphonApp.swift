import SwiftUI
import AppKit

@main
struct SiphonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single window: a second one would show the same queue twice.
        Window("Siphon", id: "main") {
            ContentView(queue: appDelegate.queue)
        }
        .defaultSize(width: 680, height: 520)

        // Siphon → Settings… (⌘,): what is set once, not for each link.
        Settings {
            SettingsView(queue: appDelegate.queue)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var queue = DownloadQueue()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.activeCount > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Downloads are in progress"
        alert.informativeText = "Quitting stops them. Partial files (.part) stay in the folder: "
            + "adding the same link again resumes where it stopped."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// yt-dlp runs as a separate process: it would outlive the app and keep
    /// downloading with nothing left to show it. Stop it on the way out.
    func applicationWillTerminate(_ notification: Notification) {
        queue.cancelAll()
    }
}
