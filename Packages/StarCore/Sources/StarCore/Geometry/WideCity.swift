import Foundation

/// 23 区の広域 3D（`Wide_<区コード>.usdz`・`Wide2_<区コード>.usdz`）の座標と、近い区を選ぶ計算。
/// USDZ は scripts/wide_ward_blender.py で、渋谷の原点からの東・北 [m]、高さはジオイド高を引いた標高 [m] で作ってある。
public enum WideCity {
    /// scripts/wide_ward_blender.py の ORIGIN_LATITUDE / ORIGIN_LONGITUDE と同じ
    public static let originLatitude = 35.658
    public static let originLongitude = 139.7016

    /// 区の箱のファイル名の頭。これに区コードが続く
    public static let boxPrefix = "Wide_"
    /// 屋根の形つき（LOD2）のファイル名の頭
    public static let detailPrefix = "Wide2_"

    /// 緯度経度 → 渋谷の原点からの東・北 [m]（CityScene.localPosition・wide_ward_blender.py と同じ式）
    public static func localPosition(latitude: Double, longitude: Double) -> (east: Double, north: Double) {
        let metersPerDegLat = 110_574.0
        let metersPerDegLon = 111_320.0 * cos(originLatitude * .pi / 180)
        return ((longitude - originLongitude) * metersPerDegLon, (latitude - originLatitude) * metersPerDegLat)
    }

    /// ファイル名（拡張子なし）から区コードを取り出す。箱のファイルでなければ nil
    public static func wardCode(fromBoxFile name: String) -> String? {
        guard name.hasPrefix(boxPrefix) else { return nil }
        let code = String(name.dropFirst(boxPrefix.count))
        return code.isEmpty ? nil : code
    }

    /// 区の広がり（東・北 [m] の長方形）
    public struct WardBounds: Equatable, Sendable {
        public let code: String
        public let minEast: Double, maxEast: Double, minNorth: Double, maxNorth: Double

        public init(code: String, minEast: Double, maxEast: Double, minNorth: Double, maxNorth: Double) {
            self.code = code
            self.minEast = minEast
            self.maxEast = maxEast
            self.minNorth = minNorth
            self.maxNorth = maxNorth
        }

        /// 点から長方形までの距離 [m]。中にあれば 0
        public func distance(east: Double, north: Double) -> Double {
            let dx = max(minEast - east, 0, east - maxEast)
            let dy = max(minNorth - north, 0, north - maxNorth)
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// 見ている中心に近い順に、最大 limit 区の区コードを返す。maxDistance [m] より遠い区は入れない
    public static func nearestWards(_ wards: [WardBounds], east: Double, north: Double,
                                    limit: Int, maxDistance: Double) -> [String] {
        var near: [(code: String, distance: Double)] = []
        for ward in wards {
            let distance = ward.distance(east: east, north: north)
            if distance <= maxDistance { near.append((ward.code, distance)) }
        }
        near.sort { a, b in a.distance == b.distance ? a.code < b.code : a.distance < b.distance }
        return near.prefix(max(limit, 0)).map { $0.code }
    }
}
