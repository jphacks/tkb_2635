import Foundation
import RealityKit
import StarCore

/// 3D の建物データの外側を、地平線までつなぐ「遠くの地面」（4-11）。
/// scripts/far_ground.py が作った `far_<シーンID>.jpg`（夜の航空写真＋衛星の夜間光）を、シーンの原点を中心とした大きな板に貼る。
/// 画像が無いシーンでは nil を返し、今までどおりアスファルトの地面を敷く。
@MainActor
final class FarGroundRenderer {
    static let shared = FarGroundRenderer()
    private var materials: [String: (material: UnlitMaterial, meters: Float)] = [:]

    /// 範囲の情報（far_<シーンID>.json）。画像の1辺が覆う長さ [m]
    private struct Info: Decodable {
        let meters: Float
    }

    static func hasImage(for scene: CityScene) -> Bool {
        Bundle.main.url(forResource: "far_\(scene.id)", withExtension: "jpg") != nil
    }

    /// シーン原点を中心とする板。scale はシーンの1mあたりの単位。位置は呼ぶ側で原点に合わせる。
    func ground(for scene: CityScene, scale: Float) async -> ModelEntity? {
        if materials[scene.id] == nil {
            guard let image = Bundle.main.url(forResource: "far_\(scene.id)", withExtension: "jpg"),
                  let json = Bundle.main.url(forResource: "far_\(scene.id)", withExtension: "json"),
                  let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: json)),
                  let texture = try? await TextureResource(contentsOf: image, options: .init(semantic: .color))
            else { return nil }
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
                // 遠くを浅い角度で見るので、異方性フィルタで明かりの点がつぶれにくくする
                descriptor.maxAnisotropy = 16
            }
            var material = UnlitMaterial()
            // 夜の暗さと街明かりは画像に焼き込んであるので、照明に関係なくそのまま出す
            material.color = .init(tint: .white, texture: .init(texture, sampler: sampler))
            // 1シーンで約 16MB の画像なので、ほかのシーンのものは手放す
            materials.removeAll()
            materials[scene.id] = (material, info.meters)
        }
        guard let entry = materials[scene.id], let mesh = try? Self.plane(half: entry.meters * scale / 2) else { return nil }
        return ModelEntity(mesh: mesh, materials: [entry.material])
    }

    /// 上を向いた正方形の板。画像の上が北（-z）、右が東（+x）になるよう、四隅の画像の位置を決める
    /// （画像の位置は左下が (0, 0)。Blender で書き出した都市モデルの地面の写真と同じ決まり）。
    private static func plane(half: Float) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "farGround")
        descriptor.positions = MeshBuffers.Positions([[-half, 0, half], [half, 0, half], [half, 0, -half], [-half, 0, -half]])
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        // 上から見て反時計回り（表が上を向く）
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try MeshResource.generate(from: [descriptor])
    }
}
