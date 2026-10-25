import Foundation
import Testing
@testable import StarCore

/// 6-04 近傍照明の机上評価・現地確認・未確認の 3 通り
@Suite struct LocalGlareCheckTests {
    private let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!

    private func evaluate(level: Int?, method: String?) throws -> (Spot, Prediction) {
        let context = try #require(try SeedData.loadContexts().first { $0.id == "shibuya_east_plaza" })
        var spot = context.spot
        spot.localGlareLevel = level
        spot.lightingCheckDate = level == nil ? nil : "2026-10-24"
        spot.lightingCheckMethod = method
        let prediction = Recommender.evaluate(SpotContext(spot: spot, scene: context.scene), target: .moon, date: date, weather: nil)
        return (spot, prediction)
    }

    @Test func deskCheckIsShownAsUnverifiedOnSite() throws {
        let (spot, p) = try evaluate(level: 2, method: "desk")
        #expect(p.dataQualityFlags.contains(.localGlareDeskChecked))
        #expect(!p.dataQualityFlags.contains(.localGlareUnverified))
        #expect(p.recommendationReasons.contains("周辺照明は写真などによる机上評価です（現地未確認）。"))
        #expect(!p.recommendationReasons.contains("ただし、周辺照明は未確認です。"))
        #expect(spot.localGlareLabel == "近傍照明（机上評価 2026-10-24）")
        #expect(spot.localGlareNote.contains("机上評価"))
    }

    @Test func onsiteCheckHasNoGlareWarning() throws {
        let (spot, p) = try evaluate(level: 2, method: "onsite")
        #expect(!p.dataQualityFlags.contains(.localGlareDeskChecked))
        #expect(!p.dataQualityFlags.contains(.localGlareUnverified))
        #expect(!p.recommendationReasons.contains { $0.contains("周辺照明") })
        #expect(spot.localGlareLabel == "近傍照明（現地確認 2026-10-24）")
    }

    @Test func missingLevelStaysUnverified() throws {
        let (spot, p) = try evaluate(level: nil, method: nil)
        #expect(p.dataQualityFlags.contains(.localGlareUnverified))
        #expect(!p.dataQualityFlags.contains(.localGlareDeskChecked))
        #expect(p.recommendationReasons.contains("ただし、周辺照明は未確認です。"))
        #expect(spot.localGlareLabel == "近傍照明（現地確認）")
    }

    @Test func deskCheckDoesNotChangeDarkness() throws {
        let (_, desk) = try evaluate(level: 2, method: "desk")
        let (_, onsite) = try evaluate(level: 2, method: "onsite")
        #expect(desk.darknessScore == onsite.darknessScore)
    }

    @Test func oldJSONWithoutMethodStillLoads() throws {
        let data = try JSONEncoder().encode(try #require(try SeedData.loadSpots().first))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "lightingCheckMethod")
        let spot = try JSONDecoder().decode(Spot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(spot.lightingCheckMethod == nil)
        #expect(spot.localGlareCheck == nil)
    }

    @Test func bundledDeskChecksHaveDates() throws {
        let spots = try SeedData.loadSpots()
        let checked = spots.filter { $0.localGlareLevel != nil }
        #expect(!checked.isEmpty)
        for spot in checked {
            #expect(spot.localGlareCheck != nil)
            #expect(spot.lightingCheckDate != nil)
        }
    }
}
