import Foundation

/// アプリの効果音（SE）。音のファイルは App/Resources/Sounds/ にあり、scripts/generate_se.py で作る。
/// 場面ごとの音量と、続けて鳴らせる間隔をここにまとめる（音の仕様書の「音響設定」）。
public enum SoundEffect: String, CaseIterable, Sendable {
    case launch
    case mapOpen
    case pinTap
    case bodySelect
    case timeTick
    case spotFound
    case mapGesture

    /// 拡張子を除いたファイル名
    public var fileName: String {
        switch self {
        case .launch: "se_launch"
        case .mapOpen: "se_map_open"
        case .pinTap: "se_pin_tap"
        case .bodySelect: "se_body_select"
        case .timeTick: "se_time_tick"
        case .spotFound: "se_spot_found"
        case .mapGesture: "se_map_gesture"
        }
    }

    /// 効果音全体に掛ける音量。BGM の上で目立ちすぎないよう、仕様書の目安の半分にする
    public static let masterVolume: Float = 0.5

    /// 実際に鳴らす音量 [0, 1]（場面ごとの音量 × 全体の音量）
    public var playbackVolume: Float { volume * Self.masterVolume }

    /// 場面ごとの音量 [0, 1]（仕様書の「音量目安」）。音のファイルは音圧をそろえてあるので、ここで大きさの差を付ける
    public var volume: Float {
        switch self {
        case .launch: 0.45
        case .mapOpen: 0.40
        case .pinTap: 0.35
        case .bodySelect: 0.40
        case .timeTick: 0.15
        case .spotFound: 0.50
        case .mapGesture: 0.15
        }
    }

    /// 前に鳴らしてから、次に鳴らせるまでの最短の間隔 [秒]。
    /// スライダーや 3D 操作は続けて動かすので、鳴りすぎてうるさくならないよう間を空ける
    public var minimumInterval: TimeInterval {
        switch self {
        case .timeTick: 0.08
        case .mapGesture: 0.6
        case .spotFound: 3
        case .launch, .mapOpen: 1
        case .pinTap, .bodySelect: 0.15
        }
    }
}

/// 効果音を続けて鳴らしすぎないように、音ごとに前に鳴らした時刻を覚える
public struct SoundThrottle: Sendable {
    private var lastPlayed: [SoundEffect: Date] = [:]

    public init() {}

    /// 今鳴らしてよいか。よければ、鳴らした時刻として覚える
    public mutating func allows(_ effect: SoundEffect, at now: Date = Date()) -> Bool {
        if let last = lastPlayed[effect], now.timeIntervalSince(last) < effect.minimumInterval {
            return false
        }
        lastPlayed[effect] = now
        return true
    }
}

public extension SoundEffect {
    /// 「観測できる場所を発見」の音を鳴らすか。実際に推薦の条件を満たしたとき（推薦になった瞬間）だけ鳴らす
    static func announcesSpotFound(previous: RecommendationTier?, current: RecommendationTier) -> Bool {
        current == .recommended && previous != .recommended
    }
}
