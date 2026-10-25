import Foundation
import StarCore
import SwiftUI
import UIKit

/// 星座の見た目（ガラス調の線・にじむ星・ガラスの名札・淡い線画）の数字を 1 か所にまとめる。
/// 3D の空（RealityKit）と AR（Canvas）で同じ色・濃さにそろえる。
enum ConstellationStyle {
    // MARK: 色（RGB 0〜1）

    /// 星座線の色（淡い水色）
    static let lineRGB: (r: Double, g: Double, b: Double) = (0.72, 0.88, 1)
    /// 星座の線画の色（線より白に近く、目立たせない）
    static let artRGB: (r: Double, g: Double, b: Double) = (0.86, 0.92, 1)
    /// 名札の文字の色
    static let labelTextRGB: (r: Double, g: Double, b: Double) = (0.9, 0.96, 1)

    static var lineColor: Color { Color(red: lineRGB.r, green: lineRGB.g, blue: lineRGB.b) }
    static var artColor: Color { Color(red: artRGB.r, green: artRGB.g, blue: artRGB.b) }
    static var labelTextColor: Color { Color(red: labelTextRGB.r, green: labelTextRGB.g, blue: labelTextRGB.b) }

    // MARK: 濃さ（0〜1）

    /// 星座線の芯（AR）
    static let lineCoreOpacity = 0.75
    /// 3D の星座線の帯全体の濃さ（芯とにじみは `ConstellationTextures.line` の明るさで決まる）
    static let skyLineOpacity = 0.7
    /// 星座線のにじみ（芯のまわりの淡い光）
    static let lineGlowOpacity = 0.35
    /// 星座の線画
    static let artOpacity = 0.22
    /// つなぎ目の星
    static let starOpacity = 0.95
    /// 名札の板（すりガラス）
    static let labelPlateOpacity = 0.14
    /// 名札の縁
    static let labelBorderOpacity = 0.4
    /// 建物などでさえぎられている線・絵・名札にかける濃さ（AR）。「薄く表示」を保つ
    static let blockedOpacity = 0.17
    static let blockedLabelOpacity = 0.28

    // MARK: 3D の空（星空の球の半径を 1 とした大きさ。だいたいラジアンの角度と同じ）

    /// 星空の球（半径 1）より内側に置き、星の画像に隠れないようにする
    static let lineRadius: Float = 0.990
    static let artRadius: Float = 0.992
    static let starRadius: Float = 0.988
    static let labelRadius: Float = 0.985
    /// 線の帯の半分の幅。帯の中で、真ん中の芯だけが明るく、外へ向かってにじむ
    static let lineHalfWidth: Float = 0.003
    static let artHalfWidth: Float = 0.0028
    /// つなぎ目の星の光の半径。明るい星（`ConstellationLabelPicker.brightMagnitude` 以下）は大きくする
    static let starHalfSize: Float = 0.008
    static let brightStarScale: Float = 1.6
    /// 名札の高さ（約 1.4°）
    static let labelHeight: Float = 0.024
    /// 長い線を球面に沿わせるために区切る角度 [度]
    static let arcStep = 1.5
    /// 3D で名札を選ぶ範囲。縦の画角にこの割合をかけた角度まで（縦長の画面の角あたり）
    static let labelFieldFraction = 0.6

    // MARK: AR（画面の大きさ [pt]）

    static let arLineWidth: CGFloat = 0.9
    static let arGlowWidth: CGFloat = 3.5
    static let arGlowBlur: CGFloat = 3
    static let arArtWidth: CGFloat = 0.9
    static let arStarCoreRadius: CGFloat = 1.6
    static let arStarGlowRadius: CGFloat = 6
    static let labelFontSize: CGFloat = 12
    static let labelPadding = CGSize(width: 9, height: 4)

    // MARK: 星座の姿の画像（PNG）

    /// 画像全体にかける濃さ。画像そのものにも半透明と光が入っているので、線画（artOpacity）より濃くする
    static let imageOpacity = 0.5
    /// 3D の空に置く画像の半径（線画と同じ。星空の球の内側）
    static let imageRadius: Float = 0.992
    /// 3D で画像を球面に沿わせる網目の細かさ（縦横それぞれのます数）
    static let imageDivisions = 24
}

/// 星座線・線画・画像のデータ（App/Resources/Sky の JSON と PNG）。一度だけ読む
@MainActor
enum ConstellationData {
    static let lines: [ConstellationLines] = load("constellations").flatMap { try? ConstellationLines.decode($0) } ?? []
    /// 星座の姿の画像。天球に置けて、PNG も読めたものだけ
    static let images: [ConstellationImage] = (load("constellation-images").flatMap { try? ConstellationImage.decode($0) } ?? [])
        .filter { $0.placement != nil && ConstellationImageAssets.image(named: $0.image) != nil }
    /// 自作の簡略な線画。画像を出す星座には重ねない（画像が読めないときは線画に戻る）
    static let art: [ConstellationArt] = {
        let imageIDs = Set(images.map(\.id))
        return (load("constellation-art").flatMap { try? ConstellationArt.decode($0) } ?? []).filter { !imageIDs.contains($0.id) }
    }()

    private static func load(_ name: String) -> Data? {
        Bundle.main.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }
}

/// 星座の画像（PNG）の読み込み。AR の描画（メインスレッドの外から呼ばれることがある）からも使うので、ここは画面の状態を持たない
enum ConstellationImageAssets {
    private static let cache: [String: UIImage] = {
        guard let data = Bundle.main.url(forResource: "constellation-images", withExtension: "json")
            .flatMap({ try? Data(contentsOf: $0) }),
              let images = try? ConstellationImage.decode(data) else { return [:] }
        var result: [String: UIImage] = [:]
        for image in images {
            if let url = Bundle.main.url(forResource: image.image, withExtension: "png"),
               let ui = UIImage(contentsOfFile: url.path) { result[image.image] = ui }
        }
        return result
    }()

    static func image(named name: String) -> UIImage? { cache[name] }
}
