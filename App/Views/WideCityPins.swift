import RealityKit
import StarCore
import SwiftUI

/// 広域 3D の上の地点ピン。地面から観測者の目の高さまでの細い棒と、その上の地図のピンの形
/// （下向きの円錐と、白い縁つきの丸い頭。頭はいつもカメラの方を向く）。色は段階の色。
/// 遠くから見ても画面上でほぼ同じ大きさに見えるよう、カメラの距離に合わせて大きさを変える（resize）。
@MainActor
enum WideCityPins {
    static let rootName = "pins"
    private static let pinPrefix = "pin-"
    private static let headName = "head"
    private static let stalkName = "stalk"
    /// 頭の大きさ = カメラの距離 × この比（全画面で頭の直径 20pt ほど）
    private static let headRatio: Float = 0.010
    private static let stalkRatio: Float = 0.0012
    /// 選んでいる（見ている中心に一番近い）ピンの大きさの倍率
    private static let selectedScale: Float = 1.4
    /// 頭の形（1 = 頭の丸の半径）。円錐の高さ、頭の丸の中心の高さ、白い縁の半径
    private static let coneHeight: Float = 1.5
    private static let coneRadius: Float = 0.55
    private static let rimRadius: Float = 1.3
    /// 棒の先から頭の丸の中心までの高さ（頭の大きさ 1 あたり）
    static let headCenterHeight: Float = coneHeight + 0.6

    /// 頭の大きさ（1 単位 = 100m）。当たり判定でも使う
    static func headSize(cameraDistance: Float, selected: Bool) -> Float {
        cameraDistance * headRatio * (selected ? selectedScale : 1)
    }

    /// 段階の色が変わったら作り直す
    static func update(in root: Entity, contexts: [SpotContext], predictions: [Prediction], scale: Float) {
        let tiers = Dictionary(predictions.map { ($0.spotId, $0.tier) }, uniquingKeysWith: { a, _ in a })
        let stamp = contexts.map { "\($0.id):\(tiers[$0.id]?.label ?? "")" }.joined(separator: ",")
        let pins = root.findEntity(named: rootName) ?? {
            let pins = Entity()
            pins.name = rootName
            root.addChild(pins)
            return pins
        }()
        guard pins.components[PinStamp.self]?.value != stamp else { return }
        pins.components.set(PinStamp(value: stamp))
        pins.children.removeAll()
        for context in contexts {
            pins.addChild(pin(for: context.spot, color: UIColor((tiers[context.id] ?? .needsCheck).color), scale: scale))
        }
    }

    /// カメラの距離（1 単位 = 100m）に合わせて、頭と棒の太さを変える。選んでいるピンは少し大きくする
    static func resize(in root: Entity, cameraDistance: Float, selectedId: String?) {
        guard let pins = root.findEntity(named: rootName) else { return }
        let stalk = cameraDistance * stalkRatio
        for pin in pins.children {
            let selected = pin.name == pinPrefix + (selectedId ?? "")
            pin.findEntity(named: headName)?.scale = .init(repeating: headSize(cameraDistance: cameraDistance, selected: selected))
            if let bar = pin.findEntity(named: stalkName) {
                bar.scale = [stalk, bar.scale.y, stalk]
            }
        }
    }

    private static func pin(for spot: Spot, color: UIColor, scale: Float) -> Entity {
        let p = WideCity.localPosition(latitude: spot.latitude, longitude: spot.longitude)
        let height = max(Float(spot.observerElevation), 1) * scale
        let pin = Entity()
        pin.name = pinPrefix + spot.id
        pin.position = [Float(p.east) * scale, 0, -Float(p.north) * scale]

        // 太さ 1・高さ height の円柱。太さは resize で変える
        let stalk = ModelEntity(mesh: .generateCylinder(height: 1, radius: 1),
                                materials: [UnlitMaterial(color: color.withAlphaComponent(0.8))])
        stalk.name = stalkName
        stalk.scale = [1, height, 1]
        stalk.position.y = height / 2
        pin.addChild(stalk)

        // 頭（大きさ 1）。棒の先に、下向きの円錐の先を合わせる。大きさは resize で変える
        let head = Entity()
        head.name = headName
        head.position.y = height
        pin.addChild(head)
        let cone = ModelEntity(mesh: .generateCone(height: coneHeight, radius: coneRadius),
                               materials: [UnlitMaterial(color: color)])
        cone.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        cone.position.y = coneHeight / 2
        head.addChild(cone)

        // 丸い頭は、いつもカメラの方を向く板。白い円の上に段階の色の円を重ね、夜景の上でも縁が見えるようにする
        let face = Entity()
        face.position.y = headCenterHeight
        face.components.set(BillboardComponent())
        head.addChild(face)
        face.addChild(disc(radius: rimRadius, color: .white, depth: 0))
        face.addChild(disc(radius: 1, color: color, depth: 0.05))
        return pin
    }

    /// カメラの方（+z）を向いた円。depth だけ手前に出す
    private static func disc(radius: Float, color: UIColor, depth: Float) -> ModelEntity {
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: radius), materials: [UnlitMaterial(color: color)])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        disc.position.z = depth
        return disc
    }
}

private struct PinStamp: Component {
    let value: String
}
