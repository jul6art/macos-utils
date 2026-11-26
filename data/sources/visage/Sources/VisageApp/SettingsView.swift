import SwiftUI

/// The settings (spec, § 9.2), in the charter's colours: the mark alive, the connection, then the face,
/// the window and the sync, each in its card.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    AnimatedMark(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings").font(.title.weight(.semibold))
                        Text(connection).foregroundStyle(Palette.cendreClaire)
                    }
                    Spacer()
                    Button("Connect my AI…") { model.showConnectWindow() }
                }
                .padding(.top, 28)

                BrandCard(title: String(localized: "Face")) {
                    FaceGrid(model: model)
                    RealismSlider(model: model)
                }
                BrandCard(title: String(localized: "Window")) {
                    WindowModeChoice(model: model)
                }
                BrandCard(title: String(localized: "Sync")) {
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
                        title: String(localized: "Lip offset"), value: model.extraLatencyMilliseconds,
                        range: -100...300,
                        help: String(
                            localized: "For Bluetooth headphones, which play the sound later than the speakers.")
                    ) { model.extraLatencyMilliseconds = $0 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 720)
        .background(Color(nsColor: Palette.charbon))
        .foregroundStyle(Palette.orPale)
        .tint(Palette.braise)
    }

    private var connection: String {
        guard let app = model.connection.app else { return String(localized: "Not connected") }
        return model.connection.state == .connected
            ? String(localized: "Connected to \(app.name)") : String(localized: "Waiting for \(app.name)")
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
                Text("\(value) ms").monospacedDigit().foregroundStyle(Palette.cendreClaire)
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { set(Int($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 10)
            Text(help).font(.caption).foregroundStyle(Palette.cendreClaire)
        }
    }
}

/// From the hologram of points to the face as real as its model allows (spec, § 8.3).
struct RealismSlider: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Realism")
                Spacer()
                Text(model.realism, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    .foregroundStyle(Palette.cendreClaire)
            }
            Slider(value: Binding(get: { model.realism }, set: { model.realism = $0 }), in: 0...1) {
                EmptyView()
            } minimumValueLabel: {
                Text("Hologram")
            } maximumValueLabel: {
                Text("Real")
            }
            Text("From light alone to skin and eyes: the hologram fades as the face becomes real.")
                .font(.caption).foregroundStyle(Palette.cendreClaire)
        }
    }
}
