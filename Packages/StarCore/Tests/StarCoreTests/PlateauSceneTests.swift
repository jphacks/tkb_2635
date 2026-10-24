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
        let shinjuku = try #require(scenes.first { $0.id == "shinjuku" })
        #expect(shinjuku.buildings.count == 8)
        #expect(shinjuku.source.contains("手作り"))
        #expect(shinjuku.buildings.contains { $0.id == "tocho_1" })
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
