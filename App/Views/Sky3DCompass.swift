import RealityKit
import StarCore
import UIKit

/// 3D の東西南北の文字（4-05）。いつもカメラの方を向き、建物の向こうでも読めるよう手前に描く。
/// 全体表示では地平線の輪（北の赤い点）のすぐ上、目線では遠くの地平線の上に置き、
/// 画面の上での大きさがカメラの距離で変わらないようにする。位置と大きさは `Sky3DCompassSystem` が毎フレーム直す。
@MainActor
enum Sky3DCompass {
    static let name = "compassLabels"

    /// 方位（北 0°、時計回り）と文字
    private static let points: [(azimuth: Double, text: String)] = [(0, "北"), (90, "東"), (180, "南"), (270, "西")]
    /// 文字の札の高さ（カメラからの距離に対する比。約 2.6°）
    static let angularHeight: Float = 0.045
    /// 全体表示で、地平線の輪（北の赤い点）から札の下端までの隙間 [シーン単位]
    static let overviewGap: Float = 0.12
    /// 目線表示で札を置く距離 [シーン単位]（街より遠く、星空の球より手前）
    static let observerRadius: Float = 100
    /// 目線表示の札の高度の下限・上限 [度]。見上げても画面の下のほうに札が残るよう、視線に合わせて上げる
    static let observerMinAltitude = 3.0
    static let observerMaxAltitude = 60.0
    /// 目線表示で、視線の高度から画面の下端寄りへ下げる量（画角に対する比）
    static let observerViewDrop = 0.38
    /// カメラが観測者からこの距離 [シーン単位] より近いときは目線表示として扱う
    static let observerThreshold: Float = 1

    /// buildScene から 1 回呼ぶ。札は全体表示・目線の両方で出す
    static func add(to root: Entity) {
        Sky3DCompassSystem.registerOnce()
        let container = Entity()
        container.name = name
        root.addChild(container)
        let group = ModelSortGroup(depthPass: nil)
        for point in points {
            guard let plate = texture(point.text, isNorth: point.azimuth == 0) else { continue }
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(plate))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            // 建物に隠れても方角が読めるよう、奥行きを見ずに描く
            material.readsDepth = false
            material.writesDepth = false
            let entity = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [material])
            entity.name = "compass-\(point.text)"
            entity.components.set(BillboardComponent())
            entity.components.set(ModelSortGroupComponent(group: group, order: 10))
            entity.components.set(Sky3DCompassLabel(azimuth: point.azimuth))
            // 最初の 1 フレームは全体表示の位置に置いておく
            entity.position = SkyRenderer.direction(altitude: 0, azimuth: point.azimuth) * Sky3DView.skyRadius
            entity.scale = .init(repeating: 0.4)
            container.addChild(entity)
        }
    }

    /// 丸い札に漢字 1 文字。北だけ赤くして、既存の北の赤い点と結びつける
    private static func texture(_ text: String, isNorth: Bool) -> TextureResource? {
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 4, y: 4, width: side - 8, height: side - 8)
            let circle = UIBezierPath(ovalIn: rect)
            (isNorth ? UIColor(red: 0.85, green: 0.16, blue: 0.16, alpha: 0.92)
                     : UIColor(red: 0.06, green: 0.09, blue: 0.18, alpha: 0.85)).setFill()
            circle.fill()
            UIColor(white: 1, alpha: 0.85).setStroke()
            circle.lineWidth = 3
            circle.stroke()
            let font = UIFont.systemFont(ofSize: 54, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2),
                                    withAttributes: attributes)
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }
}

/// 方位文字の札が持つ方位
struct Sky3DCompassLabel: Component {
    let azimuth: Double
}

/// カメラの位置に合わせて、方位文字の札の位置と大きさを毎フレーム直す
struct Sky3DCompassSystem: System {
    private static let labels = EntityQuery(where: .has(Sky3DCompassLabel.self))
    private static let cameras = EntityQuery(where: .has(PerspectiveCameraComponent.self))
    @MainActor private static var registered = false

    init(scene: RealityKit.Scene) {}

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        Sky3DCompassLabel.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        guard let camera = context.scene.performQuery(Self.cameras).first(where: { _ in true }) else { return }
        let cameraPosition = camera.position(relativeTo: nil)
        let isObserver = simd_length(cameraPosition) < Sky3DCompass.observerThreshold
        let forward = camera.orientation(relativeTo: nil).act(SIMD3<Float>(0, 0, -1))
        let fieldOfView = Double(camera.components[PerspectiveCameraComponent.self]?.fieldOfViewInDegrees
                                 ?? Float(ObserverViewpoint.defaultFieldOfView))
        let viewAltitude = Double(asin(max(-1, min(1, forward.y)))) * 180 / .pi
        let observerAltitude = min(Sky3DCompass.observerMaxAltitude,
                                   max(Sky3DCompass.observerMinAltitude, viewAltitude - fieldOfView * Sky3DCompass.observerViewDrop))

        for entity in context.scene.performQuery(Self.labels) {
            guard let label = entity.components[Sky3DCompassLabel.self] else { continue }
            let base: SIMD3<Float>
            if isObserver {
                base = SkyRenderer.direction(altitude: observerAltitude, azimuth: label.azimuth) * Sky3DCompass.observerRadius
            } else {
                base = SkyRenderer.direction(altitude: 0, azimuth: label.azimuth) * (Sky3DView.skyRadius + 0.3)
            }
            let height = max(1e-4, simd_length(base - cameraPosition) * Sky3DCompass.angularHeight)
            // 全体表示では、北の赤い点に重ならないよう札の下端を輪の少し上にそろえる
            let lift: Float = isObserver ? 0 : Sky3DCompass.overviewGap + height / 2
            entity.setPosition(base + [0, lift, 0], relativeTo: nil)
            entity.setScale(.init(repeating: height), relativeTo: nil)
        }
    }
}
