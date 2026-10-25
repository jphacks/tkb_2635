import RealityKit
import StarCore
import SwiftUI

/// 23 区の広域 3D を見る向き。target は見ている中心（渋谷の原点からの東・北 [m]）、distance は 1 単位 = 100m
struct WideCityCamera: Equatable {
    var target: SIMD2<Float> = [2_000, 4_000]
    var yaw: Float = 0
    var distance: Float = 300

    static let minDistance: Float = 3
    static let maxDistance: Float = 450
    /// 近づくほど横から、離れるほど真上寄りに見る（地図のように動かしやすくする）
    var pitch: Float {
        let t = (distance - Self.minDistance) / (Self.maxDistance - Self.minDistance)
        return 0.5 + 0.6 * min(max(t, 0), 1)
    }
}

/// ホームの 3D。23 区の建物を並べ、1 本指で移動、2 本指でひねって回転、ピンチで近づく。
/// 近づいた区だけ屋根の形つきに切り替える（WideCityLOD）。1 単位 = 100m、x が東、y が上、-z が北。
struct WideCityView: View {
    static let scale: Float = 1 / 100
    private static let groundSize: Float = 800
    private static let background = Color(red: 0.02, green: 0.03, blue: 0.10)
    static let source = "出典: 3D都市モデル（Project PLATEAU）東京都23区 LOD1・LOD2（CC BY 4.0）を加工"

    @State private var lod = WideCityLOD()
    @State private var camera = WideCityCamera()
    @State private var dragStart: WideCityCamera?
    @State private var zoomStart: WideCityCamera?
    @State private var rotateStart: WideCityCamera?
    @State private var isLoaded = false
    /// RealityView を作り終えたか。作り終えた後に画面を描き直させる（区が読み込み済みだと、全画面で真っ暗なままのことがあった）
    @State private var isMade = false

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            BuildingNightRenderer.shared.configureEnvironment(in: root)
            lod.root.scale = .init(repeating: Self.scale)
            root.addChild(lod.root)
            root.addChild(Self.ground())
            Self.addLights(to: root)
            content.add(root)

            let perspective = PerspectiveCamera()
            perspective.name = "camera"
            perspective.camera.near = 0.02
            perspective.camera.far = Self.groundSize * 2
            content.add(perspective)
            place(perspective)
            isMade = true
        } update: { content in
            if let perspective = content.entities.first(where: { $0.name == "camera" }) {
                place(perspective)
            }
            lod.update(east: Double(camera.target.x), north: Double(camera.target.y),
                       cameraDistance: camera.distance / Self.scale)
        }
        .task {
            guard !isLoaded else { return }
            await lod.loadBoxes()
            if let e = lod.extent {
                camera.target = [Float(e.minEast + e.maxEast) / 2, Float(e.minNorth + e.maxNorth) / 2]
                camera.distance = min(Float(max(e.maxEast - e.minEast, e.maxNorth - e.minNorth)) * Self.scale * 0.95,
                                      WideCityCamera.maxDistance)
            }
            isLoaded = true
        }
        .background(Self.background)
        .gesture(DragGesture()
            .onChanged { value in
                let start = dragStart ?? camera
                dragStart = start
                camera.target = Self.panned(start, by: value.translation)
            }
            .onEnded { _ in dragStart = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? camera
                zoomStart = start
                camera.distance = min(WideCityCamera.maxDistance,
                                      max(WideCityCamera.minDistance, start.distance / Float(value.magnification)))
            }
            .onEnded { _ in zoomStart = nil })
        .simultaneousGesture(RotateGesture()
            .onChanged { value in
                let start = rotateStart ?? camera
                rotateStart = start
                camera.yaw = start.yaw - Float(value.rotation.radians)
            }
            .onEnded { _ in rotateStart = nil })
        .overlay {
            if !isLoaded || !isMade {
                ProgressView("街を読み込み中")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(Self.source)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
                .padding(8)
        }
        .accessibilityElement()
        .accessibilityLabel("東京23区の建物の3D")
    }

    private func place(_ perspective: Entity) {
        let target = SIMD3<Float>(camera.target.x * Self.scale, 0, -camera.target.y * Self.scale)
        let pitch = camera.pitch
        let offset = SIMD3<Float>(sin(camera.yaw) * cos(pitch), sin(pitch), cos(camera.yaw) * cos(pitch)) * camera.distance
        perspective.look(at: target, from: target + offset, relativeTo: nil)
    }

    /// 画面を 1 本指でなぞった分だけ、見ている中心を地面の上で動かす（指に地面が付いてくる向き）
    private static func panned(_ start: WideCityCamera, by translation: CGSize) -> SIMD2<Float> {
        // 1pt あたりの移動 [m]。離れているほど大きく動かす
        let metersPerPoint = start.distance / scale * 0.004
        let dx = Float(translation.width) * metersPerPoint, dy = Float(translation.height) * metersPerPoint
        // カメラの右（東・北）と、奥（画面の上へ向かう地面の向き）
        let right = SIMD2<Float>(cos(start.yaw), sin(start.yaw))
        let forward = SIMD2<Float>(-sin(start.yaw), cos(start.yaw))
        return start.target - right * dx + forward * dy
    }

    private static func ground() -> ModelEntity {
        let plane = ModelEntity(mesh: .generatePlane(width: groundSize, depth: groundSize),
                                materials: [UnlitMaterial(color: .init(red: 0.03, green: 0.05, blue: 0.10, alpha: 1))])
        // 海抜 0m 付近の区（江東・江戸川など）の建物の足元より少し下に敷く
        plane.position.y = -5 * scale
        return plane
    }

    private static func addLights(to root: Entity) {
        let sun = DirectionalLight()
        sun.light.intensity = 700
        sun.light.color = .init(red: 0.77, green: 0.85, blue: 1, alpha: 1)
        sun.look(at: .zero, from: [3, 6, 4], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 220
        fill.light.color = .init(red: 0.66, green: 0.76, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [-4, 3, -3], relativeTo: nil)
        root.addChild(fill)
    }
}

#Preview("23 区の広域 3D") {
    WideCityView()
        .frame(height: 500)
        .preferredColorScheme(.dark)
}
