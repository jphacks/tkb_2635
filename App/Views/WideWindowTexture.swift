import CoreGraphics
import UIKit

/// 広域 3D の箱の壁に繰り返し貼る、窓明かりの画像（自分で光る色として使う）。アプリの中で描く。
/// 詳細画面の都市モデル（CityModelRenderer）の窓と同じく、各階に横長の窓の帯があり、帯の中が区切りごとに点いたり消えたりする。
/// 1 枚が横 segments 区切り × segmentMeters、縦 floors 階 × floorMeters。scripts/wide_ward_blender.py の TILE_WIDTH・TILE_HEIGHT と同じ大きさ。
enum WideWindowTexture {
    static let segments = 16
    static let segmentMeters = 2.0
    static let floors = 8
    static let floorMeters = 3.5
    private static let pixels = 256
    /// 1 階の中の窓の帯の範囲（下から。3.5m のうち約 1.75m）。屋根が指す UV（0.01, 0.01）と上下を入れ替えた位置は帯の外になる
    private static let bandBottom = 0.30
    private static let bandTop = 0.80
    /// 点いている区切りの割合と、点いた区切りの隣も点いている確率（点いた所が横に続く）
    private static let litRatio = 0.65
    private static let continueRatio = 0.8
    /// 窓の色（CityModelRenderer.lightColor の窓の 3 色と同じ。暖色・白っぽい暖色・青白い）と、その出やすさ（詳細画面の見え方に合わせ、白っぽい色を多めに）
    private static let tones: [(red: CGFloat, green: CGFloat, blue: CGFloat, weight: Int)] = [
        (1.0, 0.74, 0.40, 3), (1.0, 0.88, 0.66, 4), (0.86, 0.91, 0.98, 3),
    ]
    /// 消えている窓と外壁の、ほんのわずかな光（真っ黒にしない）
    private static let unlit = CGColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
    /// 同じ画像になるよう乱数の種を決めておく
    private static let seed: UInt64 = 2635

    static func image() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(unlit)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let cellWidth = CGFloat(pixels) / CGFloat(segments), floorHeight = CGFloat(pixels) / CGFloat(floors)
        let palette = tones.flatMap { Array(repeating: $0, count: $0.weight) }
        // 点き始める確率。続く確率と合わせて、平均の点灯率が litRatio になる値
        let start = litRatio * (1 - continueRatio) / (1 - litRatio)
        var random = SplitMix(state: seed)
        for floor in 0..<floors {
            var lit = false
            var color = unlit
            for segment in 0..<segments {
                let wasLit = lit
                lit = random.unit() < (lit ? continueRatio : start)
                if lit && !wasLit {
                    let tone = palette[Int(random.unit() * Double(palette.count)) % palette.count]
                    let k = 0.7 + 0.3 * random.unit()
                    color = CGColor(srgbRed: tone.red * k, green: tone.green * k, blue: tone.blue * k, alpha: 1)
                }
                let y = CGFloat(floor) * floorHeight
                let band = CGRect(x: CGFloat(segment) * cellWidth, y: y + floorHeight * bandBottom,
                                  width: cellWidth, height: floorHeight * (bandTop - bandBottom))
                context.setFillColor(lit ? color : CGColor(srgbRed: 0.08, green: 0.10, blue: 0.15, alpha: 1))
                context.fill(band)
                // 窓の縦の桟（区切りの境に細い線）
                context.setFillColor(unlit)
                context.fill(CGRect(x: band.minX, y: band.minY, width: 1, height: band.height))
            }
        }
        return context.makeImage()
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
