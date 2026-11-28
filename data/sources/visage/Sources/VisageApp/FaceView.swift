import AudioSource
import Shared
import SwiftUI

/// A face's window content: the hologram, and the connection's state beneath it until it speaks. Without
/// Metal, the charter's mark stands in.
struct FaceView: View {
    let model: AppModel
    let slot: FaceSlot

    var body: some View {
        ZStack(alignment: .bottom) {
            if slot.driver.renderer != nil {
                HoloView(driver: slot.driver)
            } else {
                Canvas { context, size in
                    MarkDrawing.draw(in: &context, size: size, glow: true)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(24)
            }
            if slot.connection.state != .connected {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(Palette.orPale.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            MenuContent(model: model, slot: slot)
        }
    }

    private var caption: String {
        let name = slot.connection.app?.name ?? ""
        switch slot.connection.state {
        case .connected: return String(localized: "Listening to \(name)")
        case .starting, .waitingForPermission: return String(localized: "Connecting…")
        case .permissionMissing: return String(localized: "Waiting for permission")
        case .waitingForApp: return String(localized: "Waiting for \(name)")
        case .idle, .notInstalled, .failed: return String(localized: "Not connected")
        }
    }
}

/// Draws the logo, in braise, from the shared geometry (Sources/Shared/BrandMark.swift).
enum MarkDrawing {
    /// The logo, still; with a `time`, alive (`MarkMotion`).
    static func draw(in context: inout GraphicsContext, size: CGSize, glow: Bool = false, time: Double? = nil) {
        let side = min(size.width, size.height)
        let scale = side / 100
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        if glow {
            context.addFilter(.shadow(color: Palette.braise.opacity(0.6), radius: side * 0.012))
        }
        for dot in Mark.dots {
            // Still, the logo is the dust; alive, each dot travels between the whole face and the dust.
            let p = time.map { MarkMotion.progress(of: dot, at: $0) } ?? 1
            let opacity = dot.homeOpacity + (dot.logoOpacity - dot.homeOpacity) * p
            guard opacity > 0 else { continue }
            let x = dot.home.x + (dot.logo.x - dot.home.x) * p
            let y = dot.home.y + (dot.logo.y - dot.home.y) * p
            let radius = (dot.radius + (dot.logoRadius - dot.radius) * p) * scale
            let rect = CGRect(
                x: origin.x + x * scale - radius, y: origin.y + y * scale - radius, width: 2 * radius,
                height: 2 * radius)
            context.fill(Path(ellipseIn: rect), with: .color(Palette.braise.opacity(opacity)))
        }
    }
}
