import Foundation

/// 出・南中・入りの種類
public enum RiseSetEventKind: Sendable, Equatable {
    case rise
    case transit
    case set

    public var label: String {
        switch self {
        case .rise: "出"
        case .transit: "南中"
        case .set: "入り"
        }
    }
}

public struct RiseSetEvent: Sendable, Equatable {
    public var kind: RiseSetEventKind
    public var date: Date
}

/// その夜（12:00 JST 〜 翌 12:00 JST）の天体の出・南中・入り
public struct RiseSetTimes: Sendable, Equatable {
    public enum Visibility: Sendable, Equatable {
        /// 夜の間に地平線を横切る
        case crosses
        /// 夜の間ずっと地平線の上（周極星など）
        case alwaysUp
        /// 夜の間ずっと地平線の下
        case neverUp
    }

    public var nightStart: Date
    public var nightEnd: Date
    public var visibility: Visibility
    /// 最初に昇る時刻。夜の間に昇らなければ nil
    public var rise: Date?
    /// 最初に沈む時刻。夜の間に沈まなければ nil
    public var set: Date?
    /// 一番高くなる時刻。夜の端で高度が最大になる（極大が夜の中に無い）ときは nil
    public var transit: Date?
    /// 南中時の高度 [度]
    public var transitAltitude: Double?

    /// 時刻順に並べた出・南中・入り。昇らない夜の南中（地平線の下）は含めない
    public var events: [RiseSetEvent] {
        var list: [RiseSetEvent] = []
        if let rise { list.append(RiseSetEvent(kind: .rise, date: rise)) }
        if let transit, visibility != .neverUp { list.append(RiseSetEvent(kind: .transit, date: transit)) }
        if let set { list.append(RiseSetEvent(kind: .set, date: set)) }
        return list.sorted { $0.date < $1.date }
    }
}

/// 高度の時間変化から、出・南中・入りの時刻を探す。
/// 粗い刻みで高度の符号変化と極大を見つけ、二分法・三分探索で詰める。
/// 高度 0° は大気差込みの `HorizontalCoord.altitude`（天体の中心）で判定する。
public enum RiseSet {
    /// 粗い探索の刻み
    public static let coarseStep: TimeInterval = 10 * 60
    /// 詰めたあとの時刻の誤差の上限
    public static let tolerance: TimeInterval = 1
    /// 「その夜」の始まり（JST の時）
    static let nightStartHour = 12
    static let nightLength: TimeInterval = 24 * 3600

    /// `date` を含む夜の始まり（12:00 JST）。0〜11 時台は前の日の 12:00 になる
    public static func nightStart(containing date: Date) -> Date {
        let calendar = Calendar.tokyo
        let dayStart = calendar.startOfDay(for: date)
        let noon = calendar.date(byAdding: .hour, value: nightStartHour, to: dayStart)!
        return date < noon ? calendar.date(byAdding: .day, value: -1, to: noon)! : noon
    }

    /// 選んでいる天体の、`date` を含む夜の出・南中・入り
    public static func times(for target: ObservationTarget, date: Date, latitude: Double, longitude: Double) -> RiseSetTimes {
        let position: (Date) -> HorizontalCoord = switch target {
        case .moon: { Astro.moon(date: $0, latitude: latitude, longitude: longitude).position }
        case .star(let star): { Astro.star(star, date: $0, latitude: latitude, longitude: longitude) }
        }
        return times(date: date, position: position)
    }

    /// 位置を返す関数から、`date` を含む夜の出・南中・入りを求める
    public static func times(date: Date, position: (Date) -> HorizontalCoord) -> RiseSetTimes {
        let start = nightStart(containing: date)
        return times(from: start, to: start.addingTimeInterval(nightLength), position: position)
    }

    /// 区間 [start, end] の中で出・南中・入りを求める
    public static func times(from start: Date, to end: Date, position: (Date) -> HorizontalCoord) -> RiseSetTimes {
        let altitude: (Date) -> Double = { position($0).altitude }
        let samples = stride(from: 0, through: end.timeIntervalSince(start), by: coarseStep)
            .map { start.addingTimeInterval($0) }
        let altitudes = samples.map(altitude)

        var rise: Date?
        var set: Date?
        for i in 1..<samples.count {
            let (a, b) = (altitudes[i - 1], altitudes[i])
            if rise == nil, a <= 0, b > 0 {
                rise = bisect(samples[i - 1], samples[i], altitude: altitude, rising: true)
            } else if set == nil, a > 0, b <= 0 {
                set = bisect(samples[i - 1], samples[i], altitude: altitude, rising: false)
            }
        }

        let visibility: RiseSetTimes.Visibility =
            if rise != nil || set != nil { .crosses }
            else if altitudes[0] > 0 { .alwaysUp }
            else { .neverUp }

        let culmination = transit(samples: samples, altitudes: altitudes, altitude: altitude)
        return RiseSetTimes(nightStart: start, nightEnd: end, visibility: visibility,
                            rise: rise, set: set,
                            transit: culmination?.date, transitAltitude: culmination?.altitude)
    }

    /// 高度の符号が変わる時刻を二分法で詰める。`rising` は低→高の向き
    static func bisect(_ lower: Date, _ upper: Date, altitude: (Date) -> Double, rising: Bool) -> Date {
        var lo = lower, hi = upper
        while hi.timeIntervalSince(lo) > tolerance {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            if (altitude(mid) > 0) == rising { hi = mid } else { lo = mid }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }

    /// 夜の中の極大のうち一番高いものを、三分探索で詰める。極大が夜の端にしか無ければ nil
    static func transit(samples: [Date], altitudes: [Double], altitude: (Date) -> Double) -> (date: Date, altitude: Double)? {
        guard samples.count >= 3 else { return nil }
        var best: (date: Date, altitude: Double)?
        for i in 1..<(samples.count - 1)
        where altitudes[i] >= altitudes[i - 1] && altitudes[i] > altitudes[i + 1] {
            let date = ternaryMax(samples[i - 1], samples[i + 1], altitude: altitude)
            let alt = altitude(date)
            if best == nil || alt > best!.altitude { best = (date, alt) }
        }
        return best
    }

    static func ternaryMax(_ lower: Date, _ upper: Date, altitude: (Date) -> Double) -> Date {
        var lo = lower, hi = upper
        while hi.timeIntervalSince(lo) > tolerance {
            let third = hi.timeIntervalSince(lo) / 3
            let m1 = lo.addingTimeInterval(third), m2 = hi.addingTimeInterval(-third)
            if altitude(m1) < altitude(m2) { lo = m1 } else { hi = m2 }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }
}
