import RealityKit
import StarCore
import SwiftUI

/// 観測者視点への入口。都市モデルの形と、既存データの観測者の建物を使う。
@MainActor
enum ObserverEntryRenderer {
    static let name = "observerEntry"
    private static let highlightMinimum: Float = 0.06
    private static let highlightMaximum: Float = 0.28
    private static let pulseDuration = 0.5
    private static let highlightExpansion: Float = 0.003
    private static let groundRadius: Float = 0.11
    /// 壁ごしに見せる観測者の目印の大きさ（全体表示の青い点より少しだけ大きくして、上に重ねる）
    private static let seeThroughRadius: Float = 0.065
    /// Sky3DView+Scene の全体表示だけの目印のまとまり
    private static let overviewGuidesName = "overviewGuides"

    static func add(to root: Entity, city: Entity?, context: SpotContext, scale: Float, animated: Bool) {
        guard context.scene?.observerViewEnabled == true else { return }
        let entry = Entity()
        entry.name = name
        entry.components.set(InputTargetComponent())

        if let scene = context.scene,
           let host = scene.buildings.first(where: { $0.id == context.spot.hostBuildingId }) {
            let me = scene.localPosition(latitude: context.spot.latitude, longitude: context.spot.longitude)
            let size = SIMD3<Float>(Float(host.width), Float(host.height), Float(host.depth)) * scale
            let eye = Float(context.spot.observerElevation - scene.groundElevation) * scale
            entry.position = [Float(host.x - me.east) * scale, size.y / 2 - eye, -Float(host.y - me.north) * scale]
            entry.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
            if eye < size.y { addSeeThroughMarker(to: root) }

            // 実形状の外壁だけを淡く重ね、街全体や窓を塗りつぶさない。
            if let city {
                let tag = CityModelRenderer.hostTag(for: host.id)
                let models = matchingModels(in: city, tag: tag)
                if !models.isEmpty {
                    root.addChild(entry)
                    for model in models {
                        guard let mesh = model.model?.mesh else { continue }
                        let glow = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
                        model.parent?.addChild(glow)
                        glow.transform = model.transform
                        // 面の重なりによるちらつきを防ぎ、中心を保ってわずかに外へ広げる。
                        glow.scale *= 1 + highlightExpansion
                        glow.position -= model.orientation.act(mesh.bounds.center * model.scale * highlightExpansion)
                        glow.setParent(entry, preservingWorldTransform: true)
                    }
                    pulse(entry, animated: animated)
                    return
                }
            }

            let glow = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: .white)])
            entry.addChild(glow)
            pulse(entry, animated: animated)
        } else {
            // 地上の地点は、従来の青い観測者マークの位置を入口にする。
            let marker = ModelEntity(mesh: .generateSphere(radius: groundRadius),
                                     materials: [UnlitMaterial(color: .systemCyan)])
            marker.components.set(OpacityComponent(opacity: 0.7))
            entry.addChild(marker)
            entry.components.set(CollisionComponent(shapes: [.generateSphere(radius: groundRadius * 1.5)]))
        }
        root.addChild(entry)
    }

    /// 観測者が建物の中（屋上より下）にいると、全体表示では不透明な壁に隠れて青い点が見えない。
    /// 奥行きを無視して描く青い点を観測者の位置に重ね、壁ごしでも位置が分かるようにする（全体表示の目印と一緒に出し入れする）。
    private static func addSeeThroughMarker(to root: Entity) {
        var material = UnlitMaterial(color: .systemBlue)
        // 半透明の扱いにして不透明な建物より後に描き、奥行きの比較をしないことで、壁の手前に出す。
        material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        material.readsDepth = false
        let marker = ModelEntity(mesh: .generateSphere(radius: seeThroughRadius), materials: [material])
        (root.findEntity(named: overviewGuidesName) ?? root).addChild(marker)
    }

    private static func pulse(_ entry: Entity, animated: Bool) {
        entry.components.set(OpacityComponent(opacity: animated ? highlightMinimum : highlightMaximum))
        guard animated else { return }
        let animation = FromToByAnimation<Float>(from: highlightMinimum, to: highlightMaximum,
                                                 duration: pulseDuration, timing: .easeInOut,
                                                 bindTarget: .opacity, repeatMode: .autoReverse)
        if let resource = try? AnimationResource.generate(with: animation) {
            entry.playAnimation(resource)
        }
    }

    private static func matchingModels(in entity: Entity, tag: String) -> [ModelEntity] {
        let own = (entity as? ModelEntity).flatMap { $0.name.hasSuffix(tag) ? $0 : nil }
        return (own.map { [$0] } ?? []) + entity.children.flatMap { matchingModels(in: $0, tag: tag) }
    }
}
