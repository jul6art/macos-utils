import FaceAnimation
import Foundation
import HoloRenderer
import SwiftUI

/// The faces shipped in the app (Resources/Faces, built by tools/faces): their names, and their models.
/// "points" is the charter's point head, always there.
enum FaceLibrary {
    struct Entry: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
    }

    static let points = "points"

    static var directory: URL? { Bundle.main.resourceURL?.appending(path: "Faces") }

    static let faces: [Entry] = {
        guard let url = directory?.appending(path: "faces.json"), let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }()

    /// What can be chosen: the faces, then the point head.
    static var choices: [Entry] { faces + [Entry(id: points, name: String(localized: "Points (logo)"))] }

    /// The face's model; the point head when the face is unknown or its file unreadable.
    static func model(id: String) -> HeadModel {
        guard id != points, let url = directory?.appending(path: "\(id).glb"), let head = try? MeshHead(url: url) else {
            return PointHeadModel()
        }
        return head
    }

    /// A head at rest on charbon, as `renderer` draws it: the thumbnails and the snapshots' sheet.
    static func portrait(
        _ head: HeadModel, renderer: HoloRenderer, width: Int, height: Int, seed: UInt32, realism: Float = 0
    ) -> CGImage? {
        renderer.model = head
        let animator = FaceAnimator(seed: seed)
        var pose = FacePose()
        for _ in 0..<90 { pose = animator.update(dt: 1.0 / 60, voice: nil, moment: .waiting) }
        // A portrait never blinks: caught mid-blink, a face showed in the settings with its eyes shut.
        pose[.eyeBlinkLeft] = FaceAnimator.restingLid
        pose[.eyeBlinkRight] = FaceAnimator.restingLid
        var settings = HoloSettings()
        settings.background = HoloSettings.charbon
        settings.realism = realism
        return renderer.image(pose: pose, time: 1.5, settings: settings, width: width, height: height)
    }

    /// Every choice's thumbnail, made off the main thread: reading ten faces takes a moment.
    static func thumbnails() async -> [String: CGImage] {
        let ids = choices.map(\.id)
        return await Task.detached(priority: .utility) { makeThumbnails(ids) }.value
    }

    static func makeThumbnails(_ ids: [String]) -> [String: CGImage] {
        guard let renderer = HoloRenderer() else { return [:] }
        var images: [String: CGImage] = [:]
        for (index, id) in ids.enumerated() {
            images[id] = portrait(model(id: id), renderer: renderer, width: 144, height: 180, seed: UInt32(index + 1))
        }
        return images
    }
}

/// Which head, in a face's menu: a list of names.
struct FacePicker: View {
    let slot: FaceSlot

    var body: some View {
        Picker("Face", selection: Binding(get: { slot.faceID }, set: { slot.faceID = $0 })) {
            ForEach(FaceLibrary.choices) { Text($0.name).tag($0.id) }
        }
    }
}

/// Which face, in the settings: the faces themselves, at rest, five to a row (spec, § 8.1).
struct FaceGrid: View {
    let model: AppModel

    private let columns = Array(repeating: GridItem(.fixed(72), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(FaceLibrary.choices) { choice in
                let chosen = model.faceID == choice.id
                Button {
                    model.faceID = choice.id
                } label: {
                    VStack(spacing: 4) {
                        thumbnail(choice.id)
                            .frame(width: 72, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).stroke(chosen ? Palette.braise : .clear, lineWidth: 2)
                            )
                        Text(choice.name).font(.caption).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.name)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .task { await model.loadThumbnails() }
    }

    @ViewBuilder
    private func thumbnail(_ id: String) -> some View {
        if let image = model.thumbnails[id] {
            Image(decorative: image, scale: 2)
        } else {
            Color(nsColor: Palette.charbon).overlay(ProgressView().controlSize(.small))
        }
    }
}
