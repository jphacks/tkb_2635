import Foundation

/// 建物（直方体で近似）。x は東、y は北方向のシーン原点からの距離 [m]。
public struct Building: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double
    /// 東西方向の幅 [m]
    public var width: Double
    /// 南北方向の奥行き [m]
    public var depth: Double
    /// 地面からの高さ [m]
    public var height: Double
    public var usage: String?
}

/// 代表地点の周辺建物をまとめたもの。MVP では PLATEAU を取り込まず手作りの概略データを使う。
public struct CityScene: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var originLatitude: Double
    public var originLongitude: Double
    /// 地面の標高 [m]（シーン内は平坦と見なす）
    public var groundElevation: Double
    public var source: String
    public var buildings: [Building]

    /// 緯度経度をシーン原点からの東・北方向の距離 [m] に変換する
    public func localPosition(latitude: Double, longitude: Double) -> (east: Double, north: Double) {
        let metersPerDegLat = 110_574.0
        let metersPerDegLon = 111_320.0 * cos(originLatitude * .pi / 180)
        return ((longitude - originLongitude) * metersPerDegLon,
                (latitude - originLatitude) * metersPerDegLat)
    }
}
