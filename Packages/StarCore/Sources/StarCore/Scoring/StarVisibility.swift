import Foundation

/// 3D の星空の濃さ（4-12）。地点の暗さで、星図の画像（見える一番暗い星の等級ごと）を選ぶ。
/// 見た目だけに使い、判定・スコアには使わない。
public enum StarVisibility {
    /// 星図の段階
    public enum Level: Int, CaseIterable, Sendable {
        /// 都心（約 3 等まで）
        case city
        /// 郊外（約 4.5 等まで）
        case suburban
        /// 暗い場所（約 6 等まで。天の川が見える）
        case dark

        /// 画像の名前（App/Resources/Sky/）
        public var textureName: String {
            switch self {
            case .city: "stars_city"
            case .suburban: "stars_suburban"
            case .dark: "stars_dark"
            }
        }

        /// 見える一番暗い星の等級（画像を作るときの目安）
        public var limitingMagnitude: Double {
            switch self {
            case .city: 3.0
            case .suburban: 4.5
            case .dark: 6.0
            }
        }
    }

    /// 暗さ D がこれ以上なら郊外の星空
    public static let suburbanThreshold = 0.35
    /// 暗さ D がこれ以上なら暗い場所の星空
    public static let darkThreshold = 0.6

    /// 空の暗さ（0〜1、Recommender.darkness と同じ尺度）から星図の段階を選ぶ
    public static func level(darkness: Double) -> Level {
        switch darkness {
        case darkThreshold...: .dark
        case suburbanThreshold...: .suburban
        default: .city
        }
    }

    /// 星空の明るさ（0〜1）。太陽が出ている・市民薄明では 0、夜は 1。薄明の間は直線で変える
    public static func opacity(sunAltitude: Double) -> Double {
        1 - Twilight.skyBrightnessFactor(sunAltitude: sunAltitude)
    }

    /// 地点の空の暗さ。月明かりは天頂の向きで見積もる（どの天体を見ていても、星空全体は月で明るくなる）
    public static func skyDarkness(spot: Spot, moon: MoonInfo) -> Double {
        let zenith = HorizontalCoord(altitude: 90, azimuth: 0)
        return Recommender.darkness(skyBrightness: spot.regionalLightIndex ?? 0.5,
                                    localGlareLevel: spot.localGlareLevel,
                                    moonEffect: Recommender.moonEffect(moon: moon, target: zenith)).value
    }
}
