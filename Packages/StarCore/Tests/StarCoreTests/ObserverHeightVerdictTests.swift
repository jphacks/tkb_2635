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
        // 2026-10-29 20:30 JST（4-13 で確かめたデモ日時）: 地上は渋谷ストリームの塔に隠れ、SHIBUYA SKY は見える
        // 10-25 21:00 は 4-13（PR #92）で判定を実形状に合わせた結果、地上でも見える判定になった
        let ground = try verdict("shibuya_east_plaza", "2026-10-29T11:30:00Z")
        let sky = try verdict("shibuya_sky", "2026-10-29T11:30:00Z")
        #expect(!ground.geometricVisibility)
        #expect(sky.geometricVisibility)
        #expect(abs(ground.altitude - sky.altitude) < 0.1)
        #expect(sky.obstructionElevation < ground.obstructionElevation)
    }

    @Test func groundIsBlockedAtHighAltitudeToo() throws {
        // 2026-10-24 21:00 JST: 月は高度約58°でも、地上は渋谷ストリームの塔（遮蔽仰角約65°）に隠れる
        #expect(try !verdict("shibuya_east_plaza", "2026-10-24T12:00:00Z").geometricVisibility)
        #expect(try verdict("shibuya_sky", "2026-10-24T12:00:00Z").geometricVisibility)
    }
}
