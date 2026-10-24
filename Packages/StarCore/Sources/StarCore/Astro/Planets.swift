import Foundation

/// 軌道要素。各値は「定数 + 1日あたりの変化 × d」で、d は 2000-01-00 0:00 UT（J2000.0 の 1.5 日前）からの日数。
/// 角度は度、軌道長半径は天文単位。黄経・近日点は日付の分点で表す。
struct OrbitalElements: Sendable {
    /// 昇交点黄経 N
    var ascendingNode: (Double, Double)
    /// 軌道傾斜角 i
    var inclination: (Double, Double)
    /// 近日点引数 w
    var perihelion: (Double, Double)
    /// 軌道長半径 a
    var semiMajorAxis: Double
    /// 離心率 e
    var eccentricity: (Double, Double)
    /// 平均近点角 M
    var meanAnomaly: (Double, Double)
}

/// 木星・土星の相互の摂動のどちらを入れるか
enum PlanetPerturbation: Sendable, Hashable {
    case none
    case jupiter
    case saturn
}

/// 肉眼で見える惑星
public struct Planet: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// 天文記号
    public var symbol: String
    var elements: OrbitalElements
    var perturbation: PlanetPerturbation = .none

    // 軌道要素は id ごとに決まっているので、同じ惑星かどうかは id で判定する
    public static func == (lhs: Planet, rhs: Planet) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 水星〜土星（軌道要素は Paul Schlyter「Computing planetary positions」から）
public enum PlanetCatalog {
    static let jupiterElements = OrbitalElements(
        ascendingNode: (100.4542, 2.768_54e-5), inclination: (1.3030, -1.557e-7),
        perihelion: (273.8777, 1.645_05e-5), semiMajorAxis: 5.202_56,
        eccentricity: (0.048_498, 4.469e-9), meanAnomaly: (19.8950, 0.083_085_300_1))
    static let saturnElements = OrbitalElements(
        ascendingNode: (113.6634, 2.389_80e-5), inclination: (2.4886, -1.081e-7),
        perihelion: (339.3939, 2.976_61e-5), semiMajorAxis: 9.554_75,
        eccentricity: (0.055_546, -9.499e-9), meanAnomaly: (316.9670, 0.033_444_228_2))
    /// 地球の位置を出すための太陽の見かけの軌道
    static let sunElements = OrbitalElements(
        ascendingNode: (0, 0), inclination: (0, 0),
        perihelion: (282.9404, 4.709_35e-5), semiMajorAxis: 1,
        eccentricity: (0.016_709, -1.151e-9), meanAnomaly: (356.0470, 0.985_600_258_5))

    public static let planets: [Planet] = [
        Planet(id: "mercury", name: "水星", symbol: "☿", elements: OrbitalElements(
            ascendingNode: (48.3313, 3.245_87e-5), inclination: (7.0047, 5.00e-8),
            perihelion: (29.1241, 1.014_44e-5), semiMajorAxis: 0.387_098,
            eccentricity: (0.205_635, 5.59e-10), meanAnomaly: (168.6562, 4.092_334_436_8))),
        Planet(id: "venus", name: "金星", symbol: "♀", elements: OrbitalElements(
            ascendingNode: (76.6799, 2.465_90e-5), inclination: (3.3946, 2.75e-8),
            perihelion: (54.8910, 1.383_74e-5), semiMajorAxis: 0.723_330,
            eccentricity: (0.006_773, -1.302e-9), meanAnomaly: (48.0052, 1.602_130_224_4))),
        Planet(id: "mars", name: "火星", symbol: "♂", elements: OrbitalElements(
            ascendingNode: (49.5574, 2.110_81e-5), inclination: (1.8497, -1.78e-8),
            perihelion: (286.5016, 2.929_61e-5), semiMajorAxis: 1.523_688,
            eccentricity: (0.093_405, 2.516e-9), meanAnomaly: (18.6021, 0.524_020_776_6))),
        Planet(id: "jupiter", name: "木星", symbol: "♃", elements: jupiterElements, perturbation: .jupiter),
        Planet(id: "saturn", name: "土星", symbol: "♄", elements: saturnElements, perturbation: .saturn),
    ]

    public static func planet(id: String) -> Planet? {
        planets.first { $0.id == id }
    }
}

extension Astro {
    /// Schlyter の日数の起点（2000-01-00 0:00）は J2000.0 の 1.5 日前
    static let schlyterEpochOffset = 1.5
    /// ケプラー方程式の反復の打ち切り [度]
    static let keplerTolerance = 1e-8

    /// 惑星の地平座標。太陽中心の黄道座標を求め、地球（太陽の位置）を足して地心にしてから地平座標へ変換する。
    /// 光行時間・光行差・視差は無視している（あわせて 0.05° 程度）
    public static func planet(_ planet: Planet, date: Date, latitude: Double, longitude: Double) -> HorizontalCoord {
        let d = daysSinceJ2000(date)
        let ecliptic = planetGeocentricEcliptic(planet, d: d)
        let eq = eclipticToEquatorial(lambda: ecliptic.lambda, beta: ecliptic.beta, epsilon: obliquity(d))
        return horizontal(ra: eq.ra, dec: eq.dec, d: d, latitude: latitude, longitude: longitude)
    }

    /// 地心の黄経・黄緯 [度]（日付の分点）
    static func planetGeocentricEcliptic(_ planet: Planet, d: Double) -> (lambda: Double, beta: Double) {
        let ds = d + schlyterEpochOffset
        var helio = heliocentric(planet.elements, ds: ds)
        if planet.perturbation != .none {
            let mj = PlanetCatalog.jupiterElements.value(\.meanAnomaly, ds)
            let ms = PlanetCatalog.saturnElements.value(\.meanAnomaly, ds)
            let p = perturbation(planet.perturbation, mj: mj, ms: ms)
            helio.lon += p.lon
            helio.lat += p.lat
        }
        let sun = heliocentric(PlanetCatalog.sunElements, ds: ds)

        // 太陽中心 → 地心（太陽の地心位置を足す）
        let lon = helio.lon * deg, lat = helio.lat * deg, sl = sun.lon * deg
        let x = helio.r * cos(lon) * cos(lat) + sun.r * cos(sl)
        let y = helio.r * sin(lon) * cos(lat) + sun.r * sin(sl)
        let z = helio.r * sin(lat)
        return (Angle.normalize(atan2(y, x) / deg), atan2(z, (x * x + y * y).squareRoot()) / deg)
    }

    /// 軌道要素から、太陽中心の黄経・黄緯 [度] と距離 [AU]
    static func heliocentric(_ el: OrbitalElements, ds: Double) -> (lon: Double, lat: Double, r: Double) {
        let n = el.value(\.ascendingNode, ds) * deg
        let i = el.value(\.inclination, ds) * deg
        let w = el.value(\.perihelion, ds)
        let e = el.value(\.eccentricity, ds)
        let m = Angle.normalize(el.value(\.meanAnomaly, ds))

        let ea = eccentricAnomaly(meanAnomaly: m, eccentricity: e) * deg
        let xv = el.semiMajorAxis * (cos(ea) - e)
        let yv = el.semiMajorAxis * (1 - e * e).squareRoot() * sin(ea)
        let v = atan2(yv, xv) / deg
        let r = (xv * xv + yv * yv).squareRoot()

        let u = (v + w) * deg
        let xh = r * (cos(n) * cos(u) - sin(n) * sin(u) * cos(i))
        let yh = r * (sin(n) * cos(u) + cos(n) * sin(u) * cos(i))
        let zh = r * sin(u) * sin(i)
        return (Angle.normalize(atan2(yh, xh) / deg), atan2(zh, (xh * xh + yh * yh).squareRoot()) / deg, r)
    }

    /// ケプラー方程式 M = E − e sin E をニュートン法で解く（角度は度）
    static func eccentricAnomaly(meanAnomaly m: Double, eccentricity e: Double) -> Double {
        var ea = m + e / deg * sin(m * deg) * (1 + e * cos(m * deg))
        for _ in 0..<20 {
            let delta = (ea - e / deg * sin(ea * deg) - m) / (1 - e * cos(ea * deg))
            ea -= delta
            if abs(delta) < keplerTolerance { break }
        }
        return ea
    }

    /// 木星・土星の主要な摂動 [度]（Mj・Ms は木星・土星の平均近点角）
    static func perturbation(_ kind: PlanetPerturbation, mj: Double, ms: Double) -> (lon: Double, lat: Double) {
        func s(_ a: Double) -> Double { sin(a * deg) }
        func c(_ a: Double) -> Double { cos(a * deg) }
        switch kind {
        case .none:
            return (0, 0)
        case .jupiter:
            let lon = -0.332 * s(2 * mj - 5 * ms - 67.6) - 0.056 * s(2 * mj - 2 * ms + 21)
                + 0.042 * s(3 * mj - 5 * ms + 21) - 0.036 * s(mj - 2 * ms)
                + 0.022 * c(mj - ms) + 0.023 * s(2 * mj - 3 * ms + 52)
                - 0.016 * s(mj - 5 * ms - 69)
            return (lon, 0)
        case .saturn:
            let lon = 0.812 * s(2 * mj - 5 * ms - 67.6) - 0.229 * c(2 * mj - 4 * ms - 2)
                + 0.119 * s(mj - 2 * ms - 3) + 0.046 * s(2 * mj - 6 * ms - 69)
                + 0.014 * s(mj - 3 * ms + 32)
            let lat = -0.020 * c(2 * mj - 4 * ms - 2) + 0.018 * s(2 * mj - 6 * ms - 49)
            return (lon, lat)
        }
    }
}

extension OrbitalElements {
    func value(_ key: KeyPath<Self, (Double, Double)>, _ ds: Double) -> Double {
        let (base, rate) = self[keyPath: key]
        return base + rate * ds
    }
}
