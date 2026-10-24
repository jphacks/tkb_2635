import Foundation
import Testing
@testable import StarCore

@Suite struct ObservingNightTests {
    private func tokyo(_ text: String) -> Date {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @Test func eveningBelongsToThatNight() {
        let night = ObservingNight(containing: tokyo("2026-10-24 21:00"))
        #expect(night.start == tokyo("2026-10-24 18:00"))
        #expect(night.end == tokyo("2026-10-25 06:00"))
        // 12時間を15分刻み
        #expect(night.stepCount == 48)
    }

    @Test func earlyMorningBelongsToPreviousNight() {
        let night = ObservingNight(containing: tokyo("2026-10-25 02:00"))
        #expect(night.start == tokyo("2026-10-24 18:00"))
        #expect(night.contains(tokyo("2026-10-25 02:00")))
    }

    @Test func stepsRoundTrip() {
        let night = ObservingNight(containing: tokyo("2026-10-24 21:00"))
        #expect(night.step(for: tokyo("2026-10-24 21:00")) == 12)
        #expect(night.date(atStep: 12) == tokyo("2026-10-24 21:00"))
        // 刻みの途中は一番近い刻みに丸める
        #expect(night.step(for: tokyo("2026-10-24 21:08")) == 13)
    }

    @Test func outsideTheNightClampsToEdges() {
        let night = ObservingNight(containing: tokyo("2026-10-24 15:00"))
        #expect(night.start == tokyo("2026-10-24 18:00"))
        #expect(!night.contains(tokyo("2026-10-24 15:00")))
        #expect(night.step(for: tokyo("2026-10-24 15:00")) == 0)
        #expect(night.date(atStep: 999) == night.end)
    }
}
