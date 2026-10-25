import Foundation
import Testing
@testable import StarCore

/// 7-03: 晴れ・曇りの夜に、順位と理由の文がおかしくならないことを確かめる
@Suite struct RecommendationReviewTests {
    private let date = ISO8601DateFormatter().date(from: "2026-10-25T11:00:00Z")!

    private func weather(cloud: Double, precipitation: Double = 0) -> Weather {
        Weather(gridId: "g", modelName: "m", forecastTime: date, fetchedAt: date, cloudCover: cloud,
                precipitation: precipitation, wind: nil, visibility: nil, missingStatus: .ok)
    }

    private func predictions(cloud: Double, precipitation: Double = 0) throws -> [Prediction] {
        try SeedData.loadContexts().map {
            Recommender.evaluate($0, target: .moon, date: date, weather: weather(cloud: cloud, precipitation: precipitation))
        }
    }

    @Test func clearNightKeepsRecommendedSpots() throws {
        #expect(try predictions(cloud: 10).contains { $0.tier == .recommended })
    }

    @Test func heavyCloudIsNeverRecommended() throws {
        for p in try predictions(cloud: 90) where p.tier != .unavailable && p.tier != .notVisible {
            #expect(p.tier == .needsCheck)
            #expect(p.recommendationReasons.contains { $0.contains("隠れて") })
        }
    }

    @Test func rainIsNeverRecommended() throws {
        #expect(try predictions(cloud: 20, precipitation: 1).allSatisfy { $0.tier != .recommended })
    }

    @Test func cloudierNightScoresLower() throws {
        let clear = try predictions(cloud: 10), cloudy = try predictions(cloud: 90)
        for (a, b) in zip(clear, cloudy) { #expect(b.totalScore < a.totalScore) }
    }
}
