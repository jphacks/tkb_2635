import StarCore
import SwiftUI
import ImageIO

/// 写真・折り返せる本文・固定幅のスコア。狭い幅では上下に組み直す。
struct SpotRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 9
    @State private var availableWidth: CGFloat = 390
    let spot: Spot
    let prediction: Prediction
    var distanceKm: Double? = nil

    var body: some View {
        Group {
            if availableWidth >= 350 && !typeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    SpotListThumbnail(spotId: spot.id, width: 132)
                    details.frame(minWidth: 105, maxWidth: .infinity, alignment: .leading)
                    scoreAndArrow
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SpotListThumbnail(spotId: spot.id, width: max(80, min(availableWidth - 100, 220)))
                        Spacer(minLength: 0)
                        scoreAndArrow
                    }
                    details
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(prediction.tier == .recommended ? "おすすめ" : prediction.tier.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(prediction.tier.color.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(prediction.tier.color.opacity(0.13), in: Capsule())
            Text(spot.name).font(.system(.headline, design: .serif)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Label(distanceKm.map { "現在地から \(Distance.label(km: $0))" } ?? "現在地からの距離は未取得",
                  systemImage: "mappin.and.ellipse")
                .font(.caption).foregroundStyle(HomeStyle.listSilver.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Text(prediction.recommendationReasons.first ?? "\(spot.ward)の\(spot.category.label)")
                .font(.caption).foregroundStyle(HomeStyle.listSilver.opacity(0.8))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreAndArrow: some View {
        HStack(spacing: 9) {
            VStack(spacing: 6) {
                Text("\(Int(prediction.totalScore.rounded()))")
                    .font(.system(.title3, design: .serif)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [HomeStyle.listSilver.opacity(0.75), prediction.tier.color.opacity(0.4)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                Text("観測スコア").font(.system(size: captionSize)).foregroundStyle(.secondary)
            }.frame(width: 58)
            Image(systemName: "chevron.right").font(.body.weight(.light))
                .foregroundStyle(HomeStyle.listSilver.opacity(0.7)).accessibilityHidden(true)
        }
        .foregroundStyle(.white).fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("観測スコア \(Int(prediction.totalScore.rounded()))")
    }
}


struct ScoreBadge: View {
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 9
    let score: Double
    let tier: RecommendationTier

    var body: some View {
        VStack(spacing: 0) {
            Text("\(Int(score.rounded()))")
                .font(.title3.monospacedDigit().bold())
            Text(tier.label)
                .font(.system(size: captionSize))
        }
        .frame(minWidth: 54, minHeight: 46)
        .background(tier.color.opacity(0.22), in: .rect(cornerRadius: 10))
        .foregroundStyle(tier.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スコア \(Int(score.rounded()))、\(tier.label)")
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

/// 地点を中心に切り出した同梱写真を読む。3D用の広域画像は一覧で展開しない。
private struct SpotListThumbnail: View {
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 9
    let spotId: String
    let width: CGFloat
    @State private var image: CGImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.08, green: 0.12, blue: 0.18)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(image == nil ? "写真なし" : "周辺800mの航空写真")
                .font(.system(size: captionSize)).foregroundStyle(.white.opacity(0.95))
                .padding(5).background(.black.opacity(0.6))
        }
        .frame(width: width, height: width * 0.96)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityHidden(true)
        .task(id: spotId) {
            image = nil
            guard let url = Bundle.main.url(forResource: "spot_\(spotId)", withExtension: "jpg"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return }
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary)
        }
    }
}

