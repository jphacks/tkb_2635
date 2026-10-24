import Foundation

/// 建物の用途をまとめたグループ（周辺の参考表示用）
public enum LandUseGroup: String, CaseIterable, Sendable {
    case commercial
    case residential
    case publicCultural
    case industrial
    case otherOrUnknown

    /// 割合の一覧に出す短い名前
    public var label: String {
        switch self {
        case .commercial: "商業・業務"
        case .residential: "住宅"
        case .publicCultural: "公共・文化"
        case .industrial: "工場・倉庫"
        case .otherOrUnknown: "その他・不明"
        }
    }

    /// 「〜が多い」の文に入れる名前
    public var phrase: String {
        switch self {
        case .commercial: "商業・業務施設"
        case .residential: "住宅"
        case .publicCultural: "公共・文化施設"
        case .industrial: "工場・倉庫"
        case .otherOrUnknown: "用途不明の建物"
        }
    }

    /// `Building.usage` の文字列 → グループの対応表。
    /// PLATEAU の建物用途コードリスト（渋谷シーン）と、手作りシーン（西新宿）の表記を載せる。
    /// 表に無い文字列と nil は「その他・不明」にする。
    static let usageTable: [String: LandUseGroup] = [
        // PLATEAU
        "業務施設": .commercial,
        "商業施設": .commercial,
        "宿泊施設": .commercial,
        "商業系複合施設": .commercial,
        "住宅": .residential,
        "共同住宅": .residential,
        "店舗等併用住宅": .residential,
        "店舗等併用共同住宅": .residential,
        "作業所併用住宅": .residential,
        "官公庁施設": .publicCultural,
        "文教厚生施設": .publicCultural,
        "運輸倉庫施設": .industrial,
        "工場": .industrial,
        "供給処理施設": .industrial,
        "農林漁業用施設": .otherOrUnknown,
        "防衛施設": .otherOrUnknown,
        "その他": .otherOrUnknown,
        "不明": .otherOrUnknown,
        // 手作りシーン（西新宿）
        "オフィス": .commercial,
        "ホテル": .commercial,
        "オフィス・ホテル": .commercial,
        "官公庁": .publicCultural,
    ]

    public init(usage: String?) {
        self = usage.flatMap { Self.usageTable[$0] } ?? .otherOrUnknown
    }
}

/// 1グループの棟数と割合
public struct LandUseShare: Sendable, Equatable {
    public let group: LandUseGroup
    public let count: Int
    /// 半径内の全建物に対する割合（0〜1）
    public let fraction: Double

    public var percent: Int { Int((fraction * 100).rounded()) }
}

/// 地点の周辺（半径 `Surroundings.radius` 以内）の建物用途の集計結果。
/// 参考表示だけに使い、スコアや推薦段階には使わない。
public struct SurroundingsSummary: Sendable {
    /// 半径内の建物数。シーンが無い地点は nil
    public let buildingCount: Int?
    /// 棟数の多い順。建物データ不足のときは空
    public let shares: [LandUseShare]

    public var isInsufficient: Bool { shares.isEmpty }

    /// 例「周辺: 商業・業務施設が多い（商業・業務 62%・住宅 20%）」
    public var headline: String {
        guard !isInsufficient else { return "周辺: 建物データ不足" }
        // 「その他・不明」は特徴を表さないので、分かる用途があればそちらを先に使う
        let known = shares.filter { $0.group != .otherOrUnknown }
        let top = Array((known.isEmpty ? shares : known).prefix(Surroundings.headlineGroupCount))
        let detail = top.map { "\($0.group.label) \($0.percent)%" }.joined(separator: "・")
        return "周辺: \(top[0].group.phrase)が多い（\(detail)）"
    }
}

public enum Surroundings {
    /// 集計する半径 [m]（建物の中心点で判定）
    public static let radius = 300.0
    /// これ未満の棟数では傾向を言えないので「建物データ不足」にする
    public static let minimumBuildingCount = 20
    /// 一言に入れるグループ数
    static let headlineGroupCount = 2

    public static func summarize(_ context: SpotContext) -> SurroundingsSummary {
        guard let scene = context.scene else {
            return SurroundingsSummary(buildingCount: nil, shares: [])
        }
        let position = scene.localPosition(latitude: context.spot.latitude, longitude: context.spot.longitude)
        return summarize(scene: scene, east: position.east, north: position.north)
    }

    /// シーン座標（東・北 [m]）の地点の周辺を集計する
    public static func summarize(scene: CityScene, east: Double, north: Double) -> SurroundingsSummary {
        let nearby = scene.buildings.filter { hypot($0.x - east, $0.y - north) <= radius }
        guard nearby.count >= minimumBuildingCount else {
            return SurroundingsSummary(buildingCount: nearby.count, shares: [])
        }
        let counts = Dictionary(grouping: nearby) { LandUseGroup(usage: $0.usage) }.mapValues(\.count)
        let total = Double(nearby.count)
        let shares = LandUseGroup.allCases
            .compactMap { group in counts[group].map { LandUseShare(group: group, count: $0, fraction: Double($0) / total) } }
            // 同数のときは allCases の順に並べ、表示が毎回変わらないようにする
            .enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
        return SurroundingsSummary(buildingCount: nearby.count, shares: shares)
    }
}
