import Foundation
import Testing
@testable import StarCore

/// 9-02: 観測者の高さが違うと、同じ時刻の月の判定が変わる（渋谷の地上と SHIBUYA SKY）
@Suite struct ObserverHeightVerdictTests {
    private func verdict(_ id: String, _ iso: String) throws -> Prediction {
        let context = try #require(try SeedData.loadContexts().first { $0.id == id })
        return Recommender.evaluate(context, target: .moon, date: ISO8601DateFormatter().date(from: iso)!, weather: nil)
    }

    @Test func groundIsBlockedButObservatorySeesMoon() throws {
        // 2026-10-25 19:00 JST: 月は高度約35°、地上の建物（約34°）に隠れる
        let ground = try verdict("shibuya_east_plaza", "2026-10-25T10:00:00Z")
        let sky = try verdict("shibuya_sky", "2026-10-25T10:00:00Z")
        #expect(!ground.geometricVisibility)
        #expect(sky.geometricVisibility)
        #expect(abs(ground.altitude - sky.altitude) < 0.1)
        #expect(sky.obstructionElevation < ground.obstructionElevation)
    }

    @Test func groundIsBlockedAtHighAltitudeToo() throws {
        // 21:00 JST: 月は高度約57°でも、地上は約68°の遮蔽に隠れる
        #expect(try !verdict("shibuya_east_plaza", "2026-10-25T12:00:00Z").geometricVisibility)
        #expect(try verdict("shibuya_sky", "2026-10-25T12:00:00Z").geometricVisibility)
    }
}
