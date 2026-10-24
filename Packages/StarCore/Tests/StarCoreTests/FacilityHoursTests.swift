import Foundation
import Testing
@testable import StarCore

@Suite struct FacilityHoursTests {
    private func tokyo(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "+09:00")!
    }

    private func hours(_ id: String) throws -> OpeningHours {
        let url = try #require(Bundle.module.url(forResource: "facility_hours", withExtension: "json", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        return try #require(JSONDecoder().decode([String: OpeningHours].self, from: data)[id])
    }

    @Test func kitteWeekdayWeekendAndHoliday() throws {
        let h = try hours("kitte_garden")
        #expect(h.isOpen(at: tokyo("2026-10-26T22:30:00")))  // 月曜
        #expect(!h.isOpen(at: tokyo("2026-10-24T22:00:00"))) // 土曜、閉園
        #expect(!h.isOpen(at: tokyo("2026-10-25T22:30:00"))) // 日曜
        #expect(!h.isOpen(at: tokyo("2026-11-03T22:30:00"))) // 文化の日
        #expect(!h.isOpen(at: tokyo("2026-10-26T10:59:00")))
    }

    @Test func tochoClosureMovesAfterHoliday() throws {
        let h = try hours("tocho_observatory")
        #expect(!h.isOpen(at: tokyo("2026-10-20T12:00:00"))) // 第3火曜
        #expect(h.isOpen(at: tokyo("2026-11-03T12:00:00")))  // 第1火曜だが祝日
        #expect(!h.isOpen(at: tokyo("2026-11-04T12:00:00"))) // 翌平日が休室
        #expect(!h.isOpen(at: tokyo("2026-12-30T12:00:00")))
        #expect(!h.isOpen(at: tokyo("2027-01-01T12:00:00"))) // 特別開室は未確認
    }

    @Test func lastAdmissionIsApplied() throws {
        let sky = try hours("shibuya_sky")
        #expect(sky.isOpen(at: tokyo("2026-10-24T21:20:00")))
        #expect(!sky.isOpen(at: tokyo("2026-10-24T21:21:00")))
        let tocho = try hours("tocho_observatory")
        #expect(tocho.isOpen(at: tokyo("2026-10-24T21:30:00")))
        #expect(!tocho.isOpen(at: tokyo("2026-10-24T21:31:00")))
    }

    @Test func unsupportedHolidayYearIsNotAssumedOpen() throws {
        #expect(!(try hours("kitte_garden")).isOpen(at: tokyo("2028-04-29T22:30:00")))
    }

    @Test func oldJSONAndOvernightHoursStillWork() throws {
        let data = Data(#"{"alwaysOpen":false,"open":"18:00","close":"02:00","lastAdmission":"01:00"}"#.utf8)
        let h = try JSONDecoder().decode(OpeningHours.self, from: data)
        #expect(h.isOpen(at: tokyo("2026-10-24T23:00:00")))
        #expect(h.isOpen(at: tokyo("2026-10-25T00:30:00")))
        #expect(!h.isOpen(at: tokyo("2026-10-25T01:01:00")))
    }

    @Test func bundledFacilityDataLoads() throws {
        let spots = try SeedData.loadSpots()
        for id in ["shibuya_sky", "tocho_observatory", "kitte_garden"] {
            let spot = try #require(spots.first { $0.id == id })
            #expect(spot.lastVerifiedAt != nil)
            #expect(spot.officialWebsite != nil)
            #expect(spot.localGlareLevel == nil)
        }
    }
}
