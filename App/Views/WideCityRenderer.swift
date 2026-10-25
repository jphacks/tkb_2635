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
    private lazy var material = Self.nightMaterial()

    /// 手元に残す屋根の形つきの数（同時に出す区の数 + 1 にして、行き来しても読み直さないようにする）
    private static let detailCacheCount = WideCityLOD.maxDetailWards + 1

    /// アプリに入っている区のコード（ファイル名から。区を足してもコードを直さなくてよい）
    static let wardCodes: [String] = (Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
        .compactMap { WideCity.wardCode(fromBoxFile: $0.deletingPathExtension().lastPathComponent) }
        .sorted()

    /// 区の箱の複製。並列に読み、読めた区から onLoad で渡す
    func loadBoxes(onLoad: @escaping @MainActor (String, Entity) -> Void) async {
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
        // 23 区ぶん描くので、材質は全部同じ軽いもの 1 つにする
        for model in Self.models(in: loaded) {
            guard var component = model.model else { continue }
            component.materials = Array(repeating: material, count: max(component.materials.count, 1))
            model.model = component
        }
        return loaded
    }

    /// BuildingNightRenderer の夜の建物に寄せた色。テクスチャを使わず、照明の向きに関係なく形が読めるよう少し光らせる
    private static func nightMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.40, green: 0.47, blue: 0.58, alpha: 1))
        material.roughness = .init(floatLiteral: 0.85)
        material.metallic = .init(floatLiteral: 0)
        material.emissiveColor = .init(color: .init(red: 0.30, green: 0.36, blue: 0.50, alpha: 1))
        material.emissiveIntensity = 0.12
        material.faceCulling = .none
        return material
    }

    static func models(in entity: Entity) -> [ModelEntity] {
        let own: [ModelEntity] = (entity as? ModelEntity).map { [$0] } ?? []
        return own + entity.children.flatMap { models(in: $0) }
    }
}
