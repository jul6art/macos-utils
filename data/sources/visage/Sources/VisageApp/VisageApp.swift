import AppKit
import SwiftUI

/// Visage: a face for the voice of the AI app you already talk to (docs/specs.md).
///
/// Without a window:
/// - `Visage --snapshot <directory>` renders the screens to PNG files: they can be checked without a
///   display (and without the screen recording permission);
/// - `Visage --analyse <audio file> <frames.json>` runs the voice analysis on a file;
/// - `Visage --render <audio file> <video.mov> [<frames directory>]` films the face speaking the file.
@main
enum VisageMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            exit(Snapshots.render(into: URL(fileURLWithPath: arguments[index + 1])))
        }
        if let index = arguments.firstIndex(of: "--render"), index + 2 < arguments.count {
            let framesArgument = index + 3 < arguments.count ? arguments[index + 3] : nil
            let frames = framesArgument.flatMap { $0.hasPrefix("--") ? nil : URL(fileURLWithPath: $0) }
            let face = arguments.firstIndex(of: "--face").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            exit(
                VideoRender.run(
                    input: URL(fileURLWithPath: arguments[index + 1]),
                    output: URL(fileURLWithPath: arguments[index + 2]), frames: frames,
                    face: face ?? FaceLibrary.faces.first?.id ?? FaceLibrary.points,
                    mute: arguments.contains("--mute")))
        }
        if let index = arguments.firstIndex(of: "--analyse"), index + 2 < arguments.count {
            exit(
                AnalysisReport.run(
                    input: URL(fileURLWithPath: arguments[index + 1]),
                    output: URL(fileURLWithPath: arguments[index + 2])))
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
