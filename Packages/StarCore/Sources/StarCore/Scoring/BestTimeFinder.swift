import Foundation

/// 天体から逆に、その夜でいちばんおすすめの地点と時刻を探す（7-05）
public enum BestTimeFinder {
    /// 探す刻み [分]。ObservingNight の刻みより粗くして、計算を軽くする
    public static let stepMinutes = 60

    public struct Best: Sendable {
        public var prediction: Prediction
        public var date: Date
    }

    /// 夜（18:00〜翌 6:00）の中で、推薦の段階が良く、スコアが高い 地点×時刻 を返す。
    /// 見える見込みがまったく無い夜は nil。weather は地点と時刻ごとの天気（無ければ nil）。
    public static func find(contexts: [SpotContext], target: ObservationTarget, night: ObservingNight,
                            weather: (Spot, Date) -> Weather? = { _, _ in nil }) -> Best? {
        var best: Best?
        var date = night.start
        while date <= night.end {
            for context in contexts {
                let p = Recommender.evaluate(context, target: target, date: date, weather: weather(context.spot, date))
                guard p.tier == .recommended || p.tier == .needsCheck, p.geometricVisibility else { continue }
                if let current = best?.prediction, (current.tier, -current.totalScore) <= (p.tier, -p.totalScore) { continue }
                best = Best(prediction: p, date: date)
            }
            date = date.addingTimeInterval(Double(stepMinutes * 60))
        }
        return best
    }
}
