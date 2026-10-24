import StarCore
import SwiftUI

/// 一覧の 1 行。点数バッジ → 地点名 → 距離 → 理由 1 行 → 種類・区・目の高さ（小さく）の順に並べる
struct SpotRow: View {
    @Environment(LocationModel.self) private var location
    let spot: Spot
    let prediction: Prediction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScoreBadge(score: prediction.totalScore, tier: prediction.tier)
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name).font(.headline)
                if let km = location.distanceKm(to: spot) {
                    Text("\(Image(systemName: "location")) 現在地から \(Distance.label(km: km))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let first = prediction.recommendationReasons.first {
                    Text(first)
                        .font(.footnote)
                        .lineLimit(1)
                }
                Text("\(spot.category.label)・\(spot.ward)・目の高さ 標高\(Int(spot.observerElevation))m")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .homeCard(padding: 14)
        // 左端の細い線で段階を示す（見出し・バッジ・ピンと同じ色）
        .overlay(alignment: .leading) {
            Capsule()
                .fill(prediction.tier.color)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// 段階の見出し。段階の色の点と文字に、地点数を添える
struct TierHeader: View {
    let tier: RecommendationTier
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tier.color).frame(width: 8, height: 8)
            Text(tier.sectionTitle)
                .foregroundStyle(tier.color)
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.sectionTitle)、\(count)か所")
        .accessibilityAddTraits(.isHeader)
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
