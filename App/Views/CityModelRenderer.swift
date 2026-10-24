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

    static func hasModel(for scene: CityScene) -> Bool {
        Bundle.main.url(forResource: "City_\(scene.id)", withExtension: "usdz") != nil
    }

    /// シーン原点を原点とした、1単位 = 1m の都市モデル。呼ぶたびに複製を返す（形のデータは共有）。
    func city(for scene: CityScene) async -> Entity? {
        if templates[scene.id] == nil {
            guard let url = Bundle.main.url(forResource: "City_\(scene.id)", withExtension: "usdz"),
                  let loaded = try? await Entity(contentsOf: url) else { return nil }
            let roof = await roof()
            for model in Self.models(in: loaded) {
                guard let mesh = model.model?.mesh else { continue }
                let material: any RealityKit.Material
                if model.name.hasPrefix("atlas_") || model.name == "ground_photo", let photo = model.model?.materials.first as? PhysicallyBasedMaterial {
                    material = Self.night(photo)
                } else if model.name == "roof" || model.name.hasPrefix("facade_") {
                    // 写真の無い面（全体の約1割）は、写真の調子から浮かないようコンクリートでそろえる。
                    material = roof
                } else {
                    continue
                }
                model.model = ModelComponent(mesh: mesh, materials: [material])
            }
            templates[scene.id] = loaded
        }
        return templates[scene.id]?.clone(recursive: true)
    }

    /// PLATEAU の実写テクスチャと地面の航空写真（どちらも昼の写真）を、夜の薄明かりで見ている調子にする。
    /// 写真をそのまま弱く光らせ、照明の向きに関係なく建物の柄が読めるようにする。
    private static func night(_ photo: PhysicallyBasedMaterial) -> PhysicallyBasedMaterial {
        var material = photo
        let texture = photo.baseColor.texture
        material.baseColor = .init(tint: Self.nightTint, texture: texture)
        // 発光に色の定数を足すと壁全面が同じ色に光る（8-06 で判明）ので、写真だけを渡す。
        material.emissiveColor = .init(texture: texture)
        material.emissiveIntensity = Self.nightGlowIntensity
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        material.faceCulling = .none
        return material
    }

    private static let nightTint = UIColor(red: 0.16, green: 0.18, blue: 0.27, alpha: 1)
    private static let nightGlowIntensity: Float = 0.26

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
        let ground = ModelEntity(mesh: .generatePlane(width: meters * scale, depth: meters * scale), materials: [groundMaterial!])
        // 都市モデルの航空写真の地面（高さ -0.3m）より下に敷き、写真の外側だけを埋める。
        ground.position.y = -1 * scale
        return ground
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


    private static func models(in entity: Entity) -> [ModelEntity] {
        let own: [ModelEntity] = (entity as? ModelEntity).map { [$0] } ?? []
        return own + entity.children.flatMap { models(in: $0) }
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
