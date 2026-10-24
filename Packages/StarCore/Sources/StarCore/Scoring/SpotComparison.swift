import Foundation

/// 2地点の同じ天体・同じ時刻の判定を並べた結果（task.md 8-02 の比較画面）
public struct SpotComparison: Sendable {
    public let first: Side
    public let second: Side
    /// 2地点の違いを一言で表した文
    public let summary: String

    public struct Side: Sendable {
        public let spot: Spot
        public let prediction: Prediction

        /// 天体の高度が遮蔽仰角をどれだけ上回るか [度]。負なら建物などに隠れている。
        public var clearance: Double { prediction.altitude - prediction.obstructionElevation }
    }

    public init(first: (Spot, Prediction), second: (Spot, Prediction), targetName: String) {
        self.first = Side(spot: first.0, prediction: first.1)
        self.second = Side(spot: second.0, prediction: second.1)
        summary = Self.summary(self.first, self.second, targetName: targetName)
    }

    /// 2地点を同じ条件で判定して並べる
    public static func make(_ a: SpotContext, _ b: SpotContext, target: ObservationTarget, date: Date,
                            weather: (Spot) -> Weather?) -> SpotComparison {
        let pa = Recommender.evaluate(a, target: target, date: date, weather: weather(a.spot))
        let pb = Recommender.evaluate(b, target: target, date: date, weather: weather(b.spot))
        return SpotComparison(first: (a.spot, pa), second: (b.spot, pb), targetName: target.name)
    }

    static func summary(_ a: Side, _ b: Side, targetName: String) -> String {
        let pa = a.prediction, pb = b.prediction
        if pa.altitude <= 0 && pb.altitude <= 0 {
            return "指定時刻の\(targetName)は地平線の下にあり、どちらの地点からも見えません。"
        }
        switch (pa.geometricVisibility, pb.geometricVisibility) {
        case (true, true):
            return "どちらの地点からも、\(targetName)は建物に遮られず見える見込みです。"
        case (false, false):
            return "どちらの地点からも、\(targetName)は建物などに隠れる見込みです。"
        default:
            let (seen, hidden) = pa.geometricVisibility ? (a, b) : (b, a)
            let heightGain = seen.spot.observerElevation - hidden.spot.observerElevation
            // 見える側が高く、見えない側が建物に遮られているときだけ「高さのおかげ」と言える
            if heightGain > 0, !hidden.prediction.blockedByDirectionMask, hidden.prediction.altitude > 0 {
                return "同じ時刻でも、\(hidden.spot.name)では\(targetName)が建物に隠れ（遮蔽仰角 \(format(hidden.prediction.obstructionElevation))°）、"
                    + "目の高さが \(Int(heightGain.rounded())) m 高い\(seen.spot.name)では建物の上に見える見込みです。"
            }
            return "同じ時刻でも、\(seen.spot.name)では\(targetName)が見え、\(hidden.spot.name)では見えない見込みです。"
        }
    }

    private static func format(_ value: Double) -> String { String(format: "%.0f", value) }
}

public extension Collection where Element == SpotContext {
    /// spot.comparisonSpotId に書かれた比較相手。見つからなければ nil。
    func comparisonPartner(of context: SpotContext) -> SpotContext? {
        guard let id = context.spot.comparisonSpotId, id != context.id else { return nil }
        return first { $0.id == id }
    }
}
