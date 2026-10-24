import SwiftUI

/// ホーム画面の余白・色。数字はここだけに置く
enum HomeStyle {
    static let margin: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    /// 夜空の上に重ねるカードの面と縁（背景の星が透けすぎない濃さ）
    static let cardFill = Color(red: 0.10, green: 0.12, blue: 0.22).opacity(0.88)
    static let cardStroke = Color.white.opacity(0.09)
    /// 見出しの天体名に使う淡い月の色
    static let moonlight = Color(red: 0.98, green: 0.87, blue: 0.60)
    /// 夜空のグラデーション（上: 藍、下: ほぼ黒の紺）
    static let skyTop = Color(red: 0.07, green: 0.09, blue: 0.20)
    static let skyBottom = Color(red: 0.01, green: 0.02, blue: 0.05)
    /// 地図の上に置く丸いボタンの面（地図の色に埋もれない濃さ）
    static let mapButtonFill = Color.black.opacity(0.6)
}

extension View {
    /// 夜空に浮かぶ半透明のカード
    func homeCard(padding: CGFloat = HomeStyle.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeStyle.cardFill, in: .rect(cornerRadius: HomeStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: HomeStyle.cardRadius).stroke(HomeStyle.cardStroke))
    }
}

/// 藍から黒へのグラデーションに、薄い星を散らした背景
struct NightSkyBackground: View {
    private static let starCount = 90
    /// 毎回同じ並びになるように固定の種から星を置く
    private static let seed: UInt64 = 2635

    var body: some View {
        LinearGradient(colors: [HomeStyle.skyTop, HomeStyle.skyBottom], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    var generator = SeededGenerator(seed: Self.seed)
                    for _ in 0..<Self.starCount {
                        let x = Double.random(in: 0...1, using: &generator) * size.width
                        // 星は画面の上 6 割に多く置く（地平線に向かって減る）
                        let y = pow(Double.random(in: 0...1, using: &generator), 1.6) * size.height * 0.6
                        let radius = Double.random(in: 0.4...1.2, using: &generator)
                        let opacity = Double.random(in: 0.15...0.55, using: &generator)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                                     with: .color(.white.opacity(opacity)))
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// 種を固定した乱数（SplitMix64）。背景の星の位置を毎回そろえるために使う
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
