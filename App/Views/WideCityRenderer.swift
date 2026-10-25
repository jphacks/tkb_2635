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

    /// 詳細画面の夜の建物（BuildingNightRenderer）と同じ材質。外壁と窓の画像は BuildingFacade が作る（同じコード・同じ見た目）。
    /// 箱の UV は BuildingFacade の窓 8 列 × 8 階（28.8m × 31.2m）で 1 枚になるよう、wide_ward_blender.py で付けてある
    private func nightMaterial() async -> PhysicallyBasedMaterial {
        if let material { return material }
        var made = BuildingNightRenderer.shared.facade(Self.facade)
        // 箱の面の向きがそろっていないことがあるので、裏からも描く
        made.faceCulling = .none
        material = made
        return made
    }

    /// 広域で使う外壁の種類（BuildingFacade のオフィス・商業以外の標準の外壁）
    private static let facade = BuildingFacade(style: .neutral, variant: 0)

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
        made.emissiveIntensity *= WideCityBrightness.mix(1, WideCityBrightness.farWindowGlow, level)
        made.baseColor.tint = Self.wallTint(level: level)
        wallMaterials[key] = made
        return made
    }

    /// BuildingNightRenderer の夜の色（0.55, 0.64, 0.75）から、遠いほど暗い暖色に寄せた色。外壁の画像に掛ける
    private static func wallTint(level: Float) -> UIColor {
        let far = WideCityBrightness.farWallTint
        return UIColor(red: CGFloat(WideCityBrightness.mix(nightTint.red, far.red, level)),
                       green: CGFloat(WideCityBrightness.mix(nightTint.green, far.green, level)),
                       blue: CGFloat(WideCityBrightness.mix(nightTint.blue, far.blue, level)), alpha: 1)
    }

    /// BuildingNightRenderer.facade が外壁の画像に掛けている夜の色
    private static let nightTint = (red: Float(0.55), green: Float(0.64), blue: Float(0.75))

    /// UV の無い形（作り直していない区と LOD2）の材質。窓の画像は貼れないので、BuildingNightRenderer の外壁の色
    /// （BuildingFacade の外壁 × 夜の色）と、窓明かりを平均したくらいの弱い暖色の光にする
    private static func plainMaterial(level: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let wall = UIColor(cgColor: facade.wall)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        wall.getRed(&r, green: &g, blue: &b, alpha: nil)
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0
        wallTint(level: level).getRed(&tr, green: &tg, blue: &tb, alpha: nil)
        material.baseColor = .init(tint: UIColor(red: r * tr, green: g * tg, blue: b * tb, alpha: 1))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        material.emissiveColor = .init(color: UIColor(red: 0.68, green: 0.47, blue: 0.23, alpha: 1))
        material.emissiveIntensity = plainGlow * WideCityBrightness.mix(1, WideCityBrightness.farPlainGlow, level)
        material.faceCulling = .none
        return material
    }

    /// 点いている窓（約 24%）× 窓の面積（約半分）× 窓の光る強さ 0.55 くらい
    private static let plainGlow: Float = 0.06

    static func models(in entity: Entity) -> [ModelEntity] {
        let own: [ModelEntity] = (entity as? ModelEntity).map { [$0] } ?? []
        return own + entity.children.flatMap { models(in: $0) }
    }
}
