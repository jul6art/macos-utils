import SwiftUI

/// The hologram's colours (spec, § 8.2, point 8): the charter's braise by default (docs/charter.md, § 3), and
/// four other lights.
enum HoloColour: String, CaseIterable, Identifiable {
    case braise
    case azur
    case menthe
    case rose
    case ivoire

    var id: String { rawValue }

    var name: String {
        switch self {
        case .braise: String(localized: "Ember")
        case .azur: String(localized: "Azure")
        case .menthe: String(localized: "Mint")
        case .rose: String(localized: "Rose")
        case .ivoire: String(localized: "Ivory")
        }
    }

    var rgb: SIMD3<Float> {
        switch self {
        case .braise: SIMD3(1.0, 0.788, 0.471)
        case .azur: SIMD3(0.498, 0.831, 1.0)
        case .menthe: SIMD3(0.549, 1.0, 0.769)
        case .rose: SIMD3(1.0, 0.62, 0.788)
        case .ivoire: SIMD3(1.0, 0.914, 0.769)
        }
    }

    var color: Color { Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)) }
}

/// The settings' « Hologram » card: its colour, its layers, each shown at once in the preview.
struct HologramSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ForEach(HoloColour.allCases) { colour in
                    let chosen = model.holoColour == colour
                    Button {
                        model.holoColour = colour
                    } label: {
                        Circle().fill(colour.color)
                            .frame(width: 26, height: 26)
                            .padding(3)
                            .overlay(Circle().strokeBorder(chosen ? Palette.orPale : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(colour.name)
                    .accessibilityLabel(colour.name)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
                Text(model.holoColour.name).foregroundStyle(Palette.cendreClaire)
            }
            PercentSlider(
                title: String(localized: "Halo"), value: model.halo, range: 0...1.5,
                help: String(localized: "The glow around the light.")
            ) { model.halo = $0 }
            PercentSlider(
                title: String(localized: "Scanlines"), value: model.scanlines, range: 0...1,
                help: String(localized: "The fine lines and the band that sweeps down the face.")
            ) { model.scanlines = $0 }
            Toggle("Plinth and beam", isOn: Binding(get: { model.projector }, set: { model.projector = $0 }))
            Toggle(
                "Flicker and glitches", isOn: Binding(get: { model.glitches }, set: { model.glitches = $0 }))
        }
        .toggleStyle(.switch)
    }
}

/// A setting in percent, with what it does.
struct PercentSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let help: String
    let set: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    .foregroundStyle(Palette.cendreClaire)
            }
            Slider(value: Binding(get: { value }, set: { set(($0 * 20).rounded() / 20) }), in: range)
            Text(help).font(.caption).foregroundStyle(Palette.cendreClaire)
        }
    }
}

/// The settings' « Camera » card: the option, what it does, and what to do when macOS refuses.
struct CameraSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Follow me with the camera", isOn: Binding(get: { model.camera }, set: { model.camera = $0 }))
                .toggleStyle(.switch)
            Text(
                "Its gaze rests on you and follows you, and its head turns a little as you move, as a real head behind the glass would. Images are read on your Mac, never recorded; the camera light stays on meanwhile."
            )
            .font(.caption).foregroundStyle(Palette.cendreClaire)
            .fixedSize(horizontal: false, vertical: true)
            switch model.cameraAccess {
            case .denied:
                HStack {
                    Text("macOS refuses the camera to Visage.")
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                }
            case .noCamera:
                Text("This Mac has no camera.")
            default:
                EmptyView()
            }
        }
    }
}
