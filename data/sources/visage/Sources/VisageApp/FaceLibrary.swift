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

    /// The face's model; the point head when the face is unknown or its file unreadable.
    static func model(id: String) -> HeadModel {
        guard id != points, let url = directory?.appending(path: "\(id).glb"), let head = try? MeshHead(url: url) else {
            return PointHeadModel()
        }
        return head
    }
}

/// Which face: the menu's and the settings' picker.
struct FacePicker: View {
    let model: AppModel

    var body: some View {
        Picker("Face", selection: Binding(get: { model.faceID }, set: { model.faceID = $0 })) {
            ForEach(FaceLibrary.faces) { Text($0.name).tag($0.id) }
            Text("Points (logo)").tag(FaceLibrary.points)
        }
    }
}
