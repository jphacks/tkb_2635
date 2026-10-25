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
    /// PerspectiveCamera の縦の画角（RealityKit の既定）
    static let fieldOfView: Float = 60 * .pi / 180

    /// カメラの位置と見ている点（1 単位 = 100m の空間）
    func eye(scale: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let target = SIMD3<Float>(self.target.x * scale, 0, -self.target.y * scale)
        let offset = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        return (target + offset, target)
    }

    /// 3D の点が画面のどこに見えるか [pt]。カメラの後ろなら nil
    func project(_ point: SIMD3<Float>, scale: Float, in size: CGSize) -> CGPoint? {
        let (eye, target) = eye(scale: scale)
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        let up = simd_cross(right, forward)
        let d = point - eye
        let depth = simd_dot(d, forward)
        guard depth > 0, size.height > 0 else { return nil }
        let focal = Float(size.height) / 2 / tan(Self.fieldOfView / 2)
        return CGPoint(x: size.width / 2 + CGFloat(simd_dot(d, right) / depth * focal),
                       y: size.height / 2 - CGFloat(simd_dot(d, up) / depth * focal))
    }

    /// 近づくほど横から、離れるほど真上寄りに見る（地図のように動かしやすくする）
    var pitch: Float {
        let t = (distance - Self.minDistance) / (Self.maxDistance - Self.minDistance)
        return 0.5 + 0.6 * min(max(t, 0), 1)
    }
}

/// ホームの 3D。23 区の建物と地点のピンを並べ、1 本指で移動、2 本指でひねって回転、ピンチで近づく。
/// 近づいた区だけ屋根の形つきに切り替える（WideCityLOD）。1 単位 = 100m、x が東、y が上、-z が北。
struct WideCityView: View {
    var contexts: [SpotContext] = []
    var predictions: [Prediction] = []
    /// ピン（または画面下の地点名）を押したときに、その地点の ID を渡す
    var onSelect: (String) -> Void = { _ in }

    static let scale: Float = 1 / 100
    private static let rootName = "wideRoot"
    private static let groundSize: Float = 800
    private static let background = Color(red: 0.02, green: 0.03, blue: 0.10)
    static let source = "出典: 3D都市モデル（Project PLATEAU）東京都23区 LOD1・LOD2（CC BY 4.0）を加工"

    @State private var lod = WideCityLOD()
    @State private var camera = WideCityCamera()
    @State private var dragStart: WideCityCamera?
    @State private var zoomStart: WideCityCamera?
    @State private var rotateStart: WideCityCamera?
    @State private var isLoaded = false
    @State private var size = CGSize.zero
    /// RealityView を作り終えたか。作り終えた後に画面を描き直させる（区が読み込み済みだと、全画面で真っ暗なままのことがあった）
    @State private var isMade = false
    @State private var pinSizer = WideCityPinSizer()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            BuildingNightRenderer.shared.configureEnvironment(in: root)
            lod.root.scale = .init(repeating: Self.scale)
            root.addChild(lod.root)
            root.addChild(Self.ground())
            Self.addLights(to: root)
            root.name = Self.rootName
            WideCityPins.update(in: root, contexts: contexts, predictions: predictions, scale: Self.scale)
            content.add(root)

            let perspective = PerspectiveCamera()
            perspective.name = "camera"
            perspective.camera.near = 0.02
            perspective.camera.far = Self.groundSize * 2
            content.add(perspective)
            place(perspective)
            pinSizer.start(in: content, root: root, camera: perspective)
            isMade = true
        } update: { content in
            if let perspective = content.entities.first(where: { $0.name == "camera" }) {
                place(perspective)
            }
            if let root = content.entities.first(where: { $0.name == Self.rootName }) {
                WideCityPins.update(in: root, contexts: contexts, predictions: predictions, scale: Self.scale)
                pinSizer.selectedId = centered?.id
            }
            lod.update(east: Double(camera.target.x), north: Double(camera.target.y),
                       cameraDistance: camera.distance / Self.scale)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(SpatialTapGesture().onEnded { value in
            if let id = pinId(at: value.location) { onSelect(id) }
        })
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
            VStack(alignment: .leading, spacing: 6) {
                if let centered { centeredLabel(centered) }
                Text(Self.source)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("東京23区の建物の3D")
    }

    /// 見ている中心に最も近い地点
    private var centered: SpotContext? {
        let id = WideCity.nearestSpot(contexts.map(\.spot), east: Double(camera.target.x), north: Double(camera.target.y))
        return contexts.first { $0.id == id }
    }

    /// 中心に近い地点の名前。押すと詳細へ
    private func centeredLabel(_ context: SpotContext) -> some View {
        let tier = predictions.first { $0.spotId == context.id }?.tier ?? .needsCheck
        return Button { onSelect(context.id) } label: {
            HStack(spacing: 6) {
                Circle().fill(tier.color).frame(width: 8, height: 8)
                Text(context.spot.name).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(.ultraThinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("中心の地点 \(context.spot.name)、\(tier.label)。詳細を開く")
    }

    private func place(_ perspective: Entity) {
        let (eye, target) = camera.eye(scale: Self.scale)
        perspective.look(at: target, from: eye, relativeTo: nil)
    }

    /// 押した所に最も近いピン。棒の先から頭までの線から、指で押しやすい 44pt の範囲内
    private func pinId(at location: CGPoint) -> String? {
        let selectedId = centered?.id
        let hits = contexts.compactMap { context -> (id: String, distance: CGFloat)? in
            let spot = context.spot
            let p = WideCity.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            let top = SIMD3<Float>(Float(p.east), Float(spot.observerElevation), -Float(p.north)) * Self.scale
            // 描画（WideCityPinSizer）と同じく、カメラからそのピンまでの距離で頭の大きさを決める
            let eye = camera.eye(scale: Self.scale).eye
            let size = WideCityPins.headSize(distance: simd_length(eye - top), selected: context.id == selectedId)
            let head = top + [0, size * WideCityPins.headCenterHeight, 0]
            guard let a = camera.project(top, scale: Self.scale, in: self.size),
                  let b = camera.project(head, scale: Self.scale, in: self.size) else { return nil }
            return (context.id, Self.distance(from: location, toSegment: a, b))
        }
        return hits.filter { $0.distance <= Self.hitRadius }.min { $0.distance < $1.distance }?.id
    }

    /// 点から線分までの画面上の距離 [pt]
    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1)
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static let hitRadius: CGFloat = 22

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
