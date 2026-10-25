import RealityKit
import StarCore
import UIKit

/// 3D の空の星座。星空の球（半径 1、赤道座標）の内側に、ガラス調の線・にじむ星・淡い線画・名札を置く。
/// 位置の計算は StarCore（`ConstellationLines`・`ConstellationArt`）が行い、ここは形と見た目だけを作る。
@MainActor
enum ConstellationRenderer {
    static let containerName = "constellations"

    private struct Meshes {
        let lines: MeshResource
        let stars: MeshResource
        let art: MeshResource?
    }

    private static let meshes: Meshes? = makeMeshes()

    /// 星空の球に星座を足す。球の星の画像より後に描くよう、描く順番を決めておく
    static func attach(to dome: ModelEntity) {
        guard let meshes else { return }
        let group = ModelSortGroup(depthPass: nil)
        dome.components.set(ModelSortGroupComponent(group: group, order: 0))
        let style = ConstellationStyle.self

        let container = Entity()
        container.name = containerName
        dome.addChild(container)

        if let art = meshes.art {
            container.addChild(glowEntity("constellationArt", mesh: art, texture: ConstellationTextures.art,
                                          rgb: style.artRGB, opacity: style.artOpacity, group: group, order: 1))
        }
        for image in ConstellationImageRenderer.makeEntities() {
            image.components.set(ModelSortGroupComponent(group: group, order: 1))
            container.addChild(image)
        }
        container.addChild(glowEntity("constellationLines", mesh: meshes.lines, texture: ConstellationTextures.line,
                                      rgb: style.lineRGB, opacity: style.skyLineOpacity, group: group, order: 2))
        container.addChild(glowEntity("constellationStars", mesh: meshes.stars, texture: ConstellationTextures.star,
                                      rgb: (1, 1, 1), opacity: style.starOpacity, group: group, order: 3))
        ConstellationLabelRenderer.addLabels(to: container, group: group, order: 4)
    }

    /// 薄明のときは星空と一緒に薄くする
    static func fade(_ dome: Entity, opacity: Float) {
        dome.findEntity(named: containerName)?.components.set(OpacityComponent(opacity: opacity))
    }

    private static func glowEntity(_ name: String, mesh: MeshResource, texture: TextureResource?,
                                   rgb: (r: Double, g: Double, b: Double), opacity: Double,
                                   group: ModelSortGroup, order: Int32) -> ModelEntity {
        var material = UnlitMaterial()
        let color = UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        if let texture {
            material.color = .init(tint: color, texture: .init(texture))
            material.blending = .transparent(opacity: .init(scale: Float(opacity), texture: .init(texture)))
        } else {
            material.color = .init(tint: color)
            material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity) * 0.5))
        }
        material.faceCulling = .none
        // 画像と同じく、半透明の線や光どうしで隠し合わないように奥行きは書かない
        material.writesDepth = false
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.components.set(ModelSortGroupComponent(group: group, order: order))
        return entity
    }

    // MARK: - 形

    private static func makeMeshes() -> Meshes? {
        let style = ConstellationStyle.self
        let lines = ConstellationData.lines
        let lineSegments = lines.flatMap(\.equatorialPolylines).flatMap { segments($0) }
        let artSegments = ConstellationData.art.flatMap(\.equatorialStrokes).flatMap { segments($0) }
        let brightStars = StarCatalog.stars.filter { $0.magnitude <= ConstellationLabelPicker.brightMagnitude }
            .map { EquatorialVector(rightAscension: $0.rightAscension * 15, declination: $0.declination) }
        // 画像に光る印が描き込まれている星は、アプリの光を重ねない（光が二重にならないように）
        let markedStars = ConstellationData.images.flatMap(\.markedStars)
        let stars = lines.flatMap(\.stars).filter { star in
            !markedStars.contains { $0.angle(to: star) < 0.05 }
        }.map { star in
            (star, brightStars.contains { $0.angle(to: star) < 0.3 } ? style.brightStarScale : 1)
        }
        guard let lineMesh = ribbon(lineSegments, radius: style.lineRadius, halfWidth: style.lineHalfWidth, name: "constellationLines"),
              let starMesh = sprites(stars, radius: style.starRadius, halfSize: style.starHalfSize) else { return nil }
        let artMesh = ribbon(artSegments, radius: style.artRadius, halfWidth: style.artHalfWidth, name: "constellationArt")
        return Meshes(lines: lineMesh, stars: starMesh, art: artMesh)
    }

    /// 折れ線を、球面に沿った短い線分に分ける
    private static func segments(_ polyline: [EquatorialVector]) -> [(SIMD3<Float>, SIMD3<Float>)] {
        zip(polyline, polyline.dropFirst()).flatMap { a, b -> [(SIMD3<Float>, SIMD3<Float>)] in
            let points = ConstellationGeometry.arc(from: a, to: b, maxStep: ConstellationStyle.arcStep).map(simd)
            return Array(zip(points, points.dropFirst()))
        }
    }

    private static func simd(_ v: EquatorialVector) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    /// 線分ごとの細長い帯。帯の横方向に画像の v（0〜1）を割り当て、真ん中だけを明るくする
    private static func ribbon(_ segments: [(SIMD3<Float>, SIMD3<Float>)], radius: Float, halfWidth: Float,
                               name: String) -> MeshResource? {
        guard !segments.isEmpty else { return nil }
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        positions.reserveCapacity(segments.count * 4)
        for (start, end) in segments {
            let side = simd_normalize(simd_cross(simd_normalize(start + end), end - start)) * halfWidth
            let a = start * radius, b = end * radius
            let base = UInt32(positions.count)
            positions += [a - side, a + side, b - side, b + side]
            uvs += [[0.5, 0], [0.5, 1], [0.5, 0], [0.5, 1]]
            indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
        }
        return mesh(name, positions: positions, uvs: uvs, indices: indices)
    }

    /// 星ごとの小さな四角（球の内側を向く）。丸い光の画像を貼る
    private static func sprites(_ stars: [(EquatorialVector, Float)], radius: Float, halfSize: Float) -> MeshResource? {
        guard !stars.isEmpty else { return nil }
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for (star, scale) in stars {
            let center = simd(star)
            var east = simd_cross(SIMD3<Float>(0, 0, 1), center)
            if simd_length(east) < 1e-5 { east = [0, 1, 0] }
            east = simd_normalize(east) * halfSize * scale
            let north = simd_normalize(simd_cross(center, east)) * halfSize * scale
            let c = center * radius
            let base = UInt32(positions.count)
            positions += [c - east - north, c + east - north, c - east + north, c + east + north]
            uvs += [[0, 0], [1, 0], [0, 1], [1, 1]]
            indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
        }
        return mesh("constellationStars", positions: positions, uvs: uvs, indices: indices)
    }

    private static func mesh(_ name: String, positions: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]) -> MeshResource? {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
