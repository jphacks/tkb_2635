import MapKit
import StarCore
import SwiftUI

struct SpotListView: View {
    @Environment(AppModel.self) private var model
    /// 一覧の行とマップのピンの両方から、同じ詳細画面へ遷移するための経路
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var model = model
        let predictions = model.predictions

        NavigationStack(path: $path) {
            List {
                Section {
                    DatePicker("観測日時", selection: $model.date)
                        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                    TargetPicker(target: $model.target)
                    MoonSummary(moon: model.moon)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let message = model.forecastOutOfRangeMessage {
                            ForecastOutOfRangeNote(message: message)
                        }
                        Text("スコアは観測条件の目安で、観測できる確率ではありません。")
                    }
                }

                if let error = model.weatherLoadError {
                    Section {
                        Label(error, systemImage: "cloud.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    SpotMap(contexts: model.contexts, predictions: predictions) { id in
                        path.append(id)
                    }
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(RecommendationTier.allTiers, id: \.self) { tier in
                    let rows = predictions.filter { $0.tier == tier }
                    if !rows.isEmpty {
                        Section(tier.sectionTitle) {
                            ForEach(rows) { prediction in
                                if let context = model.context(id: prediction.spotId) {
                                    NavigationLink(value: prediction.spotId) {
                                        SpotRow(spot: context.spot, prediction: prediction)
                                    }
                                }
                            }
                        }
                    }
                }

                if let error = model.loadError {
                    Text(error).foregroundStyle(.red)
                }
            }
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
}

/// 選んだ日時が天気予報の範囲外のときの注意書き
struct ForecastOutOfRangeNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "calendar.badge.exclamationmark")
            .foregroundStyle(.orange)
    }
}

struct MoonSummary: View {
    let moon: MoonInfo

    var body: some View {
        HStack {
            Image(systemName: "moon.fill")
                .foregroundStyle(.yellow)
            Text("\(moon.phaseName)（輝面 \(Int(moon.illuminatedFraction * 100))%）")
            Spacer()
            Text(moon.position.altitude > 0
                 ? "\(Angle.directionName(moon.position.azimuth)) 高度\(Int(moon.position.altitude))°"
                 : "地平線の下")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

struct SpotRow: View {
    let spot: Spot
    let prediction: Prediction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoreBadge(score: prediction.totalScore, tier: prediction.tier)
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name).font(.headline)
                Text("\(spot.category.label)・\(spot.ward)・目の高さ 標高\(Int(spot.observerElevation))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let first = prediction.recommendationReasons.first {
                    Text(first)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ScoreBadge: View {
    let score: Double
    let tier: RecommendationTier

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(score.rounded()))")
                .font(.title3.monospacedDigit().bold())
            Text(tier.label)
                .font(.system(size: 9))
        }
        .frame(width: 54, height: 46)
        .background(tier.color.opacity(0.25), in: .rect(cornerRadius: 8))
        .foregroundStyle(tier.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スコア \(Int(score.rounded()))、\(tier.label)")
    }
}

struct SpotMap: View {
    let contexts: [SpotContext]
    let predictions: [Prediction]
    /// ピンを押したときに、その地点の ID を渡す
    let onSelect: (String) -> Void

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.675, longitude: 139.77),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.22)))) {
            ForEach(contexts) { context in
                let tier = predictions.first { $0.spotId == context.id }?.tier ?? .needsCheck
                Annotation(context.spot.name,
                           coordinate: CLLocationCoordinate2D(latitude: context.spot.latitude, longitude: context.spot.longitude)) {
                    SpotPin(tier: tier) { onSelect(context.id) }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

/// マップ上の押せるピン。推薦は星、それ以外はピンの形で、段階の色を付ける
private struct SpotPin: View {
    /// 指で押しやすい大きさ（Apple の推奨する最小の当たり判定 44pt）
    private static let hitSize: CGFloat = 44
    private static let iconSize: CGFloat = 28

    let tier: RecommendationTier
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tier == .recommended ? "star.fill" : "mappin")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(tier.color, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .shadow(radius: 2)
                .frame(width: Self.hitSize, height: Self.hitSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tier.label)
    }
}

extension RecommendationTier {
    static let allTiers: [RecommendationTier] = [.recommended, .needsCheck, .notVisible, .unavailable]

    var color: Color {
        switch self {
        case .recommended: .green
        case .needsCheck: .orange
        case .notVisible: .red
        case .unavailable: .gray
        }
    }

    var sectionTitle: String {
        switch self {
        case .recommended: "推薦できる地点"
        case .needsCheck: "見える見込み（データ要確認）"
        case .notVisible: "見えない見込みの地点"
        case .unavailable: "指定時刻に利用できない地点"
        }
    }
}
