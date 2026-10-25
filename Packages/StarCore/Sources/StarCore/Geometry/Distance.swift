import Foundation

/// 2 点間の距離（現在地から観測地点までなど）
public enum Distance {
    /// 地球の平均半径 [km]（IUGG）
    public static let earthRadiusKm = 6371.0088

    /// 緯度経度 [度] の 2 点間の大圏距離 [km]（haversine 公式）
    public static func greatCircleKm(fromLatitude lat1: Double, fromLongitude lon1: Double,
                                     toLatitude lat2: Double, toLongitude lon2: Double) -> Double {
        let toRadians = Double.pi / 180
        let dLat = (lat2 - lat1) * toRadians
        let dLon = (lon2 - lon1) * toRadians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * toRadians) * cos(lat2 * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        // 丸め誤差で 1 をわずかに超えると asin が NaN になるので抑える
        return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
    }

    /// 画面に出す距離の文（1 km 未満は m、10 km 未満は小数 1 桁、それ以上は整数 km）
    public static func label(km: Double) -> String {
        if km < 1 { return "\(Int((km * 1000 / 10).rounded()) * 10) m" }
        if km < 10 { return String(format: "%.1f km", km) }
        return "\(Int(km.rounded())) km"
    }
}
