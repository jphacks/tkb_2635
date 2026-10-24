import Foundation
import Testing
@testable import StarCore

private func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// 渋谷駅東口
private let latitude = 35.658
private let longitude = 139.702816
/// 2026-10-24 21:00 JST（その夜は 10-24 12:00 〜 10-25 12:00 JST）
private let night = utc("2026-10-24T12:00:00Z")
/// skyfield と比べるときの許容差
private let referenceTolerance: TimeInterval = 3 * 60

/// 参照値は scripts/rise_set_reference.py（skyfield 1.55・DE421）で計算した。
/// 出入りは天体の中心が幾何高度 -34′（大気差ぶん）を通る時刻、南中は子午線の上方通過。
@Suite struct RiseSetTests {
    /// skyfield: 出 2026-10-24T06:34:28Z（15:34 JST）、南中 12:59:47Z（21:59 JST）、入り 19:35:32Z（10-25 04:35 JST）。
    /// こちらの南中は「高度が一番高い時刻」。skyfield の searchlib.find_maxima で同じものを探すと 13:02:19Z
    @Test func moonMatchesSkyfield() throws {
        let times = RiseSet.times(for: .moon, date: night, latitude: latitude, longitude: longitude)
        #expect(times.visibility == .crosses)
        let rise = try #require(times.rise)
        let transit = try #require(times.transit)
        let set = try #require(times.set)
        #expect(abs(rise.timeIntervalSince(utc("2026-10-24T06:34:28Z"))) < referenceTolerance)
        #expect(abs(transit.timeIntervalSince(utc("2026-10-24T12:59:47Z"))) < referenceTolerance)
        #expect(abs(transit.timeIntervalSince(utc("2026-10-24T13:02:19Z"))) < 60)
        #expect(abs(set.timeIntervalSince(utc("2026-10-24T19:35:32Z"))) < referenceTolerance)
        #expect(times.events.map(\.kind) == [.rise, .transit, .set])
    }

    /// 0〜11 時台は前の日の 12:00 からの夜として扱う
    @Test func earlyMorningBelongsToPreviousNight() {
        let midnight = utc("2026-10-24T16:30:00Z")  // 10-25 01:30 JST
        #expect(RiseSet.nightStart(containing: midnight) == night.addingTimeInterval(-9 * 3600))
        #expect(RiseSet.nightStart(containing: night) == night.addingTimeInterval(-9 * 3600))
        let afterNoon = utc("2026-10-25T03:00:00Z")  // 10-25 12:00 JST
        #expect(RiseSet.nightStart(containing: afterNoon) == afterNoon)
    }

    @Test func polarisNeverSets() throws {
        let polaris = try #require(StarCatalog.star(id: "polaris"))
        let times = RiseSet.times(for: .star(polaris), date: night, latitude: latitude, longitude: longitude)
        #expect(times.visibility == .alwaysUp)
        #expect(times.rise == nil)
        #expect(times.set == nil)
    }

    /// skyfield: 出 2026-10-24T14:02:27Z（23:02 JST）、南中 19:14:44Z（10-25 04:14 JST）。
    /// StarCatalog は歳差を入れていない（3-06）ので、許容差は 5 分にする
    @Test func siriusRisesBeforeMidnight() throws {
        let sirius = try #require(StarCatalog.star(id: "sirius"))
        let times = RiseSet.times(for: .star(sirius), date: night, latitude: latitude, longitude: longitude)
        let rise = try #require(times.rise)
        let transit = try #require(times.transit)
        #expect(abs(rise.timeIntervalSince(utc("2026-10-24T14:02:27Z"))) < 5 * 60)
        #expect(abs(transit.timeIntervalSince(utc("2026-10-24T19:14:44Z"))) < 5 * 60)
        #expect(try #require(times.transitAltitude) > 30)
    }

    @Test func neverRisingObjectHasNoEvents() {
        let times = RiseSet.times(date: night) { _ in HorizontalCoord(altitude: -20, azimuth: 0) }
        #expect(times.visibility == .neverUp)
        #expect(times.events.isEmpty)
    }

    /// 刻み（10 分）の途中にある出・入り・極大を 1 分以内に詰められる
    @Test func refinementIsWithinOneMinute() throws {
        let start = RiseSet.nightStart(containing: night)
        let peak = start.addingTimeInterval(9 * 3600 + 4 * 60 + 37)
        // 極大 30°、極大の ±3 時間で 0° を通る放物線
        let times = RiseSet.times(date: night) { date in
            let hours = date.timeIntervalSince(peak) / 3600
            return HorizontalCoord(altitude: 30 - 30 * hours * hours / 9, azimuth: 180)
        }
        let rise = try #require(times.rise)
        let transit = try #require(times.transit)
        let set = try #require(times.set)
        #expect(abs(rise.timeIntervalSince(peak.addingTimeInterval(-3 * 3600))) < 60)
        #expect(abs(transit.timeIntervalSince(peak)) < 60)
        #expect(abs(set.timeIntervalSince(peak.addingTimeInterval(3 * 3600))) < 60)
        #expect(abs(try #require(times.transitAltitude) - 30) < 0.01)
    }
}
