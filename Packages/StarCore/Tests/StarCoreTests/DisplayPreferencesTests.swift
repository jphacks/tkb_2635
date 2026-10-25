import Foundation
import Testing
@testable import StarCore

@Suite struct DisplayPreferencesTests {
    @Test func defaultsKeepTheCurrentDarkLook() {
        #expect(AppearanceMode.default == .dark)
        #expect(TimeNotation.default == .hour24)
        #expect(DirectionNotation.default == .name)
        #expect(MotionPreference.reduceDefault == false)
    }

    @Test func unknownStoredValueFallsBackToDefault() {
        #expect(AppearanceMode(rawValue: "sepia") ?? .default == .dark)
    }

    @Test func timeIsShownInTokyoWithBothNotations() {
        // 2026-10-25 12:05 UTC = 東京 21:05
        let date = ISO8601DateFormatter().date(from: "2026-10-25T12:05:00Z")!
        #expect(TimeNotation.hour24.text(date) == "21:05")
        let twelve = TimeNotation.hour12.text(date)
        #expect(twelve.contains("9:05"))
        #expect(twelve.contains("午後"))
    }

    @Test func directionIsShownAsNameOrDegrees() {
        #expect(DirectionNotation.degrees.text(135.2) == "135°")
        #expect(DirectionNotation.degrees.text(-10) == "350°")
        #expect(DirectionNotation.degrees.text(359.8) == "0°")
        #expect(DirectionNotation.name.text(180) == Angle.directionName(180))
    }
}
