import FaceAnimation
import Foundation
import simd

/// What the renderer draws: points, each with a normal and a brightness, shaped by a pose. Two kinds:
/// the charter's point head, and the MakeHuman faces (spec, § 8.1), drawn as a cloud of their vertices.
public protocol HeadModel: AnyObject, Sendable {
    var pointCount: Int { get }
    /// Per point: the normal (xyz) and the brightness (w).
    var normals: [SIMD4<Float>] { get }
    /// Size of a point relative to the renderer's default: dense clouds take smaller points.
    var pointScale: Float { get }
    /// Triangles between the points, three indices each, drawn first into the depth buffer only: what
    /// lies behind them is hidden, as behind a real head. Empty: nothing hides anything.
    var occluders: [UInt32] { get }
    /// Per point: the position (xyz) and the size (w), for this pose.
    func shape(_ pose: FacePose, time: Double) -> [SIMD4<Float>]
}

extension HeadModel {
    public var occluders: [UInt32] { [] }
}

/// The charter's point head (PointHead).
public final class PointHeadModel: HeadModel {
    public let normals: [SIMD4<Float>]
    public var pointCount: Int { normals.count }
    public let pointScale: Float = 1

    public init() {
        normals = PointHead.points.map { SIMD4($0.normal, $0.brightness) }
    }

    public func shape(_ pose: FacePose, time: Double) -> [SIMD4<Float>] {
        PointHead.deform(pose, time: time)
    }
}

/// A MakeHuman face from tools/faces: every vertex a point of light. The 52 ARKit shapes move them, as
/// sparse offsets; the eyeballs turn with the gaze.
public final class MeshHead: HeadModel {
    public let normals: [SIMD4<Float>]
    public var pointCount: Int { base.count }
    public let pointScale: Float = 0.42
    public let occluders: [UInt32]

    private let base: [SIMD4<Float>]
    /// Per `FaceShape`: the points it moves, and by how much, in head units.
    private let shapes: [(indices: [Int32], deltas: [SIMD3<Float>])]
    /// The eyeballs' points and centres, to turn them with the gaze.
    private let eyes: [(indices: [Int32], centre: SIMD3<Float>)]

    /// Each part's look: point size and brightness.
    private static let parts: [String: (size: Float, brightness: Float)] = [
        "head": (1, 0.8), "eyes": (0.6, 1), "eyebrows": (1.1, 0.9), "eyelashes": (0.6, 0.7),
        "teeth": (0.5, 0.4), "tongue": (0.5, 0.25), "hair": (0.9, 0.45),
    ]

    public init(url: URL) throws {
        let file = try GLBFile(url: url)
        guard let head = file.meshes.first(where: { $0.name.hasSuffix(".head") }) else {
            throw GLBFile.Failure.malformed("no head")
        }
        // Into the renderer's head units: the face about two units tall, eyes and mouth where the point
        // head has them, the front of the face towards +z.
        let ys = head.positions.map(\.y)
        let top = ys.max() ?? 1
        let bottom = ys.min() ?? 0
        let scale = 2.35 / max(top - bottom, 1e-3)
        let centreX = head.positions.map(\.x).reduce(0, +) / Float(max(head.positions.count, 1))
        let front = head.positions.map(\.z).max() ?? 0
        func place(_ p: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3((p.x - centreX) * scale, (p.y - top) * scale + 1.05, (p.z - front) * scale + 0.6)
        }

        var base: [SIMD4<Float>] = []
        var normals: [SIMD4<Float>] = []
        var shapes = [(indices: [Int32], deltas: [SIMD3<Float>])](
            repeating: ([], []), count: FaceShape.allCases.count)
        var eyes: [(indices: [Int32], centre: SIMD3<Float>)] = []
        var heads: [Range<Int>] = []
        var occluders: [UInt32] = []
        for mesh in file.meshes {
            let part = String(mesh.name.split(separator: ".").last ?? "")
            let look = Self.parts[part] ?? (1, 0.7)
            let offset = Int32(base.count)
            for (index, position) in mesh.positions.enumerated() {
                base.append(SIMD4(place(position), look.size))
                let normal = index < mesh.normals.count ? simd_normalize(mesh.normals[index]) : SIMD3(0, 0, 1)
                normals.append(SIMD4(normal, look.brightness))
            }
            for (targetIndex, name) in mesh.targetNames.enumerated() {
                guard let shape = FaceShape.allCases.first(where: { $0.name == name }), targetIndex < mesh.targets.count
                else { continue }
                let target = mesh.targets[targetIndex]
                shapes[shape.rawValue].indices += target.indices.map { $0 + offset }
                shapes[shape.rawValue].deltas += target.deltas.map { $0 * scale }
            }
            if part == "head" { heads.append(Int(offset)..<base.count) }
            // The skin and the eyeballs hide what is behind them: the hair at the back of the head, the
            // teeth behind closed lips, the eyeball behind a closing lid.
            if part == "head" || part == "eyes" { occluders += mesh.triangles.map { $0 + UInt32(offset) } }
            if part == "eyes" {
                // Two eyeballs: split by side, each turning about its own centre (its bounding box's: the
                // cornea's points are denser, an average would sit in front of it).
                for side: Float in [-1, 1] {
                    let indices = (0..<Int32(mesh.positions.count)).filter {
                        (base[Int(offset + $0)].x < 0 ? -1 : 1) == side
                    }.map { $0 + offset }
                    guard !indices.isEmpty else { continue }
                    let points = indices.map { SIMD3<Float>(base[Int($0)].x, base[Int($0)].y, base[Int($0)].z) }
                    let low = points.reduce(points[0], simd_min)
                    let high = points.reduce(points[0], simd_max)
                    let centre = (low + high) / 2
                    eyes.append((indices, centre))
                    // Light lets the whole eyeball through, the lids hide nothing: only what shows between
                    // them lights up, the iris more than the white, the pupil dark.
                    for (index, point) in zip(indices.map(Int.init), points) {
                        let (size, brightness) = Self.eyeLook(simd_normalize(point - centre))
                        base[index].w = size
                        normals[index].w = brightness
                    }
                }
            }
        }
        // MakeHuman's mesh is far denser around the eyes, the lips and the ears than on the cheeks; in
        // additive light, more points make more light. Each point of the head gives up some of its
        // brightness to its neighbours, enough to even it out without flattening the features.
        for range in heads {
            Self.evenOut(range, base: base, normals: &normals)
        }
        self.base = base
        self.normals = normals
        self.shapes = shapes
        self.eyes = eyes
        self.occluders = occluders
    }

    /// Dims the points of `range` by how crowded they are: `(typical / neighbours)^evenness`, neighbours
    /// counted within `crowdRadius` head units (a grid of that size, so that it stays linear).
    static func evenOut(_ range: Range<Int>, base: [SIMD4<Float>], normals: inout [SIMD4<Float>]) {
        func cell(_ point: SIMD4<Float>) -> SIMD3<Int32> {
            SIMD3(
                Int32((point.x / crowdRadius).rounded(.down)), Int32((point.y / crowdRadius).rounded(.down)),
                Int32((point.z / crowdRadius).rounded(.down)))
        }
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for index in range { grid[cell(base[index]), default: []].append(index) }
        var counts: [Int] = []
        counts.reserveCapacity(range.count)
        for index in range {
            let home = cell(base[index])
            var count = 0
            for dx: Int32 in -1...1 {
                for dy: Int32 in -1...1 {
                    for dz: Int32 in -1...1 {
                        for other in grid[home &+ SIMD3(dx, dy, dz)] ?? []
                        where simd_distance_squared(base[other], base[index]) < crowdRadius * crowdRadius {
                            count += 1
                        }
                    }
                }
            }
            counts.append(count)
        }
        guard !counts.isEmpty else { return }
        let typical = Float(counts.sorted()[counts.count / 2])
        for (index, count) in zip(range, counts) {
            normals[index].w *= min(pow(typical / Float(count), evenness), 1.2)
        }
    }

    /// The neighbourhood that counts, in head units (about 4 mm), and how far the brightness evens out
    /// (0: not at all, 1: entirely).
    static let crowdRadius: Float = 0.045
    static let evenness: Float = 0.6

    /// An eyeball point's size and brightness, by its direction from the eyeball's centre: hidden outside
    /// the lids' opening (wider than tall), then the white, the iris and the pupil.
    static func eyeLook(_ direction: SIMD3<Float>) -> (size: Float, brightness: Float) {
        let opening = pow(direction.x / 0.72, 2) + pow(direction.y / 0.5, 2)
        guard direction.z > 0, opening < 1 else { return (0, 0) }
        let fromAxis = simd_length(SIMD2(direction.x, direction.y))
        if fromAxis < 0.16 { return (0.5, 0.06) }
        if fromAxis < 0.42 { return (0.6, 0.7) }
        return (0.5, 0.16)
    }

    /// ARKit's mouthClose, from the animator's. ARKit's closes the lips over an open jaw, and past jawOpen
    /// they go through each other (a bulge under the nose on « p »); the animator's says how shut the lips
    /// are, whatever the jaw. And a mouth at rest is shut: the breath's few hundredths of jaw do not part
    /// the lips (a line of teeth showed between them).
    static func lipsClosing(shut: Float, jaw: Float) -> Float {
        let resting = min(max((0.1 - jaw) / 0.05, 0), 1)
        return min(max(shut, resting), 1) * jaw
    }

    public func shape(_ pose: FacePose, time: Double) -> [SIMD4<Float>] {
        var points = base
        var weights = pose.weights
        weights[FaceShape.mouthClose.rawValue] = Self.lipsClosing(shut: pose[.mouthClose], jaw: pose[.jawOpen])
        for (shapeIndex, weight) in weights.enumerated() where weight > 0.001 {
            let shape = shapes[shapeIndex]
            for (index, delta) in zip(shape.indices, shape.deltas) {
                let position = Int(index)
                points[position] += SIMD4(delta * weight, 0)
            }
        }
        // The gaze: the eyeballs turn (up to 20° sideways, 14° up or down).
        let rotation =
            simd_quatf(angle: pose.gaze.x * 0.35, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -pose.gaze.y * 0.25, axis: SIMD3(1, 0, 0))
        for eye in eyes {
            for index in eye.indices {
                let position = Int(index)
                let point = points[position]
                let turned = rotation.act(SIMD3(point.x, point.y, point.z) - eye.centre) + eye.centre
                points[position] = SIMD4(turned, point.w)
            }
        }
        return points
    }
}
