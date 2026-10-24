import Foundation
import Testing
@testable import StarCore

@Suite struct SpotComparisonTests {
    let contexts = try! SeedData.loadContexts()

    private func pair(_ a: String, _ b: String) -> (SpotContext, SpotContext) {
        (contexts.first { $0.id == a }!, contexts.first { $0.id == b }!)
    }

    @Test func partnersComeFromData() {
        let ground = contexts.first { $0.id == "shibuya_east_plaza" }!
        #expect(contexts.comparisonPartner(of: ground)?.id == "shibuya_sky")
        // 比較相手の書かれていない地点は nil
        let sky = contexts.first { $0.id == "shibuya_sky" }!
        #expect(contexts.comparisonPartner(of: sky) == nil)
        // 書かれた ID がすべて実在する
        for context in contexts where context.spot.comparisonSpotId != nil {
            #expect(contexts.comparisonPartner(of: context) != nil, "\(context.id) の比較相手が見つからない")
        }
    }

    @Test func summaryExplainsHeightWhenOnlyHigherSpotSees() {
        let (ground, sky) = pair("shibuya_east_plaza", "shibuya_sky")
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let base = SpotComparison.make(ground, sky, target: .moon, date: date) { _ in nil }
        var hidden = base.first.prediction
        hidden.altitude = 20
        hidden.obstructionElevation = 35
        hidden.geometricVisibility = false
        hidden.blockedByDirectionMask = false
        var seen = base.second.prediction
        seen.altitude = 20
        seen.obstructionElevation = 0
        seen.geometricVisibility = true

        let comparison = SpotComparison(first: (ground.spot, hidden), second: (sky.spot, seen), targetName: "月")
        #expect(comparison.summary.contains("遮蔽仰角 35°"))
        #expect(comparison.summary.contains("229 m 高いSHIBUYA SKY"))
        #expect(comparison.first.clearance == -15)

        // 並びが逆でも、見える側・見えない側を正しく言う
        let reversed = SpotComparison(first: (sky.spot, seen), second: (ground.spot, hidden), targetName: "月")
        #expect(reversed.summary == comparison.summary)
    }

    @Test func summaryForBothOrNeither() {
        let (ground, sky) = pair("shibuya_east_plaza", "shibuya_sky")
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let base = SpotComparison.make(ground, sky, target: .moon, date: date) { _ in nil }
        var a = base.first.prediction, b = base.second.prediction
        a.altitude = 30; b.altitude = 30
        a.geometricVisibility = true; b.geometricVisibility = true
        #expect(SpotComparison(first: (ground.spot, a), second: (sky.spot, b), targetName: "月").summary.contains("どちらの地点からも"))
        a.altitude = -5; b.altitude = -5
        a.geometricVisibility = false; b.geometricVisibility = false
        #expect(SpotComparison(first: (ground.spot, a), second: (sky.spot, b), targetName: "月").summary.contains("地平線の下"))
    }

    /// 実データで「地上では隠れ、SHIBUYA SKY では見える」月の時刻が、今後1か月の夜にあること
    @Test func realDataHasMomentWhereOnlyObservatorySeesMoon() {
        let (ground, sky) = pair("shibuya_east_plaza", "shibuya_sky")
        let start = ISO8601DateFormatter().date(from: "2026-10-24T09:00:00Z")!
        let found = (0..<(30 * 24 * 4)).lazy
            .map { start.addingTimeInterval(Double($0) * 900) }
            .first { date in
                let c = SpotComparison.make(ground, sky, target: .moon, date: date) { _ in nil }
                return !c.first.prediction.geometricVisibility && c.first.prediction.altitude > 0
                    && c.second.prediction.geometricVisibility
            }
        #expect(found != nil)
    }
}
