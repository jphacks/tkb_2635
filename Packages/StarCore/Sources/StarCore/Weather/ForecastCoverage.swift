import Foundation

/// 指定した日時が、天気予報の範囲に入っているか
public enum ForecastCoverage: Sendable {
    case inRange
    /// 予報の始まりより前（過去の日時）
    case beforeRange
    /// 予報の終わりより後（16日より先など）
    case afterRange

    public var isOutOfRange: Bool { self != .inRange }

    /// 画面に出す注意書き。範囲内なら nil。
    public var message: String? {
        switch self {
        case .inRange: nil
        case .beforeRange: "予報の範囲外：過去の日時の天気予報はありません。天気は仮の値で計算しています。"
        case .afterRange: "予報の範囲外：天気予報は今日から\(OpenMeteoClient.forecastDays)日先までです。天気は仮の値で計算しています。"
        }
    }
}

extension OpenMeteoClient {
    /// 指定時刻が予報の範囲に入っているか。
    /// 予報を取得できていればその時刻の範囲（前後 90 分の余裕つき）で、
    /// 取得できていなければ今日の 0 時から forecastDays 日先までで判定する。
    public static func coverage(of samples: [Weather], at date: Date, now: Date = Date()) -> ForecastCoverage {
        let start: Date
        let end: Date
        if let first = samples.map(\.forecastTime).min(), let last = samples.map(\.forecastTime).max() {
            start = first.addingTimeInterval(-matchTolerance)
            end = last.addingTimeInterval(matchTolerance)
        } else {
            let calendar = Calendar.tokyo
            start = calendar.startOfDay(for: now)
            end = calendar.date(byAdding: .day, value: forecastDays, to: start)!
        }
        if date < start { return .beforeRange }
        if date > end { return .afterRange }
        return .inRange
    }
}
