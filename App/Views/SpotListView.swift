import StarCore
import SwiftUI

/// ホーム画面。条件カード → 地図 → 段階ごとの一覧を、夜空の背景の上に縦に並べる
struct SpotListView: View {
    @Environment(AppModel.self) private var model
    /// 一覧の行とマップのピンの両方から、同じ詳細画面へ遷移するための経路
    @State private var path = NavigationPath()

    var body: some View {
        let predictions = model.predictions

        NavigationStack(path: $path) {
            // List だと地図のピンチ・ドラッグが行のスクロールとぶつかるので、ScrollView で並べる
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HomeStyle.sectionSpacing) {
                    HomeConditionsCard()

                    if let error = model.weatherLoadError {
                        Label(error, systemImage: "cloud.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HomeMapSection(contexts: model.contexts, predictions: predictions) { id in
                        path.append(id)
                    }

                    ForEach(RecommendationTier.allTiers, id: \.self) { tier in
                        let rows = predictions.filter { $0.tier == tier }
                        if !rows.isEmpty {
                            tierSection(tier, rows: rows)
                        }
                    }

                    if let error = model.loadError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, HomeStyle.margin)
                .padding(.bottom, HomeStyle.sectionSpacing)
            }
            .background { NightSkyBackground() }
            .navigationTitle("Astera")
            .navigationDestination(for: String.self) { id in
                if let context = model.context(id: id) {
                    SpotDetailView(context: context)
                }
            }
            .navigationDestination(for: ComparisonRoute.self) { route in
                if let first = model.context(id: route.firstId), let second = model.context(id: route.secondId) {
                    CompareView(first: first, second: second)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isLoadingWeather {
                        ProgressView()
                    } else {
                        Button("天気を更新", systemImage: "arrow.clockwise") {
                            Task { await model.refreshWeather() }
                        }
                    }
                }
            }
            .refreshable { await model.refreshWeather() }
        }
    }

    private func tierSection(_ tier: RecommendationTier, rows: [Prediction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TierHeader(tier: tier, count: rows.count)
            ForEach(rows) { prediction in
                if let context = model.context(id: prediction.spotId) {
                    NavigationLink(value: prediction.spotId) {
                        SpotRow(spot: context.spot, prediction: prediction)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
