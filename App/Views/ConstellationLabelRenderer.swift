import RealityKit
import StarCore
import UIKit

/// 3D の空の星座名（ガラスの名札）。いつもカメラの方を向き、見ている向きに近い星座だけを出す。
/// どれを出すかは StarCore の `ConstellationLabelPicker`（AR と同じ決まり）で決める。
@MainActor
enum ConstellationLabelRenderer {
    private static let prefix = "constellationLabel-"
    private static let containerName = "constellationLabels"

    /// 名札の画像は一度だけ作る（91 星座ぶん）
    private static let plates: [String: (texture: TextureResource, size: CGSize)] = {
        var result: [String: (TextureResource, CGSize)] = [:]
        for line in ConstellationData.lines {
            if let plate = ConstellationTextures.label(line.name) { result[line.id] = plate }
        }
        return result
    }()

    /// 星座ごとの名札を作って入れる。最初はすべて隠し、`update` で選んだものだけを出す
    static func addLabels(to container: Entity, group: ModelSortGroup, order: Int32) {
        let labels = Entity()
        labels.name = containerName
        container.addChild(labels)
        let style = ConstellationStyle.self
        for line in ConstellationData.lines {
            guard let center = line.equatorialCenter, let plate = plates[line.id] else { continue }
            let height = style.labelHeight * Float(plate.size.height) / Float(max(1, plate.size.height - 8))
            let width = height * Float(plate.size.width / plate.size.height)
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(plate.texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            let entity = ModelEntity(mesh: .generatePlane(width: width, height: height), materials: [material])
            entity.name = prefix + line.id
            entity.position = SIMD3(Float(center.x), Float(center.y), Float(center.z)) * style.labelRadius
            entity.components.set(ModelSortGroupComponent(group: group, order: order))
            entity.components.set(LabelBrightness(magnitude: line.brightestCatalogMagnitude))
            entity.isEnabled = false
            labels.addChild(entity)
        }
    }

    /// カメラの向きに合わせて、出す名札を選び直す（見回すたびに呼ぶ。計算は軽い）
    static func update(in scene: Entity, camera: Entity?) {
        guard let camera = camera as? PerspectiveCamera,
              let labels = scene.findEntity(named: containerName) else { return }
        let forward = camera.orientation(relativeTo: nil).act(SIMD3<Float>(0, 0, -1))
        let cameraPosition = camera.position(relativeTo: nil)
        let cameraUp = camera.orientation(relativeTo: nil).act(SIMD3<Float>(0, 1, 0))
        let candidates = labels.children.compactMap { entity -> ConstellationLabelCandidate? in
            // 観測者（原点）から見た向き。x が東、y が上、-z が北
            let p = entity.position(relativeTo: nil)
            guard simd_length(p) > 0 else { return nil }
            return ConstellationLabelCandidate(id: entity.name, direction: local(p),
                                               brightestMagnitude: entity.components[LabelBrightness.self]?.magnitude)
        }
        let view = ConstellationLabelPicker.liftedView(
            local(forward), maximumAngle: Double(camera.camera.fieldOfViewInDegrees) * ConstellationStyle.labelFieldFraction)
        let picked = Set(ConstellationLabelPicker.pick(candidates, viewDirection: view.direction, maximumAngle: view.maximumAngle))
        for entity in labels.children {
            let show = picked.contains(entity.name)
            if entity.isEnabled != show { entity.isEnabled = show }
            if show { faceCamera(entity, cameraPosition: cameraPosition, cameraUp: cameraUp) }
        }
    }

    /// 名札の表をカメラに向け、文字の上を画面の上にそろえる（見上げても傾かない）。
    /// 星空の球は回っているので、球の中の座標に直してから向きを決める
    private static func faceCamera(_ entity: Entity, cameraPosition: SIMD3<Float>, cameraUp: SIMD3<Float>) {
        guard let parent = entity.parent else { return }
        let camera = parent.convert(position: cameraPosition, from: nil)
        let up = parent.convert(direction: cameraUp, from: nil)
        let toCamera = camera - entity.position
        guard simd_length(toCamera) > 1e-6, simd_length(up) > 1e-6 else { return }
        // look(at:) は -z を相手に向けるので、カメラと反対の点を見せて +z（絵の表）をカメラに向ける
        entity.look(at: entity.position - simd_normalize(toCamera), from: entity.position,
                    upVector: simd_normalize(up), relativeTo: parent)
    }

    private static func local(_ v: SIMD3<Float>) -> LocalVector {
        let n = simd_normalize(v)
        return LocalVector(east: Double(n.x), north: Double(-n.z), up: Double(n.y))
    }
}

/// 名札の星座に含まれる、最も明るい星の等級（間引きの優先に使う）
private struct LabelBrightness: Component {
    let magnitude: Double?
}
