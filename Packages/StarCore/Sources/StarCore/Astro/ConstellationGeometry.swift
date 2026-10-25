import Foundation

/// 赤道座標（x = 春分点、y = 赤経 6 時、z = 天の北極）の単位ベクトル。星座線・星座絵を天球に置くときに使う。
public struct EquatorialVector: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// 赤経 [度]・赤緯 [度] から
    public init(rightAscension: Double, declination: Double) {
        let v = SkyOrientation.equatorial(rightAscension: rightAscension, declination: declination)
        self.init(x: v.x, y: v.y, z: v.z)
    }

    /// d3-celestial の点 [経度（-180〜180）, 赤緯]。経度は赤経を 0〜180°と-180〜0°で表している
    init?(d3Coordinate c: [Double]) {
        guard c.count >= 2 else { return nil }
        self.init(rightAscension: c[0] < 0 ? c[0] + 360 : c[0], declination: c[1])
    }

    func dot(_ o: EquatorialVector) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: EquatorialVector) -> EquatorialVector {
        EquatorialVector(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x)
    }

    func scaled(_ k: Double) -> EquatorialVector { EquatorialVector(x: x * k, y: y * k, z: z * k) }

    func plus(_ o: EquatorialVector) -> EquatorialVector { EquatorialVector(x: x + o.x, y: y + o.y, z: z + o.z) }

    var length: Double { dot(self).squareRoot() }

    var normalized: EquatorialVector {
        let n = length
        return n > 0 ? scaled(1 / n) : self
    }

    /// 2 つの向きのなす角 [度]
    public func angle(to o: EquatorialVector) -> Double {
        acos(max(-1, min(1, normalized.dot(o.normalized)))) / Astro.deg
    }

    /// 球面に沿って 2 点の間を割合 fraction（0〜1）だけ進んだ向き
    public static func slerp(_ a: EquatorialVector, _ b: EquatorialVector, fraction: Double) -> EquatorialVector {
        let angle = acos(max(-1, min(1, a.dot(b))))
        guard angle > 1e-6 else { return a.plus(b.plus(a.scaled(-1)).scaled(fraction)).normalized }
        let s = sin(angle)
        return a.scaled(sin((1 - fraction) * angle) / s).plus(b.scaled(sin(fraction * angle) / s)).normalized
    }
}

public enum ConstellationGeometry {
    /// 長い線も球面の弧をたどるよう、両端を含めて maxStep [度] ごとに点を打つ
    public static func arc(from a: EquatorialVector, to b: EquatorialVector, maxStep: Double) -> [EquatorialVector] {
        let steps = max(1, Int(ceil(a.angle(to: b) / maxStep)))
        return (0...steps).map { EquatorialVector.slerp(a, b, fraction: Double($0) / Double(steps)) }
    }
}

extension SkyOrientation {
    /// 赤道座標の向きを、地平の向きで返す
    public func direction(_ v: EquatorialVector) -> LocalVector {
        LocalVector(east: xAxis.east * v.x + yAxis.east * v.y + zAxis.east * v.z,
                    north: xAxis.north * v.x + yAxis.north * v.y + zAxis.north * v.z,
                    up: xAxis.up * v.x + yAxis.up * v.y + zAxis.up * v.z)
    }
}

extension ConstellationLines {
    /// 同じ星とみなす角度 [度]。d3-celestial では、同じ星が折れ線ごとに少しずつ違う値で入っていることはない
    static let sameStarTolerance = 0.01

    /// 折れ線（赤道座標）。点が 1 つしかない折れ線は除く
    public var equatorialPolylines: [[EquatorialVector]] {
        paths.map { $0.compactMap(EquatorialVector.init(d3Coordinate:)) }.filter { $0.count > 1 }
    }

    /// 線のつなぎ目の星（重なりを除いたもの）
    public var stars: [EquatorialVector] {
        var result: [EquatorialVector] = []
        for star in paths.joined().compactMap(EquatorialVector.init(d3Coordinate:))
        where !result.contains(where: { $0.angle(to: star) < Self.sameStarTolerance }) {
            result.append(star)
        }
        return result
    }

    /// 星の平均の向き（名前を出す位置）。星座は空の一部に収まるので、平均して長さを 1 に戻せば中心になる
    public var equatorialCenter: EquatorialVector? {
        let sum = stars.reduce(EquatorialVector(x: 0, y: 0, z: 0)) { $0.plus($1) }
        return sum.length > 1e-6 ? sum.normalized : nil
    }

    /// 線の星のうち、明るい星の一覧（`StarCatalog`）に載っている星の最も明るい等級。載っていなければ nil。
    /// 名前を出す星座を選ぶとき、明るい星を含む星座を優先するのに使う
    public var brightestCatalogMagnitude: Double? {
        let tolerance = 0.3
        let own = stars
        return StarCatalog.stars.filter { star in
            let v = EquatorialVector(rightAscension: star.rightAscension * 15, declination: star.declination)
            return own.contains { $0.angle(to: v) < tolerance }
        }.map(\.magnitude).min()
    }
}
