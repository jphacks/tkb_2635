import Foundation

public enum SpotAccessStatus: String, Sendable {
    case open, closed, unverified

    public var label: String {
        switch self {
        case .open: "入場可能（通常案内）"
        case .closed: "利用時間外・休園日"
        case .unverified: "入場可否は未確認"
        }
    }
}

/// 通常時間だけでは表せない季節・休園日・部分的な規制。古い地点データでは省略できる。
public struct SpotAccessRules: Codable, Sendable {
    public var unverified: Bool?
    public var validFrom: String?
    public var validThrough: String?
    public var seasonalHours: [SeasonalOpeningHours]?
    public var closedDates: [String]?
    public var areaRestrictions: [DatedAccessNotice]?
}

public struct SeasonalOpeningHours: Codable, Sendable {
    public var fromMonthDay: String
    public var throughMonthDay: String
    public var hours: OpeningHours

    func contains(_ monthDay: String) -> Bool {
        if fromMonthDay <= throughMonthDay {
            return fromMonthDay <= monthDay && monthDay <= throughMonthDay
        }
        return monthDay >= fromMonthDay || monthDay <= throughMonthDay
    }
}

/// 一部区域の制限は公園全体の閉園と区別し、利用者へ注意として示す。
public struct DatedAccessNotice: Codable, Sendable {
    public var from: String
    public var through: String
    public var message: String
    public var source: URL
}

public extension Spot {
    func accessStatus(at date: Date, calendar: Calendar = .tokyo) -> SpotAccessStatus {
        let day = Self.accessDay(date, calendar: calendar)
        if accessRules?.unverified == true || !accessDateIsCovered(day) { return .unverified }
        guard let hours = accessHours(at: date, calendar: calendar) else { return .unverified }
        if accessRules?.closedDates?.contains(day) == true { return .closed }
        if hours.alwaysOpen { return .open }
        guard let start = Self.accessMinutes(hours.open), let end = Self.accessMinutes(hours.close),
              start != end else { return .unverified }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let adjustedEnd = end <= start ? end + 1440 : end
        let adjustedNow = now < start && end <= start ? now + 1440 : now
        var finalAdmission = adjustedEnd
        if let value = hours.lastAdmission {
            guard let last = Self.accessMinutes(value) else { return .unverified }
            finalAdmission = last < start && end <= start ? last + 1440 : last
            guard start <= finalAdmission && finalAdmission <= adjustedEnd else { return .unverified }
        }
        return adjustedNow >= start && adjustedNow < adjustedEnd && adjustedNow <= finalAdmission ? .open : .closed
    }

    func accessHoursText(at date: Date, calendar: Calendar = .tokyo) -> String {
        if accessStatus(at: date, calendar: calendar) == .unverified { return "未確認" }
        return accessHours(at: date, calendar: calendar)?.displayText ?? "未確認"
    }

    func accessNotices(at date: Date, calendar: Calendar = .tokyo) -> [DatedAccessNotice] {
        let day = Self.accessDay(date, calendar: calendar)
        return accessRules?.areaRestrictions?.filter { $0.from <= day && day <= $0.through } ?? []
    }

    private func accessHours(at date: Date, calendar: Calendar) -> OpeningHours? {
        guard let seasons = accessRules?.seasonalHours else { return openingHours }
        let day = Self.accessDay(date, calendar: calendar)
        let matches = seasons.filter { $0.contains(String(day.suffix(5))) }
        // 重複・抜けがある季節表を推測で補わない。
        return matches.count == 1 ? matches[0].hours : nil
    }

    private func accessDateIsCovered(_ day: String) -> Bool {
        if let from = accessRules?.validFrom, day < from { return false }
        if let through = accessRules?.validThrough, day > through { return false }
        return true
    }

    private static func accessDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func accessMinutes(_ value: String?) -> Int? {
        guard let value, value.count == 5 else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
