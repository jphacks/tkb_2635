import RealityKit
import StarCore
import SwiftUI

/// 観測地点まわりの建物と、天体の方向を 3D で表示する。
/// 1 単位 = 100 m。x が東、y が上、-z が北。観測者の目を原点に置く。
struct Sky3DView: View {
    let context: SpotContext
    let prediction: Prediction
    let date: Date

    @State private var yaw: Float = .pi / 5
    @State private var pitch: Float = 0.35
    @State private var distance: Float = 10
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var zoomStart: Float?

    private static let scale: Float = 1 / 100
    private static let skyRadius: Float = 4
    private static let groundMeters: Float = 3_000
    private static let dynamicName = "timeDependent"

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let root = Entity()
            BuildingNightRenderer.shared.configureEnvironment(in: root)
            var city: Entity?
            if let scene = context.scene {
                city = await CityModelRenderer.shared.city(for: scene)
            }
            let ground = await CityModelRenderer.shared.ground(meters: Self.groundMeters, scale: Self.scale)
            buildScene(into: root, city: city, ground: ground)
            content.add(root)

            let camera = PerspectiveCamera()
            camera.name = "camera"
            camera.camera.fieldOfViewInDegrees = 55
            content.add(camera)
            placeCamera(camera)
        } update: { content in
            if let camera = content.entities.first(where: { $0.name == "camera" }) {
                placeCamera(camera)
            }
            // 時刻スライダーで動かすたびに街を作り直さず、時刻で変わる物だけを置き直す
            if let dynamic = content.entities.first?.findEntity(named: Self.dynamicName) {
                buildTimeDependent(into: dynamic)
            }
        }
        .id("\(context.id)-\(prediction.celestialBodyId)")
        .background(Color(red: 0.02, green: 0.03, blue: 0.10))
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? (yaw, pitch)
                    dragStart = start
                    yaw = start.yaw - Float(value.translation.width) * 0.008
                    pitch = min(1.45, max(0.05, start.pitch + Float(value.translation.height) * 0.006))
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? distance
                    zoomStart = start
                    distance = min(14, max(2, start / Float(value.magnification)))
                }
                .onEnded { _ in zoomStart = nil }
        )
        .overlay(alignment: .topLeading) { legend }
        .accessibilityElement()
        .accessibilityLabel(prediction.accessStatus.label + "。" + (prediction.geometricVisibility
                            ? "\(Angle.directionName(prediction.azimuth))の空に見える見込み"
                            : "建物などに遮られる見込み"))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            if prediction.accessStatus != .open {
                Label(prediction.accessStatus.label, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Label(prediction.geometricVisibility ? "見える見込み" : (prediction.altitude <= 0 ? "地平線の下" : "遮られる見込み"),
                  systemImage: prediction.geometricVisibility ? "eye" : "eye.slash")
                .foregroundStyle(prediction.geometricVisibility ? .green : .red)
            Text(context.scene?.name ?? "建物データなし（地平線は暫定値）")
                .foregroundStyle(.secondary)
            if context.scene.map(CityModelRenderer.hasModel) == true {
                Text("建物・地面は昼の実写を暗く表示")
                    .foregroundStyle(.secondary)
                // 地理院タイルは出典の明示が利用の条件
                Text("出典: PLATEAU（CC BY 4.0）・国土地理院")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("外壁・窓明かりはイメージ")
                    .foregroundStyle(.secondary)
            }
            if !prediction.geometricVisibility && !prediction.blockedByDirectionMask && prediction.altitude > 0 {
                Label("赤い枠は判定に使った建物の箱", systemImage: "cube")
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.35))
            }
        }
        .font(.caption.bold())
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
        .padding(8)
    }

    private func placeCamera(_ camera: Entity) {
        let position = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
        camera.look(at: [0, 1.2, 0], from: position, relativeTo: nil)
    }

    // MARK: - シーン構築

    /// city は PLATEAU の実形状（無ければ nil で、判定と同じ直方体を描く）。
    private func buildScene(into root: Entity, city: Entity? = nil, ground: Entity? = nil) {
        let spot = context.spot
        let groundElevation = context.scene?.groundElevation ?? spot.floorElevation
        let eyeY = Float(spot.observerElevation - groundElevation) * Self.scale
        // 観測者の目を原点にするため、地面は -eyeY に置く
        let world = Entity()
        world.position = [0, -eyeY, 0]
        root.addChild(world)

        world.addChild(ground ?? ModelEntity(mesh: .generatePlane(width: 12, depth: 12),
                                             materials: [SimpleMaterial(color: UIColor(red: 0.07, green: 0.09, blue: 0.13, alpha: 1), isMetallic: false)]))

        if let scene = context.scene {
            let me = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            func box(_ building: Building) -> (center: SIMD3<Float>, size: SIMD3<Float>) {
                let size = SIMD3<Float>(Float(building.width), Float(building.height), Float(building.depth)) * Self.scale
                return ([Float(building.x - me.east) * Self.scale, size.y / 2, -Float(building.y - me.north) * Self.scale], size)
            }
            if let city {
                // 都市モデルは1単位 = 1m、シーン原点が原点。観測者を原点に合わせて縮める。
                city.scale = .init(repeating: Self.scale)
                city.position = [-Float(me.east) * Self.scale, 0, Float(me.north) * Self.scale]
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
            dot.position = direction(altitude: h, azimuth: Double(az)) * Self.skyRadius
            root.addChild(dot)
        }

        // 方位の目印（北）
        let north = sphere(radius: 0.08, color: .systemRed)
        north.position = direction(altitude: 0, azimuth: 0) * (Self.skyRadius + 0.3)
        root.addChild(north)

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

        // 対象天体と視線
        guard prediction.altitude > -5 else { return }
        let dir = direction(altitude: prediction.altitude, azimuth: prediction.azimuth)
        let color: UIColor = prediction.geometricVisibility ? .systemGreen : .systemRed
        let body = sphere(radius: 0.22, color: prediction.celestialBodyId == "moon" ? .systemYellow : .white)
        body.position = dir * Self.skyRadius
        dynamic.addChild(body)

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

    /// 高度・方位から RealityKit 座標系の単位ベクトルへ
    private func direction(altitude: Double, azimuth: Double) -> SIMD3<Float> {
        let a = altitude * .pi / 180, z = azimuth * .pi / 180
        return SIMD3<Float>(Float(cos(a) * sin(z)), Float(sin(a)), Float(-cos(a) * cos(z)))
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
