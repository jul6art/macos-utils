import AppKit
import SwiftUI

/// Where the conversation stands with the AI's app, and the microphone option (spec, § 5, § 7.2).
struct ConversationSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(model.connection.appListening ? Palette.braise : Palette.brou)
                    .frame(width: 9, height: 9)
                Text(listening)
            }
            Toggle(
                "Hear me through the microphone",
                isOn: Binding(get: { model.microphone }, set: { model.microphone = $0 })
            )
            .toggleStyle(.switch)
            Text(
                "While your AI listens to you, Visage reads how loud your voice is, and nothing else: the face nods at your pauses and thinks once your sentence ends. The microphone opens only while your AI's is open; nothing is recorded or sent."
            )
            .font(.caption).foregroundStyle(Palette.cendreClaire)
            .fixedSize(horizontal: false, vertical: true)
            switch model.microphoneAccess {
            case .denied:
                HStack {
                    Text("macOS refuses the microphone to Visage.")
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            case .noMicrophone:
                Text("This Mac has no microphone.")
            default:
                EmptyView()
            }
            Divider()
            Toggle("Siri among the AIs", isOn: Binding(get: { model.siri }, set: { model.siri = $0 }))
                .toggleStyle(.switch)
            Text(
                "Siri gets its card in « Connect my AI ». It must answer aloud: System Settings, Siri, voice responses. Its voice plays as it is, and the face follows it without reading ahead."
            )
            .font(.caption).foregroundStyle(Palette.cendreClaire)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listening: String {
        guard let app = model.connection.app else { return String(localized: "No AI connected.") }
        return model.connection.appListening
            ? String(localized: "\(app.name) is listening to you.")
            : String(localized: "\(app.name) is not listening: start its voice mode.")
    }
}
