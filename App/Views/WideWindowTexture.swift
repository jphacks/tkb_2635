import CoreGraphics
import UIKit

/// 広域 3D の箱の壁に繰り返し貼る、窓明かりの画像（自分で光る色として使う）。BuildingNightStyle の色で、アプリの中で描く。
/// 1 枚が窓 tileColumns 列 × tileRows 階。scripts/wide_ward_blender.py の TILE_WIDTH・TILE_HEIGHT はこの大きさ [m]。
/// 詳細画面の窓と同じく、各階の窓を横長の帯にする。屋根と窓の無い所は外壁の自己発光の色。
enum WideWindowTexture {
    static let tileColumns = 8
    static let tileRows = 8
    private static let pixels = 256
    /// 1 マスの中の窓の縦の範囲（下から）。屋根が指す UV（0.01, 0.01）と上下を入れ替えた位置は窓の外になる
    private static let windowBottom = 0.30
    private static let windowTop = 0.78
    /// 点いた窓の隣も点いている確率と、点き始める確率の倍率（平均の点灯率が litRatio くらいになる値）
    private static let continueRatio = 0.7
    private static let startScale = 0.55
    /// 同じ画像になるよう乱数の種を決めておく
    private static let seed: UInt64 = 2635

    static func image() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(wallGlowColor())
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let cellWidth = CGFloat(pixels) / CGFloat(tileColumns), cellHeight = CGFloat(pixels) / CGFloat(tileRows)
        let tones = BuildingNightStyle.windowColors.flatMap { Array(repeating: $0.color, count: $0.weight) }
        var random = SplitMix(state: seed)
        for row in 0..<tileRows {
            // 詳細画面の都市モデルと同じく、点いた窓は同じ階で横に続きやすくする（同じ色で数マス続く）
            var lit = false
            var tone = tones[0]
            var brightness = 1.0
            for column in 0..<tileColumns {
                let chance = lit ? continueRatio : BuildingNightStyle.litRatio * startScale
                let wasLit = lit
                lit = random.unit() < chance
                if lit && !wasLit {
                    tone = tones[Int(random.unit() * Double(tones.count)) % tones.count]
                    brightness = 0.7 + 0.3 * random.unit()
                }
                guard lit else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                tone.getRed(&r, green: &g, blue: &b, alpha: nil)
                context.setFillColor(CGColor(srgbRed: r * brightness, green: g * brightness, blue: b * brightness, alpha: 1))
                // 隣の窓とつなげて、点いた窓が続くと横長の帯に見えるようにする
                context.fill(CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight + cellHeight * windowBottom,
                                    width: cellWidth, height: cellHeight * (windowTop - windowBottom)))
            }
        }
        return context.makeImage()
    }

    /// 外壁の自己発光（wallGlow × wallGlowIntensity）を、窓明かりの強さで割り戻した画像の色にする。
    /// こうすると、窓の無い所の光り方が UV の無い区の材質とそろう（画像も色も sRGB、計算は明るさがまっすぐな空間で行う）
    private static func wallGlowColor() -> CGColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        BuildingNightStyle.wallGlow.getRed(&r, green: &g, blue: &b, alpha: nil)
        let scale = Double(BuildingNightStyle.wallGlowIntensity / BuildingNightStyle.windowGlowIntensity)
        func convert(_ c: CGFloat) -> CGFloat {
            let linear = pow(Double(c), 2.2) * scale
            return CGFloat(pow(linear, 1 / 2.2))
        }
        return CGColor(srgbRed: convert(r), green: convert(g), blue: convert(b), alpha: 1)
    }

    /// 決まった種から同じ並びを出す簡単な乱数
    private struct SplitMix {
        var state: UInt64
        mutating func unit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }
}
