import RealityKit
import StarCore
import SwiftUI

private struct SkySceneStamp: Component, Equatable {
    let date: Date
    let bodyId: String
    let observerView: Bool
}

extension Sky3DView {
    // MARK: - シーン構築

    /// カメラを動かしただけでは月の画像や窓を作り直さず、見回しの操作を軽くする。
    func updateScene(_ active: Entity, camera: Entity?) {
        let stamp = SkySceneStamp(date: date, bodyId: prediction.celestialBodyId, observerView: isObserverView)
        if let dynamic = active.findEntity(named: Self.dynamicName), dynamic.components[SkySceneStamp.self] != stamp {
            buildTimeDependent(into: dynamic)
            if let city = active.findEntity(named: Self.cityName) {
                CityModelRenderer.updateWindows(in: city, date: date)
            }
            if let dome = active.findEntity(named: SkyRenderer.domeName) as? ModelEntity {
                SkyRenderer.shared.updateDome(dome, spot: context.spot, date: date)
            }
        }
        active.findEntity(named: "overviewGuides")?.isEnabled = self.camera.mode == .overview
        active.findEntity(named: "schematicDeck")?.isEnabled = self.camera.mode == .overview
        active.findEntity(named: ObserverEntryRenderer.name)?.isEnabled = self.camera.mode == .overview
        if let city = active.findEntity(named: Self.cityName) {
            CityModelRenderer.revealHost(of: context, in: city, revealed: self.camera.mode != .overview)
        }
        active.findEntity(named: "overviewRay")?.isEnabled = self.camera.mode == .overview
        ConstellationLabelRenderer.update(in: active, camera: camera)
        if let moon = active.findEntity(named: SkyRenderer.moonName), let camera {
            SkyRenderer.orientMoon(moon, cameraPosition: camera.position(relativeTo: nil), brightLimb: moonBrightLimb)
        }
    }

    /// city は PLATEAU の実形状（無ければ nil で、判定と同じ直方体を描く）。far は遠くの地面（シーンの原点が中心）。
    func buildScene(into root: Entity, city: Entity? = nil, ground: Entity? = nil, far: Entity? = nil) {
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
                CityModelRenderer.revealHost(of: context, in: city, revealed: self.camera.mode != .overview)
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
                    // 全体表示用の想像の柵で、目線からの本当の眺めをふさがない。
                    deck.name = "schematicDeck"
                    deck.isEnabled = self.camera.mode == .overview
                    world.addChild(deck)
                }
            }

        }

        // 観測者の顔に重なる目印は、全体表示のときだけ出す。
        let guides = Entity()
        guides.name = "overviewGuides"
        guides.isEnabled = self.camera.mode == .overview
        root.addChild(guides)
        guides.addChild(sphere(radius: 0.06, color: .systemBlue))

        ObserverEntryRenderer.add(to: root, city: city, context: context, scale: Self.scale, animated: !reduceMotion)
        root.findEntity(named: ObserverEntryRenderer.name)?.isEnabled = self.camera.mode == .overview

        // 地平線プロファイル（5°ごとの遮蔽仰角を天球上の点で表示）
        for az in stride(from: 0, to: 360, by: 5) {
            let h = context.horizon.samples[az]
            let dot = sphere(radius: 0.025, color: UIColor(white: 0.9, alpha: 0.6))
            dot.position = SkyRenderer.direction(altitude: h, azimuth: Double(az)) * Self.skyRadius
            guides.addChild(dot)
        }

        // 方位の目印（北）
        let north = sphere(radius: 0.08, color: .systemRed)
        north.position = SkyRenderer.direction(altitude: 0, azimuth: 0) * (Self.skyRadius + 0.3)
        guides.addChild(north)
        Sky3DCompass.add(to: root)
        IndoorEnclosureRenderer.add(to: root, spot: spot, scale: Self.scale)

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
        dynamic.components.set(SkySceneStamp(date: date, bodyId: prediction.celestialBodyId, observerView: isObserverView))
        let spot = context.spot
        let celestialRadius = isObserverView ? Self.observerSkyRadius : Self.skyRadius
        let celestialScale = celestialRadius / Self.skyRadius

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
            disk.position = SkyRenderer.direction(altitude: moon.position.altitude, azimuth: moon.position.azimuth) * celestialRadius
            disk.scale = .init(repeating: celestialScale)
            dynamic.addChild(disk)
        }

        // 対象天体と視線
        guard prediction.altitude > -5 else { return }
        let dir = SkyRenderer.direction(altitude: prediction.altitude, azimuth: prediction.azimuth)
        let color: UIColor = prediction.geometricVisibility ? .systemGreen : .systemRed
        if prediction.celestialBodyId != ObservationTarget.moon.id {
            let body = sphere(radius: 0.12 * celestialScale, color: .white)
            body.position = dir * celestialRadius
            dynamic.addChild(body)
        }

        guard !isObserverView else { return }
        let length = Self.skyRadius - 0.25
        let ray = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.015),
                              materials: [UnlitMaterial(color: color)])
        // 近づくと線の太さが画面を覆うため、移動が始まったら隠す。
        ray.name = "overviewRay"
        ray.isEnabled = self.camera.mode == .overview
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
