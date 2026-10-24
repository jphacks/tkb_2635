import MapKit
import StarCore
import SwiftUI

/// ホームの地図。画面幅に応じた高さで置き、右上のボタンで全画面の地図を開く
struct HomeMapSection: View {
    /// 地図の高さ = 幅 × この比。最小・最大で挟む
    private static let heightRatio: CGFloat = 0.82
    private static let minHeight: CGFloat = 260
    private static let maxHeight: CGFloat = 320

    let contexts: [SpotContext]
    let predictions: [Prediction]
    /// ピンを押したときに、その地点の ID を渡す
    let onSelect: (String) -> Void

    @State private var width: CGFloat = 0
    @State private var isExpanded = false

    private var height: CGFloat {
        min(max(width * Self.heightRatio, Self.minHeight), Self.maxHeight)
    }

    var body: some View {
        SpotMap(contexts: contexts, predictions: predictions, onSelect: onSelect)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .clipShape(.rect(cornerRadius: HomeStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: HomeStyle.cardRadius).stroke(HomeStyle.cardStroke))
            .overlay(alignment: .topTrailing) {
                Button("地図を全画面で開く", systemImage: "arrow.up.left.and.arrow.down.right") {
                    isExpanded = true
                }
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(HomeStyle.mapButtonFill, in: .circle)
                .overlay(Circle().stroke(HomeStyle.cardStroke))
                .padding(10)
            }
            .fullScreenCover(isPresented: $isExpanded) {
                FullScreenSpotMap(contexts: contexts, predictions: predictions) { id in
                    isExpanded = false
                    onSelect(id)
                }
            }
    }
}

/// 全画面の地図。ピンから詳細へ行ける
private struct FullScreenSpotMap: View {
    @Environment(\.dismiss) private var dismiss
    let contexts: [SpotContext]
    let predictions: [Prediction]
    let onSelect: (String) -> Void

    var body: some View {
        SpotMap(contexts: contexts, predictions: predictions, onSelect: onSelect)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("地図を閉じる", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(HomeStyle.mapButtonFill, in: .circle)
                    .padding()
            }
            .overlay(alignment: .bottom) {
                TierLegend()
                    .padding(.bottom, 24)
            }
    }
}

/// 全画面の地図で、ピンの色の意味を示す
private struct TierLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(RecommendationTier.allTiers, id: \.self) { tier in
                Label {
                    Text(tier.label)
                } icon: {
                    Circle().fill(tier.color).frame(width: 10, height: 10)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
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
