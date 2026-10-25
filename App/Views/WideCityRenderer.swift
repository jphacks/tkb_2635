import RealityKit
import StarCore
import SwiftUI

/// 23 区の広域 3D を読む。区の箱（`Wide_<区コード>.usdz`）はアプリに入っているものをファイル名で見つけ、
/// 屋根の形つき（`Wide2_<区コード>.usdz`）は近づいた区だけ、必要になったときに読む（WideCityRenderer+LOD.swift）。
/// USDZ は Blender の Z-up・1 単位 = 1m・渋谷の原点。RealityKit は読むときに Y-up へ回すので、x が東、y が標高、-z が北になる。
@MainActor
final class WideCityRenderer {
    static let shared = WideCityRenderer()

    /// 読み終えた区の箱。画面ごとに複製して使う（形のデータは共有）
    private var boxes: [String: Entity] = [:]
    /// 読み終えた屋根の形つき。古いものから手放す
    private var details: [(code: String, entity: Entity)] = []
    private var detailLoads: [String: Task<Entity?, Never>] = [:]
    private var material: PhysicallyBasedMaterial?

    /// 手元に残す屋根の形つきの数（同時に出す区の数 + 1 にして、行き来しても読み直さないようにする）
    private static let detailCacheCount = WideCityLOD.maxDetailWards + 1

    /// アプリに入っている区のコード（ファイル名から。区を足してもコードを直さなくてよい）
    static let wardCodes: [String] = (Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
        .compactMap { WideCity.wardCode(fromBoxFile: $0.deletingPathExtension().lastPathComponent) }
        .sorted()

    /// 区の箱の複製。並列に読み、読めた区から onLoad で渡す
    func loadBoxes(onLoad: @escaping @MainActor (String, Entity) -> Void) async {
        // 23 区を並列に読むので、先に材質（窓明かりの画像）を 1 回だけ作っておく
        _ = await nightMaterial()
        let tasks = Self.wardCodes.map { code in
            Task { @MainActor in
                if boxes[code] == nil, let loaded = await load(WideCity.boxPrefix + code) {
                    boxes[code] = loaded
                }
                if let box = boxes[code] { onLoad(code, box.clone(recursive: true)) }
            }
        }
        for task in tasks { await task.value }
    }

    /// 屋根の形つきの複製。読めなければ nil（箱のまま出す）
    func detail(for code: String) async -> Entity? {
        if let index = details.firstIndex(where: { $0.code == code }) {
            let hit = details.remove(at: index)
            details.append(hit)
            return hit.entity.clone(recursive: true)
        }
        let task = detailLoads[code] ?? Task { await load(WideCity.detailPrefix + code) }
        detailLoads[code] = task
        let loaded = await task.value
        detailLoads[code] = nil
        guard let loaded else { return nil }
        if !details.contains(where: { $0.code == code }) {
            details.append((code, loaded))
            // 表示中の複製が持っている分は、複製が消えるまで残る
            if details.count > Self.detailCacheCount { details.removeFirst() }
        }
        return loaded.clone(recursive: true)
    }

    private func load(_ name: String) async -> Entity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
              let loaded = try? await Entity(contentsOf: url) else { return nil }
        // 23 区ぶん描くので、材質は窓明かりつきと外壁だけの 2 つにする。
        // 壁の UV が無い形（作り直す前の区と LOD2）に窓明かりの画像を使うと、画像の平均の色で全面が光るので外壁だけにする
        let windows = await nightMaterial()
        for model in Self.models(in: loaded) {
            guard var component = model.model else { continue }
            let hasUV = component.mesh.contents.models.contains { $0.parts.contains { $0.textureCoordinates != nil } }
            let material = hasUV ? windows : Self.plainMaterial(level: 0)
            model.components.set(WideWallKind(hasUV: hasUV))
            component.materials = Array(repeating: material, count: max(component.materials.count, 1))
            model.model = component
        }
        return loaded
    }

    /// 詳細画面の都市モデル（CityModelRenderer）に寄せた材質。暗い青灰色の外壁に、WideWindowTexture の窓の帯を自分で光る色として貼る。
    /// 箱の UV は WideWindowTexture の 1 枚（32m × 28m）で繰り返すよう、wide_ward_blender.py で付けてある
    private func nightMaterial() async -> PhysicallyBasedMaterial {
        if let material { return material }
        var made = Self.wall(level: 0)
        if let image = WideWindowTexture.image(),
           let resource = try? await TextureResource(image: image,
                                                     options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)) {
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.sAddressMode = .repeat
                descriptor.tAddressMode = .repeat
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
                descriptor.maxAnisotropy = 8
            }
            // 色の定数を渡すと壁全面がその色に光る（CityModelRenderer の 8-06 と同じ）ので、画像だけを渡す
            made.emissiveColor = .init(texture: .init(resource, sampler: sampler))
            made.emissiveIntensity = 1
        }
        material = made
        return made
    }

    /// 明るさの段階（WideCityBrightness）ごとの材質。段階が変わったときだけ作る
    private var wallMaterials: [String: PhysicallyBasedMaterial] = [:]

    /// 壁の材質。level 0 は詳細画面と同じ、1 は 23 区全体を見るとき。窓の材質がまだできていなければ nil
    func wallMaterial(hasUV: Bool, level: Float) -> PhysicallyBasedMaterial? {
        let key = "\(hasUV)-\(level)"
        if let cached = wallMaterials[key] { return cached }
        guard hasUV else {
            let plain = Self.plainMaterial(level: level)
            wallMaterials[key] = plain
            return plain
        }
        guard var made = material else { return nil }
        made.emissiveIntensity = WideCityBrightness.mix(1, WideCityBrightness.farWindowGlow, level)
        made.baseColor.tint = Self.wallColor(level: level)
        wallMaterials[key] = made
        return made
    }

    /// 外壁の色。詳細画面の実写の外壁を夜の色（0.16, 0.18, 0.27）にして少し光らせた見た目に近い暗い青灰色。
    /// 遠くでは窓の帯がつぶれるので、窓の平均の色に近い暗い暖色に寄せる
    private static let nearWall = (red: Float(0.27), green: Float(0.29), blue: Float(0.35))
    private static let farWall = (red: Float(0.34), green: Float(0.28), blue: Float(0.20))

    private static func wallColor(level: Float) -> UIColor {
        UIColor(red: CGFloat(WideCityBrightness.mix(nearWall.red, farWall.red, level)),
                green: CGFloat(WideCityBrightness.mix(nearWall.green, farWall.green, level)),
                blue: CGFloat(WideCityBrightness.mix(nearWall.blue, farWall.blue, level)), alpha: 1)
    }

    private static func wall(level: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: wallColor(level: level))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        // 箱の面の向きがそろっていないことがあるので、裏からも描く
        material.faceCulling = .none
        return material
    }

    /// UV の無い形（作り直していない区と LOD2）の材質。窓の画像は貼れないので、外壁に窓の帯を平均したくらいの暖色の光を足す
    private static func plainMaterial(level: Float) -> PhysicallyBasedMaterial {
        var material = wall(level: level)
        material.emissiveColor = .init(color: UIColor(red: 0.95, green: 0.84, blue: 0.68, alpha: 1))
        material.emissiveIntensity = plainGlow * WideCityBrightness.mix(1, WideCityBrightness.farPlainGlow, level)
        return material
    }

    /// 窓の帯の平均の明るさくらい（点灯 65% × 帯の高さ半分 × 色の明るさ）より少し弱め（近くで無地の箱が光りすぎないように）
    private static let plainGlow: Float = 0.08

    static func models(in entity: Entity) -> [ModelEntity] {
        let own: [ModelEntity] = (entity as? ModelEntity).map { [$0] } ?? []
        return own + entity.children.flatMap { models(in: $0) }
    }
}
