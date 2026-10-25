import Foundation
import Testing
@testable import StarCore

struct FloorElevationSourceTests {
    @Test func oldSpotJSONWithoutSourceStillDecodes() throws {
        let json = #"""
        {"id":"old","name":"既存地点","ward":"渋谷区","category":"park","latitude":35.6,"longitude":139.7,
         "floorElevation":15,"eyeHeight":1.5,"indoorOutdoor":"outdoor","directionMaskVerified":true,
         "openingHours":{"alwaysOpen":true},"modelVersion":"test"}
        """#
        let spot = try JSONDecoder().decode(Spot.self, from: Data(json.utf8))
        #expect(spot.floorElevationSource == nil)
        #expect(spot.floorElevationSourceLabel == "暫定値")
    }

    @Test func groundSpotsCloseToTheirSceneUseGSIElevation() throws {
        let contexts = try SeedData.loadContexts()
        let ground = try #require(contexts.first { $0.id == "shibuya_east_plaza" })
        #expect(ground.spot.floorElevationSource?.hasPrefix("国土地理院") == true)
        // 出典のある地上の地点は、建物データの地盤標高との差が 2 m 以内（2-06 の反映条件）
        for context in contexts where context.spot.floorElevationSource?.hasPrefix("国土地理院") == true {
            guard let scene = context.scene else { continue }
            #expect(abs(context.spot.floorElevation - scene.groundElevation) <= 2, "\(context.id)")
        }
    }
}
