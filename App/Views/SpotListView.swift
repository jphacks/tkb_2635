import MapKit
import StarCore
import SwiftUI

struct SpotListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let predictions = model.predictions

        NavigationStack {
            List {
                Section {
                    DatePicker("観測日時", selection: $model.date)
                        .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                    Picker("見たい天体", selection: $model.target) {
                        Text("月").tag(ObservationTarget.moon)
                        ForEach(StarCatalog.stars) { star in
                            Text(star.name).tag(ObservationTarget.star(star))
                        }
                    }
                    MoonSummary(moon: model.moon)
                } footer: {
                    Text("スコアは観測条件の目安で、観測できる確率ではありません。")
                }

                if let error = model.weatherLoadError {
                    Section {
                        Label(error, systemImage: "cloud.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    SpotMap(contexts: model.contexts, predictions: predictions)
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

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.675, longitude: 139.77),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.22)))) {
            ForEach(contexts) { context in
                let tier = predictions.first { $0.spotId == context.id }?.tier ?? .needsCheck
                Marker(context.spot.name, systemImage: tier == .recommended ? "star.fill" : "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: context.spot.latitude, longitude: context.spot.longitude))
                    .tint(tier.color)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
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
