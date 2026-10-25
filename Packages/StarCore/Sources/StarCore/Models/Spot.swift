import Foundation

/// 観測地点の種類（仕様書 2.1）
public enum SpotCategory: String, Codable, CaseIterable, Sendable {
    case park, plaza, riverside, observatory, rooftop

    public var label: String {
        switch self {
        case .park: "公園"
        case .plaza: "広場"
        case .riverside: "河川敷"
        case .observatory: "展望台"
        case .rooftop: "屋上"
        }
    }
}

public enum IndoorOutdoor: String, Codable, Sendable {
    case indoor, outdoor, partiallyCovered

    public var label: String {
        switch self {
        case .indoor: "屋内"
        case .outdoor: "屋外"
        case .partiallyCovered: "一部屋根あり"
        }
    }
}

/// 方位角の範囲（北=0°、時計回り）。from > to のときは北をまたぐ範囲。
public struct AzimuthRange: Codable, Sendable, Hashable {
    public var from: Double
    public var to: Double

    public init(from: Double, to: Double) {
        self.from = from
        self.to = to
    }

    public func contains(_ azimuth: Double) -> Bool {
        guard azimuth.isFinite, from.isFinite, to.isFinite else { return false }
        if abs(to - from) >= 360 { return true }
        let a = Angle.normalize(azimuth)
        let f = Angle.normalize(from)
        let t = Angle.normalize(to)
        return f <= t ? (a >= f && a <= t) : (a >= f || a <= t)
    }
}

/// 観測地点（仕様書 7.1）
public struct Spot: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var ward: String
    public var category: SpotCategory
    public var latitude: Double
    public var longitude: Double
    /// 観測地点の床面標高 [m]（建物データと同じ基準）
    public var floorElevation: Double
    /// 床面からの目線高さ [m]
    public var eyeHeight: Double
    public var indoorOutdoor: IndoorOutdoor
    /// 窓・屋根などで観測できる方位が限られる場合の範囲。nil は全方位。
    public var viewingDirectionMask: [AzimuthRange]?
    /// 屋根・窓枠などで見上げられる上限の高度 [deg]。nil は制限なし。
    public var maxVisibleAltitude: Double?
    public var directionMaskVerified: Bool
    /// 公式の眺望案内と、窓の角度を確認できている範囲。
    public var viewingDirectionNotes: String?
    public var openingHours: OpeningHours
    public var accessRules: SpotAccessRules?
    public var admissionFee: String?
    public var reservationRequired: Bool?
    public var accessConditions: String?
    /// 天候による臨時閉鎖の案内。当日の開閉状況ではない。nil は未確認。
    public var weatherClosureConditions: String?
    /// 撮影機材・撮影方法の制限。nil は未確認。
    public var photographyRestrictions: String?
    public var officialWebsite: URL?
    /// 施設情報の最終確認日。nil は未確認。
    public var lastVerifiedAt: String?
    /// 3D建物データのシーン ID。nil の地点は簡易地平線を使う。
    public var sceneId: String?
    /// 観測者が立っている建物（遮蔽判定から除外する）
    public var hostBuildingId: String?
    /// 建物データが無い地点の暫定の地平線仰角 [deg]
    public var approxHorizonElevation: Double?
    /// 地域の人工光の指標 0〜1。nil は未確認、出典が nil の数値は暫定値。
    public var regionalLightIndex: Double?
    /// regionalLightIndex の出典（例: VIIRS VNL v2.2 の年次合成）。nil は未取得。
    public var regionalLightSource: String?
    /// regionalLightIndex の元データの年（例: "2023"）
    public var regionalLightMeasuredAt: String?
    /// 近傍照明の段階評価 0〜3。nil は未確認。
    public var localGlareLevel: Int?
    /// localGlareLevel を確かめた日（YYYY-MM-DD）
    public var lightingCheckDate: String?
    /// localGlareLevel の確かめ方。"desk"（写真などによる机上評価）か "onsite"（現地確認）。nil は記録なし。
    public var lightingCheckMethod: String?
    public var modelVersion: String
    public var memo: String?
    /// 高さによる見え方を並べて比べる相手の地点 ID（例: 地上 → 展望台）。nil は比較なし。
    public var comparisonSpotId: String?

    /// 観測者の目の標高 = z_floor + h_eye（仕様書 4.1）
    public var observerElevation: Double { floorElevation + eyeHeight }
    public var accessVerified: Bool { lastVerifiedAt != nil }
    public var regionalLightProvisional: Bool { regionalLightIndex != nil && regionalLightSource == nil }
    /// 画面に出す地域の光害の出典の短い名前。数値の未取得と暫定値を区別する。
    public var regionalLightShortSource: String {
        guard regionalLightIndex != nil else { return "未確認" }
        guard regionalLightSource != nil else { return "暫定値" }
        return ["VIIRS", regionalLightMeasuredAt].compactMap { $0 }.joined(separator: " ")
    }
}

public extension Calendar {
    static let tokyo: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
}
