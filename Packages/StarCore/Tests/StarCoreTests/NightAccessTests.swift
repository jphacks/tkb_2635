import Foundation
import Testing
@testable import StarCore

private func tokyoDate(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value + "+09:00")!
}

private func spot(_ id: String) throws -> Spot {
    try #require(try SeedData.loadSpots().first { $0.id == id })
}

@Suite struct NightAccessTests {
    @Test(arguments: [
        ("2026-10-24T16:00:00", SpotAccessStatus.open),
        ("2026-10-24T16:01:00", .closed),
        ("2026-10-24T16:30:00", .closed),
        ("2026-10-26T12:00:00", .closed),
        ("2026-10-12T12:00:00", .open),
        ("2026-10-13T12:00:00", .closed),
        ("2026-09-24T12:00:00", .closed),
        ("2026-04-06T12:00:00", .open),
        ("2026-11-02T12:00:00", .open),
        ("2026-12-29T12:00:00", .closed),
        ("2027-01-03T12:00:00", .closed),
        ("2026-03-14T16:01:00", .closed),
        ("2026-03-15T17:30:00", .open),
        ("2026-06-10T18:00:00", .closed),
        ("2026-06-11T18:30:00", .open),
        ("2026-06-11T18:31:00", .closed),
        ("2026-07-31T18:30:00", .open),
        ("2026-08-01T18:00:00", .closed),
        ("2028-10-24T12:00:00", .unverified),
    ])
    func gardenSeasonHolidayAndAdmission(value: String, expected: SpotAccessStatus) throws {
        #expect(try spot("shinjuku_gyoen").accessStatus(at: tokyoDate(value)) == expected)
    }

    @Test(arguments: ["shibuya_east_plaza", "arakawa_riverside"])
    func unknownEntryIsNeverPresentedAsOpen(id: String) throws {
        let value = try spot(id)
        let date = tokyoDate("2026-10-24T21:00:00")
        let weather = Weather(gridId: "test", modelName: "fixture", forecastTime: date, fetchedAt: date,
                              cloudCover: 0, precipitation: 0, wind: 0, visibility: 10_000, missingStatus: .ok)
        let result = Recommender.evaluate(SpotContext(spot: value, scene: nil), target: .moon, date: date, weather: weather)
        #expect(result.accessStatus == .unverified)
        #expect(!result.isOpen)
        #expect(result.tier != .recommended)
        #expect(result.tier != .unavailable)
        #expect(result.dataQualityFlags.contains(.accessUnverified))
        #expect(result.recommendationReasons.first?.contains("未確認") == true)
        #expect(value.accessHoursText(at: date) == "未確認")
        #expect(value.lastVerifiedAt == nil)
    }

    @Test(arguments: ["shinjuku_central_park", "yoyogi_park", "kasai_rinkai_park"])
    func normalPublicParkIsOpenAtNight(id: String) throws {
        let value = try spot(id)
        #expect(value.accessStatus(at: tokyoDate("2026-10-24T23:00:00")) == .open)
        #expect(value.accessVerified)
    }

    @Test func seasonalHoursAreShownForSelectedDate() throws {
        let value = try spot("shinjuku_gyoen")
        #expect(value.accessHoursText(at: tokyoDate("2026-06-11T12:00:00")).contains("19:00"))
        #expect(value.accessHoursText(at: tokyoDate("2026-10-24T12:00:00")).contains("16:30"))
        #expect(value.accessHoursText(at: tokyoDate("2028-10-24T12:00:00")) == "未確認")
        let result = Recommender.evaluate(SpotContext(spot: value, scene: nil), target: .moon,
                                          date: tokyoDate("2026-06-11T20:00:00"), weather: nil)
        #expect(result.recommendationReasons.first?.contains("19:00") == true)
    }

    @Test func partialRestrictionDoesNotCloseWholePark() throws {
        let value = try spot("shinjuku_central_park")
        let date = tokyoDate("2026-10-30T21:00:00")
        #expect(value.accessNotices(at: tokyoDate("2026-10-29T21:00:00")).isEmpty)
        #expect(value.accessNotices(at: date).count == 1)
        #expect(value.accessNotices(at: tokyoDate("2026-11-13T21:00:00")).count == 1)
        #expect(value.accessNotices(at: tokyoDate("2026-11-14T21:00:00")).isEmpty)
        let result = Recommender.evaluate(SpotContext(spot: value, scene: nil), target: .moon, date: date, weather: nil)
        #expect(result.isOpen)
        #expect(result.tier != .unavailable)
        #expect(result.tier != .recommended)
        #expect(result.dataQualityFlags.contains(.areaAccessRestricted))
    }

    @Test func oldJSONStillDecodes() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try spot("kasai_rinkai_park"))) as? [String: Any])
        object.removeValue(forKey: "accessRules")
        let legacy = try JSONDecoder().decode(Spot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.accessRules == nil)
        #expect(legacy.accessStatus(at: tokyoDate("2026-10-24T21:00:00")) == .open)
    }

    @Test func overnightLastAdmissionAndBadHours() throws {
        var value = try spot("kasai_rinkai_park")
        value.accessRules = nil
        value.openingHours = OpeningHours(alwaysOpen: false, open: "18:00", close: "02:00", lastAdmission: "01:00")
        #expect(value.accessStatus(at: tokyoDate("2026-10-24T23:00:00")) == .open)
        #expect(value.accessStatus(at: tokyoDate("2026-10-25T01:00:00")) == .open)
        #expect(value.accessStatus(at: tokyoDate("2026-10-25T01:01:00")) == .closed)
        #expect(value.accessStatus(at: tokyoDate("2026-10-25T03:00:00")) == .closed)
        value.openingHours.open = "99:00"
        #expect(value.accessStatus(at: tokyoDate("2026-10-25T12:00:00")) == .unverified)
    }
}
