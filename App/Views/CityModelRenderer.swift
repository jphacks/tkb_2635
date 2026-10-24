import RealityKit
import StarCore
import SwiftUI

/// PLATEAU の LOD2 から Blender で作った都市の 3D ファイル（`City_<シーンID>.usdz`）を読み、部品の名前ごとに材質を付ける。
/// 見た目専用。遮蔽判定は buildings.json の直方体のまま。ファイルが無いシーンでは nil を返し、従来の箱で描く。
@MainActor
final class CityModelRenderer {
    static let shared = CityModelRenderer()
    private var templates: [String: Entity] = [:]
    private var roofMaterial: PhysicallyBasedMaterial?
    private var groundMaterial: PhysicallyBasedMaterial?

    /// 地面の CC0 テクスチャ1枚が覆う大きさ [m]
    private static let groundTileMeters: Float = 24

    /// シーン原点を原点とした、1単位 = 1m の都市モデル。呼ぶたびに複製を返す（形のデータは共有）。
    func city(for scene: CityScene, hostBuildingId: String?) async -> Entity? {
        if templates[scene.id] == nil {
            guard let url = Bundle.main.url(forResource: "City_\(scene.id)", withExtension: "usdz"),
                  let loaded = try? await Entity(contentsOf: url) else { return nil }
            templates[scene.id] = loaded
        }
        guard let city = templates[scene.id]?.clone(recursive: true) else { return nil }
        let roof = await roof()
        let buildings = Dictionary(scene.buildings.map { ($0.id.replacingOccurrences(of: "-", with: "_"), $0) },
                                   uniquingKeysWith: { first, _ in first })
        let host = hostBuildingId?.replacingOccurrences(of: "-", with: "_")
        for model in Self.models(in: city) {
            guard let mesh = model.model?.mesh else { continue }
            let material: any RealityKit.Material
            if model.name == "roof" {
                material = roof
            } else if model.name.hasPrefix("facade_"), let appearance = Self.appearance(named: model.name) {
                material = Self.doubleSided(BuildingNightRenderer.shared.facade(appearance))
            } else if model.name == host {
                material = SimpleMaterial(color: .init(red: 0.20, green: 0.70, blue: 0.76, alpha: 0.35),
                                          roughness: 0.7, isMetallic: false)
            } else if let building = buildings[model.name] {
                // 観測者が立つ建物として分けた部品も、ほかの地点から見るときは普通の建物として描く。
                material = Self.doubleSided(BuildingNightRenderer.shared.facade(BuildingFacade(usage: building.usage, id: building.id)))
            } else {
                continue
            }
            model.model = ModelComponent(mesh: mesh, materials: [material])
        }
        return city
    }

    /// CC0 のアスファルトを貼った地面。meters は1辺の長さ [m]、scale はシーンの1mあたりの単位。
    func ground(meters: Float, scale: Float) async -> ModelEntity {
        if groundMaterial == nil {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .init(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
                                       texture: await Self.texture("Asphalt031_Color", semantic: .color))
            material.roughness = .init(scale: 1, texture: await Self.texture("Asphalt031_Roughness", semantic: .scalar))
            material.normal = .init(texture: await Self.texture("Asphalt031_NormalGL", semantic: .normal))
            material.textureCoordinateTransform = .init(scale: .init(repeating: meters / Self.groundTileMeters))
            groundMaterial = material
        }
        return ModelEntity(mesh: .generatePlane(width: meters * scale, depth: meters * scale), materials: [groundMaterial!])
    }

    private func roof() async -> PhysicallyBasedMaterial {
        if let roofMaterial { return roofMaterial }
        var material = PhysicallyBasedMaterial()
        // 屋上は窓のない打ち放しコンクリート。夜の青い環境光に合わせて暗めに色を寄せる。
        material.baseColor = .init(tint: .init(red: 0.46, green: 0.50, blue: 0.58, alpha: 1),
                                   texture: await Self.texture("Concrete034_Color", semantic: .color))
        material.roughness = .init(scale: 1, texture: await Self.texture("Concrete034_Roughness", semantic: .scalar))
        material.normal = .init(texture: await Self.texture("Concrete034_NormalGL", semantic: .normal))
        material.faceCulling = .none
        roofMaterial = material
        return material
    }

    /// `facade_<外観の種類>_<模様番号>` を BuildingFacade に戻す（scripts/plateau_shapes.py の facade_key と対）。
    private static func appearance(named name: String) -> BuildingFacade? {
        let parts = name.split(separator: "_")
        guard parts.count == 3, let raw = Int(parts[1]), let style = BuildingFacade.Style(rawValue: raw),
              let variant = Int(parts[2]) else { return nil }
        return BuildingFacade(style: style, variant: variant)
    }

    private static func models(in entity: Entity) -> [ModelEntity] {
        let own: [ModelEntity] = (entity as? ModelEntity).map { [$0] } ?? []
        return own + entity.children.flatMap { models(in: $0) }
    }

    /// PLATEAU の面の表裏が逆でも穴に見えないよう、裏面も描く。
    private static func doubleSided(_ material: PhysicallyBasedMaterial) -> PhysicallyBasedMaterial {
        var material = material
        material.faceCulling = .none
        return material
    }

    private static func texture(_ name: String, semantic: TextureResource.Semantic) async -> MaterialParameters.Texture? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let resource = try? await TextureResource(contentsOf: url, options: .init(semantic: semantic)) else { return nil }
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            descriptor.maxAnisotropy = 8
        }
        return .init(resource, sampler: sampler)
    }
}
