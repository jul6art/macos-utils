import AppKit
import SwiftUI

/// Visage: a face for the voice of the AI app you already talk to (docs/specs.md).
///
/// `Visage --snapshot <directory>` renders the screens to PNG files and quits: the screens can be checked
/// without a display (and without the screen recording permission).
@main
enum VisageMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            exit(Snapshots.render(into: URL(fileURLWithPath: arguments[index + 1])))
        }
        VisageApp.main()
    }
}

struct VisageApp: App {
    // Not `@State`: it is a macro whose plugin ships with Xcode only, and Visage builds with the Command
    // Line Tools (pilot, § 2.5). The delegate owns the model.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.launch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.connection.disconnect()
    }
}
