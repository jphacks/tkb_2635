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

    @Test func addedParksLoadThroughRecommendationPipeline() throws {
        let contexts = try SeedData.loadContexts()
        #expect(contexts.count == 43)  // 19 地点＋ a で足した展望台・地上・公園＋東京大学 本郷
        #expect(Set(contexts.map(\.id)).count == contexts.count)
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
            // 建物に隠れる地点は「見えない」、隠れなければ入場・照明が未確認なので「要確認」
            #expect(result.tier == (result.geometricVisibility ? .needsCheck : .notVisible))
            #expect(result.totalScore.isFinite)
            #expect(result.dataQualityFlags.contains(.regionalLightUnverified))
            #expect(result.dataQualityFlags.contains(.directionMaskUnverified))

            var darkAssumption = spot
            darkAssumption.regionalLightIndex = 0
            let zero = Recommender.evaluate(SpotContext(spot: darkAssumption, scene: nil), target: .moon, date: date, weather: nil)
            #expect(result.darknessScore < zero.darknessScore)
        }
    }

    /// 追加タスク f の7地点。入場を確認できた4地点と、未確認の3地点を分けて扱う。
    @Test func moreParksKeepVerifiedAndUnverifiedAccessApart() throws {
        let contexts = try SeedData.loadContexts()
        let date = ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!
        let verified = ["hikarigaoka_park", "ukima_park", "kiba_park", "kinuta_park"]
        let unverified = ["odaiba_kaihin_park", "harumi_futo_park", "jonanjima_kaihin_park"]
        for id in verified + unverified {
            let context = try #require(contexts.first { $0.id == id })
            let spot = context.spot
            #expect(spot.category == .park)
            #expect(spot.officialWebsite != nil)
            // a で全地点に PLATEAU の建物（シーン ID = 地点 ID）を入れた
            #expect(spot.sceneId == id)
            #expect(spot.approxHorizonElevation.map { (5...15).contains($0) } == true)
            #expect(spot.regionalLightSource != nil)
            #expect(spot.regionalLightMeasuredAt == "2025")
            #expect(spot.localGlareLevel == nil)
            let result = Recommender.evaluate(context, target: .moon, date: date, weather: nil)
            // 建物に隠れる地点は「見えない」、隠れなければ入場・照明が未確認なので「要確認」
            #expect(result.tier == (result.geometricVisibility ? .needsCheck : .notVisible))
            #expect(result.totalScore.isFinite)
            if verified.contains(id) {
                #expect(spot.lastVerifiedAt == "2026-10-24")
                #expect(spot.accessStatus(at: date) == .open)
            } else {
                #expect(spot.lastVerifiedAt == nil)
                #expect(spot.accessStatus(at: date) == .unverified)
            }
        }
    }
}
