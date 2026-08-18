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

            Toggle("Empêcher la mise en veille", isOn: Binding(
                get: { model.isPreventingSleep },
                set: { model.setPreventingSleep($0) }
            ))

            Toggle("Garder l'écran allumé", isOn: Binding(
                get: { model.keepDisplayAwake },
                set: { model.setKeepDisplayAwake($0) }
            ))
            .disabled(!model.isPreventingSleep)

            if model.isPreventingSleep {
                Picker("Durée", selection: Binding(
                    get: { model.duration },
                    set: { model.setDuration($0) }
                )) {
                    ForEach(AwakeDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }

                if let remaining = model.remainingText {
                    Text("Actif · \(remaining)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.keepDisplayAwake {
                    Text("L'écran s'éteindra quand même.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Lancer au démarrage", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 280)
    }
}
