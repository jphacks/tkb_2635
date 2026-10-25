import CoreGraphics
import RealityKit
import UIKit

/// 星座の線を天球の内側へ沿わせ、淡いガラス調の二重線で表示する。
@MainActor
enum ConstellationRenderer {
    private struct Constellation: Decodable {
        let paths: [[[Double]]]
    }

    private static let overlayMeshes: (glow: MeshResource, core: MeshResource)? = makeMeshes()

    static func makeOverlay() -> [ModelEntity] {
        guard let overlayMeshes else { return [] }

        var glow = UnlitMaterial(color: UIColor(red: 0.45, green: 0.78, blue: 1, alpha: 1))
        glow.blending = .transparent(opacity: .init(floatLiteral: 0.12))
        glow.faceCulling = .none

        var core = UnlitMaterial(color: UIColor(red: 0.83, green: 0.94, blue: 1, alpha: 1))
        core.blending = .transparent(opacity: .init(floatLiteral: 0.48))
        core.faceCulling = .none

        let glowEntity = ModelEntity(mesh: overlayMeshes.glow, materials: [glow])
        glowEntity.name = "constellationGlow"
        let coreEntity = ModelEntity(mesh: overlayMeshes.core, materials: [core])
        coreEntity.name = "constellationLines"
        return [glowEntity, coreEntity]
    }

    private static func makeMeshes() -> (glow: MeshResource, core: MeshResource)? {
        guard let url = Bundle.main.url(forResource: "constellations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let constellations = try? JSONDecoder().decode([Constellation].self, from: data) else {
            return nil
        }

        let segments = constellations.flatMap(\.paths).flatMap { path -> [(SIMD3<Float>, SIMD3<Float>)] in
            let points = path.compactMap(unitVector)
            guard points.count > 1 else { return [] }
            return zip(points, points.dropFirst()).flatMap(sampleArc)
        }
        guard !segments.isEmpty,
              let glow = makeRibbonMesh(segments, radius: 1.003, halfWidth: 0.0018),
              let core = makeRibbonMesh(segments, radius: 1.0035, halfWidth: 0.00038) else { return nil }
        return (glow, core)
    }

    /// d3-celestial は赤経を経度に変換し、0〜180°と-180〜0°で表している。
    private static func unitVector(_ coordinate: [Double]) -> SIMD3<Float>? {
        guard coordinate.count >= 2 else { return nil }
        let longitude = coordinate[0]
        let rightAscension = longitude < 0 ? longitude + 360 : longitude
        let dec = coordinate[1] * .pi / 180
        let ra = rightAscension * .pi / 180
        return SIMD3(Float(cos(dec) * cos(ra)), Float(cos(dec) * sin(ra)), Float(sin(dec)))
    }

    /// 長い星座線も球面の弧をたどるよう、約1.5°ごとに細分化する。
    private static func sampleArc(_ endpoints: (SIMD3<Float>, SIMD3<Float>)) -> [(SIMD3<Float>, SIMD3<Float>)] {
        let start = endpoints.0
        let end = endpoints.1
        let angle = acos(max(-1, min(1, simd_dot(start, end))))
        let steps = max(1, Int(ceil(angle / (1.5 * .pi / 180))))
        return (0..<steps).map { index in
            (sphericalPoint(start, end, fraction: Float(index) / Float(steps)),
             sphericalPoint(start, end, fraction: Float(index + 1) / Float(steps)))
        }
    }

    private static func sphericalPoint(_ start: SIMD3<Float>, _ end: SIMD3<Float>, fraction: Float) -> SIMD3<Float> {
        let dot = max(-1, min(1, simd_dot(start, end)))
        let angle = acos(dot)
        guard angle > 1e-5 else { return simd_normalize(start + (end - start) * fraction) }
        let sine = sin(angle)
        return simd_normalize(start * (sin((1 - fraction) * angle) / sine)
                              + end * (sin(fraction * angle) / sine))
    }

    private static func makeRibbonMesh(_ segments: [(SIMD3<Float>, SIMD3<Float>)],
                                       radius: Float, halfWidth: Float) -> MeshResource? {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(segments.count * 4)
        indices.reserveCapacity(segments.count * 6)

        for (start, end) in segments {
            let midpoint = simd_normalize(start + end)
            let tangent = end - start
            let side = simd_normalize(simd_cross(midpoint, tangent))
            let a = start * radius
            let b = end * radius
            let offset = side * halfWidth
            let base = UInt32(positions.count)
            positions += [a - offset, a + offset, b - offset, b + offset]
            indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
        }

        var descriptor = MeshDescriptor(name: "constellationRibbon")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
