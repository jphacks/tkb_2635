import RealityKit
import SwiftUI

/// カメラが遠いほど街を明るく見せる。近景は詳細画面と同じ見た目のまま、23 区全体を見るときは窓の発光・地面を強め、
/// 窓の帯がつぶれて見えなくなるぶん、外壁の色を窓の平均の色（暗い暖色）に寄せて、建物の塊が光って見えるようにする。
/// 段階に分けて、段階が変わったときだけ材質の係数を書き換える（毎フレームは作り直さない）。
@MainActor
enum WideCityBrightness {
    /// この距離（1 単位 = 100m）より近ければ詳細画面と同じ（level 0）。全体が入る距離で level 1
    static let nearDistance: Float = 10
    static let farDistance: Float = 300
    private static let steps = 12
    /// 全体を見るときの、窓の発光・地面の明るさの倍率
    static let farWindowGlow: Float = 2.5
    static let farPlainGlow: Float = 2.5
    static let farGroundGlow: Float = 2
    static let groundName = "wideGround"

    /// カメラの距離から段階（0 〜 steps）
    static func step(cameraDistance: Float) -> Int {
        let t = (cameraDistance - nearDistance) / (farDistance - nearDistance)
        return Int((min(max(t, 0), 1) * Float(steps)).rounded())
    }

    static func level(step: Int) -> Float { Float(step) / Float(steps) }

    /// 建物と地面の材質の係数を、その段階のものに書き換える
    static func apply(step: Int, buildings: Entity, ground: Entity?) {
        let t = level(step: step)
        for model in WideCityRenderer.models(in: buildings) {
            guard let kind = model.components[WideWallKind.self], var component = model.model,
                  let material = WideCityRenderer.shared.wallMaterial(hasUV: kind.hasUV, level: t) else { continue }
            component.materials = Array(repeating: material, count: max(component.materials.count, 1))
            model.model = component
        }
        if let ground = ground as? ModelEntity, var component = ground.model,
           var material = component.materials.first as? PhysicallyBasedMaterial {
            material.emissiveIntensity = 1 + (farGroundGlow - 1) * t
            component.materials = [material]
            ground.model = component
        }
    }

    /// 線形に近づける（a → b）
    static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
}

/// 建物の部品に付ける目印。壁の UV があれば窓の画像つきの材質、無ければ外壁だけの材質を使う
struct WideWallKind: Component {
    let hasUV: Bool
}

/// 画面ごとに、いまの明るさの段階を覚えておく（nil なら次に必ず書き換える）
@MainActor
final class WideCityBrightnessState {
    var step: Int?
}
