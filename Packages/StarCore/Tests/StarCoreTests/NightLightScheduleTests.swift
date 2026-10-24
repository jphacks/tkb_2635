import Foundation
import Testing
@testable import StarCore

struct NightLightScheduleTests {
    private func tokyo(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text + "+09:00")!
    }

    private func groupsOn(_ text: String) -> [Bool] {
        (0..<NightLightSchedule.windowGroups).map { NightLightSchedule.windowsOn(group: $0, at: tokyo(text)) }
    }

    @Test(arguments: [
        ("2026-10-24T21:00:00", [true, true, true]),
        ("2026-10-24T22:30:00", [false, true, true]),
        ("2026-10-24T23:59:00", [false, false, true]),
        ("2026-10-25T02:00:00", [false, false, true]),
        ("2026-10-25T05:00:00", [false, false, false]),
        ("2026-10-24T12:00:00", [false, false, false]),
        ("2026-10-24T17:00:00", [true, true, true]),
    ])
    func windowsGoOutLateAtNight(time: String, expected: [Bool]) {
        #expect(groupsOn(time) == expected)
    }

    @Test func usesTokyoTimeEvenForUTCDates() {
        // 2026-10-24T12:00Z は東京の 21:00
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        #expect(NightLightSchedule.windowsOn(group: 0, at: date))
    }

    @Test func unknownGroupIsOff() {
        #expect(!NightLightSchedule.windowsOn(group: 3, at: tokyo("2026-10-24T21:00:00")))
    }
}
