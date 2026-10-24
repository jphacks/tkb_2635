import StarCore
import SwiftUI

/// 地点の詳細。3D を画面いっぱいに出し、上に時刻スライダー、下に引き上げるシートを重ねる。
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext
    /// 比較画面へ進んで隠れている間は 3D を外す。3D を3つ同時に描くと、描画用のメモリが足りなくなる。
    @State private var isOnScreen = false
    @State private var sheetDetent: BottomSheet<SpotSheetHeader, SpotInfoList>.Detent = .collapsed

    /// シートをいちばん下にしたときの高さ（比較ボタンがあるときは、その分高くする）
    private static let collapsedHeight: CGFloat = 140
    private static let collapsedHeightWithCompare: CGFloat = 196

    var body: some View {
        @Bindable var model = model
        let prediction = Recommender.evaluate(context, target: model.target, date: model.date,
                                              weather: model.weather(for: context.spot),
                                              forecastCoverage: model.forecastCoverage(for: context.spot))

        ZStack {
            Group {
                if isOnScreen {
                    Sky3DView(context: context, prediction: prediction, date: model.date,
                              showsLegend: false)
                } else {
                    Color(red: 0.02, green: 0.03, blue: 0.10)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            VStack {
                TimeSlider(date: $model.date, compact: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                if let message = model.forecastCoverage(for: context.spot).message {
                    ForecastOutOfRangeNote(message: message)
                        .padding(.horizontal, 16)
                }
                // 判定は下のシートに出す。出典は利用の条件なので、3D の説明を消しても残す
                if context.scene.map(CityModelRenderer.hasModel) == true {
                    Text(SkyRenderer.credit)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 16)
                }
                Spacer()
            }

            let partner = model.contexts.comparisonPartner(of: context)
            BottomSheet(detent: $sheetDetent,
                        collapsedHeight: partner == nil ? Self.collapsedHeight : Self.collapsedHeightWithCompare) {
                SpotSheetHeader(spot: context.spot, prediction: prediction, targetName: model.target.name,
                                partner: partner)
            } content: {
                SpotInfoList(context: context, prediction: prediction)
            }
        }
        .navigationTitle(context.spot.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

/// シートをいちばん下にしたときにも見える、地点名・スコア・判定と、比較画面へのボタン
struct SpotSheetHeader: View {
    let spot: Spot
    let prediction: Prediction
    let targetName: String
    /// spots.json の comparisonSpotId に書かれた比較相手。nil ならボタンを出さない。
    let partner: SpotContext?

    var body: some View {
        VStack(spacing: 10) {
            summary
            if let partner {
                NavigationLink(value: ComparisonRoute(firstId: spot.id, secondId: partner.id)) {
                    Label("\(partner.spot.name)と比べる", systemImage: "rectangle.split.2x1")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("同じ時刻の\(targetName)が、目の高さでどう変わるかを並べて見られます")
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            ScoreBadge(score: prediction.totalScore, tier: prediction.tier)
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.headline)
                    .lineLimit(1)
                Label(verdict, systemImage: prediction.geometricVisibility ? "eye" : "eye.slash")
                    .font(.subheadline.bold())
                    .foregroundStyle(prediction.geometricVisibility ? .green : .red)
                Text("\(targetName)：\(Angle.directionName(prediction.azimuth)) 高度\(String(format: "%.0f", prediction.altitude))°・\(prediction.accessStatus.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var verdict: String {
        if prediction.altitude <= 0 { return "地平線の下" }
        if prediction.blockedByDirectionMask { return "窓の外で見えない" }
        return prediction.geometricVisibility ? "見える見込み" : "建物に遮られる見込み"
    }
}

struct MetricRow: View {
    let label: String
    let value: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value)).monospacedDigit()
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: value)
        }
    }
}
