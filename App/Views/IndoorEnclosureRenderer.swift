import RealityKit
import StarCore
import UIKit

/// 屋内展望室の窓・壁・屋根（4-06）。観測者のまわりに円筒状に置き、目線で「窓の外だけが見える」ことを見せる。
/// 窓の範囲は `viewingDirectionMask`、窓の上端は `maxVisibleAltitude`（判定と同じ値）。寸法は演出で、建物の形とは別。
@MainActor
enum IndoorEnclosureRenderer {
    static let name = "indoorEnclosure"

    /// 円筒の半径 [m]
    static let radiusMeters: Float = 3
    /// 窓の上端の高度が未設定のときの、ガラスの上端の高さ（床から）[m]。屋根は置かず、判定と食い違わないようにする
    static let defaultGlassTopMeters: Float = 2.6
    /// 壁を分ける方位の刻み [度]
    static let segmentDegrees = 5
    /// 窓枠（縦の桟）を入れる方位の刻み [度]
    static let mullionDegrees = 15
    /// 壁・屋根の厚さ [m]
    static let thicknessMeters: Float = 0.04
    /// ガラスの不透明度
    static let glassOpacity: Float = 0.08
    /// カメラが観測者からこの距離 [m] より遠いときは隠す（全体表示で観測者の目印をふさがない）
    static let visibleWithinMeters: Float = 10

    /// buildScene から 1 回呼ぶ。屋外の地点では何も置かない
    static func add(to root: Entity, spot: Spot, scale: Float) {
        guard spot.indoorOutdoor == .indoor else { return }
        IndoorEnclosureSystem.registerOnce()
        let enclosure = Entity()
        enclosure.name = name
        enclosure.components.set(IndoorEnclosureVisibility(maxDistance: visibleWithinMeters * scale))
        root.addChild(enclosure)
        // 隠すのは中身だけにして、入れ物はいつも System から見つけられるようにする
        let shell = Entity()
        enclosure.addChild(shell)

        let radius = radiusMeters * scale
        let thickness = thicknessMeters * scale
        let floorY = -Float(spot.eyeHeight) * scale
        // 窓の上端の高度から、半径 r の壁の上端の高さを決める（目の高さが 0）
        let topY: Float = spot.maxVisibleAltitude.map { Float(tan($0 * .pi / 180)) * radius }
            ?? floorY + defaultGlassTopMeters * scale
        let wallHeight = topY - floorY
        guard wallHeight > 0 else { return }

        // 外の星や街が透けて見えるよう、ごく薄い青にする（照明の照り返しで白っぽくならないよう Unlit）
        var glass = UnlitMaterial(color: .init(red: 0.55, green: 0.80, blue: 1.0, alpha: 1))
        glass.blending = .transparent(opacity: .init(floatLiteral: glassOpacity))
        // 奥の星空の球を隠さないよう、ガラスは奥行きを書かない
        glass.writesDepth = false
        let wall = UnlitMaterial(color: .init(red: 0.05, green: 0.06, blue: 0.09, alpha: 1))
        let frame = UnlitMaterial(color: .init(red: 0.16, green: 0.18, blue: 0.22, alpha: 1))

        // 1 区画の幅（弦の長さ）。隙間が出ないよう少し広げる
        let step = Double(segmentDegrees)
        let chord = 2 * radius * Float(sin(step / 2 * .pi / 180)) * 1.04
        for start in stride(from: 0, to: 360, by: segmentDegrees) {
            let azimuth = Double(start) + step / 2
            let isWindow = spot.viewingDirectionMask.map { ranges in ranges.contains { $0.contains(azimuth) } } ?? true
            let panel = ModelEntity(mesh: .generateBox(width: chord, height: wallHeight, depth: thickness),
                                    materials: [isWindow ? glass : wall])
            place(panel, azimuth: azimuth, radius: radius, y: floorY + wallHeight / 2)
            shell.addChild(panel)
            if isWindow, start % mullionDegrees == 0 {
                let mullion = ModelEntity(mesh: .generateBox(width: thickness * 1.5, height: wallHeight, depth: thickness * 1.5),
                                          materials: [frame])
                place(mullion, azimuth: Double(start), radius: radius, y: floorY + wallHeight / 2)
                shell.addChild(mullion)
            }
        }

        // 窓の上端の高度が分かっているときだけ屋根を置く（それより上の空は判定でも見えない扱い）
        if spot.maxVisibleAltitude != nil {
            let roof = ModelEntity(mesh: .generateCylinder(height: thickness, radius: radius * 1.05), materials: [wall])
            roof.position = [0, topY + thickness / 2, 0]
            shell.addChild(roof)
            // 窓の上の横の桟
            let beam = ModelEntity(mesh: .generateCylinder(height: thickness * 2, radius: radius * 1.02), materials: [frame])
            beam.position = [0, topY - thickness, 0]
            shell.addChild(beam)
        }
    }

    /// 板の表を観測者（原点）に向けて、方位 azimuth・半径 radius の位置に置く。x が東、-z が北
    private static func place(_ entity: Entity, azimuth: Double, radius: Float, y: Float) {
        let a = Float(azimuth * .pi / 180)
        entity.position = [radius * sin(a), y, -radius * cos(a)]
        entity.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
    }
}

/// カメラがこの距離より遠いときは隠す
struct IndoorEnclosureVisibility: Component {
    let maxDistance: Float
}

/// 全体表示では屋内の囲いを隠し、目線に入ったときだけ出す
struct IndoorEnclosureSystem: System {
    private static let enclosures = EntityQuery(where: .has(IndoorEnclosureVisibility.self))
    private static let cameras = EntityQuery(where: .has(PerspectiveCameraComponent.self))
    @MainActor private static var registered = false

    init(scene: RealityKit.Scene) {}

    @MainActor static func registerOnce() {
        guard !registered else { return }
        registered = true
        IndoorEnclosureVisibility.registerComponent()
        registerSystem()
    }

    func update(context: SceneUpdateContext) {
        guard let camera = context.scene.performQuery(Self.cameras).first(where: { _ in true }) else { return }
        for entity in context.scene.performQuery(Self.enclosures) {
            guard let visibility = entity.components[IndoorEnclosureVisibility.self] else { continue }
            let distance = simd_length(camera.position(relativeTo: nil) - entity.position(relativeTo: nil))
            let show = distance < visibility.maxDistance
            for shell in entity.children where shell.isEnabled != show { shell.isEnabled = show }
        }
    }
}
