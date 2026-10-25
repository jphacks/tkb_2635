import Foundation

/// 星座の姿の簡略な線画（`constellation-art.json`）。チームで作った線画で、実際の星座絵そのものではない。
///
/// 絵の点は、絵の平面の (x, y) で持つ。2 つの基準の星（`anchors`）が絵のどこに来るか（`at`）を決めておき、
/// 天球の上でその 2 つの星の位置に合わせて、絵を拡大縮小・回転・移動して置く。
/// 絵の平面は、空を見上げたときの見た目（右が西、上が北）。
public struct ConstellationArt: Decodable, Identifiable, Sendable {
    public struct Anchor: Decodable, Sendable {
        /// 星の位置 [経度（-180〜180、d3-celestial と同じ）, 赤緯]
        let star: [Double]
        /// 絵の平面での位置 [x, y]
        let at: [Double]
    }

    /// 星座の id（`constellations.json` と同じ。例: "Ori"）
    public let id: String
    let anchors: [Anchor]
    /// 折れ線の集まり。点は [x, y]。最初と最後が同じ点なら閉じた形として滑らかにつなぐ
    let strokes: [[[Double]]]

    public static func decode(_ data: Data) throws -> [ConstellationArt] {
        try JSONDecoder().decode([ConstellationArt].self, from: data)
    }

    /// 滑らかにするとき、点と点の間に足す点の数
    public static let smoothingSteps = 5

    /// 天球（赤道座標）に置いた線画。基準の星が足りないときは空
    public var equatorialStrokes: [[EquatorialVector]] {
        guard let placement = Placement(anchors) else { return [] }
        return strokes.map { stroke in
            Self.smoothed(stroke.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil }).map(placement.sky)
        }.filter { $0.count > 1 }
    }

    /// 観測地点・時刻の空に置いた線画
    public func placed(orientation: SkyOrientation, context: SpotContext) -> PlacedConstellationArt {
        let strokes = equatorialStrokes.map { stroke in
            stroke.map { v -> SkyPoint in
                let direction = orientation.direction(v)
                let h = direction.horizontal
                return SkyPoint(direction: direction, isBlocked: context.blocksSky(altitude: h.altitude, azimuth: h.azimuth))
            }
        }
        return PlacedConstellationArt(id: id, strokes: strokes)
    }

    /// Catmull-Rom 曲線で、折れ線の角を丸める（点はすべて通る）
    static func smoothed(_ points: [(Double, Double)]) -> [(Double, Double)] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        let closed = abs(first.0 - last.0) < 1e-9 && abs(first.1 - last.1) < 1e-9
        let n = points.count
        var result: [(Double, Double)] = []
        for i in 0..<(n - 1) {
            let p0 = i > 0 ? points[i - 1] : (closed ? points[n - 2] : points[i])
            let p1 = points[i], p2 = points[i + 1]
            let p3 = i + 2 < n ? points[i + 2] : (closed ? points[1] : points[i + 1])
            for step in 0...smoothingSteps {
                let t = Double(step) / Double(smoothingSteps + 1), t2 = t * t, t3 = t2 * t
                func f(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                result.append((f(p0.0, p1.0, p2.0, p3.0), f(p0.1, p1.1, p2.1, p3.1)))
            }
        }
        result.append(last)
        return result
    }
}

/// 観測地点・時刻の空に置いた星座の線画
public struct PlacedConstellationArt: Identifiable, Sendable {
    public let id: String
    public let strokes: [[SkyPoint]]
}

/// 絵の平面 → 天球。2 つの基準の星の中点で天球に接する平面（心射図法）を作り、
/// 絵の平面からその接平面へは、基準の星が合うような拡大縮小・回転・移動で移す。
struct Placement {
    let center: EquatorialVector
    /// 接平面の右（西）と上（北）
    let right: EquatorialVector
    let up: EquatorialVector
    /// 絵の (x, y) → 接平面の (u, v) [ラジアン] を複素数の掛け算 a・z + b で表したもの
    let a: (re: Double, im: Double)
    let b: (re: Double, im: Double)

    init?(_ anchors: [ConstellationArt.Anchor]) {
        guard anchors.count == 2, anchors.allSatisfy({ $0.at.count >= 2 }),
              let s0 = EquatorialVector(d3Coordinate: anchors[0].star),
              let s1 = EquatorialVector(d3Coordinate: anchors[1].star),
              s0.angle(to: s1) > 0.01 else { return nil }
        let center = s0.plus(s1).normalized
        let pole = EquatorialVector(x: 0, y: 0, z: 1)
        // 天の北極の近くでは東西が決まらないので、春分点の向きを基準にする
        var east = pole.cross(center)
        if east.length < 1e-6 { east = EquatorialVector(x: 0, y: 1, z: 0) }
        east = east.normalized
        let right = east.scaled(-1), up = center.cross(east)
        self.center = center
        self.right = right
        self.up = up

        func plane(_ p: EquatorialVector) -> (Double, Double) {
            let k = p.dot(center)
            return (p.dot(right) / k, p.dot(up) / k)
        }
        let w0 = plane(s0), w1 = plane(s1)
        let z0 = (anchors[0].at[0], anchors[0].at[1]), z1 = (anchors[1].at[0], anchors[1].at[1])
        let dz = (z1.0 - z0.0, z1.1 - z0.1), dw = (w1.0 - w0.0, w1.1 - w0.1)
        let denominator = dz.0 * dz.0 + dz.1 * dz.1
        guard denominator > 1e-12 else { return nil }
        // a = dw / dz（複素数の割り算）
        let a = ((dw.0 * dz.0 + dw.1 * dz.1) / denominator, (dw.1 * dz.0 - dw.0 * dz.1) / denominator)
        self.a = (a.0, a.1)
        self.b = (w0.0 - (a.0 * z0.0 - a.1 * z0.1), w0.1 - (a.0 * z0.1 + a.1 * z0.0))
    }

    /// 絵の点を天球の向きへ
    func sky(_ p: (Double, Double)) -> EquatorialVector {
        let u = a.re * p.0 - a.im * p.1 + b.re
        let v = a.re * p.1 + a.im * p.0 + b.im
        return center.plus(right.scaled(u)).plus(up.scaled(v)).normalized
    }
}
