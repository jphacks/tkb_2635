import Foundation
import Testing
@testable import StarCore

@Suite struct BestTimeFinderTests {
    private let night = ObservingNight(containing: ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!)

    @Test func findsVisibleSpotWithinTheNight() throws {
        let contexts = try SeedData.loadContexts()
        let best = try #require(BestTimeFinder.find(contexts: contexts, target: .moon, night: night))
        #expect(night.contains(best.date))
        #expect(best.prediction.geometricVisibility)
        #expect(best.prediction.tier != .notVisible && best.prediction.tier != .unavailable)
    }

    @Test func noCandidateWhenNothingIsVisible() throws {
        // 空の見えない地点だけ（地平線の下の天体）なら nil
        let contexts = try SeedData.loadContexts().filter { $0.id == "roppongi_ground" }
        let sun = ObservationTarget.star(Star(id: "south", name: "テスト星", rightAscension: 0, declination: -89, magnitude: 1))
        #expect(BestTimeFinder.find(contexts: contexts, target: sun, night: night) == nil)
    }

    @Test func prefersClearSkyOverCloudy() throws {
        let contexts = try SeedData.loadContexts()
        func weather(cloudyHour: Int) -> (Spot, Date) -> Weather? {
            { _, date in
                let hour = Calendar.tokyo.component(.hour, from: date)
                return Weather(gridId: "g", modelName: "m", forecastTime: date, fetchedAt: date,
                               cloudCover: hour == cloudyHour ? 5 : 95, precipitation: 0, wind: nil, visibility: nil, missingStatus: .ok)
            }
        }
        let best = try #require(BestTimeFinder.find(contexts: contexts, target: .moon, night: night, weather: weather(cloudyHour: 22)))
        #expect(Calendar.tokyo.component(.hour, from: best.date) == 22)
    }
}
