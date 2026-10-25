import Foundation
import Testing
@testable import StarCore

struct TerrainHorizonTests {
    private func terrain(_ point: TerrainHorizon.Point?) -> TerrainHorizon {
        TerrainHorizon(source: "test", spots: ["a": Array(repeating: point, count: 360)])
    }

    @Test func flatGroundGivesZero() throws {
        let angles = try #require(terrain(.init(elevation: 10, distance: 500)).elevations(spotId: "a", eyeElevation: 11.5))
        #expect(angles.allSatisfy { $0 == 0 })
    }

    @Test func hillGivesPositiveAngle() throws {
        let angles = try #require(terrain(.init(elevation: 111.5, distance: 100)).elevations(spotId: "a", eyeElevation: 11.5))
        #expect(abs(angles[0] - 45) < 1e-9)
    }

    @Test func missingSpotOrPointIsHandled() throws {
        #expect(terrain(nil).elevations(spotId: "b", eyeElevation: 0) == nil)
        #expect(try #require(terrain(nil).elevations(spotId: "a", eyeElevation: 0)).allSatisfy { $0 == 0 })
    }

    @Test func horizonTakesTheHigherOfBuildingsAndTerrain() {
        var buildings = Array(repeating: 5.0, count: 360)
        buildings[90] = 20
        var ground = Array(repeating: 0.0, count: 360)
        ground[0] = 8
        ground[90] = 3
        let profile = HorizonProfile(samples: buildings, isApproximate: false).combined(withTerrain: ground)
        #expect(profile.samples[0] == 8)
        #expect(profile.samples[90] == 20)
        #expect(profile.samples[180] == 5)
    }

    @Test func bundledTerrainCoversAllSpotsAndIsSmallIn23Wards() throws {
        let terrain = try SeedData.loadTerrain()
        for spot in try SeedData.loadSpots() {
            let angles = try #require(terrain.elevations(spotId: spot.id, eyeElevation: spot.observerElevation), "\(spot.id)")
            #expect(angles.count == 360)
            // 23 区はほぼ平坦。地形だけで 10° を超える地点は無い
            #expect(angles.max()! < 10, "\(spot.id)")
            if spot.category == .observatory {
                #expect(angles.max()! == 0, "\(spot.id)")
            }
        }
    }
}
