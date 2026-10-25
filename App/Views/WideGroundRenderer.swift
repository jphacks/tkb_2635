import Foundation
import RealityKit
import StarCore

/// 23 区の広域 3D の下に敷く地面（夜の航空写真＋衛星の夜間光）。
/// `WideGround.jpg` と、中心と大きさを書いた `WideGround.json` を読む。無ければ nil（暗い板だけになる）。
@MainActor
enum WideGroundRenderer {
    private static let name = "WideGround"

    private struct Info: Decodable {
        let centerLatitude: Double
        let centerLongitude: Double
        /// 画像の 1 辺が覆う長さ [m]
        let meters: Float
    }

    /// 渋谷の原点の空間（1 単位 = 1m、x が東、-z が北）に置いた板
    static func ground() async -> ModelEntity? {
        guard let image = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let json = Bundle.main.url(forResource: name, withExtension: "json"),
              let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: json)),
              let texture = try? await TextureResource(contentsOf: image, options: .init(semantic: .color)),
              let mesh = try? plane(half: info.meters / 2) else { return nil }
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            // 斜めから見ても街明かりの点がつぶれにくくする
            descriptor.maxAnisotropy = 16
        }
        // 夜の暗さと街明かりは画像に焼き込んであるので、照明に関係なく画像のまま出す（自分で光る色として貼る）。
        // 強さ 1 で詳細画面の遠くの地面（FarGroundRenderer）と同じ明るさ。遠くから見るときは WideCityBrightness が強める
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .black)
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0)
        material.emissiveColor = .init(texture: .init(texture, sampler: sampler))
        material.emissiveIntensity = 1
        let ground = ModelEntity(mesh: mesh, materials: [material])
        ground.name = WideCityBrightness.groundName
        let center = WideCity.localPosition(latitude: info.centerLatitude, longitude: info.centerLongitude)
        ground.position = [Float(center.east), 0, -Float(center.north)]
        return ground
    }

    /// 上を向いた正方形の板。画像の上が北、右が東（FarGroundRenderer と同じ決まり）
    private static func plane(half: Float) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "wideGround")
        descriptor.positions = MeshBuffers.Positions([[-half, 0, half], [half, 0, half], [half, 0, -half], [-half, 0, -half]])
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try MeshResource.generate(from: [descriptor])
    }
}
