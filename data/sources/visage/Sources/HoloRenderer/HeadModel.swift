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
    /// The head as surfaces, for the realistic end of the hologram (spec, § 8.3); empty: points only.
    var surfaces: [HeadSurface] { get }
    /// Per point: where it takes its colour in its surface's texture.
    var uvs: [SIMD2<Float>] { get }
    /// Per point: the position (xyz) and the size (w), for this pose.
    func shape(_ pose: FacePose, time: Double) -> [SIMD4<Float>]
}

extension HeadModel {
    public var occluders: [UInt32] { [] }
    public var surfaces: [HeadSurface] { [] }
    public var uvs: [SIMD2<Float>] { [] }
}

/// A part of a head drawn as a surface: its triangles between the points, its texture, and how it takes
/// the light.
public struct HeadSurface: Sendable {
    public enum Material: Sendable {
        /// Soft, warm in the shade, a faint sheen.
        case skin
        /// Wet: a small, sharp highlight.
        case eye
        /// Strands: cut out where their texture is transparent, a soft sheen.
        case hair
        /// The tongue: cut out, matte.
        case matte
        /// Brows and lashes: fine hairs, laid softly over the skin and the eyes by their texture's own
        /// transparency. Cut out at half of it, they were hard black strokes.
        case fine
        /// Inside the mouth, in its shade: a little darker than their texture, a faint shine.
        case teeth
    }

    public let triangles: [UInt32]
    public let texture: URL
    public let material: Material
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
    public let surfaces: [HeadSurface]
    public let uvs: [SIMD2<Float>]

    private let base: [SIMD4<Float>]
    /// Per `FaceShape`: the points it moves, and by how much, in head units.
    private let shapes: [(indices: [Int32], deltas: [SIMD3<Float>])]
    /// The eyeballs' points and centres, to turn them with the gaze.
    private let eyes: [(indices: [Int32], centre: SIMD3<Float>)]
    /// Across the mouth, in its middle and on either side: the upper lip's lowest point, the lower lip's
    /// highest, and how fast mouthClose brings them together, per unit of weight.
    let lips: [(upper: Int, lower: Int, closing: Float)]
    /// How much mouthClose shuts the mouth at rest: MakeHuman's lips rest apart, and between full lips a
    /// line of teeth showed (Amara, Kofi). Measured on the face, from 0 to `restingCloseLimit`.
    let restingClose: Float
    static let restingCloseLimit: Float = 0.35
    /// Twice what the points need: on Amara, the measure (0.031) left specks of teeth, 0.07 a clean line.
    static let restingMargin: Float = 2

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
        /// The head's points its triangles use: tools/faces dropped the faces nobody sees (inside the lips).
        var drawn = Set<Int>()
        var occluders: [UInt32] = []
        var surfaces: [HeadSurface] = []
        var uvs: [SIMD2<Float>] = []
        let folder = url.deletingLastPathComponent()
        for mesh in file.meshes {
            let part = String(mesh.name.split(separator: ".").last ?? "")
            let look = Self.parts[part] ?? (1, 0.7)
            let offset = Int32(base.count)
            for (index, position) in mesh.positions.enumerated() {
                base.append(SIMD4(place(position), look.size))
                let normal = index < mesh.normals.count ? simd_normalize(mesh.normals[index]) : SIMD3(0, 0, 1)
                normals.append(SIMD4(normal, look.brightness))
                uvs.append(index < mesh.uvs.count ? mesh.uvs[index] : .zero)
            }
            let texture = ["jpg", "png"].map { folder.appending(path: "\(mesh.name).\($0)") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            if let texture {
                let material: HeadSurface.Material =
                    switch part {
                    case "head": .skin
                    case "eyes": .eye
                    case "hair": .hair
                    case "teeth": .teeth
                    case "eyebrows", "eyelashes": .fine
                    default: .matte
                    }
                surfaces.append(
                    HeadSurface(
                        triangles: mesh.triangles.map { $0 + UInt32(offset) }, texture: texture, material: material))
            }
            for (targetIndex, name) in mesh.targetNames.enumerated() {
                guard let shape = FaceShape.allCases.first(where: { $0.name == name }), targetIndex < mesh.targets.count
                else { continue }
                let target = mesh.targets[targetIndex]
                shapes[shape.rawValue].indices += target.indices.map { $0 + offset }
                shapes[shape.rawValue].deltas += target.deltas.map { $0 * scale }
            }
            if part == "head" {
                heads.append(Int(offset)..<base.count)
                drawn.formUnion(mesh.triangles.map { Int($0) + Int(offset) })
            }
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
            Self.dropTwins(Int(offset)..<base.count, base: &base, normals: &normals)
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
        let close = shapes[FaceShape.mouthClose.rawValue]
        let lips = Self.mouthOpenings(
            moved: zip(close.indices, close.deltas).filter { index, _ in
                heads.contains { $0.contains(Int(index)) }
            }.map { (Int($0.0), $0.1) }, drawn: drawn, base: base)
        self.lips = lips
        // The widest opening sets it, with a margin: once the points meet, the lips' edges, straight from
        // point to point, still let specks of teeth through towards the corners.
        let measured = lips.map { max(base[$0.upper].y - base[$0.lower].y, 0) / $0.closing }.max() ?? 0
        restingClose = min(measured * Self.restingMargin, Self.restingCloseLimit)
        self.eyes = eyes
        self.occluders = occluders
        // Skin first, then what is cut out of its texture: brows, lashes and strands lie over the skin.
        self.surfaces =
            surfaces.filter { $0.material == .skin || $0.material == .eye }
            + surfaces.filter { $0.material != .skin && $0.material != .eye }
        self.uvs = uvs
    }

    /// A vertex on a seam of the texture is exported once per side, at the same place: drawn twice, the
    /// seams would light up. The twin stays for the surface, not as a point.
    static func dropTwins(_ range: Range<Int>, base: inout [SIMD4<Float>], normals: inout [SIMD4<Float>]) {
        var seen = Set<SIMD3<Int32>>()
        for index in range {
            let key = SIMD3<Int32>((SIMD3(base[index].x, base[index].y, base[index].z) * 1e4).rounded(.toNearestOrEven))
            if !seen.insert(key).inserted {
                base[index].w = 0
                normals[index].w = 0
            }
        }
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
        // Twins (size 0) are not neighbours: they are not drawn.
        for index in range where base[index].w > 0 { grid[cell(base[index]), default: []].append(index) }
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
    /// the lips, and `resting`, the face's own closure at rest, joins them, fading as the jaw opens.
    static func lipsClosing(shut: Float, jaw: Float, resting: Float = 0) -> Float {
        let atRest = min(max((0.1 - jaw) / 0.05, 0), 1)
        return min(max(shut, atRest), 1) * jaw + resting * atRest
    }

    /// The mouth's opening, as it shows, across the lips, up to near the corners. mouthClose
    /// lifts the lower lip: of the points it moves most (a third of its strongest move or more), within a
    /// narrow band across the lips, the highest is the lower lip's edge; above it, the lowest point of the
    /// skin is the upper lip's. Only `drawn` points count: tools/faces dropped the faces nobody sees.
    static func mouthOpenings(moved: [(Int, SIMD3<Float>)], drawn: Set<Int>, base: [SIMD4<Float>])
        -> [(upper: Int, lower: Int, closing: Float)]
    {
        let strongest = moved.map { simd_length($0.1) }.max() ?? 0
        let strong = moved.filter { simd_length($0.1) >= strongest / 3 && drawn.contains($0.0) }
        let xs = strong.map { base[$0.0].x }
        guard let low = xs.min(), let high = xs.max() else { return [] }
        let lifts = Dictionary(moved.map { ($0.0, $0.1.y) }, uniquingKeysWith: { first, _ in first })
        let band = (high - low) / 12
        // Every tenth of the way from one side to the other, short of the corners: the points are sparse,
        // and a few samples missed the widest place (Kofi's).
        return (-7...7).compactMap { (step: Int) -> (upper: Int, lower: Int, closing: Float)? in
            let x = (low + high) / 2 + Float(step) / 10 * (high - low) / 2
            guard
                let lower = strong.filter({ abs(base[$0.0].x - x) <= band && $0.1.y > 0 })
                    .max(by: { base[$0.0].y < base[$1.0].y })
            else { return nil }
            let edge = base[lower.0]
            let above = drawn.filter {
                abs(base[$0].x - x) <= band && base[$0].y > edge.y + 1e-4 && base[$0].y < edge.y + 0.2
                    && base[$0].z > edge.z - 0.04
            }
            guard let upper = above.min(by: { base[$0].y < base[$1].y }) else { return nil }
            let closing = lower.1.y - (lifts[upper] ?? 0)
            return closing > 1e-5 ? (upper, lower.0, closing) : nil
        }
    }

    public func shape(_ pose: FacePose, time: Double) -> [SIMD4<Float>] {
        var points = base
        var weights = pose.weights
        weights[FaceShape.mouthClose.rawValue] = Self.lipsClosing(
            shut: pose[.mouthClose], jaw: pose[.jawOpen], resting: restingClose)
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
