import Foundation
import Testing
@testable import StarCore

@Suite struct PlateauSceneTests {
    @Test func bundledShibuyaUsesPlateauAndHasValidGeometry() throws {
        let scenes = try SeedData.loadScenes()
        let scene = try #require(scenes.first { $0.id == "shibuya" })
        #expect(scene.source.contains("PLATEAU"))
        #expect(scene.source.contains("CC BY 4.0"))
        #expect(scene.buildings.count == 1_497)
        #expect(Set(scene.buildings.map(\.id)).count == scene.buildings.count)
        #expect(!scene.buildings.contains { $0.id == "scramble_square" })
        for building in scene.buildings {
            #expect(building.id.hasPrefix("bldg_"))
            #expect([building.x, building.y, building.width, building.depth, building.height].allSatisfy { $0.isFinite })
            #expect(building.width > 0 && building.depth > 0 && building.height > 0)
            let dx = max(abs(building.x) - building.width / 2, 0)
            let dy = max(abs(building.y) - building.depth / 2, 0)
            #expect(hypot(dx, dy) <= 500.01)
        }
    }

    /// 西新宿も渋谷と同じ手順（scripts/build_city_scene.py）で PLATEAU から作った（2-05）。
    @Test func bundledShinjukuUsesPlateauAndTochoHostsTheObservatory() throws {
        let scene = try #require(try SeedData.loadScenes().first { $0.id == "shinjuku" })
        #expect(scene.source.contains("PLATEAU"))
        #expect(scene.source.contains("CC BY 4.0"))
        #expect(scene.groundElevation == 36)
        #expect(scene.buildings.count == 791)
        #expect(Set(scene.buildings.map(\.id)).count == scene.buildings.count)
        #expect(scene.buildings.allSatisfy { $0.id.hasPrefix("bldg_") && $0.height > 0 })

        let spots = try SeedData.loadSpots()
        let tocho = try #require(spots.first { $0.id == "tocho_observatory" })
        let host = try #require(scene.buildings.first { $0.id == tocho.hostBuildingId })
        #expect(host.name == "東京都庁第一本庁舎")
        let p = scene.localPosition(latitude: tocho.latitude, longitude: tocho.longitude)
        #expect(abs(p.east - host.x) < host.width / 2 && abs(p.north - host.y) < host.depth / 2)
        // 展望室は屋内なので、目の高さは建物の屋根より低い（3D では建物を半透明にする）
        #expect(tocho.observerElevation < scene.groundElevation + host.height)

        let park = try #require(spots.first { $0.id == "shinjuku_central_park" })
        let g = scene.localPosition(latitude: park.latitude, longitude: park.longitude)
        #expect(!scene.buildings.contains {
            abs(g.east - $0.x) <= $0.width / 2 && abs(g.north - $0.y) <= $0.depth / 2
        })
    }

    /// 丸の内（KITTE）も同じ手順で作った。PLATEAU では KITTE の低層部と JP タワーが1棟なので、
    /// JP タワーを hostBuildingId にする（3D では半透明にして、屋上庭園の観測者を見せる）。
    @Test func bundledMarunouchiUsesPlateauAndKitteIsOnJPTower() throws {
        let scene = try #require(try SeedData.loadScenes().first { $0.id == "marunouchi" })
        #expect(scene.source.contains("PLATEAU") && scene.source.contains("CC BY 4.0"))
        #expect(scene.groundElevation == 3)
        #expect(scene.buildings.count == 350)
        let kitte = try #require(try SeedData.loadSpots().first { $0.id == "kitte_garden" })
        #expect(kitte.sceneId == "marunouchi")
        let tower = try #require(scene.buildings.first { $0.id == kitte.hostBuildingId })
        #expect(tower.name == "JPタワー")
        let p = scene.localPosition(latitude: kitte.latitude, longitude: kitte.longitude)
        #expect(abs(p.east - tower.x) < tower.width / 2 && abs(p.north - tower.y) < tower.depth / 2)
        let horizon = HorizonProfile.compute(spot: kitte, scene: scene)
        #expect(!horizon.isApproximate)
    }

    /// a: 全地点に PLATEAU から作ったシーンがある。地上の地点の目は、シーンの地面より下にならない。
    @Test func everySpotHasAPlateauScene() throws {
        let scenes = Dictionary(uniqueKeysWithValues: try SeedData.loadScenes().map { ($0.id, $0) })
        for spot in try SeedData.loadSpots() {
            let scene = try #require(spot.sceneId.flatMap { scenes[$0] }, "\(spot.id)")
            #expect(scene.source.contains("PLATEAU") && scene.source.contains("CC BY 4.0"))
            #expect(!scene.buildings.isEmpty)
            #expect(Set(scene.buildings.map(\.id)).count == scene.buildings.count)
            #expect(spot.observerElevation >= scene.groundElevation, "\(spot.id)")
        }
    }

    @Test func rooftopHostResolvesAndGroundIsOutsideBuildings() throws {
        let scene = try #require(try SeedData.loadScenes().first { $0.id == "shibuya" })
        let spots = try SeedData.loadSpots()
        let sky = try #require(spots.first { $0.id == "shibuya_sky" })
        let ground = try #require(spots.first { $0.id == "shibuya_east_plaza" })
        let host = try #require(scene.buildings.first { $0.id == sky.hostBuildingId })
        let p = scene.localPosition(latitude: sky.latitude, longitude: sky.longitude)
        #expect(abs(p.east - host.x) < host.width / 2)
        #expect(abs(p.north - host.y) < host.depth / 2)
        let g = scene.localPosition(latitude: ground.latitude, longitude: ground.longitude)
        #expect(!scene.buildings.contains {
            abs(g.east - $0.x) <= $0.width / 2 && abs(g.north - $0.y) <= $0.depth / 2
        })
        #expect(ground.memo?.contains("未確認") == true)
        #expect(sky.memo?.contains("未確認") == true)
    }

    @Test func hostExclusionChangesTheRealBuildingHorizon() throws {
        let scene = try #require(try SeedData.loadScenes().first { $0.id == "shibuya" })
        let spots = try SeedData.loadSpots()
        var observer = try #require(spots.first { $0.id == "shibuya_east_plaza" })
        let sky = try #require(spots.first { $0.id == "shibuya_sky" })
        let includingHost = HorizonProfile.compute(spot: observer, scene: scene)
        // 建物の外の低い視点から計算し、IDによる除外そのものを確認する。
        observer.hostBuildingId = sky.hostBuildingId
        let excludingHost = HorizonProfile.compute(spot: observer, scene: scene)
        #expect(includingHost.elevation(at: 310) > excludingHost.elevation(at: 310) + 20)
        #expect(excludingHost.samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 90 })
    }
}
