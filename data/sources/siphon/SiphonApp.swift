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
        alert.messageText = "Des téléchargements sont en cours"
        alert.informativeText = "Quitter les interrompt. Les fichiers partiels (.part) restent "
            + "dans le dossier : relancer le même lien reprend là où il s'était arrêté."
        alert.addButton(withTitle: "Quitter")
        alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// yt-dlp runs as a separate process: it would outlive the app and keep
    /// downloading with nothing left to show it. Stop it on the way out.
    func applicationWillTerminate(_ notification: Notification) {
        queue.cancelAll()
    }
}
