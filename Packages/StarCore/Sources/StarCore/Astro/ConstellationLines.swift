import Foundation

/// 星座線の元データ（`constellations.json`、d3-celestial）。赤経・赤緯 [度] の点をつないだ折れ線の集まり。
public struct ConstellationLines: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// 折れ線ごとの点。点は [赤経（-180〜180 で東回りの経度）, 赤緯]
    let paths: [[[Double]]]

    public static func decode(_ data: Data) throws -> [ConstellationLines] {
        try JSONDecoder().decode([ConstellationLines].self, from: data)
    }
}

/// 空の 1 点（地平の向き）と、そこが建物などでさえぎられているか
public struct SkyPoint: Sendable {
    public let direction: LocalVector
    public let isBlocked: Bool
}

/// 観測地点・時刻の空に置いた星座線
public struct PlacedConstellation: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let polylines: [[SkyPoint]]
    /// 名前を出す位置（線の中心あたり）。向きが定まらないときは nil
    public let label: SkyPoint?
}

extension ConstellationLines {
    func placed(orientation: SkyOrientation, context: SpotContext) -> PlacedConstellation {
        func point(_ vector: LocalVector) -> SkyPoint {
            let h = vector.horizontal
            return SkyPoint(direction: vector, isBlocked: context.blocksSky(altitude: h.altitude, azimuth: h.azimuth))
        }
        var sum = LocalVector(east: 0, north: 0, up: 0)
        var count = 0.0
        let lines = paths.map { path in
            path.compactMap { coordinate -> SkyPoint? in
                guard coordinate.count >= 2 else { return nil }
                let vector = orientation.direction(rightAscension: coordinate[0] < 0 ? coordinate[0] + 360 : coordinate[0],
                                                   declination: coordinate[1])
                sum = LocalVector(east: sum.east + vector.east, north: sum.north + vector.north, up: sum.up + vector.up)
                count += 1
                return point(vector)
            }
        }
        // 点の平均の向き。星座は空の一部に収まるので、平均して長さを 1 に戻せば中心になる
        let center = sum.normalized
        let hasCenter = count > 0 && sum.dot(sum) > 1e-6
        return PlacedConstellation(id: id, name: name, polylines: lines.filter { $0.count > 1 },
                                   label: hasCenter ? point(center) : nil)
    }
}
