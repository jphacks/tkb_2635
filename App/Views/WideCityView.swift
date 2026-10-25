import RealityKit
import StarCore
import SwiftUI

/// 23 区の広域 3D を見る向き。target は見ている中心（渋谷の原点からの東・北 [m]）、distance は 1 単位 = 100m
struct WideCityCamera: Equatable {
    var target: SIMD2<Float> = [2_000, 4_000]
    var yaw: Float = 0
    var distance: Float = 300
    /// 街の広さに合わせて最初の向きを決めたか。画面を作り直しても、決めた後の向きを保つ
    var hasFitted = false
    /// 開いた直後の動き（WideCityIntro）を見せたか。詳細から戻ったときは繰り返さない
    var hasPlayedIntro = false

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

/// ホームの 3D を開いた直後の動き（d）。23 区全体からゆっくり回りながら、少しずつ近づく。
/// 指で触ったら止め、「動きを減らす」がオンなら動かさない
enum WideCityIntro {
    /// 動きの長さ
    static let duration: Duration = .seconds(4)
    /// 回る角度（ラジアン。約 40°）
    static let turn: Float = 0.7
    /// 終わりの距離（始めの距離に対する比）
    static let finalZoom: Float = 0.55
    /// 描き直す間隔（約 60 コマ / 秒）
    static let frameInterval: Duration = .milliseconds(16)

    /// 進み具合 progress（0〜1）のときのカメラ。始めと終わりをゆっくりにする
    static func camera(from start: WideCityCamera, progress: Float) -> WideCityCamera {
        let t = min(max(progress, 0), 1)
        let eased = t * t * (3 - 2 * t)
        var camera = start
        camera.yaw = start.yaw + turn * eased
        camera.distance = max(WideCityCamera.minDistance, start.distance * (1 + (finalZoom - 1) * eased))
        return camera
    }

    /// start から動かし、終わるか止められる（Task を取り消す）まで camera を書き換える
    @MainActor
    static func play(from start: WideCityCamera, camera: Binding<WideCityCamera>) async {
        let clock = ContinuousClock()
        let begin = clock.now
        while !Task.isCancelled {
            let progress = Float((clock.now - begin) / duration)
            camera.wrappedValue = Self.camera(from: start, progress: progress)
            if progress >= 1 { return }
            try? await Task.sleep(for: frameInterval)
        }
    }
}

/// ホームの 3D。23 区の建物と地点のピンを並べ、1 本指で移動、2 本指でひねって回転、ピンチで近づく。
/// 近づいた区だけ屋根の形つきに切り替える（WideCityLOD）。1 単位 = 100m、x が東、y が上、-z が北。
struct WideCityView: View {
    var contexts: [SpotContext] = []
    var predictions: [Prediction] = []
    /// ピン（または画面下の地点名）を押したときに、その地点の ID を渡す
    var onSelect: (String) -> Void = { _ in }
    /// 見る向き。呼び出し側が持つので、3D を外して作り直しても同じ向きで出る
    @Binding var camera: WideCityCamera
    /// 画面の下に重なるもの（シートなど）の高さ。地点名をその上に出す
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 0
    /// 街を読み込み、最初の絵を出せるようになったとき
    var onReady: () -> Void = {}

    static let scale: Float = 1 / 100
    private static let rootName = "wideRoot"
    private static let groundSize: Float = 800
    /// 航空写真の地面の高さ [m]（標高）
    private static let photoDepth: Float = -3
    private static let background = Color(red: 0.02, green: 0.03, blue: 0.10)

    @State private var lod = WideCityLOD()
    @State private var dragStart: WideCityCamera?
    @State private var zoomStart: WideCityCamera?
    @State private var rotateStart: WideCityCamera?
    @State private var isLoaded = false
    @State private var size = CGSize.zero
    /// RealityView を作り終えたか。作り終えた後に画面を描き直させる（区が読み込み済みだと、全画面で真っ暗なままのことがあった）
    @State private var isMade = false
    @State private var pinSizer = WideCityPinSizer()
    @State private var brightness = WideCityBrightnessState()
    /// 開いた直後の動き。指で触ったら止める
    @State private var intro: Task<Void, Never>?
    private let motion = MotionSetting()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            BuildingNightRenderer.shared.configureEnvironment(in: root)
            lod.root.scale = .init(repeating: Self.scale)
            root.addChild(lod.root)
            root.addChild(Self.ground())
            if let photo = await WideGroundRenderer.ground() {
                // 航空写真は、海抜 0m 付近の建物の足元より少し下に敷く（暗い板はさらに下）
                photo.position.y = Self.photoDepth
                photo.scale = .init(repeating: Self.scale)
                photo.position *= Self.scale
                root.addChild(photo)
            }
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
            // 遠いほど街を明るく。段階が変わったときだけ材質を書き換える
            let step = WideCityBrightness.step(cameraDistance: camera.distance)
            if step != brightness.step, let root = content.entities.first(where: { $0.name == Self.rootName }) {
                brightness.step = step
                WideCityBrightness.apply(step: step, buildings: lod.root,
                                         ground: root.findEntity(named: WideCityBrightness.groundName))
            }
            lod.update(east: Double(camera.target.x), north: Double(camera.target.y),
                       cameraDistance: camera.distance / Self.scale)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(SpatialTapGesture().onEnded { value in
            stopIntro()
            if let id = pinId(at: value.location) { onSelect(id) }
        })
        .task {
            guard !isLoaded else { return }
            await lod.loadBoxes()
            // 読み込んだ区は近景の材質なので、次の描き直しで今の距離の明るさにする
            brightness.step = nil
            if !camera.hasFitted, let e = lod.extent {
                camera.hasFitted = true
                camera.target = [Float(e.minEast + e.maxEast) / 2, Float(e.minNorth + e.maxNorth) / 2]
                camera.distance = min(Float(max(e.maxEast - e.minEast, e.maxNorth - e.minNorth)) * Self.scale * 0.95,
                                      WideCityCamera.maxDistance)
            }
            isLoaded = true
        }
        .background(Self.background)
        .gesture(DragGesture()
            .onChanged { value in
                stopIntro()
                let start = dragStart ?? camera
                dragStart = start
                camera.target = Self.panned(start, by: value.translation)
            }
            .onEnded { _ in dragStart = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                stopIntro()
                let start = zoomStart ?? camera
                zoomStart = start
                camera.distance = min(WideCityCamera.maxDistance,
                                      max(WideCityCamera.minDistance, start.distance / Float(value.magnification)))
            }
            .onEnded { _ in zoomStart = nil })
        .simultaneousGesture(RotateGesture()
            .onChanged { value in
                stopIntro()
                let start = rotateStart ?? camera
                rotateStart = start
                camera.yaw = start.yaw - Float(value.rotation.radians)
            }
            .onEnded { _ in rotateStart = nil })
        .onChange(of: isLoaded && isMade) { _, ready in
            guard ready else { return }
            onReady()
            if !camera.hasPlayedIntro {
                camera.hasPlayedIntro = true
                if !motion.isReduced {
                    let start = camera
                    intro = Task { await WideCityIntro.play(from: start, camera: $camera) }
                }
            }
        }
        .onDisappear(perform: stopIntro)
        .overlay {
            WideCityLabels(contexts: contexts, camera: camera,
                           size: size, selectedId: centered?.id, bottomInset: bottomInset, topInset: topInset)
        }
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
            }
            .padding(8)
            .padding(.bottom, bottomInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("東京23区の建物の3D")
    }

    private func stopIntro() {
        intro?.cancel()
        intro = nil
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
        // 航空写真の外側だけを埋める。写真と重なってちらつかないよう、十分に下げる
        plane.position.y = -30 * scale
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
    @Previewable @State var camera = WideCityCamera()
    WideCityView(camera: $camera)
        .frame(height: 500)
        .preferredColorScheme(.dark)
}
