import RealityKit
import StarCore
import SwiftUI

/// 観測地点まわりの建物と、天体の方向を 3D で表示する。
/// 1 単位 = 100 m。x が東、y が上、-z が北。観測者の目を原点に置く。
struct Sky3DView: View {
    let context: SpotContext
    let prediction: Prediction
    let date: Date
    /// 渡すと視点を外で持つ（地点を切り替えても向きが変わらない）。nil ならこの 3D だけで持つ。
    var sharedCamera: Binding<SkyCamera>? = nil
    /// 比較画面では、左上の説明を判定と出典だけにする
    var compact = false
    /// false にすると左上の説明を出さない（判定と出典を別の場所に出す画面向け）
    var showsLegend = true

    @State private var ownCamera = SkyCamera()
    @State private var dragStart: SkyCamera?
    @State private var zoomStart: SkyCamera?
    /// 街の読み込みが終わったか。終わったら画面を描き直させる（そのままだと真っ暗なことがある）
    @State private var isLoaded = false

    static let scale: Float = 1 / 100
    static let skyRadius: Float = 4
    /// 目線表示の天体は街より遠く、星空の球より手前に置く。
    static let observerSkyRadius: Float = 200
    private static let groundMeters: Float = 3_000
    /// 遠くの地面を敷く深さ [m]（都市モデルの地面との重なりでちらつかないよう、少し離す）
    static let farGroundDepth: Float = 1.5
    static let dynamicName = "timeDependent"
    static let cityName = "city"
    private static let rootName = "skyRoot"
    private static let spotScenePrefix = "spot-"

    private var spotSceneName: String { Self.spotScenePrefix + context.id }

    /// この地点の街・観測者・地平線・天体をまとめた入れ物
    private func makeSpotScene() async -> Entity {
        var city: Entity?
        var far: ModelEntity?
        if let scene = context.scene {
            city = await CityModelRenderer.shared.city(for: scene)
            far = await FarGroundRenderer.shared.ground(for: scene, scale: Self.scale)
        }
        // 遠くの地面（4-11）があるシーンでは、アスファルトの板は敷かない
        let ground = far == nil ? await CityModelRenderer.shared.ground(meters: Self.groundMeters, scale: Self.scale) : nil
        let spotScene = Entity()
        spotScene.name = spotSceneName
        buildScene(into: spotScene, city: city, ground: ground, far: far)
        return spotScene
    }

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            root.name = Self.rootName
            BuildingNightRenderer.shared.configureEnvironment(in: root)
            root.addChild(await makeSpotScene())
            content.add(root)

            let camera = PerspectiveCamera()
            camera.name = "camera"
            camera.camera.fieldOfViewInDegrees = Float(ObserverViewpoint.defaultFieldOfView)
            // 星空の球（半径 300 単位）まで描く
            camera.camera.far = SkyRenderer.domeRadius * 2
            content.add(camera)
            placeCamera(camera)
            if let active = root.findEntity(named: spotSceneName) { updateScene(active, camera: camera) }
            isLoaded = true
        } update: { content in
            let camera = content.entities.first(where: { $0.name == "camera" }) as? PerspectiveCamera
            if let camera { placeCamera(camera) }
            guard let root = content.entities.first(where: { $0.name == Self.rootName }) else { return }
            // 比較画面で地点を切り替えたときは、RealityView を作り直さず中の地点だけを入れ替える。
            // 作り直すと、シミュレータでは新しい 3D が描かれないことがあった。
            for child in root.children where child.name.hasPrefix(Self.spotScenePrefix) {
                child.isEnabled = child.name == spotSceneName
            }
            if let active = root.findEntity(named: spotSceneName) {
                updateScene(active, camera: camera)
            } else {
                Task {
                    let scene = await makeSpotScene()
                    // 待っている間にほかの呼び出しが同じ地点を足していれば、足さない
                    if root.findEntity(named: scene.name) == nil {
                        root.addChild(scene)
                        updateScene(scene, camera: camera)
                    }
                }
            }
        }
        .id(prediction.celestialBodyId)
        .background(Color(red: 0.02, green: 0.03, blue: 0.10))
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? camera
                    dragStart = start
                    if isObserverView {
                        camera.observer = start.observer.turned(horizontal: -Double(value.translation.width) * 0.3,
                                                               vertical: Double(value.translation.height) * 0.3)
                    } else {
                        camera.yaw = start.yaw - Float(value.translation.width) * 0.008
                        camera.pitch = min(1.45, max(0.05, start.pitch + Float(value.translation.height) * 0.006))
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? camera
                    zoomStart = start
                    if isObserverView {
                        camera.observer = start.observer.zoomed(magnification: Double(value.magnification))
                    } else {
                        camera.distance = min(14, max(2, start.distance / Float(value.magnification)))
                    }
                }
                .onEnded { _ in zoomStart = nil }
        )
        .overlay {
            if !isLoaded {
                ProgressView("街を読み込み中")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsLegend { legend }
        }
        .onChange(of: camera.mode) { _, _ in
            dragStart = nil
            zoomStart = nil
        }
        .accessibilityElement()
        .accessibilityLabel(prediction.accessStatus.label + "。" + (prediction.geometricVisibility
                            ? "\(Angle.directionName(prediction.azimuth))の空に見える見込み"
                            : "建物などに遮られる見込み"))
    }

    private var camera: SkyCamera {
        get { sharedCamera?.wrappedValue ?? ownCamera }
        nonmutating set {
            if let sharedCamera { sharedCamera.wrappedValue = newValue } else { ownCamera = newValue }
        }
    }

    var isObserverView: Bool {
        camera.mode == .observer && context.scene?.observerViewEnabled == true
    }

    private func placeCamera(_ camera: PerspectiveCamera) {
        let c = self.camera
        camera.camera.fieldOfViewInDegrees = Float(isObserverView ? c.observer.fieldOfView : ObserverViewpoint.defaultFieldOfView)
        // 1単位=100m。目線表示では5cm先から描き、近くの壁や足元を欠かさない。
        camera.camera.near = isObserverView ? 0.0005 : 0.01
        if isObserverView {
            camera.look(at: SkyRenderer.vector(c.observer.direction), from: .zero, relativeTo: nil)
        } else {
            let position = SIMD3<Float>(sin(c.yaw) * cos(c.pitch), sin(c.pitch), cos(c.yaw) * cos(c.pitch)) * c.distance
            camera.look(at: [0, 1.2, 0], from: position, relativeTo: nil)
        }
    }

}

#Preview("夜景・SHIBUYA SKY") {
    if let context = try? SeedData.loadContexts().first(where: { $0.id == "shibuya_sky" }),
       let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z") {
        Sky3DView(context: context,
                  prediction: Recommender.evaluate(context, target: .moon, date: date, weather: nil),
                  date: date)
            .frame(height: 500)
            .preferredColorScheme(.dark)
    }
}
