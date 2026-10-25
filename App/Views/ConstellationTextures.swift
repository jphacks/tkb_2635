import CoreGraphics
import RealityKit
import UIKit

/// 3D の星座で使う画像（線のにじみ・星の光・ガラスの名札）を作る。
/// 光の画像は白黒で、明るさ = 不透明度にしてある（色はマテリアルで付ける）。
@MainActor
enum ConstellationTextures {
    /// 線の帯の横断面。真ん中の細い芯と、外へ広がる淡いにじみ
    static let line: TextureResource? = profile { d in 0.8 * exp(-pow(d / 0.14, 2)) + 0.22 * exp(-pow(d / 0.55, 2)) }
    /// 線画の帯の横断面。芯を弱くして、線より柔らかく見せる
    static let art: TextureResource? = profile { d in 0.55 * exp(-pow(d / 0.22, 2)) + 0.22 * exp(-pow(d / 0.6, 2)) }
    /// つなぎ目の星。小さな明るい芯と、にじむ光
    static let star: TextureResource? = radial { d in min(1, exp(-pow(d / 0.09, 2)) + 0.5 * exp(-pow(d / 0.32, 2))) }

    private static let profileSize = 64
    private static let radialSize = 64

    /// 帯の横断面（v 方向）の画像。d は帯の中心からの距離（0〜1）
    private static func profile(_ brightness: (Double) -> Double) -> TextureResource? {
        image(width: 4, height: profileSize) { _, y in
            brightness(abs((Double(y) + 0.5) / Double(profileSize) * 2 - 1))
        }
    }

    /// 丸い光の画像。d は中心からの距離（0〜1）
    private static func radial(_ brightness: (Double) -> Double) -> TextureResource? {
        image(width: radialSize, height: radialSize) { x, y in
            let dx = (Double(x) + 0.5) / Double(radialSize) * 2 - 1
            let dy = (Double(y) + 0.5) / Double(radialSize) * 2 - 1
            let d = (dx * dx + dy * dy).squareRoot()
            return d >= 1 ? 0 : brightness(d) * (1 - pow(d, 8))
        }
    }

    private static func image(width: Int, height: Int, value: (Int, Int) -> Double) -> TextureResource? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = UInt8(max(0, min(1, value(x, y))) * 255)
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = v
            }
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return try? TextureResource(image: cgImage, options: .init(semantic: .color))
    }

    /// ガラスの名札の画像と、その大きさ [pt]。淡い板・細い縁・上側の照り返し・光る文字
    static func label(_ text: String) -> (texture: TextureResource, size: CGSize)? {
        let font = UIFont.systemFont(ofSize: ConstellationStyle.labelFontSize, weight: .semibold)
        let style = ConstellationStyle.self
        let textColor = UIColor(red: style.labelTextRGB.r, green: style.labelTextRGB.g, blue: style.labelTextRGB.b, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .kern: 0.6]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let plate = CGSize(width: ceil(textSize.width + style.labelPadding.width * 2),
                           height: ceil(textSize.height + style.labelPadding.height * 2))
        // 文字の光が切れないよう、外側に余白を取る
        let margin: CGFloat = 4
        let size = CGSize(width: plate.width + margin * 2, height: plate.height + margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: CGPoint(x: margin, y: margin), size: plate)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: plate.height / 2)
            UIColor(white: 1, alpha: style.labelPlateOpacity).setFill()
            path.fill()
            // 上半分の照り返し（ガラスの厚みの感じ）
            cg.saveGState()
            path.addClip()
            let colors = [UIColor(white: 1, alpha: 0.16).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.midY), options: [])
            }
            cg.restoreGState()
            UIColor(white: 1, alpha: style.labelBorderOpacity).setStroke()
            path.lineWidth = 0.6
            path.stroke()
            cg.setShadow(offset: .zero, blur: 4,
                         color: UIColor(red: style.lineRGB.r, green: style.lineRGB.g, blue: style.lineRGB.b, alpha: 0.9).cgColor)
            (text as NSString).draw(at: CGPoint(x: rect.minX + style.labelPadding.width,
                                                y: rect.minY + style.labelPadding.height), withAttributes: attributes)
        }
        guard let cgImage = image.cgImage,
              let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color)) else { return nil }
        return (texture, size)
    }
}
