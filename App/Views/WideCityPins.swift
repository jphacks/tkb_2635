import RealityKit
import StarCore
import SwiftUI

/// 広域 3D の上の地点ピン。地面から観測者の目の高さまでの棒と、その上の球（段階の色）。
/// 遠くから見ても画面上でほぼ同じ大きさに見えるよう、カメラの距離に合わせて大きさを変える（resize）。
@MainActor
enum WideCityPins {
    static let rootName = "pins"
    private static let pinPrefix = "pin-"
    private static let headName = "head"
    private static let stalkName = "stalk"
    /// 球の半径 = カメラの距離 × この比（全画面で直径 20pt ほど）
    private static let headRatio: Float = 0.012
    private static let stalkRatio: Float = 0.0015

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

    /// カメラの距離（1 単位 = 100m）に合わせて、球と棒の太さを変える
    static func resize(in root: Entity, cameraDistance: Float) {
        guard let pins = root.findEntity(named: rootName) else { return }
        let head = cameraDistance * headRatio
        let stalk = cameraDistance * stalkRatio
        for pin in pins.children {
            pin.findEntity(named: headName)?.scale = .init(repeating: head)
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

        // 半径 1 の球。大きさは resize で変える
        let head = ModelEntity(mesh: .generateSphere(radius: 1), materials: [UnlitMaterial(color: color)])
        head.name = headName
        head.position.y = height
        pin.addChild(head)
        return pin
    }
}

private struct PinStamp: Component {
    let value: String
}
