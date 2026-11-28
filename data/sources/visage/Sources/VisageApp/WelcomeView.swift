import SwiftUI

/// The first launch (spec, § 4.2): in front and large, in the charter's colours, the mark alive over a
/// hologram's plinth, then the four choices on one page, then « Start ». Without it, Visage started as a
/// mere sign in the menu bar, easy to miss.
struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        ZStack(alignment: .bottom) {
                            Ellipse()
                                .stroke(Palette.braise.opacity(0.55), lineWidth: 2)
                                .frame(width: 120, height: 18)
                                .blur(radius: 1.5)
                                .offset(y: -4)
                            AnimatedMark(size: 150)
                        }
                        .padding(.bottom, 4)
                        WordmarkView(height: 30)
                        Text("A face for the voice of the AI app you already talk to.")
                            .font(.title3).foregroundStyle(Palette.orPale)
                        Text("Four choices, and it is yours.").foregroundStyle(Palette.cendreClaire)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .padding(.bottom, 10)
                    .background(
                        RadialGradient(
                            colors: [Palette.braise.opacity(0.12), .clear], center: .init(x: 0.5, y: 0.3),
                            startRadius: 10, endRadius: 260))

                    BrandCard(title: String(localized: "Your AI"), number: 1) {
                        ConnectScreen(model: model, welcoming: true)
                    }
                    BrandCard(title: String(localized: "Your face"), number: 2) {
                        HStack(alignment: .top, spacing: 18) {
                            FacePreview(model: model, width: 220)
                            VStack(alignment: .leading, spacing: 14) {
                                FaceGrid(model: model)
                                RealismSlider(model: model)
                                FaceSizeSlider(model: model)
                            }
                        }
                    }
                    BrandCard(title: String(localized: "Where it shows"), number: 3) {
                        WindowModeChoice(model: model)
                    }
                    BrandCard(title: String(localized: "Where to find Visage"), number: 4) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(nsImage: MenuBarIcon.image)
                                .foregroundStyle(Palette.orPale)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Palette.charbon)))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.brou))
                            Text(
                                "Visage lives in the menu bar, at the top right of the screen, under this sign. Click it to show or hide the face, or to change the settings or the AI."
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }

            HStack {
                Text(
                    model.connection.app == nil
                        ? String(localized: "Choose your AI to start.")
                        : String(localized: "All of it can be changed later, from the menu bar.")
                )
                .foregroundStyle(Palette.cendreClaire)
                Spacer()
                Button("Start") { model.finishWelcome() }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.braise)
                    .foregroundStyle(Color(nsColor: Palette.charbon))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.connection.app == nil)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Palette.surface)
            .overlay(alignment: .top) { Rectangle().fill(Palette.brou).frame(height: 1) }
        }
        .frame(width: 860, height: 820)
        .background(Color(nsColor: Palette.charbon))
        .foregroundStyle(Palette.orPale)
        .tint(Palette.braise)
    }
}

/// The window's two modes, each with what it does.
struct WindowModeChoice: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(WindowMode.allCases) { mode in
                Button {
                    model.windowMode = mode
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: model.windowMode == mode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(model.windowMode == mode ? Palette.braise : Palette.cendreClaire)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                            Text(mode.detail).font(.caption).foregroundStyle(Palette.cendreClaire)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.windowMode == mode ? .isSelected : [])
            }
            Toggle(
                "A night behind the face", isOn: Binding(get: { model.backdrop }, set: { model.backdrop = $0 })
            )
            .toggleStyle(.switch)
            Text(
                "A dark city night, rain and far lights, behind the hologram: its light shows on any desktop. Two faces side by side share one night."
            )
            .font(.caption).foregroundStyle(Palette.cendreClaire)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
