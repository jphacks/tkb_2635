import Foundation

/// 地平の向き（東・北・天頂）で表した単位ベクトル。3D 表示の座標への直し方は画面側で決める。
public struct LocalVector: Sendable, Equatable {
    public var east: Double
    public var north: Double
    public var up: Double

    public init(east: Double, north: Double, up: Double) {
        self.east = east
        self.north = north
        self.up = up
    }

    public init(_ coord: HorizontalCoord) {
        let a = coord.altitude * Astro.deg, z = coord.azimuth * Astro.deg
        self.init(east: cos(a) * sin(z), north: cos(a) * cos(z), up: sin(a))
    }

    func dot(_ o: LocalVector) -> Double { east * o.east + north * o.north + up * o.up }

    func cross(_ o: LocalVector) -> LocalVector {
        LocalVector(east: north * o.up - up * o.north, north: up * o.east - east * o.up, up: east * o.north - north * o.east)
    }

    func scaled(_ k: Double) -> LocalVector { LocalVector(east: east * k, north: north * k, up: up * k) }

    func minus(_ o: LocalVector) -> LocalVector { LocalVector(east: east - o.east, north: north - o.north, up: up - o.up) }

    var normalized: LocalVector {
        let n = dot(self).squareRoot()
        return n > 0 ? scaled(1 / n) : self
    }
}

/// 星図（J2000 の赤経・赤緯）を、観測地点・時刻の空に合わせる回転（4-12）。
/// 星図の球を赤道座標で作っておき、この回転をかけるだけで星が本物の位置に来る。
/// 歳差（J2000 から 2026 年まで約 0.37°）と大気差は入れない。
public struct SkyOrientation: Sendable {
    /// 赤道座標の x（春分点）・y（赤経 6 時）・z（天の北極）の向きを、地平の向きで表したもの
    public let xAxis: LocalVector
    public let yAxis: LocalVector
    public let zAxis: LocalVector

    public init(date: Date, latitude: Double, longitude: Double) {
        let lst = Astro.localSiderealTime(Astro.daysSinceJ2000(date), longitude: longitude) * Astro.deg
        let phi = latitude * Astro.deg
        // 地平の向き = 行列 × 赤道の向き。行は 東・北・天頂、列は x・y・z
        xAxis = LocalVector(east: -sin(lst), north: -sin(phi) * cos(lst), up: cos(phi) * cos(lst))
        yAxis = LocalVector(east: cos(lst), north: -sin(phi) * sin(lst), up: cos(phi) * sin(lst))
        zAxis = LocalVector(east: 0, north: cos(phi), up: sin(phi))
    }

    /// 赤経 [度]・赤緯 [度] の方向を、地平の向きで返す
    public func direction(rightAscension ra: Double, declination dec: Double) -> LocalVector {
        let v = Self.equatorial(rightAscension: ra, declination: dec)
        return LocalVector(east: xAxis.east * v.x + yAxis.east * v.y + zAxis.east * v.z,
                           north: xAxis.north * v.x + yAxis.north * v.y + zAxis.north * v.z,
                           up: xAxis.up * v.x + yAxis.up * v.y + zAxis.up * v.z)
    }

    /// 赤経・赤緯の単位ベクトル（赤道座標）
    public static func equatorial(rightAscension ra: Double, declination dec: Double) -> (x: Double, y: Double, z: Double) {
        let a = ra * Astro.deg, d = dec * Astro.deg
        return (cos(d) * cos(a), cos(d) * sin(a), sin(d))
    }
}

/// 星図の画像（正距円筒・天の座標）の、どの位置がどの赤経・赤緯か。
/// NASA SVS Deep Star Maps の celestial 版は、画像の中央が赤経 0 時で、左へ行くほど赤経が増える。
/// 実際の画像で向きを確かめたら、ここの定数だけを直す。
public enum StarMapProjection {
    /// 画像の左端（u = 0）の赤経 [度]
    public static let rightAscensionAtLeftEdge = 180.0
    /// 左から右へ進むと赤経が減るか
    public static let rightAscensionDecreasesToRight = true

    /// 赤経 [度]・赤緯 [度] → 画像の位置（u: 左 0〜右 1、v: 上 0〜下 1）
    public static func uv(rightAscension ra: Double, declination dec: Double) -> (u: Double, v: Double) {
        let offset = Angle.normalize(rightAscensionDecreasesToRight ? rightAscensionAtLeftEdge - ra : ra - rightAscensionAtLeftEdge)
        return (offset / 360, (90 - dec) / 180)
    }
}
