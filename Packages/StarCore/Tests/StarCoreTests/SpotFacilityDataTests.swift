import Foundation
import Testing
@testable import StarCore

@Suite struct SpotFacilityDataTests {
    @Test func legacySpotJSONStillLoadsWithoutNewFields() throws {
        let original = try #require(try SeedData.loadSpots().first { $0.id == "shibuya_sky" })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        for key in ["weatherClosureConditions", "photographyRestrictions", "viewingDirectionNotes"] {
            json.removeValue(forKey: key)
        }
        let spot = try JSONDecoder().decode(Spot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(spot.weatherClosureConditions == nil)
        #expect(spot.photographyRestrictions == nil)
        #expect(spot.viewingDirectionNotes == nil)
        #expect(spot.regionalLightIndex == original.regionalLightIndex)
    }

    @Test func facilityConditionsAreSeparateAndUnknownIsNotUnrestricted() throws {
        let spots = try SeedData.loadSpots()
        let sky = try #require(spots.first { $0.id == "shibuya_sky" })
        #expect(sky.weatherClosureConditions?.contains("強風") == true)
        #expect(sky.photographyRestrictions?.contains("三脚") == true)
        let tocho = try #require(spots.first { $0.id == "tocho_observatory" })
        #expect(tocho.weatherClosureConditions != nil)
        #expect(tocho.photographyRestrictions?.contains("三脚") == true)
        let kitte = try #require(spots.first { $0.id == "kitte_garden" })
        #expect(kitte.weatherClosureConditions != nil)
        #expect(kitte.photographyRestrictions == nil)
    }

    @Test func twelveUniqueSpotsLoadThroughRecommendationPipeline() throws {
        let contexts = try SeedData.loadContexts()
        #expect(contexts.count == 12)
        #expect(Set(contexts.map(\.id)).count == 12)
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let newIDs = ["toneri_park", "mizumoto_park", "komazawa_olympic_park"]
        for id in newIDs {
            let context = try #require(contexts.first { $0.id == id })
            let spot = context.spot
            #expect(spot.category == .park)
            #expect(spot.officialWebsite != nil)
            #expect(spot.lastVerifiedAt == "2026-10-24")
            #expect(spot.accessStatus(at: date) == .open)
            #expect(spot.regionalLightIndex == nil)
            #expect(spot.regionalLightShortSource == "未確認")
            #expect(!spot.regionalLightProvisional)
            #expect(spot.localGlareLevel == nil)
            #expect(spot.weatherClosureConditions == nil)
            #expect(spot.photographyRestrictions == nil)
            let result = Recommender.evaluate(context, target: .moon, date: date, weather: nil)
            #expect(result.tier == .needsCheck)
            #expect(result.totalScore.isFinite)
            #expect(result.dataQualityFlags.contains(.regionalLightUnverified))
            #expect(result.dataQualityFlags.contains(.directionMaskUnverified))

            var darkAssumption = spot
            darkAssumption.regionalLightIndex = 0
            let zero = Recommender.evaluate(SpotContext(spot: darkAssumption, scene: nil), target: .moon, date: date, weather: nil)
            #expect(result.darknessScore < zero.darknessScore)
        }
    }
}
