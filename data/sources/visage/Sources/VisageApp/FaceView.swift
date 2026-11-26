import AudioSource
import Shared
import SwiftUI

/// The face's window content. Until the hologram renderer (lot 3), the charter's mark stands in for the
/// face, drawn once, with the connection's state beneath it.
struct FaceView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Canvas { context, size in
                MarkDrawing.draw(in: &context, size: size, glow: true)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(caption)
                .font(.callout)
                .foregroundStyle(Palette.orPale.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            MenuContent(model: model)
        }
    }

    private var caption: String {
        let name = model.connection.app?.name ?? ""
        switch model.connection.state {
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
    static func draw(in context: inout GraphicsContext, size: CGSize, glow: Bool = false) {
        let side = min(size.width, size.height)
        let scale = side / 100
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        if glow {
            context.addFilter(.shadow(color: Palette.braise.opacity(0.6), radius: side * 0.012))
        }
        for dot in Mark.dots where dot.logoOpacity > 0 {
            let radius = dot.logoRadius * scale
            let rect = CGRect(
                x: origin.x + dot.logo.x * scale - radius, y: origin.y + dot.logo.y * scale - radius,
                width: 2 * radius, height: 2 * radius)
            context.fill(Path(ellipseIn: rect), with: .color(Palette.braise.opacity(dot.logoOpacity)))
        }
    }
}
