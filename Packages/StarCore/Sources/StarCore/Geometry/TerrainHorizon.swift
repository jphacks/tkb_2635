import Foundation

/// 地形による地平線（task.md の 2-07）。地点ごとに、方位 1° ごとの「目から最も高く見える地形の点」を持つ。
/// 点は実効標高（地球の丸みと大気差を引いた値）と距離で持ち、仰角は目の標高から計算する。
/// 作り方は scripts/terrain_horizon.py（国土地理院の標高タイル、周囲 3 km）。
public struct TerrainHorizon: Decodable, Sendable {
    /// 地形の 1 点。[実効標高 m, 距離 m] の配列で保存する
    public struct Point: Decodable, Sendable, Equatable {
        public var elevation: Double
        public var distance: Double

        public init(elevation: Double, distance: Double) {
            self.elevation = elevation
            self.distance = distance
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            elevation = try container.decode(Double.self)
            distance = try container.decode(Double.self)
        }
    }

    public var source: String
    /// 地点 ID → 方位 0〜359° の点（地形データが無い方位は nil）
    public var spots: [String: [Point?]]

    public init(source: String, spots: [String: [Point?]]) {
        self.source = source
        self.spots = spots
    }

    /// 地点の目の標高から見た、方位ごとの地形の仰角 [度]（地平線より下は 0）。データが無い地点は nil。
    public func elevations(spotId: String, eyeElevation: Double) -> [Double]? {
        guard let points = spots[spotId], points.count == 360 else { return nil }
        return points.map { point in
            guard let point, point.distance > 0 else { return 0 }
            return max(0, atan2(point.elevation - eyeElevation, point.distance) * 180 / .pi)
        }
    }
}

public extension HorizonProfile {
    /// 建物と地形の仰角の大きいほうを方位ごとに取る
    func combined(withTerrain terrain: [Double]) -> HorizonProfile {
        guard terrain.count == samples.count else { return self }
        return HorizonProfile(samples: zip(samples, terrain).map { max($0, $1) }, isApproximate: isApproximate)
    }
}
