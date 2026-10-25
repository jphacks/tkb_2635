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
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var zoomStart: Float?
    /// 街の読み込みが終わったか。終わったら画面を描き直させる（そのままだと真っ暗なことがある）
    @State private var isLoaded = false

    private static let scale: Float = 1 / 100
    private static let skyRadius: Float = 4
    private static let groundMeters: Float = 3_000
    /// 遠くの地面を敷く深さ [m]（都市モデルの地面との重なりでちらつかないよう、少し離す）
    private static let farGroundDepth: Float = 1.5
    private static let dynamicName = "timeDependent"
    private static let cityName = "city"
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
            camera.camera.fieldOfViewInDegrees = 55
            // 星空の球（半径 300 単位）まで描く
            camera.camera.far = SkyRenderer.domeRadius * 2
            content.add(camera)
            placeCamera(camera)
            isLoaded = true
        } update: { content in
            let camera = content.entities.first(where: { $0.name == "camera" })
            if let camera { placeCamera(camera) }
            guard let root = content.entities.first(where: { $0.name == Self.rootName }) else { return }
            // 比較画面で地点を切り替えたときは、RealityView を作り直さず中の地点だけを入れ替える。
            // 作り直すと、シミュレータでは新しい 3D が描かれないことがあった。
            for child in root.children where child.name.hasPrefix(Self.spotScenePrefix) {
                child.isEnabled = child.name == spotSceneName
            }
            if let active = root.findEntity(named: spotSceneName) {
                // 時刻スライダーで動かすたびに街を作り直さず、時刻で変わる物だけを置き直す
                if let dynamic = active.findEntity(named: Self.dynamicName) {
                    buildTimeDependent(into: dynamic)
                }
                if let city = active.findEntity(named: Self.cityName) {
                    CityModelRenderer.updateWindows(in: city, date: date)
                }
                if let dome = active.findEntity(named: SkyRenderer.domeName) as? ModelEntity {
                    SkyRenderer.shared.updateDome(dome, spot: context.spot, date: date)
                }
                if let moon = active.findEntity(named: SkyRenderer.moonName), let camera {
                    SkyRenderer.orientMoon(moon, cameraPosition: camera.position(relativeTo: nil), brightLimb: moonBrightLimb)
                }
            } else {
                Task {
                    let scene = await makeSpotScene()
                    // 待っている間にほかの呼び出しが同じ地点を足していれば、足さない
                    if root.findEntity(named: scene.name) == nil { root.addChild(scene) }
                }
            }
        }
        .id(prediction.celestialBodyId)
        .background(Color(red: 0.02, green: 0.03, blue: 0.10))
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? (camera.yaw, camera.pitch)
                    dragStart = start
                    camera.yaw = start.yaw - Float(value.translation.width) * 0.008
                    camera.pitch = min(1.45, max(0.05, start.pitch + Float(value.translation.height) * 0.006))
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? camera.distance
                    zoomStart = start
                    camera.distance = min(14, max(2, start / Float(value.magnification)))
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

    private func placeCamera(_ camera: Entity) {
        let c = self.camera
        let position = SIMD3<Float>(sin(c.yaw) * cos(c.pitch), sin(c.pitch), cos(c.yaw) * cos(c.pitch)) * c.distance
        camera.look(at: [0, 1.2, 0], from: position, relativeTo: nil)
    }

    // MARK: - シーン構築

    /// city は PLATEAU の実形状（無ければ nil で、判定と同じ直方体を描く）。far は遠くの地面（シーンの原点が中心）。
    private func buildScene(into root: Entity, city: Entity? = nil, ground: Entity? = nil, far: Entity? = nil) {
        let spot = context.spot
        let groundElevation = context.scene?.groundElevation ?? spot.floorElevation
        let eyeY = Float(spot.observerElevation - groundElevation) * Self.scale
        // 観測者の目を原点にするため、地面は -eyeY に置く
        let world = Entity()
        world.position = [0, -eyeY, 0]
        root.addChild(world)

        if far == nil {
            world.addChild(ground ?? ModelEntity(mesh: .generatePlane(width: 12, depth: 12),
                                                 materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 1), isMetallic: false)]))
        }

        if let scene = context.scene {
            let me = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            if let far {
                // 都市モデルの航空写真の地面（-0.3m）より下に敷き、その外側だけが見えるようにする
                far.position = [-Float(me.east) * Self.scale, -Self.farGroundDepth * Self.scale, Float(me.north) * Self.scale]
                world.addChild(far)
            }
            func box(_ building: Building) -> (center: SIMD3<Float>, size: SIMD3<Float>) {
                let size = SIMD3<Float>(Float(building.width), Float(building.height), Float(building.depth)) * Self.scale
                return ([Float(building.x - me.east) * Self.scale, size.y / 2, -Float(building.y - me.north) * Self.scale], size)
            }
            if let city {
                // 都市モデルは1単位 = 1m、シーン原点が原点。観測者を原点に合わせて縮める。
                city.scale = .init(repeating: Self.scale)
                city.position = [-Float(me.east) * Self.scale, 0, Float(me.north) * Self.scale]
                city.name = Self.cityName
                CityModelRenderer.updateWindows(in: city, date: date)
                if let host = scene.buildings.first(where: { $0.id == spot.hostBuildingId }),
                   spot.observerElevation < groundElevation + host.height {
                    CityModelRenderer.revealHost(host.id, in: city)
                }
                world.addChild(city)
            } else {
                for building in scene.buildings {
                    let entity = BuildingNightRenderer.shared.entity(for: building, scale: Self.scale,
                                                                     isHost: building.id == spot.hostBuildingId)
                    entity.position = box(building).center
                    world.addChild(entity)
                }
            }

            if let host = scene.buildings.first(where: { $0.id == spot.hostBuildingId }) {
                let (center, size) = box(host)
                let floor = Float(spot.floorElevation - groundElevation) * Self.scale
                if let deck = Sky3DMarkers.observationDeck(center: [center.x, 0, center.z], size: size,
                                                           floor: floor, observer: [0, 0]) {
                    world.addChild(deck)
                }
            }

        }

        // 観測者
        root.addChild(sphere(radius: 0.06, color: .systemBlue))

        // 地平線プロファイル（5°ごとの遮蔽仰角を天球上の点で表示）
        for az in stride(from: 0, to: 360, by: 5) {
            let h = context.horizon.samples[az]
            let dot = sphere(radius: 0.025, color: UIColor(white: 0.9, alpha: 0.6))
            dot.position = SkyRenderer.direction(altitude: h, azimuth: Double(az)) * Self.skyRadius
            root.addChild(dot)
        }

        // 方位の目印（北）
        let north = sphere(radius: 0.08, color: .systemRed)
        north.position = SkyRenderer.direction(altitude: 0, azimuth: 0) * (Self.skyRadius + 0.3)
        root.addChild(north)

        // 星空（4-12）。観測者を中心に、地点・時刻の空に合わせて回す
        if let dome = SkyRenderer.shared.makeDome() {
            SkyRenderer.shared.updateDome(dome, spot: spot, date: date)
            root.addChild(dome)
        }

        let dynamic = Entity()
        dynamic.name = Self.dynamicName
        root.addChild(dynamic)
        buildTimeDependent(into: dynamic)

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

    /// 時刻で変わる物（対象天体・視線・判定に使った建物の枠）。呼ぶたびに中身を作り直す。
    private func buildTimeDependent(into dynamic: Entity) {
        dynamic.children.removeAll()
        let spot = context.spot

        // 建物に遮られる見込みのとき、判定に使った箱（実際の形より大きい直方体）を枠で示す。
        if let scene = context.scene,
           !prediction.geometricVisibility && !prediction.blockedByDirectionMask && prediction.altitude > 0,
           let blocker = HorizonProfile.highestBuilding(spot: spot, scene: scene, azimuth: prediction.azimuth) {
            let me = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            let eyeY = Float(spot.observerElevation - scene.groundElevation) * Self.scale
            let size = SIMD3<Float>(Float(blocker.width), Float(blocker.height), Float(blocker.depth)) * Self.scale
            let center = SIMD3<Float>(Float(blocker.x - me.east) * Self.scale, size.y / 2 - eyeY,
                                      -Float(blocker.y - me.north) * Self.scale)
            dynamic.addChild(Sky3DMarkers.judgmentFrame(center: center, size: size,
                                                        color: UIColor(red: 1, green: 0.45, blue: 0.35, alpha: 1)))
        }

        // 月（4-10）。どの天体を見ていても、本物の位置に満ち欠けつきで出す
        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude)
        if moon.position.altitude > -5 {
            let disk = SkyRenderer.shared.makeMoon(fraction: moon.illuminatedFraction)
            disk.position = SkyRenderer.direction(altitude: moon.position.altitude, azimuth: moon.position.azimuth) * Self.skyRadius
            dynamic.addChild(disk)
        }

        // 対象天体と視線
        guard prediction.altitude > -5 else { return }
        let dir = SkyRenderer.direction(altitude: prediction.altitude, azimuth: prediction.azimuth)
        let color: UIColor = prediction.geometricVisibility ? .systemGreen : .systemRed
        if prediction.celestialBodyId != ObservationTarget.moon.id {
            let body = sphere(radius: 0.12, color: .white)
            body.position = dir * Self.skyRadius
            dynamic.addChild(body)
        }

        let length = Self.skyRadius - 0.25
        let ray = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.015),
                              materials: [UnlitMaterial(color: color)])
        ray.orientation = simd_quatf(from: [0, 1, 0], to: dir)
        ray.position = dir * (length / 2)
        dynamic.addChild(ray)
    }

    private func sphere(radius: Float, color: UIColor) -> ModelEntity {
        ModelEntity(mesh: .generateSphere(radius: radius), materials: [UnlitMaterial(color: color)])
    }

    /// 月の明るい側が向いている 3D の向き（太陽と重なるときは nil）
    private var moonBrightLimb: SIMD3<Float>? {
        let spot = context.spot
        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude).position
        let sun = Astro.sun(date: date, latitude: spot.latitude, longitude: spot.longitude)
        return MoonPhase.brightLimbDirection(moon: moon, sun: sun).map(SkyRenderer.vector)
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
