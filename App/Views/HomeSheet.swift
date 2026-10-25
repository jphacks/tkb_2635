import StarCore
import SwiftUI

/// ホームの下から引き上げるシート。段階ごとの地点の一覧と、観測の条件（日時・天体・月）をまとめる。
/// 出し方は地点の詳細のシートと同じ（たたむ／半分／全開。半分までは裏の 3D も触れる）。
struct HomeSheet: View {
    /// たたんだときの高さ（見出しだけ）
    static let collapsedHeight: CGFloat = 64
    static let collapsedDetent = PresentationDetent.height(collapsedHeight)
    /// たたんだシートが画面の下で隠す高さ（シートの高さ＋画面の下の余白）。3D の地点名をこの上に出す
    static let coveredHeight: CGFloat = collapsedHeight + 30
    /// 半分まで引き上げたときの、画面の高さに対する割合
    static let mediumDetent = PresentationDetent.fraction(0.48)
    /// いちばん上まで引き上げたとき。上に 3D を少し残す
    static let largeDetent = PresentationDetent.fraction(0.9)

    @Environment(AppModel.self) private var model
    @Binding var detent: PresentationDetent
    /// 行を押したときに、その地点の ID を渡す
    let onSelect: (String) -> Void

    var body: some View {
        let predictions = model.predictions

        VStack(spacing: 0) {
            header(predictions)
            ScrollView {
                VStack(alignment: .leading, spacing: HomeStyle.sectionSpacing) {
                    BestTimeRow(onSelect: onSelect)
                    SpotResultsList(predictions: predictions, onSelect: onSelect)
                    HomeConditionsCard(showsTitle: false)
                    if let error = model.loadError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, HomeStyle.margin)
                .padding(.bottom, HomeStyle.sectionSpacing)
            }
        }
        .presentationDetents([Self.collapsedDetent, Self.mediumDetent, Self.largeDetent], selection: $detent)
        // 半分までなら、シートの裏の 3D・時刻スライダー・ボタンも触れる
        .presentationBackgroundInteraction(.enabled(upThrough: Self.mediumDetent))
        .presentationBackground { NightSkyBackground() }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    /// たたんだときにも見える見出し。押すと半分まで開く
    private func header(_ predictions: [Prediction]) -> some View {
        let recommended = predictions.filter { $0.tier == .recommended }.count
        return Button {
            if detent == Self.collapsedDetent { detent = Self.mediumDetent }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("観測地点").font(.headline)
                Spacer()
                Text("おすすめ \(recommended) か所 / 全 \(predictions.count) か所")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HomeStyle.margin)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .accessibilityHint("一覧を半分まで開きます")
    }
}
