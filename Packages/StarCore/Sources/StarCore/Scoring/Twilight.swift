import Foundation

/// 太陽高度で決まる空の状態（薄明の区分）
public enum SkyState: String, Sendable, CaseIterable {
    /// 太陽が市民薄明の限界より上（昼間〜日没直後）
    case daylight
    /// 市民薄明（太陽高度 −6°〜0°）。空が明るく、恒星は見えない
    case civilTwilight
    /// 航海薄明（−12°〜−6°）。明るい星だけ見え始める
    case nauticalTwilight
    /// 天文薄明（−18°〜−12°）。空にまだ太陽の光が残る
    case astronomicalTwilight
    /// 夜（−18° 以下）。太陽の影響が無い
    case night

    public var label: String {
        switch self {
        case .daylight: "昼間"
        case .civilTwilight: "市民薄明"
        case .nauticalTwilight: "航海薄明"
        case .astronomicalTwilight: "天文薄明"
        case .night: "夜"
        }
    }
}

/// 太陽高度から薄明の状態と、太陽による空の明るさの残りを求める。
/// 境界の角度は天文学の標準的な定義（市民 −6°、航海 −12°、天文 −18°）。
public enum Twilight {
    /// 市民薄明の限界 [deg]。これより太陽が高いと恒星は見えない
    public static let civilLimit = -6.0
    /// 航海薄明の限界 [deg]
    public static let nauticalLimit = -12.0
    /// 天文薄明の限界 [deg]。これより下なら太陽の光は空に残らない
    public static let astronomicalLimit = -18.0

    public static func state(sunAltitude: Double) -> SkyState {
        switch sunAltitude {
        case ...astronomicalLimit: .night
        case ...nauticalLimit: .astronomicalTwilight
        case ...civilLimit: .nauticalTwilight
        case ...0: .civilTwilight
        default: .daylight
        }
    }

    /// 太陽による空の明るさの残り（0 = 夜、1 = 市民薄明より明るい）。
    /// 天文薄明の限界（−18°）から市民薄明の限界（−6°）まで直線的に増やす。
    public static func skyBrightnessFactor(sunAltitude: Double) -> Double {
        let t = (sunAltitude - astronomicalLimit) / (civilLimit - astronomicalLimit)
        return min(max(t, 0), 1)
    }

    /// 恒星を見られる程度に空が暗いか（太陽が市民薄明の限界より下）
    public static func allowsStars(sunAltitude: Double) -> Bool {
        sunAltitude <= civilLimit
    }
}
