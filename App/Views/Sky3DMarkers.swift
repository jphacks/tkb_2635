import RealityKit
import SwiftUI

/// 3D の目印（屋上の展望デッキ、判定に使った箱の枠）。座標はすべて Sky3DView のシーン単位（1単位 = 100m）。
@MainActor
enum Sky3DMarkers {
    /// 屋上の展望デッキ。観測者の床が建物の屋根より高いとき（屋外の屋上展望台）だけ作る。形はイメージで、寸法の計算には使わない。
    /// - Parameters:
    ///   - center: 建物の中心（地面の高さ）
    ///   - size: 判定に使う建物の箱の幅・高さ・奥行き
    ///   - floor: 観測者が立つ床の高さ
    ///   - observer: 観測者の水平位置（x, z）
    static func observationDeck(center: SIMD3<Float>, size: SIMD3<Float>, floor: Float, observer: SIMD2<Float>) -> Entity? {
        let thickness = floor - size.y
        guard thickness > 0.005 else { return nil }
        // 観測者が必ずデッキの上に乗るよう、建物の7割の大きさを基本に広げる。
        let margin: Float = 0.06
        let width = min(size.x, max(size.x * 0.7, 2 * abs(observer.x - center.x) + margin))
        let depth = min(size.z, max(size.z * 0.7, 2 * abs(observer.y - center.z) + margin))
        let deck = Entity()
        deck.position = [center.x, size.y, center.z]

        let slab = ModelEntity(mesh: .generateBox(width: width, height: thickness, depth: depth, cornerRadius: 0.004),
                               materials: [SimpleMaterial(color: .init(red: 0.10, green: 0.13, blue: 0.18, alpha: 1),
                                                          roughness: 0.6, isMetallic: false)])
        slab.position.y = thickness / 2
        deck.addChild(slab)

        // デッキのふちの足元灯と、ガラスの柵
        let rail: Float = 0.022
        let glass = SimpleMaterial(color: .init(red: 0.55, green: 0.85, blue: 0.95, alpha: 0.28), roughness: 0.1, isMetallic: false)
        let light = UnlitMaterial(color: .init(red: 1.0, green: 0.78, blue: 0.45, alpha: 1))
        for (length, offset, alongX) in [(width, depth / 2, true), (width, -depth / 2, true),
                                         (depth, width / 2, false), (depth, -width / 2, false)] {
            let panel = ModelEntity(mesh: .generateBox(width: alongX ? length : 0.003, height: rail, depth: alongX ? 0.003 : length),
                                    materials: [glass])
            panel.position = alongX ? [0, thickness + rail / 2, offset] : [offset, thickness + rail / 2, 0]
            deck.addChild(panel)
            let strip = ModelEntity(mesh: .generateBox(width: alongX ? length : 0.006, height: 0.004, depth: alongX ? 0.006 : length),
                                    materials: [light])
            strip.position = alongX ? [0, thickness + 0.002, offset] : [offset, thickness + 0.002, 0]
            deck.addChild(strip)
        }
        return deck
    }

    /// 遮蔽判定に使った直方体の 12 本の辺。3D の見た目（実際の形）と判定の根拠の違いを見せる。
    static func judgmentFrame(center: SIMD3<Float>, size: SIMD3<Float>, color: UIColor) -> Entity {
        let frame = Entity()
        frame.position = center
        let t: Float = 0.012
        let material = UnlitMaterial(color: color)
        let h = size / 2
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                let vertical = ModelEntity(mesh: .generateBox(width: t, height: size.y, depth: t), materials: [material])
                vertical.position = [sx * h.x, 0, sz * h.z]
                frame.addChild(vertical)
            }
            for sy: Float in [-1, 1] {
                let alongZ = ModelEntity(mesh: .generateBox(width: t, height: t, depth: size.z), materials: [material])
                alongZ.position = [sx * h.x, sy * h.y, 0]
                frame.addChild(alongZ)
                let alongX = ModelEntity(mesh: .generateBox(width: size.x, height: t, depth: t), materials: [material])
                alongX.position = [0, sy * h.y, sx * h.z]
                frame.addChild(alongX)
            }
        }
        return frame
    }
}
