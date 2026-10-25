import Foundation

extension LocalVector {
    /// 地平座標（高度・方位）。方位は北が 0°、東が 90°
    public var horizontal: HorizontalCoord {
        HorizontalCoord(altitude: asin(max(-1, min(1, up))) * 180 / .pi,
                        azimuth: Angle.normalize(atan2(east, north) * 180 / .pi))
    }
}

extension SpotContext {
    /// その方向が、建物・地形、または見える方向の制限でさえぎられているか。
    /// 判定は推薦（`Recommender`）と同じ余裕 `visibilityMargin` を使う。地平線より下は「さえぎられている」のではなく見えない方向なので false。
    public func blocksSky(altitude: Double, azimuth: Double) -> Bool {
        guard altitude > 0 else { return false }
        return altitude <= horizon.elevation(at: azimuth) + Recommender.visibilityMargin
            || spot.isBlockedByViewingLimits(azimuth: azimuth, altitude: altitude)
    }
}
