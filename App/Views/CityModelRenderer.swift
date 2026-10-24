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
            // 1シーンで実写のアトラスが GPU メモリを 100MB ほど使うので、ほかのシーンの元データは手放す
            // （表示中の複製が残っていれば、その分は複製が消えるまで残る）。
            templates.removeAll()
            guard let url = Bundle.main.url(forResource: "City_\(scene.id)", withExtension: "usdz"),
                  let loaded = try? await Entity(contentsOf: url) else { return nil }
            let roof = await roof()
            for model in Self.models(in: loaded) {
                guard let mesh = model.model?.mesh else { continue }
                let material: any RealityKit.Material
                let name = Self.partName(model.name)
                if name == "ground_night", let photo = model.model?.materials.first as? PhysicallyBasedMaterial {
                    // 夜の暗さと街灯の明かりは Blender で写真に焼き込んであるので、照明に関係なくそのまま出す。
                    var unlit = UnlitMaterial()
                    unlit.color = .init(tint: .white, texture: photo.baseColor.texture)
                    material = unlit
                } else if name.hasPrefix("atlas_") || name == "ground_photo", let photo = model.model?.materials.first as? PhysicallyBasedMaterial {
                    material = Self.night(photo)
                } else if let light = Self.lightColor(for: name) {
                    material = UnlitMaterial(color: light)
                } else if name == "roof" || name.hasPrefix("facade_") {
                    // 写真の無い面（全体の約1割）は、写真の調子から浮かないようコンクリートでそろえる。
                    material = roof
                } else {
                    continue
                }
                model.model = ModelComponent(mesh: mesh, materials: [material])
            }
            templates[scene.id] = loaded
        }
        guard let city = templates[scene.id]?.clone(recursive: true) else { return nil }
        // 複製にはアニメーションが引き継がれないので、ここで点滅を始める。
        for model in Self.models(in: city) where model.name == "aviation" {
            Self.blink(model)
        }
        return city
    }

    /// 窓明かりを、地点の時刻に合わせてグループごとに点けたり消したりする（部品の名前は windows_<グループ>_<色>）。
    static func updateWindows(in city: Entity, date: Date) {
        for model in models(in: city) where model.name.hasPrefix("windows_") {
            let parts = partName(model.name).split(separator: "_")
            guard parts.count == 3, let group = Int(parts[1]) else { continue }
            model.isEnabled = NightLightSchedule.windowsOn(group: group, at: date)
        }
    }

    /// 観測者が中にいる建物（屋内の展望室など）を半透明にして、外から観測者の位置が見えるようにする。
    /// その建物の部品は、名前の最後に hostTag が付いている（scripts/plateau_shapes.py）。
    static func revealHost(_ buildingId: String, in city: Entity) {
        let tag = hostTag(for: buildingId)
        for model in models(in: city) where model.name.hasSuffix(tag) {
            model.components.set(OpacityComponent(opacity: hostOpacity))
        }
    }

    private static let hostOpacity: Float = 0.3

    /// scripts/plateau_shapes.py の host_tag と同じ規則（_h と gml:id の英数字の先頭 8 文字）。
    static func hostTag(for buildingId: String) -> String {
        let id = buildingId.hasPrefix("bldg_") ? String(buildingId.dropFirst(5)) : buildingId
        return "_h" + String(id.filter { $0.isLetter || $0.isNumber }.prefix(8)).lowercased()
    }

    /// 部品の名前から、観測者のいる建物の目印（_h + 英数字 8 文字）を外した名前。材質と明かりはこの名前で決める。
    private static func partName(_ name: String) -> String {
        guard let range = name.range(of: #"_h[0-9a-z]{8}$"#, options: .regularExpression) else { return name }
        return String(name[..<range.lowerBound])
    }

    /// 窓（色の番号 0: 暖色、1: 白っぽい暖色、2: 青白い）・街灯・遠くの街・航空障害灯の色。明かりの部品でなければ nil。
    private static func lightColor(for name: String) -> UIColor? {
        if name.hasPrefix("windows_"), let tone = name.split(separator: "_").last.flatMap({ Int($0) }) {
            return [UIColor(red: 1.0, green: 0.74, blue: 0.40, alpha: 1),
                    UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1),
                    UIColor(red: 0.86, green: 0.91, blue: 0.98, alpha: 1)][min(tone, 2)]
        }
        switch name {
        case "lamps": return UIColor(red: 1.0, green: 0.82, blue: 0.56, alpha: 1)
        case "far_lights": return UIColor(red: 0.95, green: 0.70, blue: 0.42, alpha: 1)
        case "aviation": return UIColor(red: 1.0, green: 0.12, blue: 0.08, alpha: 1)
        default: return nil
        }
    }

    /// 航空障害灯を、ゆっくり明るくなったり暗くなったりさせる。
    private static func blink(_ model: ModelEntity) {
        let animation = FromToByAnimation<Float>(from: 1, to: 0.05, duration: 0.75, timing: .easeInOut,
                                                 bindTarget: .opacity, repeatMode: .autoReverse)
        guard let resource = try? AnimationResource.generate(with: animation) else { return }
        model.components.set(OpacityComponent(opacity: 1))
        model.playAnimation(resource)
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
    private static let nightGlowIntensity: Float = 0.3

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
