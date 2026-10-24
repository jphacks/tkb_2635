import Foundation

/// 観測したい天体
public enum ObservationTarget: Hashable, Sendable {
    case moon
    case star(Star)

    public var id: String {
        switch self {
        case .moon: "moon"
        case .star(let s): s.id
        }
    }

    public var name: String {
        switch self {
        case .moon: "月"
        case .star(let s): s.name
        }
    }
}

/// 推薦に使ったデータの不足・未確認の内容
public enum DataQualityFlag: String, Sendable, CaseIterable {
    case localGlareUnverified
    case regionalLightUnverified
    case weatherMissing
    case horizonApproximate
    case buildingDataSample
    case accessUnverified
    case directionMaskUnverified
    case areaAccessRestricted
    case regionalLightProvisional

    public var message: String {
        switch self {
        case .localGlareUnverified: "近傍照明が未確認のため、暗さの推定精度が不足しています"
        case .regionalLightUnverified: "地域の光害が未確認のため、暗さは仮の値で計算しています"
        case .weatherMissing: "指定時刻の天気予報を取得できていません"
        case .horizonApproximate: "建物データ未取り込みのため、地平線は暫定値です"
        case .buildingDataSample: "建物は手作りの概略データです（PLATEAU 取り込み前）"
        case .accessUnverified: "営業時間・立入条件は未確認の暫定値です。公式情報を確認してください"
        case .directionMaskUnverified: "窓・柵などで見える方角は未確認です"
        case .areaAccessRestricted: "園内の一部に利用制限があります。登録地点と制限区域の対応は未確認です"
        case .regionalLightProvisional: "地域の光害は衛星データ取り込み前の暫定値です"
        }
    }
}

/// 推薦の段階（仕様書 5.3 の成立条件）
public enum RecommendationTier: Int, Comparable, Sendable {
    /// 成立条件をすべて満たす
    case recommended = 0
    /// 立入可能・幾何学的に可視だが、主要データや方角が未確認
    case needsCheck = 1
    /// 建物・地平線に遮られる、または地平線の下
    case notVisible = 2
    /// 指定時刻に利用できない（STEP 1 で除外）
    case unavailable = 3

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .recommended: "推薦"
        case .needsCheck: "要確認"
        case .notVisible: "見えない見込み"
        case .unavailable: "利用不可"
        }
    }
}

/// 地点 × 天体 × 時刻の判定結果（仕様書 7.3）
public struct Prediction: Identifiable, Sendable {
    public var spotId: String
    public var celestialBodyId: String
    public var azimuth: Double
    public var altitude: Double
    /// 天体の方位での遮蔽仰角 h(A)
    public var obstructionElevation: Double
    public var geometricVisibility: Bool
    public var blockedByDirectionMask: Bool
    public var isOpen: Bool
    public var accessStatus: SpotAccessStatus
    public var openness: Double
    /// W（天気が無いときは nil）
    public var weatherScore: Double?
    public var cloudCover: Double?
    public var darknessScore: Double
    public var moonEffect: Double
    public var totalScore: Double
    public var tier: RecommendationTier
    public var recommendationReasons: [String]
    public var dataQualityFlags: [DataQualityFlag]

    public var id: String { spotId }
}

public enum Recommender {
    /// 遮蔽判定の誤差余裕 δ [度]
    public static let visibilityMargin = 1.0
    private static let unknownRegionalLightIndex = 0.5

    /// 暗さ指標 D = clamp(1 − (0.45 B_sky + 0.25 B_local + 0.30 M))（仕様書 3.6）
    /// 近傍照明が未確認のときは 0 とせず中間値 0.5 で仮計算し、assumed = true を返す。
    public static func darkness(skyBrightness: Double, localGlareLevel: Int?, moonEffect: Double) -> (value: Double, assumed: Bool) {
        let local = localGlareLevel.map { Double(min(max($0, 0), 3)) / 3 }
        let d = 1 - (0.45 * skyBrightness + 0.25 * (local ?? 0.5) + 0.30 * moonEffect)
        return (min(max(d, 0), 1), local == nil)
    }

    /// 月明かりの影響 M（0〜1、暫定式）。月が高く満ちているほど、対象に近いほど大きい。
    public static func moonEffect(moon: MoonInfo, target: HorizontalCoord) -> Double {
        guard moon.position.altitude > 0 else { return 0 }
        let altitudeFactor = 0.4 + 0.6 * sin(moon.position.altitude * .pi / 180)
        let proximity = Astro.separation(moon.position, target) < 20 ? 1.3 : 1.0
        return min(1, moon.illuminatedFraction * altitudeFactor * proximity)
    }

    /// 天気指標 W。雲量が少ないほど高く、降水があれば大きく下げる。
    public static func weatherScore(_ weather: Weather) -> Double? {
        guard let cloud = weather.cloudCover else { return nil }
        let rainPenalty = (weather.precipitation ?? 0) >= 0.1 ? 0.2 : 1.0
        return min(max(1 - cloud / 100, 0), 1) * rainPenalty
    }

    /// S = 100 (0.35 O + 0.40 W + 0.25 D)（仕様書 5.3）
    public static func score(openness: Double, weather: Double, darkness: Double) -> Double {
        100 * (0.35 * openness + 0.40 * weather + 0.25 * darkness)
    }

    public static func evaluate(_ context: SpotContext, target: ObservationTarget, date: Date, weather: Weather?) -> Prediction {
        let spot = context.spot
        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude)
        let position: HorizontalCoord = switch target {
        case .moon: moon.position
        case .star(let s): Astro.star(s, date: date, latitude: spot.latitude, longitude: spot.longitude)
        }

        var flags: [DataQualityFlag] = []

        // STEP 1: 立入条件
        let accessStatus = spot.accessStatus(at: date)
        let isOpen = accessStatus == .open
        if !spot.accessVerified || accessStatus == .unverified { flags.append(.accessUnverified) }
        let hasAreaRestriction = !spot.accessNotices(at: date).isEmpty
        if hasAreaRestriction { flags.append(.areaAccessRestricted) }

        // STEP 2: 天体の可視性 V = [a > h(A) + δ]、窓・屋根のマスク
        let obstruction = context.horizon.elevation(at: position.azimuth)
        let aboveObstruction = position.altitude > obstruction + visibilityMargin
        let maskBlocked = spot.isBlockedByViewingLimits(azimuth: position.azimuth, altitude: position.altitude)
        let visible = aboveObstruction && !maskBlocked
        if context.horizon.isApproximate { flags.append(.horizonApproximate) }
        if context.scene != nil { flags.append(.buildingDataSample) }
        if !spot.hasVerifiedViewingDirections { flags.append(.directionMaskUnverified) }

        // STEP 3: 天気
        let w = weather.flatMap(weatherScore)
        if w == nil { flags.append(.weatherMissing) }

        // STEP 4: 暗さ（月を見るときは月明かりを減点しない）
        let m: Double = if case .moon = target { 0 } else { moonEffect(moon: moon, target: position) }
        // 未取得の広域光害はゼロ（暗い）とせず、中間値で仮計算する。
        let dark = darkness(skyBrightness: spot.regionalLightIndex ?? unknownRegionalLightIndex,
                            localGlareLevel: spot.localGlareLevel, moonEffect: m)
        if spot.regionalLightIndex == nil { flags.append(.regionalLightUnverified) }
        if dark.assumed { flags.append(.localGlareUnverified) }
        if spot.regionalLightProvisional { flags.append(.regionalLightProvisional) }

        // STEP 5: スコアと段階。天気が無いときは 0 にせず 0.5 で仮計算し、推薦段階には入れない。
        let openness = context.horizon.openness
        let total = score(openness: openness, weather: w ?? 0.5, darkness: dark.value)
        let tier: RecommendationTier
        if accessStatus == .closed {
            tier = .unavailable
        } else if !visible {
            tier = .notVisible
        } else if accessStatus == .unverified || hasAreaRestriction || !spot.accessVerified || w == nil || !spot.hasVerifiedViewingDirections || context.horizon.isApproximate || spot.regionalLightIndex == nil {
            tier = .needsCheck
        } else {
            tier = .recommended
        }

        let prediction = Prediction(
            spotId: spot.id, celestialBodyId: target.id,
            azimuth: position.azimuth, altitude: position.altitude,
            obstructionElevation: obstruction, geometricVisibility: visible, blockedByDirectionMask: maskBlocked,
            isOpen: isOpen, accessStatus: accessStatus, openness: openness, weatherScore: w, cloudCover: weather?.cloudCover,
            darknessScore: dark.value, moonEffect: m, totalScore: total, tier: tier,
            recommendationReasons: [], dataQualityFlags: flags)

        // STEP 6: 推薦理由
        var result = prediction
        result.recommendationReasons = reasons(for: prediction, spot: spot, target: target, date: date)
        return result
    }

    /// 段階 → スコアの順に並べる（STEP 5）
    public static func rank(_ predictions: [Prediction]) -> [Prediction] {
        predictions.sorted { ($0.tier, -$0.totalScore) < ($1.tier, -$1.totalScore) }
    }

    static func reasons(for p: Prediction, spot: Spot, target: ObservationTarget, date: Date) -> [String] {
        var lines: [String] = []
        let dir = Angle.directionName(p.azimuth)
        let alt = String(format: "%.0f", p.altitude)
        let obs = String(format: "%.0f", p.obstructionElevation)

        if p.accessStatus == .unverified {
            lines.append("指定時刻の入場可否は未確認です。利用できることを確認してからお出かけください。")
        } else if !p.isOpen {
            lines.append("指定時刻は利用時間外または休園日です（\(spot.accessHoursText(at: date))）。")
        }
        if p.altitude <= 0 {
            lines.append("指定時刻の\(target.name)は地平線の下にあります。")
        } else if p.blockedByDirectionMask {
            lines.append("\(target.name)は\(dir)・高度\(alt)°にありますが、窓や屋根の向きからこの施設では見えない見込みです。")
        } else if p.geometricVisibility {
            lines.append("この地点は\(dir)方向の空が開けており（遮蔽仰角 \(obs)°）、指定時刻の\(target.name)（高度\(alt)°）を建物に遮られず観測できる見込みです。")
        } else {
            lines.append("指定時刻の\(target.name)は\(dir)・高度\(alt)°にあり、周辺の建物など（遮蔽仰角 \(obs)°）に隠れる見込みです。")
        }

        if let cloud = p.cloudCover {
            lines.append("雲量の予報は \(Int(cloud))% です。")
        }
        if spot.localGlareLevel == nil {
            lines.append("ただし、周辺照明は未確認です。")
        }
        if spot.indoorOutdoor == .indoor {
            lines.append("屋内のため、室内照明の窓への映り込みに注意してください。")
        }
        return lines
    }
}
