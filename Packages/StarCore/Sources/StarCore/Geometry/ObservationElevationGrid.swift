import Foundation

/// 地域の原点から東・北のメートルで持つ標高格子。欠損は nil のまま扱う。
public struct ObservationElevationGrid: Codable, Sendable {
    public let minEast: Double
    public let minNorth: Double
    public let step: Double
    public let columns: Int
    public let rows: Int
    public let values: [Double?]

    public func elevation(east: Double, north: Double) -> Double? {
        guard step.isFinite, step > 0, columns >= 2, rows >= 2,
              columns <= values.count, rows <= values.count / columns,
              values.count == columns * rows else { return nil }
        let x = (east - minEast) / step
        let y = (north - minNorth) / step
        guard x.isFinite, y.isFinite, x >= 0, y >= 0,
              x <= Double(columns - 1), y <= Double(rows - 1) else { return nil }
        let col = min(Int(x), columns - 2)
        let row = min(Int(y), rows - 2)
        let dx = x - Double(col), dy = y - Double(row)
        let corners = [
            (row * columns + col, (1 - dx) * (1 - dy)),
            (row * columns + col + 1, dx * (1 - dy)),
            ((row + 1) * columns + col, (1 - dx) * dy),
            ((row + 1) * columns + col + 1, dx * dy)
        ]
        var height = 0.0
        for (index, weight) in corners where weight > 0 {
            guard let value = values[index], value.isFinite else { return nil }
            height += value * weight
        }
        return height
    }

    /// 任意の観測位置から周囲3kmの地形を調べる。登録地点の地平線を流用しない。
    func horizon(east: Double, north: Double, eyeElevation: Double) -> [Double]? {
        var result = [Double]()
        for azimuth in 0..<360 {
            let angle = Double(azimuth) * .pi / 180
            var highest = 0.0
            for distance in stride(from: Self.terrainStep, through: Self.terrainRadius, by: Self.terrainStep) {
                guard let ground = elevation(east: east + sin(angle) * distance,
                                             north: north + cos(angle) * distance) else { return nil }
                let drop = (1 - Self.refraction) * distance * distance / (2 * Self.earthRadius)
                highest = max(highest, atan2(ground - drop - eyeElevation, distance) * 180 / .pi)
            }
            result.append(highest)
        }
        return result
    }

    private static let terrainRadius = 3_000.0
    private static let terrainStep = 100.0
    private static let earthRadius = 6_371_000.0
    private static let refraction = 0.13
}
