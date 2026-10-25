import Foundation
import Testing
@testable import StarCore

@Suite struct WeatherCacheTests {
    private let now = Date(timeIntervalSince1970: 1_792_843_200)

    private func sample(_ gridId: String) -> Weather {
        Weather(gridId: gridId, modelName: "test", forecastTime: now, fetchedAt: now,
                cloudCover: 10, precipitation: 0, wind: 5, visibility: 20_000, missingStatus: .ok)
    }

    @Test func emptyCacheFetchesEveryGrid() {
        let cache = WeatherCache()
        #expect(cache.gridsToFetch(["a", "b"], now: now) == ["a", "b"])
        #expect(cache.samples(for: "a") == nil)
    }

    @Test func freshGridIsNotFetchedAgain() {
        var cache = WeatherCache()
        cache.store([sample("a")], for: "a", fetchedAt: now)
        let later = now.addingTimeInterval(WeatherCache.freshFor - 1)
        #expect(cache.isFresh("a", now: later))
        #expect(cache.gridsToFetch(["a", "b"], now: later) == ["b"])
        #expect(cache.samples(for: "a")?.count == 1)
    }

    @Test func staleGridIsFetchedAgainButKeepsSamples() {
        var cache = WeatherCache()
        cache.store([sample("a")], for: "a", fetchedAt: now)
        let later = now.addingTimeInterval(WeatherCache.freshFor)
        #expect(!cache.isFresh("a", now: later))
        #expect(cache.gridsToFetch(["a"], now: later) == ["a"])
        #expect(cache.samples(for: "a") != nil)
    }

    @Test func removedGridIsFetchedAgain() {
        var cache = WeatherCache()
        cache.store([sample("a")], for: "a", fetchedAt: now)
        cache.remove("a")
        #expect(cache.samples(for: "a") == nil)
        #expect(cache.gridsToFetch(["a"], now: now) == ["a"])
    }
}
