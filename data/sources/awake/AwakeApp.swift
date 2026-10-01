import SwiftUI

@main
struct AwakeApp: App {
    @StateObject private var model = AwakeModel()

    var body: some Scene {
        MenuBarExtra {
            AwakeMenu(model: model)
        } label: {
            // Deliberately two different glyphs, not a fill variant: at menu bar
            // size a filled cup and a hollow one are impossible to tell apart.
            Image(systemName: model.isPreventingSleep ? "cup.and.saucer.fill" : "moon.zzz")
        }
        .menuBarExtraStyle(.window)
    }
}

struct AwakeMenu: View {
    @ObservedObject var model: AwakeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.isPreventingSleep ? "moon.zzz.fill" : "moon.zzz")
                Text("Awake")
                    .font(.headline)
                Spacer()
            }

            Toggle("Prevent sleep", isOn: Binding(
                get: { model.isPreventingSleep },
                set: { model.setPreventingSleep($0) }
            ))

            Toggle("Keep the display on", isOn: Binding(
                get: { model.keepDisplayAwake },
                set: { model.setKeepDisplayAwake($0) }
            ))
            .disabled(!model.isPreventingSleep)

            if model.isPreventingSleep {
                Picker("Duration", selection: Binding(
                    get: { model.duration },
                    set: { model.setDuration($0) }
                )) {
                    ForEach(AwakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }

                if let remaining = model.remainingText {
                    Text("Active · \(remaining) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.keepDisplayAwake {
                    Text("The display will still turn off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 280)
    }
}
