import Foundation

/// 地平座標（高度・方位は度。方位は北=0°、東=90°）
public struct HorizontalCoord: Sendable, Equatable {
    public var altitude: Double
    public var azimuth: Double

    public init(altitude: Double, azimuth: Double) {
        self.altitude = altitude
        self.azimuth = azimuth
    }
}

public struct MoonInfo: Sendable {
    public var position: HorizontalCoord
    /// 輝面比 0（新月）〜1（満月）
    public var illuminatedFraction: Double
    /// 月と太陽の黄経差 0〜360°（0=新月, 90=上弦, 180=満月, 270=下弦）
    public var phaseAngle: Double

    public var phaseName: String {
        switch phaseAngle {
        case ..<22.5, 337.5...: "新月"
        case ..<67.5: "三日月"
        case ..<112.5: "上弦の月"
        case ..<157.5: "十三夜月"
        case ..<202.5: "満月"
        case ..<247.5: "十八夜月"
        case ..<292.5: "下弦の月"
        default: "有明月"
        }
    }
}

/// 明るい恒星（J2000.0 の赤経・赤緯）
public struct Star: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// 赤経 [時]
    public var rightAscension: Double
    /// 赤緯 [度]
    public var declination: Double
    public var magnitude: Double
}

/// 月・太陽・恒星の位置計算。
/// 月・太陽は天文年鑑の低精度式（月の位置誤差はおおむね 0.4° 以内）を使う。
/// 恒星は J2000.0 の座標に歳差補正をかける（章動・光行差は未補正で、誤差は 0.01° 程度）。
/// 精度の検証は docs/astro/verification.md。
public enum Astro {
    static let deg = Double.pi / 180

    /// J2000.0（2000-01-01 12:00 TT）からの日数
    static func daysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
    }

    static func obliquity(_ d: Double) -> Double { 23.439 - 0.000_000_4 * d }

    /// 地方恒星時 [度]
    static func localSiderealTime(_ d: Double, longitude: Double) -> Double {
        Angle.normalize(280.460_618_37 + 360.985_647_366_29 * d + longitude)
    }

    /// 黄道座標 → 赤道座標（赤経・赤緯は度）
    static func eclipticToEquatorial(lambda: Double, beta: Double, epsilon: Double) -> (ra: Double, dec: Double) {
        let l = lambda * deg, b = beta * deg, e = epsilon * deg
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        return (Angle.normalize(ra / deg), dec / deg)
    }

    /// 赤道座標 → 地平座標（大気差を含む）
    static func horizontal(ra: Double, dec: Double, d: Double, latitude: Double, longitude: Double) -> HorizontalCoord {
        let h = (localSiderealTime(d, longitude: longitude) - ra) * deg
        let phi = latitude * deg, delta = dec * deg
        let alt = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h)) / deg
        let az = atan2(-cos(delta) * sin(h), sin(delta) * cos(phi) - cos(delta) * cos(h) * sin(phi)) / deg
        return HorizontalCoord(altitude: alt + refraction(alt), azimuth: Angle.normalize(az))
    }

    /// 大気差 [度]（Sæmundsson の式）
    static func refraction(_ altitude: Double) -> Double {
        guard altitude > -1 else { return 0 }
        return 1.02 / tan((altitude + 10.3 / (altitude + 5.11)) * deg) / 60
    }

    static func sunEcliptic(_ d: Double) -> Double {
        let l = 280.460 + 0.985_647_4 * d
        let g = (357.528 + 0.985_600_3 * d) * deg
        return Angle.normalize(l + 1.915 * sin(g) + 0.020 * sin(2 * g))
    }

    public static func sun(date: Date, latitude: Double, longitude: Double) -> HorizontalCoord {
        let d = daysSinceJ2000(date)
        let eq = eclipticToEquatorial(lambda: sunEcliptic(d), beta: 0, epsilon: obliquity(d))
        return horizontal(ra: eq.ra, dec: eq.dec, d: d, latitude: latitude, longitude: longitude)
    }

    public static func moon(date: Date, latitude: Double, longitude: Double) -> MoonInfo {
        let d = daysSinceJ2000(date)
        let t = d / 36_525
        func s(_ a: Double, _ b: Double) -> Double { sin((a + b * t) * deg) }
        func c(_ a: Double, _ b: Double) -> Double { cos((a + b * t) * deg) }

        let lambda = 218.32 + 481_267.881 * t
            + 6.29 * s(135.0, 477_198.87) - 1.27 * s(259.3, -413_335.36)
            + 0.66 * s(235.7, 890_534.22) + 0.21 * s(269.9, 954_397.74)
            - 0.19 * s(357.5, 35_999.05) - 0.11 * s(186.5, 966_404.03)
        let beta = 5.13 * s(93.3, 483_202.02) + 0.28 * s(228.2, 960_400.89)
            - 0.28 * s(318.3, 6_003.15) - 0.17 * s(217.6, -407_332.21)
        let parallax = 0.9508 + 0.0518 * c(135.0, 477_198.87) + 0.0095 * c(259.3, -413_335.36)
            + 0.0078 * c(235.7, 890_534.22) + 0.0028 * c(269.9, 954_397.74)

        let eq = eclipticToEquatorial(lambda: Angle.normalize(lambda), beta: beta, epsilon: obliquity(d))
        let h = (localSiderealTime(d, longitude: longitude) - eq.ra) * deg
        let phi = latitude * deg, delta = eq.dec * deg
        let geoAlt = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h)) / deg
        let az = atan2(-cos(delta) * sin(h), sin(delta) * cos(phi) - cos(delta) * cos(h) * sin(phi)) / deg
        // 月は近いので、地心から観測地点への視差（最大約1°）で高度を補正する
        let topoAlt = geoAlt - parallax * cos(geoAlt * deg)

        let phaseAngle = Angle.normalize(lambda - sunEcliptic(d))
        let elongation = acos(cos(beta * deg) * cos(phaseAngle * deg))
        return MoonInfo(
            position: HorizontalCoord(altitude: topoAlt + refraction(topoAlt), azimuth: Angle.normalize(az)),
            illuminatedFraction: (1 - cos(elongation)) / 2,
            phaseAngle: phaseAngle
        )
    }

    public static func star(_ star: Star, date: Date, latitude: Double, longitude: Double) -> HorizontalCoord {
        let d = daysSinceJ2000(date)
        let eq = precessFromJ2000(ra: star.rightAscension * 15, dec: star.declination, d: d)
        return horizontal(ra: eq.ra, dec: eq.dec, d: d, latitude: latitude, longitude: longitude)
    }

    /// 秒角 → 度
    static let arcsecond = 1.0 / 3600

    /// J2000.0 の赤経・赤緯 [度] を、観測日の平均分点の赤経・赤緯 [度] に変換する（歳差補正）。
    /// IAU 1976 の歳差（ζ, z, θ の 3 回転）。式は Meeus『Astronomical Algorithms』第 2 版 第 21 章
    /// の式 (21.3)（元期を J2000.0 にした場合）と (21.4)。章動・光行差は入れていない
    static func precessFromJ2000(ra: Double, dec: Double, d: Double) -> (ra: Double, dec: Double) {
        let t = d / 36_525
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsecond
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsecond
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsecond

        let a0 = (ra + zeta) * deg, d0 = dec * deg, th = theta * deg
        let a = cos(d0) * sin(a0)
        let b = cos(th) * cos(d0) * cos(a0) - sin(th) * sin(d0)
        let c = sin(th) * cos(d0) * cos(a0) + cos(th) * sin(d0)
        // 天の北極の近く（北極星など）でも誤差が出にくいよう、赤緯は asin ではなく atan2 で求める
        let newDec = atan2(c, (a * a + b * b).squareRoot()) / deg
        return (Angle.normalize(atan2(a, b) / deg + z), newDec)
    }

    /// 2つの地平座標の角距離 [度]
    public static func separation(_ a: HorizontalCoord, _ b: HorizontalCoord) -> Double {
        let a1 = a.altitude * deg, a2 = b.altitude * deg
        let dz = (a.azimuth - b.azimuth) * deg
        let v = sin(a1) * sin(a2) + cos(a1) * cos(a2) * cos(dz)
        return acos(min(1, max(-1, v))) / deg
    }
}

public enum Angle {
    public static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// 16方位の日本語名
    public static func directionName(_ azimuth: Double) -> String {
        let names = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                     "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        return names[Int((normalize(azimuth) + 11.25) / 22.5) % 16]
    }
}
