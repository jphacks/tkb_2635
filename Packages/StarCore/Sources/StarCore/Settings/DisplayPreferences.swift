import Foundation

/// 外観の選択（設定画面）。初期値は今までの見た目と同じダーク。
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    public static let storageKey = "settings.appearance"
    public static let `default`: AppearanceMode = .dark

    public var title: String {
        switch self {
        case .system: "システムに合わせる"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }
}

/// 時刻の表記（24 時間／12 時間）
public enum TimeNotation: String, CaseIterable, Sendable {
    case hour24, hour12

    public static let storageKey = "settings.timeNotation"
    public static let `default`: TimeNotation = .hour24

    public var title: String { self == .hour24 ? "24時間表記" : "12時間表記" }

    /// 東京時間の「21:05」または「午後9:05」
    public func text(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Tokyo")!) -> String {
        // ja_JP の書式は 12 時間指定を無視して 24 時間になるので、時と分を取り出して組み立てる
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let minuteText = String(format: "%02d", minute)
        switch self {
        case .hour24: return String(format: "%02d:", hour) + minuteText
        case .hour12: return "\(hour < 12 ? "午前" : "午後")\(hour % 12 == 0 ? 12 : hour % 12):" + minuteText
        }
    }
}

/// 方位の表記（「南東」か「135°」）
public enum DirectionNotation: String, CaseIterable, Sendable {
    case name, degrees

    public static let storageKey = "settings.directionNotation"
    public static let `default`: DirectionNotation = .name

    public var title: String { self == .name ? "方角の名前（南東）" : "角度の数字（135°）" }

    /// 方位角（北 0°、時計回り）の表示
    public func text(_ azimuth: Double) -> String {
        switch self {
        case .name: Angle.directionName(azimuth)
        case .degrees: "\(Int((azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360)°"
        }
    }
}

/// 動きを少なくする設定のキー
public enum MotionPreference {
    public static let reduceKey = "settings.reduceMotion"
    public static let reduceDefault = false
}
