import SwiftUI

/// The settings (spec, § 9.2). The hologram's layers and the camera arrive with their lots.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Picker("Window", selection: Binding(get: { model.windowMode }, set: { model.windowMode = $0 })) {
                ForEach(WindowMode.allCases) { Text($0.title).tag($0) }
            }
            FacePicker(model: model)

            Section {
                MillisecondsSlider(
                    title: String(localized: "Delay"), value: model.delayMilliseconds, range: 80...300,
                    help: String(
                        localized:
                            "How long the voice waits for the face to read ahead. Unnoticeable in a conversation.")
                ) { model.delayMilliseconds = $0 }
                MillisecondsSlider(
                    title: String(localized: "Anticipation"), value: model.anticipationMilliseconds, range: 0...120,
                    help: String(localized: "How early the lips move before the sound, as in a real face.")
                ) { model.anticipationMilliseconds = $0 }
                MillisecondsSlider(
                    title: String(localized: "Lip offset"), value: model.extraLatencyMilliseconds, range: -100...300,
                    help: String(localized: "For Bluetooth headphones, which play the sound later than the speakers.")
                ) { model.extraLatencyMilliseconds = $0 }
            } header: {
                Text("Sync")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

private struct MillisecondsSlider: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let help: String
    let set: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) ms").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { set(Int($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 10)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}
