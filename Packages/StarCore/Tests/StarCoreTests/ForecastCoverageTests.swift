import Foundation
import Testing
@testable import StarCore

@Suite struct ForecastCoverageTests {
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private func fixtureSamples() throws -> [Weather] {
        let url = try #require(Bundle.module.url(forResource: "open_meteo_sample", withExtension: "json", subdirectory: "Fixtures"))
        return try OpenMeteoClient.decode(Data(contentsOf: url), gridId: "test", fetchedAt: Date())
    }

    @Test func requestsSixteenDays() {
        #expect(OpenMeteoClient.forecastDays == 16)
    }

    @Test func coverageFollowsFetchedSamples() throws {
        let samples = try fixtureSamples()
        let first = try #require(samples.first).forecastTime
        let last = try #require(samples.last).forecastTime
        #expect(OpenMeteoClient.coverage(of: samples, at: first) == .inRange)
        #expect(OpenMeteoClient.coverage(of: samples, at: last.addingTimeInterval(hour)) == .inRange)
        #expect(OpenMeteoClient.coverage(of: samples, at: last.addingTimeInterval(3 * hour)) == .afterRange)
        #expect(OpenMeteoClient.coverage(of: samples, at: first.addingTimeInterval(-day)) == .beforeRange)
    }

    @Test func coverageWithoutSamplesUsesForecastDays() {
        // 2026-10-24 21:00 JST
        let now = Date(timeIntervalSince1970: 1_792_843_200)
        #expect(OpenMeteoClient.coverage(of: [], at: now.addingTimeInterval(15 * day), now: now) == .inRange)
        #expect(OpenMeteoClient.coverage(of: [], at: now.addingTimeInterval(17 * day), now: now) == .afterRange)
        #expect(OpenMeteoClient.coverage(of: [], at: now.addingTimeInterval(-2 * day), now: now) == .beforeRange)
    }

    @Test func messagesExplainOutOfRange() throws {
        #expect(ForecastCoverage.inRange.message == nil)
        #expect(!ForecastCoverage.inRange.isOutOfRange)
        let after = try #require(ForecastCoverage.afterRange.message)
        #expect(after.contains("予報の範囲外"))
        #expect(after.contains("16日先"))
        #expect(try #require(ForecastCoverage.beforeRange.message).contains("予報の範囲外"))
        #expect(DataQualityFlag.weatherOutOfRange.message.contains("16日先"))
    }

    @Test func evaluateFlagsOutOfRangeWeather() throws {
        let context = try #require(try SeedData.loadContexts().first)
        let date = Date(timeIntervalSince1970: 1_792_843_200)
        let outOfRange = Recommender.evaluate(context, target: .moon, date: date, weather: nil, forecastCoverage: .afterRange)
        let missing = Recommender.evaluate(context, target: .moon, date: date, weather: nil)
        #expect(outOfRange.dataQualityFlags.contains(.weatherOutOfRange))
        #expect(!outOfRange.dataQualityFlags.contains(.weatherMissing))
        #expect(outOfRange.recommendationReasons.contains("指定時刻は天気予報の範囲外のため、天気は仮の値で計算しています。"))
        #expect(outOfRange.tier != .recommended)
        #expect(outOfRange.totalScore == missing.totalScore)
        #expect(missing.dataQualityFlags.contains(.weatherMissing))
    }
}
