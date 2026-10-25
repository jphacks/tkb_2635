import Foundation
import Testing
@testable import StarCore

private func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct TwilightTests {
    @Test func statesFollowStandardLimits() {
        #expect(Twilight.state(sunAltitude: 30) == .daylight)
        #expect(Twilight.state(sunAltitude: -3) == .civilTwilight)
        #expect(Twilight.state(sunAltitude: -6) == .nauticalTwilight)
        #expect(Twilight.state(sunAltitude: -9) == .nauticalTwilight)
        #expect(Twilight.state(sunAltitude: -15) == .astronomicalTwilight)
        #expect(Twilight.state(sunAltitude: -18) == .night)
        #expect(Twilight.state(sunAltitude: -40) == .night)
    }

    @Test func skyBrightnessFactorIsLinearBetweenLimits() {
        #expect(Twilight.skyBrightnessFactor(sunAltitude: -30) == 0)
        #expect(Twilight.skyBrightnessFactor(sunAltitude: -18) == 0)
        #expect(abs(Twilight.skyBrightnessFactor(sunAltitude: -12) - 0.5) < 1e-9)
        #expect(Twilight.skyBrightnessFactor(sunAltitude: -6) == 1)
        #expect(Twilight.skyBrightnessFactor(sunAltitude: 20) == 1)
        #expect(Twilight.allowsStars(sunAltitude: -6.5))
        #expect(!Twilight.allowsStars(sunAltitude: -5.5))
    }

    /// 昼の 12:00 JST に恒星を選ぶと、建物に関係なく「見えない見込み」になる
    @Test func starsAreNotVisibleInDaylight() throws {
        let sky = try #require(try SeedData.loadContexts().first { $0.id == "shibuya_sky" })
        let vega = try #require(StarCatalog.star(id: "vega"))
        let noon = utc("2026-10-24T03:00:00Z")  // 12:00 JST
        let p = Recommender.evaluate(sky, target: .star(vega), date: noon, weather: nil)
        #expect(p.skyState == .daylight)
        #expect(p.sunAltitude > 0)
        #expect(p.skyTooBright)
        #expect(p.tier == .notVisible)
        #expect(p.darknessScore == 0)
        #expect(p.recommendationReasons.contains { $0.contains("恒星は見えません") })
    }

    /// 月は昼間でも「見えない」にはしないが、「推薦」にもしない
    @Test func moonInDaylightIsAtMostNeedsCheck() throws {
        let sky = try #require(try SeedData.loadContexts().first { $0.id == "shibuya_sky" })
        let p = Recommender.evaluate(sky, target: .moon, date: utc("2026-10-24T03:00:00Z"), weather: nil)
        #expect(!p.skyTooBright)
        #expect(p.tier != .recommended)
        #expect(p.recommendationReasons.contains { $0.contains("星空観測には向きません") })
    }

    /// 航海薄明（17:40 JST ごろ）は、夜より暗さが下がるが恒星は除外しない
    @Test func twilightLowersDarknessWithoutExcludingStars() throws {
        let sky = try #require(try SeedData.loadContexts().first { $0.id == "shibuya_sky" })
        let vega = try #require(StarCatalog.star(id: "vega"))
        let dusk = utc("2026-10-24T08:40:00Z")   // 17:40 JST
        let night = utc("2026-10-24T12:00:00Z")  // 21:00 JST
        let d = Recommender.evaluate(sky, target: .star(vega), date: dusk, weather: nil)
        let n = Recommender.evaluate(sky, target: .star(vega), date: night, weather: nil)
        #expect(d.skyState == .nauticalTwilight, "太陽高度 \(d.sunAltitude)")
        #expect(!d.skyTooBright)
        #expect(n.skyState == .night, "太陽高度 \(n.sunAltitude)")
        #expect(d.darknessScore > 0)
        #expect(d.darknessScore < n.darknessScore)
        #expect(d.recommendationReasons.contains { $0.contains("航海薄明") })
        #expect(!n.recommendationReasons.contains { $0.contains("薄明") })
    }
}
