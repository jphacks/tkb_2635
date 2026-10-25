import UIKit

/// 夜の建物の見た目の値。詳細画面の都市モデル（CityModelRenderer：実写の外壁を夜の調子にし、窓の明かりの部品を光らせる）に
/// 広域 3D（WideCityRenderer）を合わせるため、ここに 1 か所にまとめる。
/// CityModelRenderer はほかの人の作業とぶつからないよう今は書き換えず、同じ値をここに写している（値を変えるときは両方そろえる）。
enum BuildingNightStyle {
    /// 窓明かりの 3 色（CityModelRenderer.lightColor の windows_<色> と同じ。暖色・白っぽい暖色・青白い）と、その出やすさ
    static let windowColors: [(color: UIColor, weight: Int)] = [
        (UIColor(red: 1.0, green: 0.74, blue: 0.40, alpha: 1), 5),
        (UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1), 3),
        (UIColor(red: 0.86, green: 0.91, blue: 0.98, alpha: 1), 2),
    ]
    /// 点いている窓の割合
    static let litRatio = 0.35
    /// 外壁の色。詳細画面の実写の外壁（夜の色 0.16, 0.18, 0.27 と写真の発光 0.3）の見た目に近い、ほぼ無彩色の灰色
    static let wall = UIColor(red: 0.31, green: 0.31, blue: 0.33, alpha: 1)
    /// 外壁がわずかに自分で光る色と強さ（照明の向きに関係なく形が読めるように）
    static let wallGlow = UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1)
    static let wallGlowIntensity: Float = 0.2
    /// 窓明かりの光る強さ
    static let windowGlowIntensity: Float = 1
    /// 窓 1 マスの大きさ [m]（BuildingFacade の窓ベイ・階高と同じ）
    static let columnMeters = Double(BuildingFacade.columnMeters)
    static let floorMeters = Double(BuildingFacade.floorMeters)
}
