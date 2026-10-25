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
    /// 棒の先から頭の白い縁のいちばん上までの高さ（頭の大きさ 1 あたり）。地点名をこの上に出す
    static let headTopHeight: Float = headCenterHeight + rimRadius

    /// 頭の大きさの下限・上限（1 単位 = 100m）。極端に近い・遠いときに、ピンが点や巨大な球にならないようにする
    private static let minHeadSize: Float = 0.01
    private static let maxHeadSize: Float = 8

    /// 頭の大きさ（1 単位 = 100m）。distance はカメラからそのピンまでの距離。当たり判定でも使う
    static func headSize(distance: Float, selected: Bool) -> Float {
        min(max(distance * headRatio, minHeadSize), maxHeadSize) * (selected ? selectedScale : 1)
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

    /// 毎フレーム、実際のカメラの位置からピンごとの距離を測って、頭と棒の太さを決め直す。
    /// SwiftUI の状態（ピンチ中のカメラの距離）を使うと、描画とずれてピンだけが大きくなることがあった
    static func resize(in root: Entity, cameraPosition: SIMD3<Float>, selectedId: String?) {
        guard let pins = root.findEntity(named: rootName) else { return }
        for pin in pins.children {
            guard let head = pin.findEntity(named: headName) else { continue }
            let distance = simd_length(cameraPosition - head.position(relativeTo: nil))
            let selected = pin.name == pinPrefix + (selectedId ?? "")
            head.scale = .init(repeating: headSize(distance: distance, selected: selected))
            if let bar = pin.findEntity(named: stalkName) {
                let stalk = min(max(distance * stalkRatio, minHeadSize * stalkRatio / headRatio), maxHeadSize * stalkRatio / headRatio)
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

/// 毎フレームのピンの大きさ合わせ（resize）の購読と、選んでいる地点。画面ごとに 1 つ持つ
@MainActor
final class WideCityPinSizer {
    var selectedId: String?
    private var subscription: EventSubscription?

    func start(in content: RealityViewCameraContent, root: Entity, camera: Entity) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            WideCityPins.resize(in: root, cameraPosition: camera.position(relativeTo: nil), selectedId: self?.selectedId)
        }
    }
}

private struct PinStamp: Component {
    let value: String
}
