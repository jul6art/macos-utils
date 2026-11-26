import AppKit
import SwiftUI

/// Without a window:
///   `VisagePilot --list`                  the audio processes and the public taps
///   `VisagePilot --destroy-tap UID`       destroys a public tap left behind by a dead process
///   `open -W VisagePilot.app --args --mic SECONDS OUT.json`
///                                         the microphone's level, to hear whether a target plays
/// Anything else opens the window.
@main
enum PilotMain {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--list") {
            print("PID    FLAGS   BUNDLE ID  EXECUTABLE")
            ProcessCatalog.all().sorted { $0.pid < $1.pid }.forEach { print($0.summary) }
            print("\ntaps: \(TapCatalog.uids().joined(separator: ", "))")
            return
        }
        if let index = arguments.firstIndex(of: "--destroy-tap"), index + 1 < arguments.count {
            exit(TapCatalog.destroy(uid: arguments[index + 1]))
        }
        if let index = arguments.firstIndex(of: "--mic"), index + 2 < arguments.count,
           let seconds = Double(arguments[index + 1]) {
            exit(MicProbe.run(seconds: seconds, output: URL(fileURLWithPath: arguments[index + 2])))
        }
        PilotApp.main()
    }
}

struct PilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var delegate
    // Not `@State`: in this SDK it is a macro whose plugin ships with Xcode only, and the pilot
    // builds with the Command Line Tools. The app is created once, so a plain reference holds.
    private let model = PilotModel(arguments: CommandLine.arguments)

    var body: some Scene {
        Window("Visage — pilot", id: "pilot") {
            PilotView(model: model)
                .frame(minWidth: 620, minHeight: 760)
        }
    }
}

final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct PilotView: View {
    @Bindable var model: PilotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Bundle ID prefix or executable name", text: $model.target)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isConnected)
                Picker("", selection: $model.mode) {
                    ForEach(TapTargetMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .disabled(model.isConnected)
            }

            HStack {
                Button(model.isConnected ? "Disconnect" : "Connect") {
                    if model.isConnected { model.disconnect(reason: "button") } else { model.connect() }
                }
                .keyboardShortcut(.defaultAction)
                Toggle("Private tap", isOn: $model.privateTap)
                    .disabled(model.isConnected)
                Spacer()
                Button("Crash (R3)", role: .destructive) { model.crash() }
            }

            Picker("Delay", selection: $model.delayMilliseconds) {
                ForEach([0, 80, 150, 300], id: \.self) { Text("\($0) ms").tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Anticipation", selection: $model.anticipationMilliseconds) {
                ForEach([0, 40, 80], id: \.self) { Text("\($0) ms").tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Extra output latency: \(model.extraLatencyMilliseconds) ms")
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { Double(model.extraLatencyMilliseconds) },
                        set: { model.extraLatencyMilliseconds = Int($0) }
                    ),
                    in: -100...300,
                    step: 10
                )
            }

            MouthView(model: model)
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(model.status).font(.headline)
            if let error = model.lastError {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            ScrollView {
                Text(model.details)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 170)
        }
        .padding()
    }
}

/// The sketch of a mouth the pilot judges the sync with: the jaw follows the level of the sound that
/// will be heard when the frame shows, read `anticipation` ahead.
struct MouthView: View {
    let model: PilotModel

    var body: some View {
        TimelineView(.animation) { timeline in
            let opening = model.mouthOpening()
            Canvas { context, size in
                HoloSketch.draw(in: &context, size: size, opening: opening, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .background(Color.black)
    }
}

enum HoloSketch {
    static func draw(in context: inout GraphicsContext, size: CGSize, opening: Double, time: Double) {
        let cyan = Color(red: 0.35, green: 0.95, blue: 1.0)
        let width = size.width
        let height = size.height
        let centre = width / 2

        context.addFilter(.shadow(color: cyan.opacity(0.9), radius: 6))

        let face = CGRect(x: centre - height * 0.32, y: height * 0.06, width: height * 0.64, height: height * 0.88)
        context.stroke(Path(ellipseIn: face), with: .color(cyan.opacity(0.85)), lineWidth: 2)

        for offset in [-0.12, 0.12] {
            let eye = CGRect(x: centre + height * offset - height * 0.05, y: height * 0.36, width: height * 0.1, height: height * 0.035)
            context.stroke(Path(ellipseIn: eye), with: .color(cyan), lineWidth: 2)
        }

        // The upper lip stays; the jaw drops with the opening.
        let mouthWidth = height * (0.2 - 0.04 * opening)
        let top = height * 0.68
        let drop = height * (0.01 + 0.11 * opening)
        var mouth = Path()
        mouth.move(to: CGPoint(x: centre - mouthWidth / 2, y: top))
        mouth.addQuadCurve(to: CGPoint(x: centre + mouthWidth / 2, y: top), control: CGPoint(x: centre, y: top - height * 0.015))
        mouth.addQuadCurve(to: CGPoint(x: centre - mouthWidth / 2, y: top), control: CGPoint(x: centre, y: top + 2 * drop))
        context.fill(mouth, with: .color(cyan.opacity(0.2)))
        context.stroke(mouth, with: .color(cyan), lineWidth: 2.5)

        // Scanlines, drifting down.
        let shift = (time * 30).truncatingRemainder(dividingBy: 4)
        var line = shift
        while line < height {
            context.fill(Path(CGRect(x: 0, y: line, width: width, height: 1)), with: .color(cyan.opacity(0.05)))
            line += 4
        }
    }
}
