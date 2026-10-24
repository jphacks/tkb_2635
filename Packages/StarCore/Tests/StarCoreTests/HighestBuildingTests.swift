import Foundation
import Testing
@testable import StarCore

@Suite struct HighestBuildingTests {
    /// 3D で枠を出す建物が、判定に使う遮蔽仰角 h(A) を決めている建物と一致すること
    @Test(arguments: ["shibuya_east_plaza", "shibuya_sky"])
    func matchesHorizonProfile(spotId: String) throws {
        let scene = try #require(try SeedData.loadScenes().first { $0.id == "shibuya" })
        let spot = try #require(try SeedData.loadSpots().first { $0.id == spotId })
        let profile = HorizonProfile.compute(spot: spot, scene: scene)
        let p = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
        for azimuth in stride(from: 0, to: 360, by: 10) {
            let found = HorizonProfile.highestBuilding(spot: spot, scene: scene, azimuth: Double(azimuth))
            guard let found else {
                #expect(profile.samples[azimuth] == 0)
                continue
            }
            #expect(found.id != spot.hostBuildingId)
            let alone = HorizonProfile.compute(observerEast: p.east, observerNorth: p.north,
                                               eyeElevation: spot.observerElevation,
                                               groundElevation: scene.groundElevation, buildings: [found])
            #expect(abs(alone.samples[azimuth] - profile.samples[azimuth]) < 1e-9)
        }
    }
}
