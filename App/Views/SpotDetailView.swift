import StarCore
import SwiftUI

/// 地点の詳細。3D を画面いっぱいに出し、上に時刻スライダー、下に引き上げるシートを重ねる。
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext
    /// 比較画面へ進んで隠れている間は 3D を外す。3D を3つ同時に描くと、描画用のメモリが足りなくなる。
    @State private var isOnScreen = false
    @State private var sheetDetent: BottomSheet<SpotSheetHeader, SpotInfoList>.Detent = .collapsed

    /// シートをいちばん下にしたときの高さ（取っ手＋地点名。比較ボタンがあるときは、その分高くする）。
    /// 判定はシートの中に出すので、たたんだときは見出しだけにして 3D を広く見せる
    private static let collapsedHeight: CGFloat = 70
    private static let collapsedHeightWithCompare: CGFloat = 114

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
                SpotSheetHeader(spot: context.spot, targetName: model.target.name, partner: partner)
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

/// シートをいちばん下にしたときにも見える、地点名と比較画面へのボタン。
/// 判定はシートの中（SpotInfoList の「判定」）に出し、たたんだときは 3D を広く見せる。
struct SpotSheetHeader: View {
    let spot: Spot
    let targetName: String
    /// spots.json の comparisonSpotId に書かれた比較相手。nil ならボタンを出さない。
    let partner: SpotContext?

    var body: some View {
        VStack(spacing: 10) {
            Text(spot.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
