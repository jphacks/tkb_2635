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
    /// シーンの共通 groundElevation から屋根までの有効高さ [m]
    public var height: Double
    public var usage: String?
    /// 遮蔽判定に使う部分の箱（LOD2 の形から作る。省略時は上の箱 1 つで判定する）。表示・タップは上の箱を使う
    public var parts: [BuildingPart]?
}

/// 代表地点の周辺建物。原典と近似・暫定値の注意は source に記録する。
public struct CityScene: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var originLatitude: Double
    public var originLongitude: Double
    /// 地面の標高 [m]（シーン内は平坦と見なす）
    public var groundElevation: Double
    public var source: String
    public var buildings: [Building]
    /// 観測者の目線へ入れるシーンで true にする（今は全シーン）。合わないシーンは省くか false にし、全体表示だけにする。
    public var observerViewEnabled: Bool?

    /// 緯度経度をシーン原点からの東・北方向の距離 [m] に変換する
    public func localPosition(latitude: Double, longitude: Double) -> (east: Double, north: Double) {
        let metersPerDegLat = 110_574.0
        let metersPerDegLon = 111_320.0 * cos(originLatitude * .pi / 180)
        return ((longitude - originLongitude) * metersPerDegLon,
                (latitude - originLatitude) * metersPerDegLat)
    }
}
