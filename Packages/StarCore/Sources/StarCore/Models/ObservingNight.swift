import Foundation

/// 時刻スライダーで動かす「その夜」の範囲（18:00〜翌 6:00、東京時間）
public struct ObservingNight: Sendable, Equatable {
    public static let startHour = 18
    public static let endHour = 6
    /// スライダーの刻み [分]
    public static let stepMinutes = 15

    public let start: Date
    public let end: Date

    /// date を含む夜。正午より前なら前の日の夜、正午以降ならその日の夜とする。
    public init(containing date: Date, calendar: Calendar = .tokyo) {
        let hour = calendar.component(.hour, from: date)
        let day = hour < 12 ? calendar.date(byAdding: .day, value: -1, to: date)! : date
        start = calendar.date(bySettingHour: Self.startHour, minute: 0, second: 0, of: day)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        end = calendar.date(bySettingHour: Self.endHour, minute: 0, second: 0, of: nextDay)!
    }

    /// 最後の刻みの番号（start が 0、end が stepCount）
    public var stepCount: Int {
        Int((end.timeIntervalSince(start) / Double(Self.stepMinutes * 60)).rounded())
    }

    public func date(atStep step: Int) -> Date {
        start.addingTimeInterval(Double(min(max(step, 0), stepCount) * Self.stepMinutes * 60))
    }

    /// date に一番近い刻み。夜の範囲の外なら端の刻みにする。
    public func step(for date: Date) -> Int {
        let raw = (date.timeIntervalSince(start) / Double(Self.stepMinutes * 60)).rounded()
        return min(max(Int(raw), 0), stepCount)
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}
