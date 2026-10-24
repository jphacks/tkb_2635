import Foundation

/// 日付・曜日ごとの例外。省略された時刻は通常営業時間を使う。
public struct HoursOverride: Codable, Sendable {
    public var closed: Bool?
    public var unverified: Bool?
    public var open: String?
    public var close: String?
    public var lastAdmission: String?
}

/// 時刻は東京時間の HH:mm。日付の例外を曜日の例外より先に適用する。
public struct OpeningHours: Codable, Sendable {
    public var alwaysOpen: Bool
    public var open: String?
    public var close: String?
    public var lastAdmission: String?
    public var note: String?
    /// Calendarの曜日番号（1=日曜、7=土曜）。古いJSONでは省略できる。
    public var weeklyOverrides: [String: HoursOverride]?
    public var dateOverrides: [String: HoursOverride]?
    public var validFrom: String?
    public var validThrough: String?

    public init(alwaysOpen: Bool, open: String? = nil, close: String? = nil,
                lastAdmission: String? = nil, note: String? = nil) {
        self.alwaysOpen = alwaysOpen
        self.open = open
        self.close = close
        self.lastAdmission = lastAdmission
        self.note = note
    }

    /// その時刻に新たに入場できるか。最終入場・閉室・休日を反映する。
    public func isOpen(at date: Date, calendar: Calendar = .tokyo) -> Bool {
        if alwaysOpen { return true }
        let key = dateKey(date, calendar: calendar)
        if let validFrom, key < validFrom { return false }
        if let validThrough, key > validThrough { return false }
        let exception = dateOverrides?[key] ?? weeklyOverrides?[String(calendar.component(.weekday, from: date))]
        if exception?.closed == true || exception?.unverified == true { return false }
        guard let start = Self.minutes(exception?.open ?? open),
              let end = Self.minutes(exception?.close ?? close) else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        // 日をまたぐ営業時間では、開館からの経過分にそろえて比較する。
        let duration = (end - start + 1_440) % 1_440
        let elapsed = (now - start + 1_440) % 1_440
        guard duration > 0, elapsed < duration else { return false }
        if let last = Self.minutes(exception?.lastAdmission ?? lastAdmission) {
            let lastElapsed = (last - start + 1_440) % 1_440
            if elapsed > lastElapsed { return false }
        }
        return true
    }

    public var displayText: String {
        if alwaysOpen { return "常時開放" }
        var value = "\(open ?? "?")〜\(close ?? "?")"
        if let lastAdmission { value += "（最終入場 \(lastAdmission)）" }
        if weeklyOverrides != nil || dateOverrides != nil { value += " ※曜日・祝日・休室日の例外あり" }
        return value
    }

    private func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func minutes(_ value: String?) -> Int? {
        guard let parts = value?.split(separator: ":"), parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return h * 60 + m
    }
}
