import MapKit
import StarCore
import SwiftUI

/// 地図で、ピンの色の意味を示す
struct TierLegend: View {
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

/// 23 区の 2D の地図に、段階の色のピンを並べる
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
                    SpotPin(tier: tier) {
                        SoundPlayer.shared.play(.pinTap)
                        onSelect(context.id)
                    }
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
