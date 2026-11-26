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

    @Test("every face has its surfaces: a texture per part, light enough (R7), and coordinates for its points")
    func surfaces() throws {
        for id in Self.ids {
            let head = try head(id)
            #expect(head.surfaces.count == 7, "\(id)")
            #expect(head.uvs.count == head.pointCount, "\(id)")
            var bytes = 0
            for surface in head.surfaces {
                bytes += try #require(try surface.texture.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                #expect(surface.triangles.count % 3 == 0 && surface.triangles.allSatisfy { Int($0) < head.pointCount })
            }
            #expect(bytes < 2_500_000, "\(id)")
            // The skin and the eyes first, then what is cut out of a texture and lies over them.
            let solid = head.surfaces.map { $0.material == .skin || $0.material == .eye }
            #expect(solid == solid.sorted { $0 && !$1 }, "\(id)")
        }
    }

    @Test("a vertex on a texture seam is drawn once as a point")
    func twins() throws {
        let points = try head("lea").shape(FacePose(), time: 0).filter { $0.w > 0 }
        let places = Set(points.map { SIMD3<Int32>((SIMD3($0.x, $0.y, $0.z) * 1e4).rounded(.toNearestOrEven)) })
        #expect(places.count == points.count)
    }

    @Test("mouthClose never shuts the lips past the jaw, and a mouth at rest stays shut")
    func lipsShut() throws {
        let head = try head("lea")
        let rest = head.shape(FacePose(), time: 0)
        #expect(head.shape(pose(.mouthClose, 1), time: 0) == rest)
        var open = pose(.jawOpen, 0.3)
        let jaw = head.shape(open, time: 0)
        open.weights[FaceShape.mouthClose.rawValue] = 1
        #expect(head.shape(open, time: 0) != jaw)
        // At rest, the jaw ajar with the breath, the lips stay shut, asked or not.
        var resting = pose(.jawOpen, 0.04)
        let sealed = head.shape(resting, time: 0)
        resting.weights[FaceShape.mouthClose.rawValue] = 1
        #expect(head.shape(resting, time: 0) == sealed)
        #expect(MeshHead.lipsClosing(shut: 0, jaw: 0.04) == 0.04)
        #expect(MeshHead.lipsClosing(shut: 0, jaw: 0.3) == 0)
        #expect(MeshHead.lipsClosing(shut: 0.5, jaw: 0.3) == 0.15)
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
