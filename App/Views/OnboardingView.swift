import SwiftUI

/// 初めて開いたときだけ出す、使い方の短い案内（8-07）
struct OnboardingView: View {
    static let storageKey = "hasSeenOnboarding"
    @Environment(\.dismiss) private var dismiss

    private let steps: [(symbol: String, title: String, text: String)] = [
        ("moon.stars", "見たい天体を選ぶ", "月・惑星・恒星・星座から、見たいものを選びます。"),
        ("building.2", "見える場所をさがす", "東京の観測地点が、建物に隠れず見えるかどうかで並びます。地上と展望台の違いも比べられます。"),
        ("clock", "時刻を動かして確かめる", "スライダーで時間を動かすと、天体の位置と見え方が変わります。")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Astera の使い方")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(steps, id: \.title) { step in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: step.symbol)
                        .font(.title2).foregroundStyle(.cyan).frame(width: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(.headline)
                        Text(step.text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("はじめる").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
