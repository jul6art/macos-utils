import Foundation
import Testing
import simd

@testable import FaceAnimation
@testable import HoloRenderer

@Suite("The MakeHuman faces, as points")
struct MeshHeadTests {
    private static let faces = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Resources/Faces").standardized

    private struct Entry: Decodable { let id: String }

    private static var ids: [String] {
        guard let data = try? Data(contentsOf: faces.appending(path: "faces.json")) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data).map(\.id)) ?? []
    }

    private func head(_ id: String) throws -> MeshHead {
        try MeshHead(url: Self.faces.appending(path: "\(id).glb"))
    }

    private func pose(_ shape: FaceShape, _ weight: Float) -> FacePose {
        var pose = FacePose()
        pose.weights[shape.rawValue] = weight
        return pose
    }

    @Test("the ten faces are shipped, light (R7), each with its parts and the 52 shapes on its head")
    func shipped() throws {
        #expect(Self.ids.count == 10)
        for id in Self.ids {
            let url = Self.faces.appending(path: "\(id).glb")
            let bytes = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            #expect(bytes < 3_000_000, "\(id)")
            let file = try GLBFile(url: url)
            let parts = Set(file.meshes.map { String($0.name.split(separator: ".").last ?? "") })
            #expect(parts.isSuperset(of: ["head", "eyes", "eyebrows", "eyelashes", "teeth", "tongue"]), "\(id)")
            let head = try #require(file.meshes.first { $0.name == "\(id).head" })
            #expect(Set(head.targetNames) == Set(FaceShape.allCases.map(\.name)), "\(id)")
        }
    }

    @Test("every face loads, framed like the point head: about two units tall, the face towards +z")
    func framed() throws {
        for id in Self.ids {
            let head = try head(id)
            let points = head.shape(FacePose(), time: 0)
            #expect(points.count == head.normals.count)
            #expect(points.count > 5000 && points.count < 40000, "\(id)")
            let ys = points.map(\.y)
            #expect(abs((ys.max() ?? 0) - 1.05) < 0.3, "\(id)")
            #expect((points.map(\.z).max() ?? 0) < 0.9, "\(id)")
        }
    }

    @Test("the skin and the eyeballs hide what is behind them: whole triangles between existing points")
    func occluders() throws {
        for id in Self.ids {
            let head = try head(id)
            #expect(head.occluders.count > 3000 && head.occluders.count % 3 == 0, "\(id)")
            #expect(head.occluders.allSatisfy { Int($0) < head.pointCount }, "\(id)")
        }
        #expect(PointHeadModel().occluders.isEmpty)
    }

    @Test("jawOpen moves the points it moves downwards, and leaves the brow where it is")
    func jaw() throws {
        let head = try head("lea")
        let rest = head.shape(FacePose(), time: 0)
        let open = head.shape(pose(.jawOpen, 1), time: 0)
        let moved = zip(rest, open).filter { simd_distance($0.0, $0.1) > 1e-4 }
        #expect(moved.count > 100)
        let drop = moved.map { $0.1.y - $0.0.y }.reduce(0, +) / Float(moved.count)
        #expect(drop < -0.02)
        #expect(moved.allSatisfy { $0.0.y < 0.3 })
    }

    @Test("the gaze turns the eyeballs only")
    func gaze() throws {
        let head = try head("lea")
        let rest = head.shape(FacePose(), time: 0)
        var looking = FacePose()
        looking.gaze = SIMD2(1, 0)
        let turned = head.shape(looking, time: 0)
        let moved = zip(rest, turned).filter { simd_distance($0.0, $0.1) > 1e-4 }.map(\.0)
        #expect(!moved.isEmpty)
        // Both eyes, and nothing outside them: within a few centimetres of eye level.
        #expect(moved.contains { $0.x < 0 } && moved.contains { $0.x > 0 })
        let levels = moved.map(\.y)
        #expect((levels.max() ?? 0) - (levels.min() ?? 0) < 0.4)
    }

    @Test("only what shows between the lids lights up: the iris more than the white, the pupil dark")
    func eyes() {
        let pupil = MeshHead.eyeLook(SIMD3(0, 0, 1))
        let iris = MeshHead.eyeLook(simd_normalize(SIMD3(0.3, 0, 1)))
        let white = MeshHead.eyeLook(simd_normalize(SIMD3(0.6, 0, 0.8)))
        #expect(iris.brightness > white.brightness && white.brightness > pupil.brightness)
        #expect(MeshHead.eyeLook(simd_normalize(SIMD3(0, 0.7, 0.7))).brightness == 0)
        #expect(MeshHead.eyeLook(SIMD3(0, 0, -1)).brightness == 0)
    }
}
