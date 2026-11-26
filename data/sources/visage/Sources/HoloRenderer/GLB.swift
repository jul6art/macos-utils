import Foundation
import simd

/// A minimal reader of binary glTF 2.0 (.glb), for the faces of tools/faces (spec, § 8.1): positions,
/// normals, texture coordinates, triangles, and morph targets (dense or sparse) with their names. A few hundred lines instead of a library.
struct GLBFile {
    struct Mesh {
        /// The node's name: `<face>.<part>` (head, eyes, eyebrows, eyelashes, teeth, tongue, hair).
        var name: String
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        /// Where each vertex takes its colour in the part's texture; empty when the file has none.
        var uvs: [SIMD2<Float>]
        /// Three vertex indices per triangle.
        var triangles: [UInt32]
        /// Per target, in the order of `targetNames`: the vertices it moves and by how much.
        var targets: [(indices: [Int32], deltas: [SIMD3<Float>])]
        var targetNames: [String]
    }

    enum Failure: Error {
        case notGLB
        case malformed(String)
    }

    let meshes: [Mesh]

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard data.count >= 20, data.readUInt32(at: 0) == 0x4654_6C67 else { throw Failure.notGLB }
        let jsonLength = Int(data.readUInt32(at: 12))
        guard data.readUInt32(at: 16) == 0x4E4F_534A, data.count >= 20 + jsonLength + 8 else {
            throw Failure.malformed("JSON chunk")
        }
        let json = data.subdata(in: 20..<(20 + jsonLength))
        let binaryStart = 20 + jsonLength + 8
        let binary = data.subdata(in: binaryStart..<data.count)
        guard let gltf = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw Failure.malformed("JSON")
        }
        let reader = Reader(gltf: gltf, binary: binary)

        var meshes: [Mesh] = []
        for node in gltf["nodes"] as? [[String: Any]] ?? [] {
            guard let meshIndex = node["mesh"] as? Int,
                let mesh = (gltf["meshes"] as? [[String: Any]])?[meshIndex],
                let primitive = (mesh["primitives"] as? [[String: Any]])?.first,
                let attributes = primitive["attributes"] as? [String: Int],
                let positionAccessor = attributes["POSITION"]
            else { continue }
            let positions = try reader.vectors(positionAccessor)
            let normals = try attributes["NORMAL"].map { try reader.vectors($0) } ?? []
            let uvs = try attributes["TEXCOORD_0"].map { try reader.pairs($0) } ?? []
            guard primitive["mode"] as? Int ?? 4 == 4 else { throw Failure.malformed("not triangles") }
            let triangles = try (primitive["indices"] as? Int).map { try reader.integers($0) } ?? []
            var targets: [(indices: [Int32], deltas: [SIMD3<Float>])] = []
            for target in primitive["targets"] as? [[String: Int]] ?? [] {
                guard let accessor = target["POSITION"] else {
                    targets.append(([], []))
                    continue
                }
                targets.append(try reader.sparseVectors(accessor, count: positions.count))
            }
            let names = (mesh["extras"] as? [String: Any])?["targetNames"] as? [String] ?? []
            meshes.append(
                Mesh(
                    name: node["name"] as? String ?? "", positions: positions, normals: normals, uvs: uvs,
                    triangles: triangles.map(UInt32.init(bitPattern:)), targets: targets, targetNames: names))
        }
        self.meshes = meshes
    }

    private struct Reader {
        let gltf: [String: Any]
        let binary: Data

        private func accessor(_ index: Int) throws -> [String: Any] {
            guard let accessors = gltf["accessors"] as? [[String: Any]], index < accessors.count else {
                throw Failure.malformed("accessor \(index)")
            }
            return accessors[index]
        }

        private func offset(view: Int, extra: Int) throws -> Int {
            guard let views = gltf["bufferViews"] as? [[String: Any]], view < views.count else {
                throw Failure.malformed("buffer view \(view)")
            }
            return (views[view]["byteOffset"] as? Int ?? 0) + extra
        }

        private func floats3(at offset: Int, count: Int) -> [SIMD3<Float>] {
            (0..<count).map { index in
                let base = offset + index * 12
                return SIMD3(binary.readFloat(at: base), binary.readFloat(at: base + 4), binary.readFloat(at: base + 8))
            }
        }

        /// A SCALAR accessor of unsigned integers: the triangles' corners.
        func integers(_ index: Int) throws -> [Int32] {
            let accessor = try accessor(index)
            guard let view = accessor["bufferView"] as? Int else { throw Failure.malformed("indices") }
            return integers(
                at: try offset(view: view, extra: accessor["byteOffset"] as? Int ?? 0),
                count: accessor["count"] as? Int ?? 0, component: accessor["componentType"] as? Int ?? 5125)
        }

        /// Unsigned integers (triangles' corners, a sparse target's vertices), of any of glTF's widths.
        private func integers(at offset: Int, count: Int, component: Int) -> [Int32] {
            (0..<count).map { item in
                switch component {
                case 5121: Int32(binary[binary.startIndex + offset + item])
                case 5123: Int32(binary.readUInt16(at: offset + item * 2))
                default: Int32(bitPattern: binary.readUInt32(at: offset + item * 4))
                }
            }
        }

        /// A dense VEC2 float accessor.
        func pairs(_ index: Int) throws -> [SIMD2<Float>] {
            let accessor = try accessor(index)
            guard let view = accessor["bufferView"] as? Int else { throw Failure.malformed("texture coordinates") }
            let start = try offset(view: view, extra: accessor["byteOffset"] as? Int ?? 0)
            return (0..<(accessor["count"] as? Int ?? 0)).map { item in
                SIMD2(binary.readFloat(at: start + item * 8), binary.readFloat(at: start + item * 8 + 4))
            }
        }

        /// A dense VEC3 float accessor.
        func vectors(_ index: Int) throws -> [SIMD3<Float>] {
            let accessor = try accessor(index)
            let count = accessor["count"] as? Int ?? 0
            guard let view = accessor["bufferView"] as? Int else {
                return [SIMD3<Float>](repeating: .zero, count: count)
            }
            return floats3(at: try offset(view: view, extra: accessor["byteOffset"] as? Int ?? 0), count: count)
        }

        /// A morph target: only the vertices it moves. Sparse accessors stay sparse; dense ones are thinned.
        func sparseVectors(_ index: Int, count: Int) throws -> (indices: [Int32], deltas: [SIMD3<Float>]) {
            let accessor = try accessor(index)
            if let sparse = accessor["sparse"] as? [String: Any], accessor["bufferView"] == nil,
                let sparseCount = sparse["count"] as? Int,
                let indexInfo = sparse["indices"] as? [String: Any], let valueInfo = sparse["values"] as? [String: Any],
                let indexView = indexInfo["bufferView"] as? Int, let valueView = valueInfo["bufferView"] as? Int
            {
                let indices = integers(
                    at: try offset(view: indexView, extra: indexInfo["byteOffset"] as? Int ?? 0), count: sparseCount,
                    component: indexInfo["componentType"] as? Int ?? 5125)
                let deltas = floats3(
                    at: try offset(view: valueView, extra: valueInfo["byteOffset"] as? Int ?? 0), count: sparseCount)
                return (indices, deltas)
            }
            let dense = try vectors(index)
            var indices: [Int32] = []
            var deltas: [SIMD3<Float>] = []
            for (vertex, delta) in dense.enumerated() where simd_length_squared(delta) > 1e-12 {
                indices.append(Int32(vertex))
                deltas.append(delta)
            }
            return (indices, deltas)
        }
    }
}

extension Data {
    fileprivate func readUInt32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) {
            copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    fileprivate func readUInt16(at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) {
            copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    fileprivate func readFloat(at offset: Int) -> Float {
        Float(bitPattern: readUInt32(at: offset))
    }
}
