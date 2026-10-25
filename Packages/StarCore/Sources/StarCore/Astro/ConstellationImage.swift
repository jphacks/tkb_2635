import Foundation

/// 星座の姿の画像（`constellation-images.json` と PNG）。画像の画素と恒星の対応（基準点）から、
/// 画像を天球の上に、恒星と同じ向きで置く。
///
/// 画像の座標は左上が (0, 0)、右が +x、下が +y [画素]。
/// 天球へは、基準点の星の中心で天球に接する平面（空を見上げた見た目: 右が西、上が北）を経由して写す。
/// 基準点が 2 つなら拡大縮小・回転・移動だけ、3 つ以上なら基準点をすべて通るように画像をなめらかに変形する（薄板スプライン）。
public struct ConstellationImage: Decodable, Identifiable, Sendable {
    public struct Anchor: Decodable, Sendable {
        /// 星の位置 [経度（-180〜180、d3-celestial と同じ）, 赤緯]
        let star: [Double]
        /// 画像の上の位置 [x, y]（左上が原点、y は下向き）
        let pixel: [Double]
        /// 画像にこの星の光る印が描き込まれているか（アプリの星の光と二重にしないため）
        let marked: Bool?
    }

    /// 星座の id（`constellations.json` と同じ）
    public let id: String
    /// 画像のファイル名（拡張子なし、png）
    public let image: String
    /// 画像の大きさ [幅, 高さ]（画素）
    let size: [Double]
    let anchors: [Anchor]

    public static func decode(_ data: Data) throws -> [ConstellationImage] {
        try JSONDecoder().decode([ConstellationImage].self, from: data)
    }

    /// 天球への置き方。設定がおかしい（基準点が足りない・重なる・画像が折れ返る・大きすぎる）ときは nil
    public var placement: ConstellationImagePlacement? {
        guard size.count == 2, size[0] > 0, size[1] > 0 else { return nil }
        let pairs = anchors.compactMap { anchor -> (pixel: (Double, Double), star: EquatorialVector)? in
            guard anchor.pixel.count >= 2, let star = EquatorialVector(d3Coordinate: anchor.star) else { return nil }
            return ((anchor.pixel[0], anchor.pixel[1]), star)
        }
        guard pairs.count == anchors.count else { return nil }
        return ConstellationImagePlacement(width: size[0], height: size[1], anchors: pairs)
    }

    /// 画像に光る印が描き込まれている星
    public var markedStars: [EquatorialVector] {
        anchors.filter { $0.marked == true }.compactMap { EquatorialVector(d3Coordinate: $0.star) }
    }

    /// 観測地点・時刻の空に置いた画像の網目（AR 用）
    public func placed(orientation: SkyOrientation, context: SpotContext, divisions: Int) -> PlacedConstellationImage? {
        guard let placement else { return nil }
        func point(_ v: EquatorialVector) -> SkyPoint {
            let direction = orientation.direction(v)
            let h = direction.horizontal
            return SkyPoint(direction: direction, isBlocked: context.blocksSky(altitude: h.altitude, azimuth: h.azimuth))
        }
        return PlacedConstellationImage(id: id, image: image, width: placement.width, height: placement.height,
                                        divisions: divisions, grid: placement.grid(divisions: divisions).map { $0.map(point) },
                                        markedStars: markedStars.map(point))
    }
}

/// 観測地点・時刻の空に置いた星座の画像
public struct PlacedConstellationImage: Identifiable, Sendable {
    public let id: String
    public let image: String
    public let width: Double
    public let height: Double
    /// 網目の分け方（縦横それぞれ divisions 個のます）
    public let divisions: Int
    /// 網目の点。grid[行][列]。行は画像の上（y = 0）から下へ、列は左（x = 0）から右へ
    public let grid: [[SkyPoint]]
    /// 画像に光る印が描き込まれている星
    public let markedStars: [SkyPoint]
}

/// 画像の画素 → 天球の向き
public struct ConstellationImagePlacement: Sendable {
    /// 画像の幅が天球の上でこれより小さい・大きい [度] 設定はおかしいとみなす
    public static let minimumSpan = 2.0
    public static let maximumSpan = 90.0
    /// 折れ返りを調べる網目の細かさ
    static let foldCheckDivisions = 16

    public let width: Double
    public let height: Double
    private let center: EquatorialVector
    private let right: EquatorialVector
    private let up: EquatorialVector
    /// 画像の点（x, -y）→ 接平面（右・上）[ラジアン]
    private let warp: PlaneWarp

    init?(width: Double, height: Double, anchors: [(pixel: (Double, Double), star: EquatorialVector)]) {
        guard anchors.count >= 2 else { return nil }
        // 基準点どうしが画像の上でも空の上でも重ならないこと
        for i in anchors.indices {
            for j in anchors.indices where j > i {
                let a = anchors[i], b = anchors[j]
                guard hypot(a.pixel.0 - b.pixel.0, a.pixel.1 - b.pixel.1) > 1, a.star.angle(to: b.star) > 0.05 else { return nil }
            }
        }
        let sum = anchors.reduce(EquatorialVector(x: 0, y: 0, z: 0)) { $0.plus($1.star) }
        guard sum.length > 1e-6 else { return nil }
        let center = sum.normalized
        var east = EquatorialVector(x: 0, y: 0, z: 1).cross(center)
        if east.length < 1e-6 { east = EquatorialVector(x: 0, y: 1, z: 0) }
        east = east.normalized
        let right = east.scaled(-1), up = center.cross(east)
        // 基準の星が接平面の前（中心から 90°未満）にあること
        guard anchors.allSatisfy({ $0.star.dot(center) > 0.2 }) else { return nil }

        // 画像の y は下向きなので、ここで一度だけ上向きに直す
        let source = anchors.map { ($0.pixel.0, -$0.pixel.1) }
        let target = anchors.map { a -> (Double, Double) in
            let k = a.star.dot(center)
            return (a.star.dot(right) / k, a.star.dot(up) / k)
        }
        guard let warp = PlaneWarp(source: source, target: target) else { return nil }

        self.width = width
        self.height = height
        self.center = center
        self.right = right
        self.up = up
        self.warp = warp

        let span = sky(x: 0, y: height / 2).angle(to: sky(x: width, y: height / 2))
        guard span >= Self.minimumSpan, span <= Self.maximumSpan, !isFolded else { return nil }
    }

    /// 画像の画素 (x, y)（左上が原点、y は下向き）の天球の向き
    public func sky(x: Double, y: Double) -> EquatorialVector {
        let p = warp.map((x, -y))
        return center.plus(right.scaled(p.0)).plus(up.scaled(p.1)).normalized
    }

    /// 画像を縦横 divisions 個のますに分けた網目の点。grid[行][列]、行は上から下、列は左から右
    public func grid(divisions: Int) -> [[EquatorialVector]] {
        let n = max(1, divisions)
        return (0...n).map { row in
            (0...n).map { column in
                sky(x: width * Double(column) / Double(n), y: height * Double(row) / Double(n))
            }
        }
    }

    /// 変形で画像が折れ返っていないか（ますの向き（符号付きの面積）がそろっているか）
    var isFolded: Bool {
        let n = Self.foldCheckDivisions
        var sign = 0.0
        for row in 0..<n {
            for column in 0..<n {
                let x0 = width * Double(column) / Double(n), x1 = width * Double(column + 1) / Double(n)
                let y0 = height * Double(row) / Double(n), y1 = height * Double(row + 1) / Double(n)
                let a = warp.map((x0, -y0)), b = warp.map((x1, -y0)), c = warp.map((x0, -y1))
                let area = (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0)
                if abs(area) < 1e-15 { return true }
                if sign == 0 { sign = area > 0 ? 1 : -1 } else if (area > 0 ? 1 : -1) != sign { return true }
            }
        }
        return false
    }
}

/// 平面から平面への写し方。2 点なら相似変換（拡大縮小・回転・移動）、3 点以上なら薄板スプライン（基準点をすべて通る）
struct PlaneWarp: Sendable {
    private let source: [(Double, Double)]
    /// x・y それぞれの重み（基準点ごとの重み n 個 + 定数・x・y の 3 個）
    private let weightsX: [Double]
    private let weightsY: [Double]
    /// 相似変換のとき: target = a * source + b（複素数）
    private let similarity: (a: (Double, Double), b: (Double, Double))?

    init?(source: [(Double, Double)], target: [(Double, Double)]) {
        guard source.count == target.count, source.count >= 2 else { return nil }
        self.source = source
        if source.count == 2 {
            let dz = (source[1].0 - source[0].0, source[1].1 - source[0].1)
            let dw = (target[1].0 - target[0].0, target[1].1 - target[0].1)
            let d = dz.0 * dz.0 + dz.1 * dz.1
            guard d > 1e-12 else { return nil }
            let a = ((dw.0 * dz.0 + dw.1 * dz.1) / d, (dw.1 * dz.0 - dw.0 * dz.1) / d)
            let b = (target[0].0 - (a.0 * source[0].0 - a.1 * source[0].1), target[0].1 - (a.0 * source[0].1 + a.1 * source[0].0))
            similarity = (a, b)
            weightsX = []
            weightsY = []
            return
        }
        let n = source.count
        var k = [[Double]](repeating: [Double](repeating: 0, count: n + 3), count: n + 3)
        for i in 0..<n {
            for j in 0..<n { k[i][j] = Self.kernel(source[i], source[j]) }
            k[i][n] = 1; k[i][n + 1] = source[i].0; k[i][n + 2] = source[i].1
            k[n][i] = 1; k[n + 1][i] = source[i].0; k[n + 2][i] = source[i].1
        }
        guard let wx = Self.solve(k, target.map(\.0) + [0, 0, 0]),
              let wy = Self.solve(k, target.map(\.1) + [0, 0, 0]) else { return nil }
        weightsX = wx
        weightsY = wy
        similarity = nil
    }

    func map(_ p: (Double, Double)) -> (Double, Double) {
        if let s = similarity {
            return (s.a.0 * p.0 - s.a.1 * p.1 + s.b.0, s.a.0 * p.1 + s.a.1 * p.0 + s.b.1)
        }
        let n = source.count
        var x = weightsX[n] + weightsX[n + 1] * p.0 + weightsX[n + 2] * p.1
        var y = weightsY[n] + weightsY[n + 1] * p.0 + weightsY[n + 2] * p.1
        for i in 0..<n {
            let u = Self.kernel(p, source[i])
            x += weightsX[i] * u
            y += weightsY[i] * u
        }
        return (x, y)
    }

    /// 薄板スプラインの基本の形 r² log r
    private static func kernel(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r2 = (a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1)
        return r2 < 1e-12 ? 0 : r2 * log(r2) / 2
    }

    /// 連立一次方程式（部分ピボットのガウス消去）。解けないときは nil
    private static func solve(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        var m = matrix, v = vector
        let n = v.count
        for i in 0..<n {
            guard let pivot = (i..<n).max(by: { abs(m[$0][i]) < abs(m[$1][i]) }), abs(m[pivot][i]) > 1e-12 else { return nil }
            m.swapAt(i, pivot)
            v.swapAt(i, pivot)
            for r in 0..<n where r != i {
                let f = m[r][i] / m[i][i]
                guard f != 0 else { continue }
                for c in i..<n { m[r][c] -= f * m[i][c] }
                v[r] -= f * v[i]
            }
        }
        return (0..<n).map { v[$0] / m[$0][$0] }
    }
}

/// 画面の三角形どうしを結ぶ一次変換（AR で画像を網目ごとに貼るのに使う）。
/// x' = a·x + c·y + tx、y' = b·x + d·y + ty（CoreGraphics の CGAffineTransform と同じ並び）
public struct TriangleAffine: Sendable, Equatable {
    public let a, b, c, d, tx, ty: Double

    /// from の 3 点を to の 3 点へ移す変換。from の 3 点が一直線上にあるときは nil
    public init?(from p: [(Double, Double)], to q: [(Double, Double)]) {
        guard p.count == 3, q.count == 3 else { return nil }
        let det = (p[1].0 - p[0].0) * (p[2].1 - p[0].1) - (p[2].0 - p[0].0) * (p[1].1 - p[0].1)
        guard abs(det) > 1e-9 else { return nil }
        let u1 = (p[1].0 - p[0].0, p[1].1 - p[0].1), u2 = (p[2].0 - p[0].0, p[2].1 - p[0].1)
        let v1 = (q[1].0 - q[0].0, q[1].1 - q[0].1), v2 = (q[2].0 - q[0].0, q[2].1 - q[0].1)
        // [a c; b d] = V · U⁻¹
        a = (v1.0 * u2.1 - v2.0 * u1.1) / det
        c = (v2.0 * u1.0 - v1.0 * u2.0) / det
        b = (v1.1 * u2.1 - v2.1 * u1.1) / det
        d = (v2.1 * u1.0 - v1.1 * u2.0) / det
        tx = q[0].0 - a * p[0].0 - c * p[0].1
        ty = q[0].1 - b * p[0].0 - d * p[0].1
    }
}
